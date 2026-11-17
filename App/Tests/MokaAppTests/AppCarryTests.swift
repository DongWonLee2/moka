import AppKit
import Foundation
import MokaCore
import XCTest

/// spec 005 단위 3: 이월 카드(US2, T026). 활성화가 이월 판정을 돌리고, 카드가 있으면 노치는 카드를 보인다.
/// 메모리 저장소와 주입한 시계만 쓴다. 가짜 할 일만 쓴다(ADR-0006).
@MainActor
final class AppCarryTests: XCTestCase {
    /// 할 일을 만든 때(어제, 2027-01-12 12:00).
    private static let created = AppTestFixture.at(2027, 1, 12, 12, 0)
    private static let jan13 = LocalDay(text: "2027-01-13")!
    private static let jan14 = LocalDay(text: "2027-01-14")!

    private static func insert(
        _ title: String, deadline: String? = nil, recurrence: Recurrence = .none, cycleDay: LocalDay? = nil,
        into repository: any TaskRepository
    ) throws -> MokaTask {
        try repository.insertTask(
            NewTask(
                title: title, deadline: deadline.flatMap(LocalDay.init(text:)), estMin: nil, recurrence: recurrence,
                weekday: nil),
            cycleDay: cycleDay, at: created)
    }

    /// 지금 노치 할 일을 시작하고 `minutes` 뒤 두 줄과 함께 미룬다.
    private static func startAndSkip(_ state: AppState, clock: TestClock, minutes: Int = 5, next: String = "") {
        state.start()
        clock.advance(minutes: minutes)
        state.beginSetAside(.skip)
        state.editNotes(NotesDraft(done: "", next: next))
        state.submitSetAside()
    }

    private struct Morning {
        let state: AppState
        let repository: InMemoryTaskRepository
        let clock: TestClock
        let settings: InMemorySettingsStore
    }

    /// US2-1 바탕: A(마감 없음)에 어제 판정 뒤 체크포인트, B는 마감이 어제, C는 손대지 않았고 마감이 다음 주.
    /// 첫날 정오에 켜서 판정하고 A를 미룬 뒤, 다음 날 07:00에 설정 창을 열어(활성화) 판정한다.
    private static func judgedNextMorning() throws -> Morning {
        let repository = InMemoryTaskRepository()
        _ = try insert("가짜 할 일 A", into: repository)
        _ = try insert("가짜 할 일 B", deadline: "2027-01-13", into: repository)
        _ = try insert("가짜 할 일 C", deadline: "2027-01-20", into: repository)
        let clock = TestClock(AppTestFixture.noon)
        let settings = InMemorySettingsStore()
        let state = makeState(repository, settings: settings, clock: clock)
        state.launch()
        state.chooseOtherTask(1)
        startAndSkip(state, clock: clock, next: "가짜 첫 행동")
        clock.advanceToNextDay(hour: 7)
        state.activate()
        return Morning(state: state, repository: repository, clock: clock, settings: settings)
    }

    // MARK: - US2-1, 7: 판정과 카드, 답하기 전에는 어디에도 뜨지 않음

    func test_FR08_R412_R413_R414_US2_1_cardHasTouchedAndOverdueOnly() throws {
        let morning = try Self.judgedNextMorning()
        let state = morning.state

        XCTAssertEqual(try morning.repository.tasks().map(\.dueDecision), [true, true, false])
        XCTAssertEqual(
            state.notchMode, .carryCard(taskID: 2, left: 2, reason: .overdue(days: 1)), "마감 지난 B가 먼저, 남은 개수는 지금 것 포함")
        XCTAssertEqual(state.timer, .empty(draft: nil), "카드가 있으면 초안을 비운다(R-413)")
        XCTAssertEqual(state.ranks, [3: 1], "순위는 이월 답 대기를 뺀 후보로 다시 센다")
        XCTAssertEqual(state.nextMarkID, 3)
        XCTAssertEqual(state.otherTaskItems.map(\.id), [3], "다른 할 일 목록에 이월 대상이 없다")

        XCTAssertTrue(state.answerCarry(.today, for: 2))
        XCTAssertEqual(state.notchMode, .carryCard(taskID: 1, left: 1, reason: .touched))
        XCTAssertEqual(state.carryCardTask?.firstAction, "가짜 첫 행동", "카드에 이어서 할 일이 함께 보인다")
        XCTAssertEqual(state.carryAnswered, 1)
    }

    func test_FR08_R413_SC403_dueTaskIsNotPickedWhileCardWaits() throws {
        let morning = try Self.judgedNextMorning()
        let state = morning.state
        XCTAssertTrue(state.addTask(NewTask(title: "가짜 할 일 D", deadline: nil, estMin: nil, recurrence: .none, weekday: nil)))
        XCTAssertEqual(state.timer, .empty(draft: nil), "카드가 떠 있는 동안 새 할 일이 들어와도 고르지 않는다")
        XCTAssertTrue(state.answerCarry(.today, for: 2))
        XCTAssertEqual(state.timer, .empty(draft: nil), "카드가 남아 있으면 고르지 않는다")
        XCTAssertFalse(state.ranks.keys.contains(1))
    }

    // MARK: - US2-2~4: 답 셋

    func test_FR08_R415_US2_2_todayRaisesCarryCountAndReturnsToCandidates() throws {
        let morning = try Self.judgedNextMorning()
        XCTAssertTrue(morning.state.answerCarry(.today, for: 2))
        let task = try XCTUnwrap(try morning.repository.tasks().first { $0.id == 2 })
        XCTAssertEqual(task.carryCount, 1)
        XCTAssertFalse(task.dueDecision)
        XCTAssertEqual(morning.state.ranks[2], 1, "B는 다시 후보")
    }

    func test_FR08_R415_US2_3_dropMakesTaskDropped() throws {
        let morning = try Self.judgedNextMorning()
        XCTAssertTrue(morning.state.answerCarry(.drop, for: 2))
        let task = try XCTUnwrap(try morning.repository.tasks().first { $0.id == 2 })
        XCTAssertEqual(task.status, .dropped)
        XCTAssertFalse(task.dueDecision)
    }

    func test_FR08_R415_US2_4_moveFromTomorrowSetsDeadlineAndKeepsCandidate() throws {
        let morning = try Self.judgedNextMorning()
        let state = morning.state
        state.beginCarryMove()
        XCTAssertEqual(state.carryMoveDay, LocalDay(text: "2027-01-15"), "날짜 고르기는 내일을 고른 채 열린다")
        state.pickCarryMoveDay(Self.jan14)
        XCTAssertEqual(state.carryMoveDay, LocalDay(text: "2027-01-15"), "오늘은 고를 수 없다")
        state.pickCarryMoveDay(LocalDay(text: "2027-01-17")!)
        XCTAssertEqual(state.carryMoveDay, LocalDay(text: "2027-01-17"))
        XCTAssertTrue(try morning.repository.decisions().allSatisfy { $0.userAction != .carryMove }, "고르기만으로는 쓰지 않는다")

        XCTAssertTrue(state.confirmCarryMove())

        let task = try XCTUnwrap(try morning.repository.tasks().first { $0.id == 2 })
        XCTAssertEqual(task.deadline, LocalDay(text: "2027-01-17"))
        XCTAssertEqual(task.carryCount, 0)
        XCTAssertFalse(task.dueDecision)
        XCTAssertNil(state.carryMoveDay)
        XCTAssertEqual(state.notchMode, .carryCard(taskID: 1, left: 1, reason: .touched))
        XCTAssertNotNil(state.ranks[2], "B는 오늘도 후보")
    }

    func test_FR08_R415_cancelMoveReturnsToCardWithoutWriting() throws {
        let morning = try Self.judgedNextMorning()
        let before = try morning.repository.decisions().count
        morning.state.beginCarryMove()
        morning.state.cancelCarryMove()
        XCTAssertNil(morning.state.carryMoveDay)
        XCTAssertEqual(try morning.repository.decisions().count, before)
        XCTAssertEqual(morning.state.notchMode, .carryCard(taskID: 2, left: 2, reason: .overdue(days: 1)))
    }

    func test_FR08_R412_answeringAllCardsPicksFromCandidates() throws {
        let morning = try Self.judgedNextMorning()
        let state = morning.state
        XCTAssertTrue(state.answerCarry(.today, for: 2))
        XCTAssertTrue(state.answerCarry(.drop, for: 1))
        XCTAssertEqual(state.notchMode, .session)
        XCTAssertNotNil(state.session.taskID, "카드를 다 답하면 고른다")
        XCTAssertNotEqual(state.session.taskID, 1)
        XCTAssertEqual(state.carryAnswered, 0, "카드가 끝나면 답한 수를 비운다")
    }

    // MARK: - US2-5, 6, 6a: 다음 판정

    func test_FR08_R412_US2_5_6a_movedTaskReturnsOnlyAfterNewDeadlinePasses() throws {
        let morning = try Self.judgedNextMorning()
        let state = morning.state
        state.beginCarryMove()
        state.pickCarryMoveDay(LocalDay(text: "2027-01-17")!)
        XCTAssertTrue(state.confirmCarryMove())
        XCTAssertTrue(state.answerCarry(.today, for: 1))

        morning.clock.advanceToNextDay(hour: 7)  // 01-15
        state.activate()
        XCTAssertEqual(try morning.repository.tasks().map(\.dueDecision), [false, false, false], "손대지 않았고 마감 전")

        morning.clock.advanceToNextDay(hour: 7)  // 01-16
        morning.clock.advanceToNextDay(hour: 7)  // 01-17, 새 마감 날 아침은 지난 것이 아니다
        state.activate()
        XCTAssertFalse(try XCTUnwrap(try morning.repository.tasks().first { $0.id == 2 }).dueDecision)

        morning.clock.advanceToNextDay(hour: 7)  // 01-18
        state.activate()
        XCTAssertTrue(try XCTUnwrap(try morning.repository.tasks().first { $0.id == 2 }).dueDecision, "새 마감이 지나면 다시 카드")
    }

    func test_FR08_R412_US2_6_touchedOnJudgedDayAppearsAfterDaysAway() throws {
        let repository = InMemoryTaskRepository()
        _ = try Self.insert("가짜 할 일 A", into: repository)
        _ = try Self.insert("가짜 할 일 B", into: repository)
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(repository, clock: clock)
        state.launch()
        Self.startAndSkip(state, clock: clock)
        let touched = try XCTUnwrap(try repository.checkpoints().first).taskID

        for _ in 0..<3 { clock.advanceToNextDay(hour: 7) }  // 01-16, 사흘 켜지 않음
        state.activate()

        XCTAssertEqual(try repository.tasks().filter(\.dueDecision).map(\.id), [touched], "어제가 아니라 지난 판정 뒤로 본다")
    }

    // MARK: - US2-6b, 6c: 하루 경계에 진행 중

    /// 첫날 판정 뒤 다음 날 `hour`:`minute`(하루 시작 06:00 전)까지 시계를 보낸 상태.
    private static func beforeBoundary(hour: Int, minute: Int) throws -> (AppState, InMemoryTaskRepository, TestClock) {
        let repository = InMemoryTaskRepository()
        _ = try insert("가짜 할 일 D", into: repository)
        _ = try insert("가짜 할 일 E", into: repository)
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(repository, clock: clock)
        state.launch()
        clock.advanceToNextDay(hour: hour, minute: minute)
        return (state, repository, clock)
    }

    func test_FR08_R417_US2_6b_runningTaskKeepsRunningThenSkipShowsCard() throws {
        let (state, repository, clock) = try Self.beforeBoundary(hour: 5, minute: 50)
        let running = try XCTUnwrap(state.session.taskID)
        state.start()
        clock.advance(minutes: 15)  // 06:05
        state.setHovering(true)

        guard case .running = state.timer else { return XCTFail("도는 타이머는 끊지 않는다: \(state.timer)") }
        XCTAssertEqual(state.notchMode, .session)
        let marked = try XCTUnwrap(try repository.tasks().first { $0.id == running })
        XCTAssertEqual(marked.status, .active)
        XCTAssertTrue(marked.dueDecision, "진행 중 할 일에는 표시만 붙는다")

        state.beginSetAside(.skip)
        state.setAsideWithoutNotes()

        XCTAssertEqual(try XCTUnwrap(try repository.tasks().first { $0.id == running }).status, .todo)
        XCTAssertEqual(
            state.notchMode, .carryCard(taskID: running, left: 1, reason: .touched), "카드 없이 대기로 돌아온 할 일이 없다(SC-403)")
        XCTAssertEqual(state.timer, .empty(draft: nil))
    }

    func test_FR08_R417_US2_6b_completingRunningTaskClearsMark() throws {
        let (state, repository, clock) = try Self.beforeBoundary(hour: 5, minute: 50)
        let running = try XCTUnwrap(state.session.taskID)
        state.start()
        clock.advance(minutes: 15)
        state.setHovering(true)

        state.complete()

        let done = try XCTUnwrap(try repository.tasks().first { $0.id == running })
        XCTAssertEqual(done.status, .done)
        XCTAssertFalse(done.dueDecision)
        XCTAssertEqual(state.notchMode, .session)
        XCTAssertNotNil(state.session.taskID, "카드가 없으면 다음 할 일을 고른다")
    }

    func test_FR08_R417_US2_6c_expiredTaskRestartsThenSkipShowsCard() throws {
        let (state, repository, clock) = try Self.beforeBoundary(hour: 5, minute: 30)
        let expired = try XCTUnwrap(state.session.taskID)
        state.start()
        clock.advance(minutes: 35)  // 06:05, 05:55에 끝남
        state.tick()
        guard case .expired = state.timer else { return XCTFail("시간 끝이어야 한다: \(state.timer)") }
        state.setHovering(true)
        XCTAssertTrue(try XCTUnwrap(try repository.tasks().first { $0.id == expired }).dueDecision)

        state.start()
        guard case .running = state.timer else { return XCTFail("N분 더는 그대로 된다: \(state.timer)") }
        XCTAssertEqual(state.notchMode, .session, "다시 도는 동안 카드는 미룬다")

        clock.advance(minutes: 2)
        state.beginSetAside(.skip)
        state.setAsideWithoutNotes()
        XCTAssertEqual(state.notchMode, .carryCard(taskID: expired, left: 1, reason: .touched))
    }

    // MARK: - US2-6d와 되돌린 할 일(R-111 → 판정)

    /// 어제(2027-01-12) 07:00에 판정했고, 진행 중으로 남은 가짜 할 일 F 하나(체크포인트 없음).
    private static func leftActive(in repository: any TaskRepository, judgedAt: Date) throws {
        var task = try insert("가짜 할 일 F", into: repository)
        task.status = .active
        try repository.apply(StoreBatch(updatedTasks: [task]))
        try repository.applyCarryJudgment(.empty, judgedAt: judgedAt)
    }

    func test_FR08_R412_US2_6d_launchRevertsThenJudgesRevertedAsTouched() throws {
        let repository = CallRecordingRepository()
        try Self.leftActive(in: repository.inner, judgedAt: AppTestFixture.at(2027, 1, 12, 7, 0))
        let state = makeState(repository)

        state.launch()

        let task = try XCTUnwrap(try repository.tasks().first)
        XCTAssertEqual(task.status, .todo)
        XCTAssertTrue(task.dueDecision)
        XCTAssertEqual(state.notchMode, .carryCard(taskID: task.id, left: 1, reason: .touched))
        XCTAssertEqual(repository.calls, ["apply", "applyCarryJudgment"], "켤 때 복구 뒤에 이월 판정")
    }

    func test_FR08_R412_failedRecoveryRetriesBeforeJudgmentAtNextActivation() throws {
        let repository = CallRecordingRepository()
        try Self.leftActive(in: repository.inner, judgedAt: AppTestFixture.at(2027, 1, 12, 7, 0))
        let state = makeState(repository)
        repository.failsApply = true
        state.launch()
        XCTAssertEqual(repository.calls, ["apply"], "복구 쓰기가 실패하면 판정하지 않는다")

        repository.failsApply = false
        state.activate()

        XCTAssertEqual(repository.calls, ["apply", "apply", "applyCarryJudgment"])
        let task = try XCTUnwrap(try repository.tasks().first)
        XCTAssertEqual(task.status, .todo)
        XCTAssertTrue(task.dueDecision)
    }

    func test_FR08_R412_revertedStaysInMemoryUntilJudgmentWriteSucceeds() throws {
        let repository = CallRecordingRepository()
        try Self.leftActive(in: repository.inner, judgedAt: AppTestFixture.at(2027, 1, 12, 7, 0))
        let state = makeState(repository)
        repository.failsJudgment = true
        state.launch()
        XCTAssertEqual(try repository.tasks().map(\.status), [.todo])
        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [false], "판정 쓰기가 실패하면 표시가 없다")
        XCTAssertEqual(try repository.lastCarryJudgment(), AppTestFixture.at(2027, 1, 12, 7, 0))

        repository.failsJudgment = false
        state.activate()

        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [true], "되돌린 할 일은 다음 활성화의 재판정에도 든다")
    }

    func test_FR08_R412_sameDayRestartKeepsRevertedForNextBoundary() throws {
        let repository = InMemoryTaskRepository()
        try Self.leftActive(in: repository, judgedAt: AppTestFixture.at(2027, 1, 13, 7, 0))
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(repository, clock: clock)
        state.launch()
        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [false], "같은 하루라 판정하지 않는다")

        clock.advanceToNextDay(hour: 7)
        state.activate()

        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [true], "앱을 끄지 않고 하루를 넘기면 그 판정에 든다")
    }

    // MARK: - US2-8, 9, 10

    func test_FR08_R413_US2_8_restartShowsSameCardAgain() throws {
        let morning = try Self.judgedNextMorning()
        XCTAssertTrue(morning.state.answerCarry(.today, for: 2))
        let judgedAt = try morning.repository.lastCarryJudgment()

        let restarted = makeState(morning.repository, settings: morning.settings, clock: morning.clock)
        restarted.launch()

        XCTAssertEqual(restarted.notchMode, .carryCard(taskID: 1, left: 1, reason: .touched))
        XCTAssertEqual(try morning.repository.lastCarryJudgment(), judgedAt, "같은 하루라 다시 판정하지 않는다")
    }

    func test_FR08_R412_US2_9_recurringTaskResetsWithoutCard() throws {
        let repository = InMemoryTaskRepository()
        let daily = try Self.insert("가짜 매일 할 일", recurrence: .daily, cycleDay: Self.jan13, into: repository)
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(repository, clock: clock)
        state.launch()
        XCTAssertEqual(state.session.taskID, daily.id)
        Self.startAndSkip(state, clock: clock)

        clock.advanceToNextDay(hour: 7)
        state.activate()

        let reset = try XCTUnwrap(try repository.tasks().first)
        XCTAssertFalse(reset.dueDecision, "반복 할 일은 이월 대상이 아니다")
        XCTAssertEqual(reset.status, .todo)
        XCTAssertEqual(reset.cycleDay, Self.jan14)
        XCTAssertEqual(state.notchMode, .session)
    }

    func test_FR08_R416_US2_10_eachAnswerWritesOneLogLine() throws {
        let morning = try Self.judgedNextMorning()
        let before = try morning.repository.decisions().count
        XCTAssertTrue(morning.state.answerCarry(.today, for: 2))
        XCTAssertEqual(try morning.repository.decisions().count, before + 1)
        morning.state.beginCarryMove()
        XCTAssertTrue(morning.state.confirmCarryMove())
        let lines = try morning.repository.decisions().dropFirst(before)
        XCTAssertEqual(lines.map(\.userAction), [.carryToday, .carryMove])
        XCTAssertEqual(lines.map(\.schedulerChoice), [.carryCardV1, .carryCardV1])
    }

    // MARK: - 활성화 넷(R-412, research R11)

    /// 마감이 오늘(01-13)인 가짜 할 일 하나를 첫날 판정하고 다음 날 07:00으로 보낸 상태.
    private static func dueTomorrow(center: NotificationCenter = NotificationCenter()) throws -> (
        AppState, InMemoryTaskRepository
    ) {
        let repository = InMemoryTaskRepository()
        _ = try insert("가짜 할 일 B", deadline: "2027-01-13", into: repository)
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(repository, clock: clock, workspaceCenter: center)
        state.launch()
        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [false])
        clock.advanceToNextDay(hour: 7)
        return (state, repository)
    }

    func test_FR08_R412_launchJudges() throws {
        let repository = InMemoryTaskRepository()
        _ = try Self.insert("가짜 할 일 B", deadline: "2027-01-12", into: repository)
        let state = makeState(repository)
        state.launch()
        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [true])
        XCTAssertEqual(try repository.lastCarryJudgment(), AppTestFixture.noon)
    }

    func test_FR08_R412_wakeJudges() throws {
        let center = NotificationCenter()
        let (state, repository) = try Self.dueTomorrow(center: center)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [true])
        XCTAssertEqual(state.notchMode, .carryCard(taskID: 1, left: 1, reason: .overdue(days: 1)))
    }

    func test_FR08_R412_notchExpansionJudges() throws {
        let (state, repository) = try Self.dueTomorrow()
        state.setHovering(true)
        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [true])
        XCTAssertEqual(state.timer, .empty(draft: nil), "펼친 노치의 초안을 비우고 카드")
    }

    func test_FR08_R412_settingsWindowJudges() throws {
        let (state, repository) = try Self.dueTomorrow()
        state.activate()
        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [true])
    }

    // MARK: - 저장할 수 없음, 답 쓰기 실패

    func test_FR11_R119_storageUnavailableShowsNoCard() {
        let state = makeState(nil)
        state.launch()
        state.activate()
        XCTAssertEqual(state.notchMode, .storageUnavailable)
        XCTAssertNil(state.carryCardTask)
    }

    func test_FR08_R414_failedAnswerKeepsCardAndShowsLine() throws {
        let repository = FailingAfterStartRepository()
        _ = try Self.insert("가짜 할 일 B", deadline: "2027-01-10", into: repository.inner)
        let state = makeState(repository)
        state.launch()
        XCTAssertEqual(state.notchMode, .carryCard(taskID: 1, left: 1, reason: .overdue(days: 3)))

        repository.failsApply = true
        XCTAssertFalse(state.answerCarry(.today, for: 1))
        XCTAssertTrue(state.carryAnswerFailed)
        XCTAssertEqual(state.notchMode, .carryCard(taskID: 1, left: 1, reason: .overdue(days: 3)))
        XCTAssertEqual(try repository.tasks().first?.carryCount, 0)

        state.beginCarryMove()
        XCTAssertFalse(state.confirmCarryMove())
        XCTAssertNotNil(state.carryMoveDay, "날짜 바꾸기 쓰기가 실패하면 달력에 남는다")

        repository.failsApply = false
        XCTAssertTrue(state.confirmCarryMove())
        XCTAssertFalse(state.carryAnswerFailed, "다음 답이 되면 한 줄을 지운다")
    }

    // MARK: - R-434 남은 글: 기본 탭 하루 시작 시각 안내(시안 13번 마지막 줄)

    func test_R434_dayStartHintMentionsCarry() {
        XCTAssertEqual(BasicTabText.dayStartHint, "이 시각이 지나면 반복 할 일이 다시 대기로 돌아오고, 남은 할 일을 오늘 할지 물어요.")
    }
}

/// 쓰기 순서를 남기는 가짜 저장소. `failsApply`·`failsJudgment`로 그 쓰기만 실패시킨다. 읽기는 안쪽 메모리 저장소.
private final class CallRecordingRepository: TaskRepository {
    struct Failure: Error {}

    let inner = InMemoryTaskRepository()
    var failsApply = false
    var failsJudgment = false
    private(set) var calls: [String] = []

    func tasks() throws -> [MokaTask] { try inner.tasks() }
    func insertTask(_ task: NewTask, cycleDay: LocalDay?, at: Date) throws -> MokaTask {
        try inner.insertTask(task, cycleDay: cycleDay, at: at)
    }
    func checkpoints() throws -> [Checkpoint] { try inner.checkpoints() }
    func decisions() throws -> [DecisionLogEntry] { try inner.decisions() }
    func apply(_ batch: StoreBatch) throws {
        calls.append("apply")
        if failsApply { throw Failure() }
        try inner.apply(batch)
    }
    func lastCarryJudgment() throws -> Date? { try inner.lastCarryJudgment() }
    func applyCarryJudgment(_ batch: StoreBatch, judgedAt: Date) throws {
        calls.append("applyCarryJudgment")
        if failsJudgment { throw Failure() }
        try inner.applyCarryJudgment(batch, judgedAt: judgedAt)
    }
}
