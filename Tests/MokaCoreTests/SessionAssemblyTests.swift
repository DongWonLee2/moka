import Foundation
import MokaCore
import Testing

// #72 조립 순서(SessionAssembly). 앱과 moka-sim이 같이 부르는 켤 때 복구, 활성화, 버튼 뒤 순서. 가짜 할 일만 쓴다.

private final class ReloadCounter {
    let repository: any TaskRepository
    var count = 0

    init(_ repository: any TaskRepository) {
        self.repository = repository
    }

    func reload() throws -> [MokaTask] {
        count += 1
        return try repository.tasks()
    }
}

@Suite struct SessionAssemblyTests {
    private static let noon = Fake.noon
    private static let nextMorning = Fake.at(2027, 1, 14, 7, 0)

    private static func repository(_ tasks: [MokaTask]) throws -> InMemoryTaskRepository {
        let repository = try InMemoryTaskRepository.seeded(tasks.count)
        try repository.apply(
            StoreBatch(
                updatedTasks: zip(try repository.tasks(), tasks).map { stored, wanted in
                    var task = wanted
                    task.id = stored.id
                    task.title = stored.title
                    return task
                }))
        return repository
    }

    // MARK: - 켤 때 복구(R-111)

    @Test("FR-07 R-111: 노치의 할 일은 빼고 진행 중을 대기로 되돌려 쓰고 다시 읽은 뒤 되돌린 id를 돌려준다")
    func recoverRevertsExceptNotch() throws {
        let repository = try Self.repository([Fake.task(1, status: .active), Fake.task(2, status: .active)])
        let counter = ReloadCounter(repository)

        let revertedIDs = try SessionAssembly.recover(
            try repository.tasks(), keeping: 2, in: repository, reload: counter.reload)

        #expect(try repository.tasks().map(\.status) == [.todo, .active])
        #expect(revertedIDs == [1])
        #expect(counter.count == 1)
    }

    @Test("FR-07 R-111: 되돌릴 할 일이 없으면 쓰지 않고 다시 읽지 않는다")
    func recoverWritesNothingWhenNothingToRevert() throws {
        let repository = FailingTaskRepository()
        _ = try repository.inner.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: Self.noon)
        let counter = ReloadCounter(repository)
        let tasks = try repository.tasks()

        let revertedIDs = try SessionAssembly.recover(tasks, keeping: nil, in: repository, reload: counter.reload)

        #expect(revertedIDs.isEmpty)
        #expect(counter.count == 0)
    }

    @Test("FR-11 R-119: 복구 쓰기가 실패하면 같은 오류를 던지고 다시 읽지 않는다")
    func recoverRethrowsWriteFailure() throws {
        let repository = FailingTaskRepository()
        var active = try repository.inner.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: Self.noon)
        active.status = .active
        try repository.inner.apply(StoreBatch(updatedTasks: [active]))
        let counter = ReloadCounter(repository)

        #expect(throws: FailingTaskRepository.Failure()) {
            try SessionAssembly.recover(try repository.tasks(), keeping: nil, in: repository, reload: counter.reload)
        }
        #expect(counter.count == 0)
    }

    // MARK: - 활성화(하루 판정 → 이월 판정 → 고르기)

    @Test("FR-09 R-113: 하루 판정을 쓰고 다시 읽은 목록에서 고른다")
    func activateResetsThenPicks() throws {
        let repository = try Self.repository([
            Fake.task(1, status: .done, recurrence: .daily, cycleDay: Fake.day("2027-01-13"), streak: 1)
        ])
        let counter = ReloadCounter(repository)

        let activated = try SessionAssembly.activate(
            .initial, Fake.input(try repository.tasks(), now: Self.nextMorning), dayStart: Fake.sixAM, schedule: nil,
            in: repository, reload: counter.reload)

        #expect(try repository.tasks().map(\.status) == [.todo])
        #expect(activated.session.taskID == 1)
        #expect(activated.schedule == nil)
        #expect(counter.count == 1)
    }

    @Test("FR-11 R-119: 하루 판정 쓰기가 실패하면 같은 오류를 던지고 저장소를 그대로 둔다")
    func activateRethrowsResetFailure() throws {
        let repository = FailingTaskRepository()
        var daily = try repository.inner.insertTask(
            NewTask(title: "가짜 매일 할 일", deadline: nil, estMin: nil, recurrence: .daily, weekday: nil),
            cycleDay: Fake.day("2027-01-13"), at: Self.noon)
        daily.status = .done
        try repository.inner.apply(StoreBatch(updatedTasks: [daily]))
        let before = try repository.tasks()

        #expect(throws: FailingTaskRepository.Failure()) {
            try SessionAssembly.activate(
                .initial, Fake.input(before, now: Self.nextMorning), dayStart: Fake.sixAM, schedule: nil,
                in: repository, reload: repository.tasks)
        }
        #expect(try repository.tasks() == before)
    }

    @Test("spec 005 plan 단위 2: 하루 값이 없으면(앱) 이월 판정을 돌리지 않고 세션 모드로 고른다")
    func activateWithoutScheduleSkipsCarry() throws {
        let repository = try Self.repository([Fake.task(1, deadline: Fake.day("2027-01-10"))])

        let activated = try SessionAssembly.activate(
            .initial, Fake.input(try repository.tasks()), dayStart: Fake.sixAM, schedule: nil, in: repository,
            reload: repository.tasks)

        #expect(try repository.tasks().map(\.dueDecision) == [false])
        #expect(activated.session.taskID == 1)
    }

    @Test("R-412: 하루 값이 있으면 이월 판정을 쓰고 판정 시각을 남기며 되돌린 할 일 기억을 비운다. 카드 모드면 고르지 않는다")
    func activateWithScheduleRunsCarryThenClears() throws {
        let repository = try Self.repository([
            Fake.task(1, deadline: Fake.day("2027-01-10")), Fake.task(2), Fake.task(3),
        ])
        let schedule = SessionAssembly.Schedule(
            today: Fake.day("2027-01-13"), budget: nil, carryJudgedAt: nil, revertedIDs: [3])

        let activated = try SessionAssembly.activate(
            .initial, Fake.input(try repository.tasks()), dayStart: Fake.sixAM, schedule: schedule, in: repository,
            reload: repository.tasks)

        #expect(try repository.tasks().map(\.dueDecision) == [true, false, true])
        #expect(activated.schedule?.carryJudgedAt == Self.noon)
        #expect(activated.schedule?.revertedIDs == [])
        #expect(activated.session == .initial, "이월 카드가 뜨면 초안을 띄우지 않는다")
    }

    @Test("R-412: 같은 하루에 이미 판정했으면 이월 판정을 돌리지 않고 하루 값을 그대로 돌려준다")
    func activateSkipsCarryAlreadyJudgedToday() throws {
        let repository = try Self.repository([Fake.task(1, deadline: Fake.day("2027-01-10"))])
        let schedule = SessionAssembly.Schedule(
            today: Fake.day("2027-01-13"), budget: .answered(day: Fake.day("2027-01-13"), minutes: 120),
            carryJudgedAt: Fake.at(2027, 1, 13, 7, 0), revertedIDs: [1])

        let activated = try SessionAssembly.activate(
            .initial, Fake.input(try repository.tasks()), dayStart: Fake.sixAM, schedule: schedule, in: repository,
            reload: repository.tasks)

        #expect(try repository.tasks().map(\.dueDecision) == [false])
        #expect(activated.schedule == schedule)
        #expect(activated.session.taskID == 1)
    }

    @Test("R-412: 이월 대상이 없으면 표시 묶음을 쓰지 않고 판정 시각만 남긴다")
    func activateWritesNoCarryMarkingWhenNoTargets() throws {
        let repository = FailingTaskRepository()
        _ = try repository.inner.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: Self.noon)
        let schedule = SessionAssembly.Schedule(
            today: Fake.day("2027-01-13"), budget: .answered(day: Fake.day("2027-01-13"), minutes: 120),
            carryJudgedAt: nil, revertedIDs: [])

        let activated = try SessionAssembly.activate(
            .initial, Fake.input(try repository.tasks(), now: Self.nextMorning), dayStart: Fake.sixAM,
            schedule: schedule, in: repository, reload: repository.tasks)

        #expect(try repository.tasks().map(\.dueDecision) == [false])
        #expect(activated.schedule?.carryJudgedAt == Self.nextMorning)
    }

    @Test("FR-11 R-119: 이월 표시 쓰기가 실패하면 같은 오류를 던진다")
    func activateRethrowsCarryMarkingFailure() throws {
        let repository = FailingTaskRepository()
        _ = try repository.inner.insertTask(
            NewTask(
                title: "가짜 마감 지난 할 일", deadline: Fake.day("2027-01-10"), estMin: nil, recurrence: .none, weekday: nil),
            cycleDay: nil, at: Self.noon)
        let before = try repository.tasks()
        let schedule = SessionAssembly.Schedule(
            today: Fake.day("2027-01-13"), budget: nil, carryJudgedAt: nil, revertedIDs: [])

        #expect(throws: FailingTaskRepository.Failure()) {
            try SessionAssembly.activate(
                .initial, Fake.input(before), dayStart: Fake.sixAM, schedule: schedule, in: repository,
                reload: repository.tasks)
        }
        #expect(try repository.tasks() == before)
    }

    // MARK: - 버튼 뒤(커밋 → 다시 읽기), 모드 → 고르기

    @Test("FR-05 R-104: 커밋하고 다시 읽은 뒤 step의 세션을 돌려준다")
    func commitAppliesThenRereads() throws {
        let repository = try InMemoryTaskRepository.seeded(2)
        let counter = ReloadCounter(repository)
        let drafted = NotchSession.initial.picked(Fake.input(try repository.tasks()))
        let step = try drafted.start(Fake.input(try repository.tasks()))

        let session = try SessionAssembly.commit(step, in: repository, reload: counter.reload)

        #expect(session == step.session)
        #expect(try repository.tasks().map(\.status) == [.active, .todo])
        #expect(counter.count == 1)
    }

    @Test("FR-11 R-119: 커밋이 실패하면 같은 오류를 던지고 다시 읽지 않는다")
    func commitRethrowsFailure() throws {
        let repository = FailingTaskRepository()
        _ = try repository.inner.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: Self.noon)
        let counter = ReloadCounter(repository)
        let drafted = NotchSession.initial.picked(Fake.input(try repository.tasks()))
        let step = try drafted.start(Fake.input(try repository.tasks()))

        #expect(throws: FailingTaskRepository.Failure()) {
            try SessionAssembly.commit(step, in: repository, reload: counter.reload)
        }
        #expect(counter.count == 0)
    }

    @Test("data-model §12: 하루 값이 없으면 빈 상태에서 고르고, 가용 시간 질문 모드면 초안을 비운다")
    func settleFollowsMode() {
        let tasks = Fake.todos(1...2)
        let input = Fake.input(tasks)
        #expect(SessionAssembly.settle(.initial, input, schedule: nil).taskID == 1)

        let drafted = NotchSession.initial.picked(input)
        let asking = SessionAssembly.Schedule(
            today: Fake.day("2027-01-13"), budget: nil, carryJudgedAt: Self.noon, revertedIDs: [])
        #expect(SessionAssembly.mode(drafted.timer, tasks: tasks, schedule: asking) == .askBudget)
        #expect(SessionAssembly.settle(drafted, input, schedule: asking) == drafted.clearingDraft())
        #expect(SessionAssembly.mode(drafted.timer, tasks: tasks, schedule: nil) == .session)
    }
}
