import Foundation

/// storage 모드(contracts/moka-sim-v1-additions.md). 앱과 같은 MokaCore 함수(`NotchSession`, `RotateByIDRule`,
/// `RecurrenceReset`, `LaunchRecovery`, `TaskWriteRules`, `SessionCommit`)만 부르고 저장은 메모리 저장소다.
extension SimRunner {
    static func executeStorage(_ scenario: SimScenario, settings: InMemorySettingsStore) throws(SimError) -> String {
        let repository = InMemoryTaskRepository()
        let calendar = GregorianCalendar.make(timeZone: scenario.timezone)
        if let dayStart = scenario.dayStart {
            try storing(seq: nil) { try CoreSettings.writeDayStart(dayStart, to: settings) }
        }

        // 시작 직후: 저장소 비어 있음, 노치 빈 상태, 하루 판정 한 번(대상 없음).
        var previous = SimStorageState(session: .initial, tasks: [], checkpoints: [], decisions: [])
        var output = ""
        for event in scenario.events {
            let step = StorageEvent(event: event, repository: repository, settings: settings, calendar: calendar)
            let session = try step.run(previous.session)
            let state = try storing(seq: event.seq) {
                SimStorageState(
                    session: session, tasks: try repository.tasks(), checkpoints: try repository.checkpoints(),
                    decisions: try repository.decisions())
            }
            if let violation = checkStorageInvariant(state, previous: previous, at: event.at, seq: event.seq) {
                throw violation
            }
            output += SimOutput.storageLine(event, state: state, previous: previous)
            previous = state
        }
        return output
    }

    /// 계약 "오류 덧붙임" 종료 코드 1 줄. 이벤트 하나를 적용한 뒤 `previous`(직전 줄의 상태)와 견준다.
    public static func checkStorageInvariant(
        _ state: SimStorageState, previous: SimStorageState, at now: Date, seq: Int
    ) -> SimError? {
        storageViolation(state, previous: previous, at: now).map { invariantViolation($0, seq: seq) }
    }

    private static func storageViolation(_ state: SimStorageState, previous: SimStorageState, at now: Date) -> String? {
        if let reason = state.session?.timer.invariantViolation(at: now) {
            return reason
        }
        let active = state.tasks.filter { $0.status == .active }
        if active.count > 1 {
            return "active 할 일이 \(active.count)개다"
        }
        if let session = state.session {
            let notch = session.taskID.flatMap { id in state.tasks.first { $0.id == id } }
            switch session.timer {
            case .running, .expired:
                guard notch?.status == .active else { return "도는 중·시간 끝인데 notch_task가 active가 아니다" }
            case .empty(let draft):
                guard active.isEmpty else { return "타이머가 빈 상태인데 active 할 일이 있다" }
                if draft != nil, notch?.status != .todo {
                    return "초안의 notch_task가 todo가 아니다"
                }
            }
        }
        for task in state.tasks {
            if !MokaTask.isValidWeekday(task.weekday, recurrence: task.recurrence) {
                return "할 일 \(task.id)의 recurrence와 weekday가 맞지 않는다"
            }
            if (task.recurrence == .none) != (task.cycleDay == nil) {
                return "할 일 \(task.id)의 recurrence와 cycle_day가 맞지 않는다"
            }
            if task.skipCount < 0 || task.streak < 0 {
                return "할 일 \(task.id)의 skip_count·streak가 음수다"
            }
        }
        return appendOnlyViolation("체크포인트", state.checkpoints, previous.checkpoints)
            ?? appendOnlyViolation("로그", state.decisions, previous.decisions)
    }

    /// 줄 수는 줄지 않고, 이전 줄은 그대로이며, 이벤트 하나는 최대 한 줄을 더한다.
    private static func appendOnlyViolation<Row: Equatable>(_ name: String, _ rows: [Row], _ previous: [Row])
        -> String?
    {
        guard rows.count >= previous.count, Array(rows.prefix(previous.count)) == previous else {
            return "\(name) 줄이 줄었거나 이전 줄이 바뀌었다"
        }
        guard rows.count <= previous.count + 1 else { return "이벤트 하나가 \(name)를 둘 이상 남겼다" }
        return nil
    }

    /// 메모리 저장소·설정 쓰기 실패는 유효한 입력으로는 나오지 않는다(MokaCore 버그 신호, 종료 코드 1).
    fileprivate static func storing<T>(seq: Int?, _ body: () throws -> T) throws(SimError) -> T {
        do {
            return try body()
        } catch {
            throw invariantViolation("저장소가 쓰기를 거부했다: \(error)", seq: seq)
        }
    }
}

/// 이벤트 하나를 storage 모드 세션에 적용한다(계약 "단계 × 이벤트").
private struct StorageEvent {
    let event: SimEvent
    let repository: InMemoryTaskRepository
    let settings: InMemorySettingsStore
    let calendar: Calendar

    private var defaultQuantumMin: Int { QuantumSettings.readDefault(from: settings) }
    private var dayStart: DayStart { CoreSettings.readDayStart(from: settings) }

    /// 적용 뒤 세션. nil이면 꺼짐.
    func run(_ current: NotchSession?) throws(SimError) -> NotchSession? {
        guard var session = current else {
            guard case .relaunch = event.kind else { throw SimRunner.notAllowed(event) }
            return try launch()
        }
        // 암묵 tick(꺼짐 단계 제외)
        _ = session.timer.apply(.tick, at: event.at, defaultQuantumMin: defaultQuantumMin)

        switch event.kind {
        case .addTask(let new):
            _ = try insert(new)
            return session.picked(try input())

        case .enterTitle(let title):
            guard case .empty = session.timer else { throw SimRunner.notAllowed(event) }
            guard MokaTask.normalizedTitle(title) != nil else {
                throw SimRunner.rejection(.emptyTitle, event: event)
            }
            let task = try insert(NewTask(title: title, deadline: nil, estMin: nil, recurrence: .none, weekday: nil))
            return session.addedTask(task, try input())

        case .chooseQuantum(let minutes):
            try applyTimer(.chooseQuantum(minutes), to: &session)
            return session

        case .tick:
            return session

        case .setDefaultQuantum(let minutes):
            try SimRunner.write(minutes, to: settings, seq: event.seq)
            session.timer.applyDefaultQuantumChange(defaultQuantumMin, isEditingCustom: false)
            return session

        case .start(let notes):
            let input = try input()
            if case .expired(_, let chipMin, _) = session.timer {
                return try commit { () throws(SessionError) in
                    try session.restart(notes ?? .empty, quantumMin: chipMin, input)
                }
            }
            guard notes == nil else { throw SimRunner.notAllowed(event) }
            return try commit { () throws(SessionError) in try session.start(input) }

        case .complete(let notes):
            let input = try input()
            return try commit { () throws(SessionError) in try session.complete(notes, input) }.picked(try self.input())

        case .skip(let notes):
            let input = try input()
            return try commit { () throws(SessionError) in try session.skip(notes, input) }.picked(try self.input())

        case .switchTask(let notes):
            let input = try input()
            return try commit { () throws(SessionError) in try session.switchTask(notes, input) }
                .picked(try self.input())

        case .quit:
            if let batch = session.lifecycleCheckpoint(.quit, try input()) {
                try apply(batch)
            }
            return nil

        case .relaunch:
            return try launch()

        case .activate:
            try judgeDay()
            return session.picked(try input())
        }
    }

    /// 앱 시작: 메모리 상태를 버리고 R-111 복구 → 하루 판정 → 고르기.
    private func launch() throws(SimError) -> NotchSession {
        try apply(StoreBatch(updatedTasks: LaunchRecovery.revert(try tasks())))
        try judgeDay()
        return NotchSession.initial.picked(try input())
    }

    /// 하루 판정(R-113).
    private func judgeDay() throws(SimError) {
        let reset = RecurrenceReset.reset(try tasks(), now: event.at, dayStart: dayStart, calendar: calendar)
        try apply(StoreBatch(updatedTasks: reset))
    }

    /// data-model §5.8: `prepareNew` → `insertTask`. 디코딩에서 값 검증을 마쳤다.
    private func insert(_ new: NewTask) throws(SimError) -> MokaTask {
        guard let prepared = TaskWriteRules.prepareNew(new, now: event.at, dayStart: dayStart, calendar: calendar)
        else { throw SimRunner.invariantViolation("검증한 할 일을 prepareNew가 거부했다", seq: event.seq) }
        return try SimRunner.storing(seq: event.seq) {
            try repository.insertTask(prepared.task, cycleDay: prepared.cycleDay, at: event.at)
        }
    }

    private func applyTimer(_ timerEvent: TimerEvent, to session: inout NotchSession) throws(SimError) {
        if case .rejected(let reason) = session.timer.apply(
            timerEvent, at: event.at, defaultQuantumMin: defaultQuantumMin)
        {
            throw SimRunner.rejection(reason, event: event)
        }
    }

    /// 버튼 동작. 거부는 종료 코드 2, 쓰기는 `SessionCommit`.
    private func commit(_ action: () throws(SessionError) -> SessionStep) throws(SimError) -> NotchSession {
        let step: SessionStep
        do {
            step = try action()
        } catch {
            throw SimRunner.notAllowed(event)
        }
        return try SimRunner.storing(seq: event.seq) { try SessionCommit.commit(step, to: repository) }
    }

    private func apply(_ batch: StoreBatch) throws(SimError) {
        try SimRunner.storing(seq: event.seq) { try repository.apply(batch) }
    }

    private func tasks() throws(SimError) -> [MokaTask] {
        try SimRunner.storing(seq: event.seq) { try repository.tasks() }
    }

    private func input() throws(SimError) -> SessionInput {
        SessionInput(tasks: try tasks(), now: event.at, defaultQuantumMin: defaultQuantumMin, calendar: calendar)
    }
}
