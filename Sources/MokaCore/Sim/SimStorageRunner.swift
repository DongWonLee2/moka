import Foundation

/// storage 모드(contracts/moka-sim-v1-additions.md, spec 003 덧붙임은 moka-sim-v1-additions-003.md). 앱과 같은
/// MokaCore 함수(`NotchSession`, `PriorityRotateRule`, `RecurrenceReset`, `LaunchRecovery`, `TaskWriteRules`,
/// `SessionCommit`, `ScoreRules`)만 부르고 저장은 메모리 저장소다.
extension SimRunner {
    static func executeStorage(_ scenario: SimScenario, settings: InMemorySettingsStore) throws(SimError) -> String {
        let repository = InMemoryTaskRepository()
        let scores = InMemoryScoreStore(tasks: repository)
        let questions: QuestionSet
        do {
            questions = try QuestionSet.bundled()
        } catch {
            throw invariantViolation("번들 질문 파일을 읽지 못했다: \(error)", seq: nil)
        }
        let showsJudgment = scenario.events.contains {
            switch $0.kind {
            case .judge, .key: true
            default: false
            }
        }
        // 키 유무와 판단 결과는 Keychain·앱 DB에 있는 값이라 quit·relaunch를 넘어 남는다.
        var hasKey = false
        let calendar = GregorianCalendar.make(timeZone: scenario.timezone)
        if let dayStart = scenario.dayStart {
            try storing(seq: nil) { try CoreSettings.writeDayStart(dayStart, to: settings) }
        }

        // 시작 직후: 저장소 비어 있음, 노치 빈 상태, 하루 판정 한 번(대상 없음).
        var previous = SimStorageState(session: .initial, tasks: [], checkpoints: [], decisions: [])
        var output = ""
        for event in scenario.events {
            var step = StorageEvent(
                event: event, repository: repository, scores: scores, questions: questions, hasKey: hasKey,
                settings: settings, calendar: calendar)
            let session = try step.run(previous.session)
            hasKey = step.hasKey
            let state = try storing(seq: event.seq) {
                SimStorageState(
                    session: session, tasks: try repository.tasks(), checkpoints: try repository.checkpoints(),
                    decisions: try repository.decisions())
            }
            if let violation = checkStorageInvariant(state, previous: previous, at: event.at, seq: event.seq) {
                throw violation
            }
            let judgment =
                showsJudgment
                ? SimJudgmentFields(order: PriorityOrder.order(try step.input()).map(\.id), hasKey: hasKey) : nil
            output += SimOutput.storageLine(event, state: state, previous: previous, judgment: judgment)
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
    let scores: InMemoryScoreStore
    let questions: QuestionSet
    /// `key` 이벤트가 바꾼다.
    var hasKey: Bool
    let settings: InMemorySettingsStore
    let calendar: Calendar

    private var defaultQuantumMin: Int { QuantumSettings.readDefault(from: settings) }
    private var dayStart: DayStart { CoreSettings.readDayStart(from: settings) }

    /// 적용 뒤 세션. nil이면 꺼짐.
    mutating func run(_ current: NotchSession?) throws(SimError) -> NotchSession? {
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

        case .judge(let judge):
            try save(judge)
            return session

        case .key(let present):
            hasKey = present
            return session
        }
    }

    /// 앱이 답을 받을 때와 같은 `ScoreRules.score`로 판단 결과를 저장한다. 가짜 답의 확신도·옵션 확률은 고정 값이다.
    private func save(_ judge: SimJudge) throws(SimError) {
        guard let task = try tasks().first(where: { $0.id == judge.taskID }) else {
            throw SimError(kind: .outOfRange, seq: event.seq, message: "task \(judge.taskID)인 할 일이 없다")
        }
        guard task.status == .todo || task.status == .active else { throw SimRunner.notAllowed(event) }
        let checkpoints = try SimRunner.storing(seq: event.seq) { try repository.checkpoints() }
        let state = JudgmentState.build(
            task: task, contexts: [], checkpoints: checkpoints, today: today, calendar: calendar)
        let response = DecisionResponse(
            model: Self.fakeModel,
            answers: [
                "urgency": Self.fakeScore(judge.urgency, options: 4),
                "impact": Self.fakeScore(judge.impact, options: 3),
                "concrete": .noul(judge.concrete), "avoiding": .noul(judge.avoiding),
            ])
        guard
            let score = ScoreRules.score(
                taskID: task.id, response: response, questions: questions, provider: Self.fakeProvider,
                stateHash: state.hash, now: event.at)
        else { throw SimRunner.invariantViolation("검증한 judge 답을 ScoreRules가 거부했다", seq: event.seq) }
        try SimRunner.storing(seq: event.seq) { try scores.upsertScore(score) }
    }

    /// 가짜 공급자는 질문 파일 `models`를 거치지 않고 기준 모델 ID를 직접 받는다(spec 006 research R14).
    private static let fakeProvider = "fake"
    private static let baseModel = "jev-1.13.0"
    private static let fakeModel = "fake-1"

    /// 확신도 1, 옵션 확률은 모두 같은 값.
    private static func fakeScore(_ score: Double, options: Int) -> Answer {
        .score(
            score: score, confidence: 1,
            probabilities: Dictionary(uniqueKeysWithValues: (0..<options).map { ($0, 1 / Double(options)) }))
    }

    private var today: LocalDay {
        DayBoundary.day(containing: event.at, dayStart: dayStart, calendar: calendar)
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

    /// 앱 `AppState.input(at:)`처럼 키 유무로 거른 판단 결과를 넘긴다.
    func input() throws(SimError) -> SessionInput {
        let stored = try SimRunner.storing(seq: event.seq) { try scores.scores() }
        return SessionInput(
            tasks: try tasks(), now: event.at, defaultQuantumMin: defaultQuantumMin, calendar: calendar,
            scoring: SessionScoring(
                usable: ScoreRules.usable(
                    scores: stored, hasKey: hasKey, questionVersion: questions.version, provider: Self.fakeProvider),
                questions: questions, thresholds: questions.thresholds(for: Self.baseModel), today: today))
    }
}
