import Foundation
import MokaCore
import Testing

private final class WriteFailingSettings: SettingsStore {
    struct Failure: Error, Equatable {}
    func value(for key: String) throws -> String? { nil }
    func setValue(_ value: String, for key: String) throws { throw Failure() }
}

@Suite struct SessionAssemblyStoreTests {
    private static let noon = Fake.noon
    private static let today = Fake.day("2027-01-13")
    private static let nextMorning = Fake.at(2027, 1, 14, 7, 0)

    private static func repository(_ tasks: [NewTask]) throws -> InMemoryTaskRepository {
        let repository = InMemoryTaskRepository()
        for task in tasks { _ = try repository.insertTask(task, cycleDay: nil, at: Fake.at(2027, 1, 12, 12, 0)) }
        return repository
    }

    private static func task(_ title: String, deadline: String? = nil) -> NewTask {
        NewTask(title: title, deadline: deadline.map(Fake.day), estMin: nil, recurrence: .none, weekday: nil)
    }

    private static func dayInput(_ tasks: [MokaTask], now: Date = noon, today: LocalDay = today) -> SessionInput {
        var input = Fake.input(tasks, now: now)
        input.today = today
        return input
    }

    // MARK: - 이월 판정 경계(Q1-B, SC-406)

    @Test("FR-08 R-412 SC-406: 활성화의 이월 판정은 표시와 판정 시각을 할 일 저장소에 함께 쓴다")
    func activateWritesJudgmentThroughRepository() throws {
        let repository = try Self.repository([Self.task("가짜 마감 지난 할 일", deadline: "2027-01-10"), Self.task("가짜 할 일 B")])
        let schedule = SessionAssembly.Schedule(today: Self.today, budget: nil, revertedIDs: [])

        _ = try SessionAssembly.activate(
            .initial, Fake.input(try repository.tasks()), dayStart: Fake.sixAM, schedule: schedule, in: repository,
            reload: repository.tasks)

        #expect(try repository.tasks().map(\.dueDecision) == [true, false])
        #expect(try repository.lastCarryJudgment() == Self.noon)
    }

    @Test("FR-08 R-412 SC-406: 판정은 저장소의 지난 판정 시각을 읽어, 같은 하루에는 돌지 않고 다음 하루에 돈다")
    func judgeCarryReadsPreviousJudgment() throws {
        let repository = try Self.repository([Self.task("가짜 마감 지난 할 일", deadline: "2027-01-10")])
        try repository.applyCarryJudgment(.empty, judgedAt: Fake.at(2027, 1, 13, 7, 0))

        let sameDay = try SessionAssembly.judgeCarry(
            try repository.tasks(), revertedIDs: [], now: Self.noon, dayStart: Fake.sixAM, calendar: Fake.seoul,
            in: repository, reload: repository.tasks)
        #expect(sameDay == false)
        #expect(try repository.tasks().map(\.dueDecision) == [false])
        #expect(try repository.lastCarryJudgment() == Fake.at(2027, 1, 13, 7, 0))

        let nextDay = try SessionAssembly.judgeCarry(
            try repository.tasks(), revertedIDs: [], now: Self.nextMorning, dayStart: Fake.sixAM,
            calendar: Fake.seoul, in: repository, reload: repository.tasks)
        #expect(nextDay == true)
        #expect(try repository.tasks().map(\.dueDecision) == [true])
        #expect(try repository.lastCarryJudgment() == Self.nextMorning)
    }

    @Test("FR-08 R-412: 판정은 이번 앱 시작에서 되돌린 할 일을 손댄 할 일로 센다")
    func judgeCarryCountsRevertedTasks() throws {
        let repository = try Self.repository([Self.task("가짜 할 일 A"), Self.task("가짜 할 일 B")])
        let ran = try SessionAssembly.judgeCarry(
            try repository.tasks(), revertedIDs: [2], now: Self.noon, dayStart: Fake.sixAM, calendar: Fake.seoul,
            in: repository, reload: repository.tasks)
        #expect(ran)
        #expect(try repository.tasks().map(\.dueDecision) == [false, true])
    }

    @Test("FR-08 R-412 SC-406 FR-11 R-119: 판정 쓰기가 실패하면 같은 오류를 던지고 표시와 판정 시각이 둘 다 없다")
    func judgeCarryFailureLeavesNothing() throws {
        let repository = FailingTaskRepository()
        _ = try repository.inner.insertTask(
            Self.task("가짜 마감 지난 할 일", deadline: "2027-01-10"), cycleDay: nil, at: Fake.at(2027, 1, 12, 12, 0))

        #expect(throws: FailingTaskRepository.Failure()) {
            try SessionAssembly.judgeCarry(
                try repository.tasks(), revertedIDs: [], now: Self.noon, dayStart: Fake.sixAM, calendar: Fake.seoul,
                in: repository, reload: repository.tasks)
        }
        #expect(try repository.tasks().map(\.dueDecision) == [false])
        #expect(try repository.lastCarryJudgment() == nil)
    }

    // MARK: - 시작 커밋의 last_start_day(R-406)

    @Test("FR-05 R-406: 시작을 커밋하면 그 하루를 마지막 시작 하루로 쓴다")
    func startCommitWritesLastStartDay() throws {
        let repository = try Self.repository([Self.task("가짜 할 일 A")])
        let settings = InMemorySettingsStore()
        let drafted = NotchSession.initial.picked(Self.dayInput(try repository.tasks()))
        let step = try drafted.start(Self.dayInput(try repository.tasks()))

        let session = try SessionAssembly.commit(step, in: repository, settings: settings, reload: repository.tasks)

        #expect(session == step.session)
        #expect(CoreSettings.readLastStartDay(from: settings) == Self.today)
    }

    @Test("FR-05 R-406: 시간 끝의 \"N분 더\"는 시작이 아니라 마지막 시작 하루를 바꾸지 않는다")
    func restartCommitKeepsLastStartDay() throws {
        let repository = try Self.repository([Self.task("가짜 할 일 A")])
        let settings = InMemorySettingsStore()
        let drafted = NotchSession.initial.picked(Self.dayInput(try repository.tasks()))
        var running = try SessionAssembly.commit(
            try drafted.start(Self.dayInput(try repository.tasks())), in: repository, settings: settings,
            reload: repository.tasks)
        try CoreSettings.writeLastStartDay(Fake.day("2027-01-12"), to: settings)

        let later = Self.noon.addingTimeInterval(60 * 60)
        _ = running.timer.apply(.tick, at: later, defaultQuantumMin: 25, extendMin: 10)
        let step = try running.restart(
            .empty, quantumMin: 10, Self.dayInput(try repository.tasks(), now: later))
        _ = try SessionAssembly.commit(step, in: repository, settings: settings, reload: repository.tasks)

        #expect(CoreSettings.readLastStartDay(from: settings) == Fake.day("2027-01-12"))
    }

    @Test("FR-05 R-406: 마지막 시작 하루 쓰기가 실패해도 시작은 커밋되고 실패를 알린다")
    func lastStartDayWriteFailureDoesNotBlockStart() throws {
        let repository = try Self.repository([Self.task("가짜 할 일 A")])
        let drafted = NotchSession.initial.picked(Self.dayInput(try repository.tasks()))
        let step = try drafted.start(Self.dayInput(try repository.tasks()))
        var failures: [any Error] = []

        let session = try SessionAssembly.commit(
            step, in: repository, settings: WriteFailingSettings(), reload: repository.tasks,
            settingsFailed: { failures.append($0) })

        #expect(session == step.session)
        #expect(try repository.tasks().map(\.status) == [.active])
        #expect(failures.count == 1)
    }

    @Test("FR-05 R-406 FR-11 R-119: 시작 커밋이 실패하면 마지막 시작 하루를 쓰지 않는다")
    func failedStartCommitWritesNoLastStartDay() throws {
        let repository = FailingTaskRepository()
        _ = try repository.inner.insertTask(Self.task("가짜 할 일 A"), cycleDay: nil, at: Self.noon)
        let settings = InMemorySettingsStore()
        let drafted = NotchSession.initial.picked(Self.dayInput(try repository.tasks()))
        let step = try drafted.start(Self.dayInput(try repository.tasks()))

        #expect(throws: FailingTaskRepository.Failure()) {
            try SessionAssembly.commit(step, in: repository, settings: settings, reload: repository.tasks)
        }
        #expect(CoreSettings.readLastStartDay(from: settings) == nil)
    }
}
