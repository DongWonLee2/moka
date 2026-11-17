import Foundation
import MokaCore
import XCTest

/// spec 005 단위 1: 앱 노치 순서(T043). 단위 1은 앱 코드를 바꾸지 않고 `NotchSession`의 고르기만 바꾼다.
/// 키 없음(판단 설정 없음), 메모리 저장소, 주입한 시계만 쓴다. 가짜 할 일만 쓴다.
@MainActor
final class AppSchedulerTests: XCTestCase {
    /// 마감 순 A(1)·B(2)·C(3)·D(4).
    private static func seeded() throws -> InMemoryTaskRepository {
        let repository = InMemoryTaskRepository()
        for (index, day) in ["2027-01-20", "2027-01-21", "2027-01-22", "2027-01-23"].enumerated() {
            _ = try repository.insertTask(
                NewTask(
                    title: "가짜 할 일 \(index + 1)", deadline: LocalDay(text: day), estMin: nil, recurrence: .none,
                    weekday: nil),
                cycleDay: nil, at: AppTestFixture.noon)
        }
        return repository
    }

    func test_FR05_R403_R408_switchAndSkipRotateTopThreeByRankShares() throws {
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(try Self.seeded(), clock: clock)
        state.launch()
        var shown: [TaskID] = []
        for index in 0..<20 {
            let current = try XCTUnwrap(state.session.taskID)
            shown.append(current)
            state.start()
            clock.advance(minutes: 1)
            state.beginSetAside(index.isMultiple(of: 2) ? .skip : .switch)
            state.setAsideWithoutNotes()
            XCTAssertNotEqual(state.session.taskID, current, "바꾸기·미루기 바로 뒤에 방금 할 일이 다시 뜨지 않는다")
        }
        let tally = shown.reduce(into: [TaskID: Int]()) { $0[$1, default: 0] += 1 }
        XCTAssertNil(tally[4], "넷째 D는 한 번도 뜨지 않는다")
        XCTAssertEqual(tally[1], 10)
        XCTAssertEqual(tally[2], 6)
        XCTAssertEqual(tally[3], 4)
    }

    func test_FR05_R403_newDayClearsCredits() throws {
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(try Self.seeded(), clock: clock)
        state.launch()
        XCTAssertEqual(state.session.memory.memoryDay, LocalDay(text: "2027-01-13"))
        state.start()
        clock.advance(minutes: 19 * 60)
        state.tick()
        state.complete()
        XCTAssertEqual(state.session.memory.memoryDay, LocalDay(text: "2027-01-14"), "하루가 바뀐 뒤 첫 고르기")
        XCTAssertEqual(state.session.taskID, 2)
        XCTAssertEqual(state.session.memory.credits, [2: -5, 3: 3, 4: 2], "어제 몫 상태는 비우고 0에서 다시 셈")
    }

    func test_FR05_R408_completeHasNothingToExclude() throws {
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(try Self.seeded(), clock: clock)
        state.launch()
        XCTAssertEqual(state.session.taskID, 1)
        state.start()
        clock.advance(minutes: 1)
        state.complete()
        XCTAssertNil(state.session.previousTaskID, "완료 뒤에는 뺄 할 일이 없다")
        XCTAssertEqual(state.session.taskID, 2)
    }

    private static let questions = try! QuestionSet.bundled()

    private struct Scored {
        let repository: InMemoryTaskRepository
        let scores: InMemoryScoreStore
        let settings: InMemorySettingsStore
        let keys: InMemoryKeyStore
        let provider: FakeDecisionProvider
        let clock: TestClock

        @MainActor func state() -> AppState {
            makeState(
                repository, settings: settings, clock: clock, scores: scores,
                decision: DecisionSetup(keyStore: keys, provider: provider, questions: AppSchedulerTests.questions))
        }
    }

    private static func scored(_ rows: [(urgency: Double, estMin: Int?)]) throws -> Scored {
        let repository = InMemoryTaskRepository()
        let scores = InMemoryScoreStore(tasks: repository)
        for (index, row) in rows.enumerated() {
            let task = try repository.insertTask(
                NewTask(
                    title: "가짜 할 일 \(index + 1)", deadline: nil, estMin: row.estMin, recurrence: .none, weekday: nil),
                cycleDay: nil, at: AppTestFixture.noon)
            try scores.upsertScore(
                TaskScore(
                    taskID: task.id, questionVersion: questions.version, provider: "fake", modelSnapshot: nil,
                    urgency: row.urgency, impact: 0, concrete: 0.9, avoiding: 0, probsJSON: "{}",
                    stateHash: "가짜", scoredAt: AppTestFixture.noon))
        }
        return Scored(
            repository: repository, scores: scores, settings: InMemorySettingsStore(),
            keys: InMemoryKeyStore(key: "fake-key"), provider: FakeDecisionProvider(answer: .failure(.timeout)),
            clock: TestClock(AppTestFixture.noon))
    }

    private static func launched(_ state: AppState) async -> AppState {
        state.launch()
        await state.requestScores()?.value
        return state
    }

    private static func startThenSwitch(_ state: AppState, _ clock: TestClock) {
        state.start()
        clock.advance(minutes: 1)
        state.beginSetAside(.switch)
        state.setAsideWithoutNotes()
    }

    func test_FR05_R403_US1_7_noKeyDraftsDeadlineFirstAndRanksTopThree() throws {
        let state = makeState(try Self.seeded())
        state.launch()
        XCTAssertEqual(state.session.taskID, 1, "키 없음이면 마감이 가장 가까운 할 일부터")
        XCTAssertEqual(state.ranks, [1: 1, 2: 2, 3: 3], "넷째 할 일에는 순위가 없다")
    }

    func test_FR05_R403_US1_1_scoredTasksRotateByPriorityShares() async throws {
        let h = try Self.scored([(1.0, nil), (0.5, nil), (0.5, nil), (0.1, nil)])
        let state = await Self.launched(h.state())
        var shown: [TaskID] = []
        for _ in 0..<20 {
            shown.append(try XCTUnwrap(state.session.taskID))
            Self.startThenSwitch(state, h.clock)
        }
        let tally = shown.reduce(into: [TaskID: Int]()) { $0[$1, default: 0] += 1 }
        XCTAssertEqual(tally[1], 10, "priority 1.0 : 0.5 : 0.5의 몫 2:1:1(순위 몫 5:3:2가 아님)")
        XCTAssertEqual(tally[2], 5)
        XCTAssertEqual(tally[3], 5)
        XCTAssertNil(tally[4], "창 밖 넷째 할 일은 뜨지 않는다")
    }

    func test_FR05_R406_firstPickOfDayIsWarmupAndSameDayRelaunchIsNot() async throws {
        let h = try Self.scored([(1.0, 60), (0.5, 20)])
        let first = await Self.launched(h.state())
        XCTAssertEqual(first.session.taskID, 2, "하루 첫 고르기는 짧고 구체적인 할 일")
        XCTAssertEqual(first.session.memory.pickedBy, .warmupV1)
        Self.startThenSwitch(first, h.clock)
        XCTAssertEqual(try h.repository.decisions().last?.schedulerChoice, .warmupV1, "버튼 줄의 선택 규칙 이름")
        XCTAssertEqual(CoreSettings.readLastStartDay(from: h.settings), LocalDay(text: "2027-01-13"))

        let relaunched = await Self.launched(h.state())
        XCTAssertEqual(relaunched.session.taskID, 1, "같은 하루에 다시 켜면 워밍업 없이 가중 순환")
        XCTAssertEqual(relaunched.session.memory.pickedBy, .weightedRotateV1)
    }

    func test_FR05_R406_nextDayFirstPickIsWarmupAgain() async throws {
        let h = try Self.scored([(1.0, 60), (0.5, 20)])
        try CoreSettings.writeLastStartDay(LocalDay(text: "2027-01-13")!, to: h.settings)
        let state = await Self.launched(h.state())
        XCTAssertEqual(state.session.taskID, 1, "오늘 이미 시작했으면 워밍업 없음")
        state.start()
        h.clock.advanceToNextDay(hour: 7)
        state.tick()
        state.complete()
        XCTAssertEqual(try h.repository.decisions().last?.schedulerChoice, .weightedRotateV1)
        XCTAssertEqual(state.session.taskID, 2, "하루가 바뀐 뒤 첫 고르기는 다시 워밍업")
        XCTAssertEqual(state.session.memory.pickedBy, .warmupV1)
    }

    func test_FR05_R407_US1_8_expiredKeepsButtonsWithoutOtherTask() throws {
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(try Self.seeded(), clock: clock)
        state.launch()
        state.start()
        clock.advance(minutes: 30)
        state.tick()
        guard case .expired = state.session.timer else { return XCTFail("시간 끝이 아니다: \(state.session.timer)") }
        state.beginOtherTask()
        XCTAssertFalse(state.isPickingOtherTask, "시간 끝 화면에는 다른 할 일 고르기가 없다")
        XCTAssertEqual(state.session.taskID, 1, "시간 끝에는 고르지 않고 같은 할 일")
    }

    func test_FR05_R411_noKeyButtonLineIsWeightedRotate() throws {
        let clock = TestClock(AppTestFixture.noon)
        let repository = try Self.seeded()
        let state = makeState(repository, clock: clock)
        state.launch()
        state.start()
        clock.advance(minutes: 1)
        state.complete()
        XCTAssertEqual(try repository.decisions().map(\.schedulerChoice), [.weightedRotateV1])
    }

    func test_R434_nextMarkIsNextPick() throws {
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(try Self.seeded(), clock: clock)
        state.launch()
        XCTAssertEqual(state.nextMarkID, 1, "초안이면 그 할 일")
        state.start()
        let predicted = try XCTUnwrap(state.nextMarkID)
        XCTAssertNotEqual(predicted, 1, "도는 중이면 지금 할 일을 뺀 다음 고르기")
        clock.advance(minutes: 1)
        state.complete()
        XCTAssertEqual(state.session.taskID, predicted, "완료 뒤 실제 고르기와 같다")
    }

    private static func withOverdue() throws -> InMemoryTaskRepository {
        let repository = InMemoryTaskRepository()
        for (index, day) in ["2027-01-10", "2027-01-20", "2027-01-21", "2027-01-22"].enumerated() {
            _ = try repository.insertTask(
                NewTask(
                    title: "가짜 할 일 \(index + 1)", deadline: LocalDay(text: day), estMin: nil, recurrence: .none,
                    weekday: nil),
                cycleDay: nil, at: AppTestFixture.at(2027, 1, 12, 12, 0))
        }
        return repository
    }

    func test_FR08_R412_activationDoesNotJudgeCarry() throws {
        let repository = try Self.withOverdue()
        let state = makeState(repository)
        state.launch()
        state.activate()
        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [false, false, false, false])
        XCTAssertNil(try repository.lastCarryJudgment(), "단위 2는 활성화에서 판정하지 않는다")
    }

    func test_FR08_R412_R413_judgeCarryMarksAndRanksSkipDue() throws {
        let clock = TestClock(AppTestFixture.noon)
        let repository = try Self.withOverdue()
        let state = makeState(repository, clock: clock)
        state.launch()
        XCTAssertEqual(state.session.taskID, 1)
        state.start()
        clock.advance(minutes: 1)
        state.complete()

        let other = try repository.insertTask(
            NewTask(
                title: "가짜 할 일 5", deadline: LocalDay(text: "2027-01-09"), estMin: nil, recurrence: .none,
                weekday: nil),
            cycleDay: nil, at: AppTestFixture.at(2027, 1, 12, 12, 0))
        clock.advanceToNextDay(hour: 7)
        XCTAssertTrue(state.judgeCarryIfNeeded())

        XCTAssertEqual(try repository.tasks().first { $0.id == other.id }?.dueDecision, true)
        XCTAssertEqual(try repository.lastCarryJudgment(), AppTestFixture.at(2027, 1, 14, 7, 0))
        XCTAssertNil(state.ranks[other.id], "이월 답 대기는 순위에서 빠진다")
        XCTAssertFalse(state.otherTaskItems.contains { $0.id == other.id }, "다른 할 일 목록에서도 빠진다")
        XCTAssertTrue(state.judgeCarryIfNeeded(), "같은 하루에 다시 부르면 돌지 않고 실패도 아니다")
        XCTAssertEqual(try repository.lastCarryJudgment(), AppTestFixture.at(2027, 1, 14, 7, 0))
    }

    func test_FR08_R412_judgeCarryCountsRevertedUntilWriteSucceeds() throws {
        let repository = FailingAfterStartRepository()
        _ = try repository.inner.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: AppTestFixture.at(2027, 1, 12, 12, 0))
        var active = try XCTUnwrap(try repository.inner.tasks().first)
        active.status = .active
        try repository.inner.apply(StoreBatch(updatedTasks: [active]))
        let state = makeState(repository)
        state.launch()
        XCTAssertEqual(try repository.tasks().first?.status, .todo, "켤 때 복구가 진행 중을 대기로 되돌림")

        repository.failsApply = true
        XCTAssertFalse(state.judgeCarryIfNeeded(), "판정 쓰기 실패")
        XCTAssertNil(try repository.lastCarryJudgment())
        repository.failsApply = false
        XCTAssertTrue(state.judgeCarryIfNeeded())
        XCTAssertEqual(try repository.tasks().first?.dueDecision, true, "되돌린 할 일은 판정 쓰기가 성공할 때까지 손댄 할 일")
    }

    func test_FR08_R415_R416_answerCarryWritesTaskAndLogLine() throws {
        let repository = try Self.withOverdue()
        let state = makeState(repository)
        XCTAssertTrue(state.judgeCarryIfNeeded())
        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [true, false, false, false])
        state.launch()

        XCTAssertFalse(state.answerCarry(.move(LocalDay(text: "2027-01-13")!), for: 1), "날짜는 내일부터")
        XCTAssertTrue(try repository.decisions().isEmpty)
        XCTAssertFalse(state.answerCarry(.today, for: 2), "카드에 오르지 않은 할 일에는 답하지 않는다")

        XCTAssertTrue(state.answerCarry(.today, for: 1))
        let task = try XCTUnwrap(try repository.tasks().first)
        XCTAssertEqual(task.carryCount, 1)
        XCTAssertFalse(task.dueDecision)
        let line = try XCTUnwrap(try repository.decisions().last)
        XCTAssertEqual(line.userAction, .carryToday)
        XCTAssertEqual(line.schedulerChoice, .carryCardV1)
        XCTAssertEqual(line.judgment?.provider, "fallback", "판단 결과가 없으면 fallback")
    }
}
