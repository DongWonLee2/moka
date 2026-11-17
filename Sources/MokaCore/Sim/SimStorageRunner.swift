import Foundation

/// storage 모드(contracts/moka-sim-v1-additions.md, spec 003 덧붙임은 moka-sim-v1-additions-003.md, spec 005 덧붙임은
/// moka-sim-v1-additions-005.md). 앱과 같은 MokaCore 함수(`NotchSession`, `SessionAssembly`, `SchedulerPick`,
/// `CarryAnswer`, `DayBudget`, `NotchMode`, `TaskWriteRules`, `ScoreRules`)만 부르고 저장은 메모리 저장소다.
extension SimRunner {
    /// 가짜 공급자 `fake`의 기준 모델 ID. 질문 파일 `models`를 거치지 않고 직접 받는다(spec 006 research R14).
    public static let fakeBaseModel = "jev-1.13.0"

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
        var day = SimDayState(scheduled: scenario.events.contains { $0.kind.turnsOnSchedule })
        // 시작 직후의 이월 판정(대상 없음)은 첫 이벤트 시각에 판정 시각만 남긴다(data-model §15).
        if day.scheduled, let first = scenario.events.first?.at {
            try storing(seq: nil) { try repository.applyCarryJudgment(.empty, judgedAt: first) }
        }

        var previous = SimStorageState(session: .initial, tasks: [], checkpoints: [], decisions: [])
        var output = ""
        for event in scenario.events {
            var step = StorageEvent(
                event: event, repository: repository, scores: scores, questions: questions, hasKey: hasKey,
                settings: settings, calendar: calendar, day: day)
            let session = try step.run(previous.session)
            hasKey = step.hasKey
            day = step.day
            let schedule = day.scheduled ? try step.schedule(session) : nil
            let state = try storing(seq: event.seq) {
                SimStorageState(
                    session: session, tasks: try repository.tasks(), checkpoints: try repository.checkpoints(),
                    decisions: try repository.decisions(), schedule: schedule)
            }
            if let violation = checkStorageInvariant(state, previous: previous, at: event.at, seq: event.seq) {
                throw violation
            }
            if let reason = eventViolation(event, state, previous: previous) {
                throw invariantViolation(reason, seq: event.seq)
            }
            let judgment =
                showsJudgment
                ? SimJudgmentFields(order: PriorityOrder.order(try step.input(session)).map(\.id), hasKey: hasKey)
                : nil
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
        return scheduleViolation(state)
            ?? appendOnlyViolation("체크포인트", state.checkpoints, previous.checkpoints)
            ?? appendOnlyViolation("로그", state.decisions, previous.decisions)
    }

    /// spec 005 새 불변식(켜짐일 때만).
    private static func scheduleViolation(_ state: SimStorageState) -> String? {
        guard let schedule = state.schedule else { return nil }
        if let session = state.session, case .empty = session.timer,
            let id = session.taskID, state.tasks.contains(where: { $0.id == id && $0.dueDecision })
        {
            return "빈 상태인데 notch_task가 이월 답 대기다"
        }
        if schedule.mode.clearsDraft, let session = state.session, session.timer != .empty(draft: nil) {
            return "이월 카드·가용 시간 질문·오늘 끝인데 타이머가 빈 상태가 아니다"
        }
        if let budget = schedule.budget, !budget.more, budget.usedSeconds > budget.minutes * 60 {
            return "더 할래요 전인데 쓴 시간이 가용 시간보다 크다"
        }
        return nil
    }

    /// 이벤트에 따라 붙는 spec 005 불변식: 이월 답은 로그 한 줄, 가용 시간 답·더 할래요·늘리기는 로그 없음.
    private static func eventViolation(_ event: SimEvent, _ state: SimStorageState, previous: SimStorageState)
        -> String?
    {
        let newDecisions = state.decisions.dropFirst(previous.decisions.count)
        let newCheckpoints = state.checkpoints.count - previous.checkpoints.count
        switch event.kind {
        case .carry:
            guard newDecisions.count == 1, let line = newDecisions.first, newCheckpoints == 0,
                [.carryToday, .carryDrop, .carryMove].contains(line.userAction), line.schedulerChoice == .carryCardV1
            else { return "carry 이벤트가 이월 답 로그 한 줄만 남기지 않았다" }
        case .budget, .more:
            guard newDecisions.isEmpty, newCheckpoints == 0 else { return "\(event.kind.name)가 로그나 체크포인트를 남겼다" }
        case .start(_, extend: true):
            guard newDecisions.isEmpty else { return "늘리기가 로그를 남겼다" }
            guard let today = state.schedule?.today, let chip = state.session?.run?.quantumMin,
                let before = DayBudget.record(previous.schedule?.budget, for: today),
                let after = DayBudget.record(state.schedule?.budget, for: today)
            else { return "늘리기 전후의 오늘 기록이 없다" }
            let extra = chip - before.remainingMinutes
            guard after.minutes == before.minutes + extra, after.extendedMinutes == before.extendedMinutes + extra
            else {
                return "늘린 가용 시간이 칩 − 남은 분과 다르다"
            }
        default:
            break
        }
        return nil
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

/// 이벤트 사이에 남는 스케줄러 값. 앱에서는 설정 키 `day_budget`과 실행 메모리(`revertedIDs`)다(data-model §9·§13).
/// quit·relaunch를 넘어 남고, `revertedIDs`만 시작마다 새로 채운다. 이월 판정 시각은 할 일 저장소, 마지막 시작 하루는
/// 설정 저장소에 앱과 같은 `SessionAssembly` 경계로 쓴다.
private struct SimDayState {
    /// 새 이벤트(`carry`·`budget`·`more`)가 있어 이월·가용 시간이 켜졌다(Q3-C).
    let scheduled: Bool
    var budget: DayBudget?
    var revertedIDs: Set<TaskID> = []
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
    var day: SimDayState

    private var defaultQuantumMin: Int { QuantumSettings.readDefault(from: settings) }
    private var extendMin: Int { CoreSettings.readExtendMin(from: settings) }
    private var dayStart: DayStart { CoreSettings.readDayStart(from: settings) }

    /// 적용 뒤 세션. nil이면 꺼짐.
    mutating func run(_ current: NotchSession?) throws(SimError) -> NotchSession? {
        guard var session = current else {
            guard case .relaunch = event.kind else { throw SimRunner.notAllowed(event) }
            return try launch()
        }
        // 암묵 tick(꺼짐 단계 제외). 시간 끝 칩은 그 작업 시간을 시작한 하루의 남은 분 이하다.
        _ = session.timer.apply(
            .tick, at: event.at, defaultQuantumMin: defaultQuantumMin, extendMin: expiredChip(session))

        switch event.kind {
        case .addTask(let new):
            _ = try insert(new)
            return try settle(session)

        case .enterTitle(let title):
            guard case .empty = session.timer else { throw SimRunner.notAllowed(event) }
            guard MokaTask.normalizedTitle(title) != nil else {
                throw SimRunner.rejection(.emptyTitle, event: event)
            }
            let task = try insert(NewTask(title: title, deadline: nil, estMin: nil, recurrence: .none, weekday: nil))
            // 카드·질문·오늘 끝 중에는 저장만 하고 초안으로 띄우지 않는다(spec 005 Edge Cases).
            guard try mode(session) == .session else { return session }
            return session.addedTask(task, try input(session))

        case .chooseQuantum(let minutes):
            if case .expired = session.timer, day.scheduled {
                let record = DayBudget.record(day.budget, for: budgetDay(session))
                if NotchMode.expiredDayEnd(timer: session.timer, budgetDayRecord: record) {
                    throw SimRunner.notAllowed(event)
                }
                if let cap = DayBudget.capMinutes(record), minutes > cap { throw SimRunner.notAllowed(event) }
            }
            try applyTimer(.chooseQuantum(minutes), to: &session)
            return session

        case .tick:
            return session

        case .setDefaultQuantum(let minutes):
            try SimRunner.write(minutes, to: settings, seq: event.seq)
            session.timer.applyDefaultQuantumChange(
                QuantumChip.cap(chipMin: defaultQuantumMin, remainingMinutes: try input(session).draftChipCap),
                isEditingCustom: false)
            return session

        case .start(let notes, let extend):
            let input = try input(session)
            if case .expired(_, let chipMin, _) = session.timer {
                // 시간 끝에는 늘리기가 없고, 오늘 끝과 겹치면 "N분 더"가 꺼져 있다(R-421, R-422).
                guard !extend, !input.dayEndExpired else { throw SimRunner.notAllowed(event) }
                return try commit { () throws(SessionError) in
                    try session.restart(notes ?? .empty, quantumMin: chipMin, input)
                }
            }
            guard notes == nil, case .empty(.some(let draft)) = session.timer else { throw SimRunner.notAllowed(event) }
            if let needed = QuantumChip.extendNeeded(chipMin: draft.chipMin, remainingMinutes: input.draftChipCap) {
                guard extend else { throw SimRunner.notAllowed(event) }
                day.budget = day.budget?.extended(by: needed)
            } else if extend {
                throw SimRunner.notAllowed(event)
            }
            return try commit { () throws(SessionError) in try session.start(input) }

        case .complete(let notes):
            let input = try input(session)
            return try settle(try commit { () throws(SessionError) in try session.complete(notes, input) })

        case .skip(let notes):
            let input = try input(session)
            return try settle(try commit { () throws(SessionError) in try session.skip(notes, input) })

        case .switchTask(let notes):
            let input = try input(session)
            return try settle(try commit { () throws(SessionError) in try session.switchTask(notes, input) })

        case .quit:
            let input = try input(session)
            if let batch = session.lifecycleCheckpoint(.quit, input) {
                try apply(batch)
            }
            use(session.lifecycleRefund(.quit, input))
            return nil

        case .relaunch:
            return try launch()

        case .activate:
            return try activate(session)

        case .judge(let judge):
            try save(judge)
            return session

        case .key(let present):
            hasKey = present
            return session

        case .carry(let carry):
            guard case .carryCard(let front, _, _) = try mode(session), front == carry.taskID,
                let task = try tasks().first(where: { $0.id == front })
            else { throw SimRunner.notAllowed(event) }
            let answerInput = try input(session)
            let batch: StoreBatch
            do {
                batch = try CarryAnswer.apply(carry.answer, task: task, today: today, input: answerInput)
            } catch {
                switch error {
                case .dateNotAfterToday:
                    throw SimError(kind: .outOfRange, seq: event.seq, message: "date가 오늘보다 뒤가 아니다")
                case .notOnCard:
                    throw SimRunner.notAllowed(event)
                }
            }
            try apply(batch)
            return try settle(session)

        case .budget(let minutes):
            guard try mode(session) == .askBudget else { throw SimRunner.notAllowed(event) }
            day.budget = .answered(day: today, minutes: minutes)
            return try settle(session)

        case .more:
            guard try mode(session) == .dayEnd else { throw SimRunner.notAllowed(event) }
            day.budget = day.budget?.withMore()
            return try settle(session)
        }
    }

    /// 출력·불변식이 읽는 이월·가용 시간 상태.
    func schedule(_ session: NotchSession?) throws(SimError) -> SimSchedule {
        SimSchedule(mode: try mode(session), budget: day.budget, today: today)
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

    private static let fakeProvider = "fake"
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

    /// 앱 시작: 메모리 상태를 버리고 R-111 복구 → 활성화(하루 판정 → 이월 판정 → 모드 → 고르기, data-model §15).
    private mutating func launch() throws(SimError) -> NotchSession {
        day.revertedIDs = try SimRunner.storing(seq: event.seq) {
            try SessionAssembly.recover(try repository.tasks(), keeping: nil, in: repository, reload: repository.tasks)
        }
        return try activate(.initial)
    }

    private mutating func activate(_ session: NotchSession) throws(SimError) -> NotchSession {
        let input = try input(session)
        let activated = try SimRunner.storing(seq: event.seq) {
            try SessionAssembly.activate(
                session, input, dayStart: dayStart, schedule: try schedule(), in: repository,
                reload: repository.tasks)
        }
        if let schedule = activated.schedule {
            day.revertedIDs = schedule.revertedIDs
        }
        return activated.session
    }

    private func schedule() throws(SimError) -> SessionAssembly.Schedule? {
        guard day.scheduled else { return nil }
        return SessionAssembly.Schedule(
            today: today, budget: day.budget,
            carryJudgedAt: try SimRunner.storing(seq: event.seq) { try repository.lastCarryJudgment() },
            revertedIDs: day.revertedIDs)
    }

    /// 꺼짐이면 늘 세션. 켜짐이면 data-model §12 표.
    private func mode(_ session: NotchSession?) throws(SimError) -> NotchMode {
        guard let schedule = try schedule() else { return .session }
        return SessionAssembly.mode(session?.timer ?? .empty(draft: nil), tasks: try tasks(), schedule: schedule)
    }

    /// 버튼 처리 뒤: 모드 판정 → 카드·질문·오늘 끝이면 초안을 비우고, 세션이면 빈 상태에서 고른다(data-model §12).
    private func settle(_ session: NotchSession) throws(SimError) -> NotchSession {
        SessionAssembly.settle(session, try input(session), schedule: try schedule())
    }

    /// 작업 시간을 시작한 하루. 도는 중·시간 끝이 아니면 오늘.
    private func budgetDay(_ session: NotchSession) -> LocalDay {
        session.run?.budgetDay ?? today
    }

    private func expiredChip(_ session: NotchSession) -> Int {
        guard day.scheduled else { return extendMin }
        return QuantumChip.expiredChip(
            extendMin: extendMin,
            remainingMinutes: DayBudget.capMinutes(DayBudget.record(day.budget, for: budgetDay(session))))
    }

    private mutating func use(_ budgetUse: BudgetUse?) {
        guard let budgetUse else { return }
        day.budget = day.budget?.applying(budgetUse)
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
            timerEvent, at: event.at, defaultQuantumMin: defaultQuantumMin, extendMin: extendMin)
        {
            throw SimRunner.rejection(reason, event: event)
        }
    }

    /// 버튼 동작. 거부는 종료 코드 2, 쓰기는 `SessionCommit`. 커밋한 뒤 쓴 시간을 그 하루 기록에 반영한다.
    private mutating func commit(_ action: () throws(SessionError) -> SessionStep) throws(SimError) -> NotchSession {
        let step: SessionStep
        do {
            step = try action()
        } catch {
            throw SimRunner.notAllowed(event)
        }
        let next = try SimRunner.storing(seq: event.seq) {
            try SessionAssembly.commit(step, in: repository, settings: settings, reload: repository.tasks)
        }
        use(step.budgetUse)
        return next
    }

    private func apply(_ batch: StoreBatch) throws(SimError) {
        try SimRunner.storing(seq: event.seq) { try repository.apply(batch) }
    }

    private func tasks() throws(SimError) -> [MokaTask] {
        try SimRunner.storing(seq: event.seq) { try repository.tasks() }
    }

    /// 앱 `AppState.input(at:)`처럼 키 유무로 거른 판단 결과를 넘긴다. 하루·워밍업은 늘, 칩 상한과 시간 끝 겹침은
    /// 켜짐일 때만 채운다.
    func input(_ session: NotchSession?) throws(SimError) -> SessionInput {
        let stored = try SimRunner.storing(seq: event.seq) { try scores.scores() }
        var input = SessionInput(
            tasks: try tasks(), now: event.at, defaultQuantumMin: defaultQuantumMin,
            extendMin: session.map(expiredChip) ?? extendMin, calendar: calendar,
            scoring: SessionScoring(
                usable: ScoreRules.usable(
                    scores: stored, hasKey: hasKey, questionVersion: questions.version, provider: Self.fakeProvider),
                questions: questions, thresholds: questions.thresholds(for: SimRunner.fakeBaseModel), today: today),
            today: today, isWarmup: CoreSettings.readLastStartDay(from: settings) != today)
        if day.scheduled {
            input.draftChipCap = DayBudget.capMinutes(DayBudget.record(day.budget, for: today))
            if let session {
                var ticked = session.timer
                _ = ticked.apply(.tick, at: event.at, defaultQuantumMin: defaultQuantumMin, extendMin: extendMin)
                input.dayEndExpired = NotchMode.expiredDayEnd(
                    timer: ticked, budgetDayRecord: DayBudget.record(day.budget, for: budgetDay(session)))
            }
        }
        return input
    }
}
