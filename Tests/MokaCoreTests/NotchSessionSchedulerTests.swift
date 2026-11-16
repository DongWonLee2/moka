import Foundation
import MokaCore
import Testing

// spec 005 data-model §5·§6·§10~§12·§16, research R10·R11·R12·R15. 주입한 시각만 쓴다. 가짜 할 일만 쓴다.

private let questions = try! QuestionSet.bundled()
private let jev = ModelThresholds(concrete: 0.5, avoiding: 0.7)
private let day13 = Fake.day("2027-01-13")
private let day14 = Fake.day("2027-01-14")

private func score(_ id: TaskID, urgency: Double, concrete: Double = 0.5) -> TaskScore {
    TaskScore(
        taskID: id, questionVersion: questions.version, provider: "fake", modelSnapshot: nil, urgency: urgency,
        impact: 0, concrete: concrete, avoiding: 0.1, probsJSON: "{}", stateHash: "0123456789abcdef",
        scoredAt: Fake.noon)
}

/// 앱·`moka-sim`이 하는 순서를 그대로 따라 하는 호출자(data-model §11·§12·§15). 저장소는 메모리 저장소다.
private struct Caller {
    var session = NotchSession.initial
    let repository: any TaskRepository
    var budget: DayBudget?
    var lastStartDay: LocalDay?
    var now: Date
    var usable: [TaskID: TaskScore] = [:]
    var defaultMin = 25
    let extendMin = 10

    init(_ repository: any TaskRepository, at now: Date, budget: DayBudget? = nil, lastStartDay: LocalDay? = nil) {
        self.repository = repository
        self.now = now
        self.budget = budget
        self.lastStartDay = lastStartDay
    }

    var today: LocalDay { DayBoundary.day(containing: now, dayStart: Fake.sixAM, calendar: Fake.seoul) }
    var tasks: [MokaTask] { (try? repository.tasks()) ?? [] }
    var budgetDay: LocalDay { session.run?.budgetDay ?? today }
    /// 가용 시간 기록을 쓰지 않는 호출자(기록 없음)는 늘 세션이다.
    var mode: NotchMode {
        guard budget != nil else { return .session }
        return NotchMode.of(storageAvailable: true, timer: ticked, tasks: tasks, budget: budget, today: today)
    }
    var ticked: NotchTimer {
        var timer = session.timer
        _ = timer.apply(.tick, at: now, defaultQuantumMin: defaultMin, extendMin: extendChip)
        return timer
    }
    var extendChip: Int {
        QuantumChip.expiredChip(
            extendMin: extendMin, remainingMinutes: DayBudget.capMinutes(DayBudget.record(budget, for: budgetDay)))
    }
    var chip: Int? {
        if case .empty(.some(let draft)) = session.timer { return draft.chipMin }
        return nil
    }

    func input() -> SessionInput {
        var input = Fake.input(tasks, now: now, defaultQuantumMin: defaultMin, extendMin: extendChip)
        input.scoring = SessionScoring(usable: usable, questions: questions, thresholds: jev, today: today)
        input.today = today
        input.isWarmup = lastStartDay != today
        input.draftChipCap = DayBudget.capMinutes(DayBudget.record(budget, for: today))
        input.dayEndExpired = NotchMode.expiredDayEnd(
            timer: ticked, budgetDayRecord: DayBudget.record(budget, for: budgetDay))
        return input
    }

    /// 모드 판정 → 카드·질문·오늘 끝이면 초안 비움, 세션이면 고르기.
    mutating func settle() {
        let mode = self.mode
        if mode.clearsDraft {
            session = session.clearingDraft()
        } else if mode == .session {
            session = session.picked(input())
        }
    }

    /// 버튼: 커밋 → 남은 초 돌려주기 → 모드 판정 → 고르기(data-model §12 순서).
    mutating func press(_ action: (NotchSession, SessionInput) throws(SessionError) -> SessionStep) throws {
        let step = try action(session, input())
        session = try SessionCommit.commit(step, to: repository)
        if let use = step.budgetUse { budget = budget?.applying(use) }
        settle()
    }

    mutating func choose(_ minutes: Int) {
        _ = session.timer.apply(.chooseQuantum(minutes), at: now, defaultQuantumMin: defaultMin, extendMin: extendChip)
    }

    /// 시작 전 화면의 시작. 칩이 남은 분보다 길면 늘리기 확인을 받아야 한다(`extend`).
    mutating func start(extend: Bool = false) throws {
        if let needed = QuantumChip.extendNeeded(
            chipMin: chip ?? 0, remainingMinutes: DayBudget.capMinutes(DayBudget.record(budget, for: today)))
        {
            guard extend else { throw SessionError.notAllowed }
            budget = budget?.extended(by: needed)
        }
        let startDay = today
        try press { (session, input) throws(SessionError) in try session.start(input) }
        lastStartDay = startDay
    }

    mutating func advance(minutes: Int) {
        now += TimeInterval(minutes * 60)
    }
}

private func repository(_ tasks: [NewTask]) throws -> InMemoryTaskRepository {
    let repository = InMemoryTaskRepository()
    for task in tasks {
        _ = try repository.insertTask(task, cycleDay: nil, at: Fake.noon)
    }
    return repository
}

private func fakes(_ count: Int, est: Int? = nil) -> [NewTask] {
    (1...count).map { NewTask(title: "가짜 할 일 \($0)", deadline: nil, estMin: est, recurrence: .none, weekday: nil) }
}

private func complete(_ session: NotchSession, _ input: SessionInput) throws(SessionError) -> SessionStep {
    try session.complete(nil, input)
}

private func skip(_ session: NotchSession, _ input: SessionInput) throws(SessionError) -> SessionStep {
    try session.skip(.empty, input)
}

private func switchTask(_ session: NotchSession, _ input: SessionInput) throws(SessionError) -> SessionStep {
    try session.switchTask(.empty, input)
}

@Suite struct NotchSessionSchedulerPickTests {
    @Test("FR-05 R-403 R-411: 빈 상태 고르기는 가중 순환이고, 버튼 줄의 scheduler_choice는 weighted_rotate_v1")
    func rotateNameOnLine() throws {
        var caller = Caller(try repository(fakes(3)), at: Fake.noon, lastStartDay: day13)
        caller.settle()
        #expect(caller.session.memory.pickedBy == .weightedRotateV1)
        try caller.start()
        caller.advance(minutes: 1)
        try caller.press(skip)
        #expect(try caller.repository.decisions().last?.schedulerChoice == .weightedRotateV1)
    }

    @Test("FR-05 R-403 R-408: 바꾸기·미루기 뒤 방금 할 일은 다음 고르기에서 빠지고, 앞 셋이 순위 몫 5:3:2로 뜬다")
    func excludedAfterSetAside() throws {
        var caller = Caller(try repository(fakes(4)), at: Fake.noon, lastStartDay: day13)
        caller.settle()
        var shown: [TaskID] = []
        for index in 0..<20 {
            let current = try #require(caller.session.taskID)
            shown.append(current)
            try caller.start()
            caller.advance(minutes: 1)
            try caller.press(index.isMultiple(of: 2) ? skip : switchTask)
            #expect(caller.session.taskID != current)
        }
        let tally = shown.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        #expect(tally[4] == nil)
        #expect(tally[1]! > tally[2]!)
        #expect(tally[2]! > tally[3]!)
    }

    @Test("FR-05 R-408: 완료 뒤에는 뺄 할 일이 없다")
    func completeHasNoExcluded() throws {
        var caller = Caller(try repository(fakes(2)), at: Fake.noon, lastStartDay: day13)
        caller.settle()
        try caller.start()
        try caller.press(complete)
        #expect(caller.session.previousTaskID == nil)
        #expect(caller.session.taskID == 2)
    }

    @Test("FR-05 R-406 R-411: 하루 첫 고르기는 워밍업이고, 다른 할 일로 바꿔도 이름은 warmup_v1")
    func warmupKeepsNameThroughOtherTask() throws {
        var caller = Caller(try repository(fakes(3, est: 20)), at: Fake.noon)
        caller.usable = [1: score(1, urgency: 0.9), 2: score(2, urgency: 0.5, concrete: 0.9), 3: score(3, urgency: 0.1)]
        caller.settle()
        #expect(caller.session.taskID == 2)
        #expect(caller.session.memory.pickedBy == .warmupV1)
        caller.session = caller.session.chosenDraft(3, caller.input())
        #expect(caller.session.taskID == 3)
        try caller.start()
        caller.advance(minutes: 1)
        try caller.press(switchTask)
        #expect(try caller.repository.decisions().last?.schedulerChoice == .warmupV1)
        #expect(caller.session.memory.pickedBy == .weightedRotateV1)
    }

    @Test("FR-05 R-411 research R12: 빠른 입력으로 바로 초안이 된 할 일은 앞 이름, 없으면 weighted_rotate_v1")
    func quickInputName() throws {
        let input = Fake.input([Fake.task(1)])
        let added = NotchSession.initial.addedTask(Fake.task(1), input)
        #expect(added.memory.pickedBy == .weightedRotateV1)
        var warm = NotchSession.initial
        warm.memory.pickedBy = .warmupV1
        warm = warm.addedTask(Fake.task(1), input)
        #expect(warm.addedTask(Fake.task(2), Fake.input([Fake.task(1), Fake.task(2)])).memory.pickedBy == .warmupV1)
    }

    @Test("FR-05 R-406: 같은 하루에 시작한 적이 있으면 워밍업 없이 가중 순환")
    func noWarmupAfterStart() throws {
        var caller = Caller(try repository(fakes(2, est: 20)), at: Fake.noon, lastStartDay: day13)
        caller.usable = [1: score(1, urgency: 0.9), 2: score(2, urgency: 0.5, concrete: 0.9)]
        caller.settle()
        #expect(caller.session.taskID == 1)
        #expect(caller.session.memory.pickedBy == .weightedRotateV1)
    }

    @Test("FR-05 R-403: 하루가 바뀐 뒤 첫 고르기는 몫 상태를 비운다")
    func newDayClearsCredits() throws {
        var caller = Caller(try repository(fakes(3)), at: Fake.noon, lastStartDay: day13)
        caller.settle()
        #expect(caller.session.memory.memoryDay == day13)
        #expect(!caller.session.memory.credits.isEmpty)
        caller.session = caller.session.clearingDraft()
        caller.now = Fake.at(2027, 1, 14, 7, 0)
        caller.lastStartDay = day14
        caller.settle()
        #expect(caller.session.memory.memoryDay == day14)
        #expect(caller.session.memory.credits == [1: -5, 2: 3, 3: 2])
    }

    @Test("FR-08 R-417: 진행 중 완료는 이월 답 대기 표시를 지우고, 미루기·바꾸기는 그대로 둔다")
    func completeClearsDue() throws {
        var drafted = NotchSession.initial.picked(Fake.input([Fake.task(1)]))
        let start = try drafted.start(Fake.input([Fake.task(1)]))
        drafted = start.session
        let running = [Fake.task(1, status: .active, dueDecision: true)]
        let done = try drafted.complete(nil, Fake.input(running, now: Fake.noon + 60))
        #expect(done.batch.updatedTasks.first?.dueDecision == false)
        let skipped = try drafted.skip(.empty, Fake.input(running, now: Fake.noon + 60))
        #expect(skipped.batch.updatedTasks.first?.dueDecision == true)
    }

    @Test("FR-10 R-422 research R11: 오늘 끝과 겹친 시간 끝의 세 버튼은 체크포인트 계기 day_end, 아니면 quantum")
    func dayEndTrigger() throws {
        let drafted = NotchSession.initial.picked(Fake.input([Fake.task(1)]))
        let running = try drafted.start(Fake.input([Fake.task(1)])).session
        let active = [Fake.task(1, status: .active)]
        let late = Fake.noon + 26 * 60
        var ended = Fake.input(active, now: late)
        ended.dayEndExpired = true
        let plain = Fake.input(active, now: late)
        #expect(try complete(running, ended).batch.newCheckpoints.map(\.trigger) == [.dayEnd])
        #expect(try skip(running, ended).batch.newCheckpoints.map(\.trigger) == [.dayEnd])
        #expect(try switchTask(running, ended).batch.newCheckpoints.map(\.trigger) == [.dayEnd])
        #expect(try complete(running, plain).batch.newCheckpoints.map(\.trigger) == [.quantum])
        #expect(try skip(running, plain).batch.newCheckpoints.map(\.trigger) == [.quantum])
        #expect(try switchTask(running, plain).batch.newCheckpoints.map(\.trigger) == [.quantum])
    }

    @Test("FR-05 R-404 R-407: N분 더는 고르기가 아니라 최근 고르기를 바꾸지 않는다")
    func restartKeepsRecentPicks() throws {
        var caller = Caller(try repository(fakes(2)), at: Fake.noon, lastStartDay: day13)
        caller.settle()
        try caller.start()
        let before = caller.session.memory
        caller.advance(minutes: 26)
        try caller.press { (session, input) throws(SessionError) in try session.restart(.empty, quantumMin: 10, input) }
        #expect(caller.session.memory == before)
    }

    @Test("FR-01 R-434 research R15: 다음 표시는 초안이면 그 할 일, 도는 중이면 상태를 바꾸지 않고 미리 돌린 다음 고르기")
    func nextMark() throws {
        var caller = Caller(try repository(fakes(3)), at: Fake.noon, lastStartDay: day13)
        caller.settle()
        #expect(caller.session.nextMark(caller.input()) == 1)
        try caller.start()
        let before = caller.session
        #expect(caller.session.nextMark(caller.input()) == 2)
        #expect(caller.session == before)
        try caller.press(complete)
        #expect(caller.session.taskID == 2)
        #expect(NotchSession.initial.nextMark(caller.input()) == nil)
    }

    @Test("FR-08 R-413: 초안 비우기는 할 일과 이름을 내리고 커서는 둔다")
    func clearingDraft() {
        var session = NotchSession.initial.picked(Fake.input(Fake.todos(1...2)))
        session.previousTaskID = 2
        let cleared = session.clearingDraft()
        #expect(cleared.timer == .empty(draft: nil))
        #expect(cleared.taskID == nil)
        #expect(cleared.previousTaskID == 2)
        #expect(cleared.memory.pickedBy == nil)
        #expect(cleared.memory.credits == session.memory.credits)
    }
}

@Suite struct NotchSessionBudgetTests {
    @Test("FR-10 R-420 R-421 SC-405: 가용 2시간에서 끝까지 이어 돌리면 시작 칩은 남은 분 이하, 쓴 시간은 120분 이하, 닿으면 오늘 끝")
    func twoHours() throws {
        var caller = Caller(
            try repository(fakes(6)), at: Fake.noon, budget: .answered(day: day13, minutes: 120), lastStartDay: day13)
        caller.settle()
        var chips: [Int] = []
        while let chip = caller.chip {
            #expect(chip <= caller.budget!.remainingMinutes)
            chips.append(chip)
            try caller.start()
            #expect(caller.budget!.usedSeconds <= caller.budget!.minutes * 60)
            caller.advance(minutes: chip)
            try caller.press(complete)
        }
        #expect(chips == [25, 25, 25, 25, 20])
        #expect(caller.budget?.usedSeconds == 7200)
        #expect(caller.mode == .dayEnd)
        #expect(caller.session.timer == .empty(draft: nil))
    }

    @Test("FR-10 R-420 SC-405: 버튼 처리 순서 — 60분을 10분에 완료하면 돌려주기가 모드 판정보다 먼저라 오늘 끝이 아니다")
    func refundBeforeMode() throws {
        var caller = Caller(
            try repository(fakes(2)), at: Fake.noon, budget: .answered(day: day13, minutes: 60), lastStartDay: day13)
        caller.defaultMin = 60
        caller.settle()
        try caller.start()
        #expect(caller.budget?.usedSeconds == 3600)
        caller.advance(minutes: 10)
        try caller.press(complete)
        #expect(caller.budget?.usedSeconds == 600)
        #expect(caller.mode == .session)
        #expect(caller.session.taskID == 2)
        #expect(caller.chip == 50)
    }

    @Test("FR-10 R-420: 도는 중 미루기·바꾸기는 남은 초를 돌려주고, 시간 끝까지 간 작업 시간은 돌려줄 것이 없다")
    func refundOnSetAside() throws {
        var caller = Caller(
            try repository(fakes(2)), at: Fake.noon, budget: .answered(day: day13, minutes: 120), lastStartDay: day13)
        caller.settle()
        try caller.start()
        caller.advance(minutes: 5)
        try caller.press(skip)
        #expect(caller.budget?.usedSeconds == 300)
        try caller.start()
        caller.advance(minutes: 30)
        try caller.press(switchTask)
        #expect(caller.budget?.usedSeconds == 300 + 1500)
    }

    @Test("FR-10 R-420: 도는 중 종료는 남은 초를 돌려주고, 잠자기는 돌려주지 않는다")
    func quitRefundsSleepDoesNot() throws {
        let drafted = NotchSession.initial.picked(Fake.input([Fake.task(1)]))
        var start = Fake.input([Fake.task(1)])
        start.today = day13
        let step = try drafted.start(start)
        #expect(step.budgetUse == BudgetUse(day: day13, seconds: 1500))
        let later = Fake.input([Fake.task(1, status: .active)], now: Fake.noon + 600)
        #expect(step.session.lifecycleRefund(.quit, later) == BudgetUse(day: day13, seconds: -900))
        #expect(step.session.lifecycleRefund(.sleep, later) == nil)
        let expired = Fake.input([Fake.task(1, status: .active)], now: Fake.noon + 1600)
        #expect(step.session.lifecycleRefund(.quit, expired) == nil)
    }

    @Test("FR-10 R-421 US3-2a: 110분 쓴 뒤 25분 칩이면 늘리고 시작 — 가용 135분, 25분 시작")
    func extendAndStart() throws {
        var caller = Caller(
            try repository(fakes(2)), at: Fake.noon,
            budget: DayBudget(day: day13, minutes: 120, extendedMinutes: 0, usedSeconds: 6600, more: false),
            lastStartDay: day13)
        caller.settle()
        #expect(caller.chip == 10)
        caller.choose(25)
        #expect(throws: SessionError.notAllowed) { try caller.start() }
        try caller.start(extend: true)
        #expect(caller.budget?.minutes == 135)
        #expect(caller.budget?.extendedMinutes == 15)
        #expect(caller.budget?.usedSeconds == 8100)
        #expect(caller.session.run?.quantumMin == 25)
    }

    @Test("FR-10 R-421: 늘리지 않으면 칩을 남은 분으로 되돌리고 시작하지 않는다")
    func keepRemaining() throws {
        var caller = Caller(
            try repository(fakes(2)), at: Fake.noon,
            budget: DayBudget(day: day13, minutes: 120, extendedMinutes: 0, usedSeconds: 6600, more: false),
            lastStartDay: day13)
        caller.settle()
        caller.choose(25)
        caller.choose(caller.budget!.remainingMinutes)
        #expect(caller.chip == 10)
        #expect(caller.session.run == nil)
        #expect(caller.budget?.minutes == 120)
    }

    @Test("FR-10 R-421: 늘리기는 됐는데 시작 커밋이 실패하면 늘린 가용 시간은 남고 다음 시작은 확인 없이 바로")
    func extendThenStartFails() throws {
        let failing = FailingTaskRepository()
        _ = try failing.inner.insertTask(fakes(1)[0], cycleDay: nil, at: Fake.noon)
        var caller = Caller(
            failing, at: Fake.noon,
            budget: DayBudget(day: day13, minutes: 120, extendedMinutes: 0, usedSeconds: 6600, more: false),
            lastStartDay: day13)
        caller.settle()
        caller.choose(25)
        #expect(throws: FailingTaskRepository.Failure.self) { try caller.start(extend: true) }
        #expect(caller.budget?.minutes == 135)
        #expect(caller.session.run == nil)
        #expect(QuantumChip.extendNeeded(chipMin: 25, remainingMinutes: caller.budget?.remainingMinutes) == nil)
    }

    @Test("FR-10 R-422 US3-4a·4b SC-405: 시간 끝에 가용 시간이 닿으면 미루기 계기는 day_end, 그 뒤 고르기 0번이고 오늘 끝")
    func expiredDayEnd() throws {
        var caller = Caller(
            try repository(fakes(2)), at: Fake.noon,
            budget: DayBudget(day: day13, minutes: 120, extendedMinutes: 0, usedSeconds: 6600, more: false),
            lastStartDay: day13)
        caller.settle()
        try caller.start()
        caller.advance(minutes: 10)
        #expect(caller.input().dayEndExpired)
        try caller.press(skip)
        #expect(try caller.repository.checkpoints().last?.trigger == .dayEnd)
        #expect(caller.mode == .dayEnd)
        #expect(caller.session.taskID == nil)
    }

    @Test("FR-10 R-422 US3-5: 더 할래요 뒤에는 상한 없이 고른다")
    func more() throws {
        var caller = Caller(
            try repository(fakes(2)), at: Fake.noon,
            budget: DayBudget(day: day13, minutes: 60, extendedMinutes: 0, usedSeconds: 3600, more: false),
            lastStartDay: day13)
        caller.settle()
        #expect(caller.mode == .dayEnd)
        caller.budget = caller.budget?.withMore()
        caller.settle()
        #expect(caller.chip == 25)
    }

    @Test("FR-10 R-420 R-421 R-406 research R10: 하루 경계를 넘긴 작업 시간과 N분 더는 시작한 하루에 들고, 다음 첫 고르기는 워밍업")
    func boundaryRun() throws {
        var caller = Caller(
            try repository(fakes(2, est: 20)), at: Fake.at(2027, 1, 14, 5, 55),
            budget: DayBudget(day: day13, minutes: 120, extendedMinutes: 0, usedSeconds: 6000, more: false),
            lastStartDay: day13)
        caller.usable = [1: score(1, urgency: 0.1, concrete: 0.9), 2: score(2, urgency: 0.9, concrete: 0.9)]
        caller.settle()
        caller.choose(10)
        try caller.start()
        #expect(caller.session.run?.budgetDay == day13)
        caller.advance(minutes: 11)
        #expect(caller.today == day14)
        #expect(caller.extendChip == 10)
        try caller.press { (session, input) throws(SessionError) in try session.restart(.empty, quantumMin: 10, input) }
        #expect(caller.session.run?.budgetDay == day13)
        #expect(caller.budget?.usedSeconds == 7200)
        #expect(caller.lastStartDay == day13)
        caller.advance(minutes: 11)
        #expect(caller.input().dayEndExpired)
        try caller.press(complete)
        #expect(try caller.repository.checkpoints().last?.trigger == .dayEnd)
        #expect(caller.budget!.usedSeconds <= caller.budget!.minutes * 60)
        #expect(caller.mode == .askBudget)
        caller.budget = .answered(day: day14, minutes: 60)
        caller.settle()
        #expect(caller.session.memory.pickedBy == .warmupV1)
    }

    @Test("FR-10 R-421: 시작한 하루에 기록이 없거나 더 할래요였으면 하루 경계 뒤 N분 더에 상한이 없다")
    func boundaryWithoutCap() throws {
        var caller = Caller(try repository(fakes(1)), at: Fake.at(2027, 1, 14, 5, 55), lastStartDay: day13)
        caller.settle()
        try caller.start()
        caller.advance(minutes: 30)
        #expect(caller.extendChip == 10)
        #expect(!caller.input().dayEndExpired)
        caller.budget = DayBudget(day: day13, minutes: 60, extendedMinutes: 0, usedSeconds: 3600, more: true)
        #expect(!caller.input().dayEndExpired)
    }
}
