import Foundation
import MokaCore
import XCTest

/// spec 004 단위 2: 구체화 게이트 앱 연결(data-model §3·§4). 가짜 공급자·메모리 키 보관함·메모리 판단 결과 저장소만 쓴다.
/// 실제 판단 API, 실제 Keychain, 앱 DB를 열지 않는다(R-319). 가짜 할 일과 가짜 첫 행동만 쓴다. 기다림은 실행기 `Task`와
/// 붙잡기(`hold`)로 하고 실제 시간을 기다리지 않는다. 붙잡은 수는 그 시점에 보낼 수 있는 질의 수만 기다린다.
@MainActor
final class AppGateTests: XCTestCase {
    private static let questions = try! QuestionSet.bundled()

    /// concrete만 바꾼 가짜 답. 임계값은 질문 파일의 0.5다.
    private static func answer(concrete: Double) -> DecisionResponse {
        DecisionResponse(
            model: "jev-1.13.0",
            answers: [
                "urgency": .score(score: 1, confidence: 0.7, probabilities: [0: 0.25, 1: 0.25, 2: 0.25, 3: 0.25]),
                "impact": .score(score: 1, confidence: 0.6, probabilities: [0: 0.2, 1: 0.4, 2: 0.4]),
                "concrete": .noul(concrete),
                "avoiding": .noul(0.3),
            ])
    }

    private static func provider(concrete: Double) -> FakeDecisionProvider {
        FakeDecisionProvider(answer: .success(answer(concrete: concrete)))
    }

    private struct Harness {
        let state: AppState
        let repository: InMemoryTaskRepository
        let scoreStore: InMemoryScoreStore
        let provider: FakeDecisionProvider
        let keys: InMemoryKeyStore
        let clock: TestClock
    }

    /// 할 일 `count`개를 넣은 상태. 노치는 1번을 고른다(마감 없음, 같으면 id 순).
    private func harness(
        count: Int, key: String? = "fake-key", provider: FakeDecisionProvider = AppGateTests.provider(concrete: 0.3),
        repository: InMemoryTaskRepository = InMemoryTaskRepository(), taskRepository: (any TaskRepository)? = nil
    ) throws -> Harness {
        for index in 0..<count {
            _ = try repository.insertTask(
                NewTask(title: "가짜 할 일 \(index + 1)", deadline: nil, estMin: nil, recurrence: .none, weekday: nil),
                cycleDay: nil, at: AppTestFixture.noon)
        }
        let scoreStore = InMemoryScoreStore(tasks: repository)
        let keys = InMemoryKeyStore(key: key)
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(
            taskRepository ?? repository, clock: clock, scores: scoreStore,
            decision: DecisionSetup(keyStore: keys, provider: provider, questions: Self.questions))
        return Harness(
            state: state, repository: repository, scoreStore: scoreStore, provider: provider, keys: keys, clock: clock)
    }

    /// 앱을 켜고 첫 질의가 끝날 때까지 기다린다.
    private func launched(_ harness: Harness) async -> Harness {
        harness.state.launch()
        await harness.state.requestScores()?.value
        return harness
    }

    // MARK: - 열림(FR-13 R-306)

    func test_FR13_R306_lowConcreteDraftOpensGate() async throws {
        let low = await launched(try harness(count: 1))
        XCTAssertEqual(low.state.session.taskID, 1)
        XCTAssertEqual(low.state.gatePhase, .asking)

        let high = await launched(try harness(count: 1, provider: Self.provider(concrete: 0.7)))
        XCTAssertEqual(high.state.gatePhase, .closed, "임계값 이상이면 열지 않는다")
    }

    func test_FR13_R306_gateStaysClosedWhenCannotQueryOrNoScore() async throws {
        let noKey = await launched(try harness(count: 1, key: nil))
        XCTAssertEqual(noKey.state.gatePhase, .closed, "키 없음")

        let noScore = await launched(
            try harness(count: 1, provider: FakeDecisionProvider(answer: .failure(.timeout))))
        XCTAssertEqual(noScore.state.gatePhase, .closed, "판단 결과 없음")

        let deleted = await launched(try harness(count: 1))
        XCTAssertEqual(deleted.state.gatePhase, .asking)
        XCTAssertTrue(deleted.state.deleteKey())
        XCTAssertEqual(deleted.state.gatePhase, .closed, "키를 지우면 닫힌다")

        let rejected = await launched(try harness(count: 1))
        XCTAssertEqual(rejected.state.gatePhase, .asking)
        await rejected.provider.setAnswer(.failure(.unauthorized), for: 1)
        XCTAssertTrue(rejected.state.editTask(1, TaskEdit(title: "가짜 할 일 1 고침")))
        await rejected.state.requestScores()?.value
        XCTAssertTrue(rejected.state.keyNeedsCheck)
        XCTAssertEqual(rejected.state.gatePhase, .closed, "키 확인이 필요하면 닫힌다")
    }

    func test_FR13_R306_scoreSavedWhileDraftOpensGateButNotWhileRunning() async throws {
        let provider = Self.provider(concrete: 0.3)
        await provider.hold()
        let draft = try harness(count: 1, provider: provider)
        draft.state.launch()
        let runner = try XCTUnwrap(draft.state.requestScores())
        await provider.waitForHeld(count: 1)
        XCTAssertEqual(draft.state.gatePhase, .closed, "판단 결과가 오기 전")
        await provider.releaseAll()
        await runner.value
        XCTAssertEqual(draft.state.gatePhase, .asking, "시작 전인 동안 판단 결과가 저장되면 연다")

        let heldRunning = Self.provider(concrete: 0.3)
        await heldRunning.hold()
        let running = try harness(count: 1, provider: heldRunning)
        running.state.launch()
        let second = try XCTUnwrap(running.state.requestScores())
        await heldRunning.waitForHeld(count: 1)
        running.state.start()
        await heldRunning.releaseAll()
        await second.value
        guard case .running = running.state.timer else { return XCTFail("도는 중: \(running.state.timer)") }
        XCTAssertEqual(running.state.gatePhase, .closed, "도는 중에는 열지 않는다")
    }

    // MARK: - 제출과 재판정(FR-13 R-307·R-308·R-309·R-310, SC-303, SC-306)

    func test_FR13_R307_R310_submitSavesFirstActionAndAsksOnceWithNewHash() async throws {
        let h = await launched(try harness(count: 2))
        XCTAssertEqual(h.state.gatePhase, .asking)
        let before = await h.provider.calls
        await h.provider.setAnswer(.success(Self.answer(concrete: 0.8)), for: 1)
        await h.provider.hold()

        XCTAssertFalse(h.state.submitFirstAction(" \n "), "빈 줄은 제출하지 않는다")
        XCTAssertEqual(h.state.gatePhase, .asking)
        XCTAssertTrue(h.state.submitFirstAction("  가짜 첫 행동\n"))
        let runner = try XCTUnwrap(h.state.requestScores())
        await h.provider.waitForHeld(count: 1)

        XCTAssertEqual(try h.repository.tasks().first { $0.id == 1 }?.firstAction, "가짜 첫 행동", "앞뒤를 지워 저장한다")
        let calls = await h.provider.calls
        XCTAssertEqual(Array(calls.dropFirst(before.count)), [1], "질의 1건")
        XCTAssertEqual(h.state.gatePhase, .checking)
        XCTAssertEqual(h.state.gateDraftText, "가짜 첫 행동")
        XCTAssertFalse(h.state.submitFirstAction("가짜 다른 줄"), "확인하는 중에는 제출을 받지 않는다")
        let whileChecking = await h.provider.calls
        XCTAssertEqual(whileChecking, calls)
        XCTAssertEqual(h.state.gateRecords[1]?.submissions, 1)

        await h.provider.releaseAll()
        await runner.value
        XCTAssertEqual(h.state.gatePhase, .closed, "0.8이면 통과")
        XCTAssertEqual(h.state.firstAction, "가짜 첫 행동", "통과한 첫 행동이 제목 아래 보인다")
        XCTAssertEqual(h.state.gateRecords[1], GateRecord(submissions: 1, passed: true))
        XCTAssertNil(h.state.gateWaitingTaskID)
    }

    func test_FR13_R310_startWorksWhileChecking() async throws {
        let h = await launched(try harness(count: 2))
        await h.provider.hold()
        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동"))
        let runner = try XCTUnwrap(h.state.requestScores())
        await h.provider.waitForHeld(count: 1)
        XCTAssertEqual(h.state.gatePhase, .checking)

        h.state.start()
        guard case .running = h.state.timer else { return XCTFail("확인하는 중에도 시작한다: \(h.state.timer)") }
        XCTAssertEqual(h.state.gatePhase, .closed, "시작하면 닫힌다")
        XCTAssertNil(h.state.gateWaitingTaskID)
        XCTAssertEqual(h.state.gateRecords[1]?.passed, false, "시작은 통과가 아니다")
        await h.provider.releaseAll()
        await runner.value
        XCTAssertEqual(h.state.gatePhase, .closed)
    }

    func test_FR13_R310_otherTaskWorksWhileCheckingAndKeepsFirstAction() async throws {
        let provider = Self.provider(concrete: 0.3)
        await provider.setAnswer(.success(Self.answer(concrete: 0.8)), for: 2)
        let h = await launched(try harness(count: 2, provider: provider))
        XCTAssertEqual(h.state.gatePhase, .asking)
        await provider.hold()
        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동"))
        let runner = try XCTUnwrap(h.state.requestScores())
        await provider.waitForHeld(count: 1)

        h.state.chooseOtherTask(2)
        XCTAssertEqual(h.state.session.taskID, 2)
        XCTAssertEqual(h.state.gatePhase, .closed, "노치 할 일이 바뀌면 닫힌다")
        XCTAssertNil(h.state.gateWaitingTaskID)
        await provider.releaseAll()
        await runner.value

        XCTAssertEqual(try h.repository.tasks().first { $0.id == 1 }?.firstAction, "가짜 첫 행동", "저장한 첫 행동은 되돌리지 않는다")
        XCTAssertEqual(h.state.gateRecords[1]?.submissions, 1, "기록은 남긴다")
        XCTAssertEqual(h.state.gateRecords[1]?.passed, false)
        let calls = await provider.calls
        XCTAssertEqual(calls.filter { $0 == 1 }.count, 2, "다시 묻기도 되돌리지 않는다")
    }

    func test_FR13_R308_R309_lowAnswerAsksAgainAndThirdSubmissionPasses() async throws {
        let h = await launched(try harness(count: 1))

        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동 1"))
        await h.state.requestScores()?.value
        XCTAssertEqual(h.state.gatePhase, .asking, "0.3이면 다시 묻는다")
        XCTAssertEqual(h.state.gateDraftText, "가짜 첫 행동 1", "칸에 지난 줄")
        XCTAssertEqual(h.state.gateRecords[1], GateRecord(submissions: 1, passed: false))

        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동 2"))
        await h.state.requestScores()?.value
        XCTAssertEqual(h.state.gatePhase, .asking)

        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동 3"))
        await h.state.requestScores()?.value
        XCTAssertEqual(h.state.gatePhase, .closed, "세 번째 뒤에는 미만이어도 통과")
        XCTAssertEqual(h.state.gateRecords[1], GateRecord(submissions: 3, passed: true))
        let calls = await h.provider.calls
        XCTAssertEqual(calls, [1, 1, 1, 1])
    }

    func test_FR13_R308_sameLineAsksNothingAndJudgesCurrentScore() async throws {
        let h = await launched(try harness(count: 1))
        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동"))
        await h.state.requestScores()?.value
        XCTAssertEqual(h.state.gatePhase, .asking)

        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동"))
        XCTAssertNil(h.state.requestScores(), "해시가 그대로라 질의가 나가지 않는다")
        XCTAssertEqual(h.state.gatePhase, .asking, "지금 판단 결과 0.3으로 바로 판정")
        XCTAssertEqual(h.state.gateRecords[1], GateRecord(submissions: 2, passed: false))

        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동"))
        XCTAssertEqual(h.state.gatePhase, .closed, "세 번째")
        let calls = await h.provider.calls
        XCTAssertEqual(calls, [1, 1])
    }

    // MARK: - 실패로 통과(FR-13 R-309, SC-305)

    func test_FR13_R309_SC305_failedRecheckPassesWithThatSubmission() async throws {
        let errors: [DecisionError] = [
            .missingKey, .timeout, .rateLimited, .overloaded, .server(status: 500), .network, .malformed, .unauthorized,
        ]
        for error in errors {
            let h = await launched(try harness(count: 2))
            XCTAssertEqual(h.state.gatePhase, .asking, "\(error)")
            await h.provider.setAnswer(.failure(error), for: 1)
            let session = h.state.session
            let remaining = h.state.remainingSeconds

            XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동"), "\(error)")
            await h.state.requestScores()?.value

            XCTAssertEqual(h.state.gatePhase, .closed, "\(error)")
            XCTAssertEqual(h.state.gateRecords[1], GateRecord(submissions: 1, passed: true), "\(error)")
            XCTAssertEqual(h.state.session, session, "\(error): 노치 그대로")
            XCTAssertEqual(h.state.remainingSeconds, remaining, "\(error): 타이머 그대로")
        }
    }

    func test_FR13_R309_deletingKeyWhileCheckingPasses() async throws {
        let h = await launched(try harness(count: 1))
        await h.provider.hold()
        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동"))
        let runner = try XCTUnwrap(h.state.requestScores())
        await h.provider.waitForHeld(count: 1)
        XCTAssertEqual(h.state.gatePhase, .checking)

        XCTAssertTrue(h.state.deleteKey())

        XCTAssertEqual(h.state.gatePhase, .closed)
        XCTAssertEqual(h.state.gateRecords[1], GateRecord(submissions: 1, passed: true))
        await h.provider.releaseAll()
        await runner.value
    }

    // MARK: - 넘기기와 닫기(FR-13 R-307·R-309·R-310)

    func test_FR13_R307_skipPassesWithoutWritingOrAsking() async throws {
        let h = await launched(try harness(count: 2))
        XCTAssertEqual(h.state.gatePhase, .asking)
        let calls = await h.provider.calls

        h.state.skipGate()

        XCTAssertEqual(h.state.gatePhase, .closed)
        XCTAssertEqual(h.state.gateRecords[1]?.passed, true)
        XCTAssertNil(try h.repository.tasks().first { $0.id == 1 }?.firstAction, "첫 행동 그대로")
        XCTAssertNil(h.state.requestScores(), "질의 그대로")
        h.state.chooseOtherTask(2)
        h.state.chooseOtherTask(1)
        XCTAssertEqual(h.state.session.taskID, 1)
        XCTAssertEqual(h.state.gatePhase, .closed, "다시 떠도 열지 않는다")
        let after = await h.provider.calls
        XCTAssertEqual(after, calls)
    }

    func test_FR13_R307_startClosesGateAndReopensWithRemainingCount() async throws {
        let h = await launched(try harness(count: 2))
        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동"))
        await h.state.requestScores()?.value
        XCTAssertEqual(h.state.gatePhase, .asking)

        h.state.start()
        XCTAssertEqual(h.state.gatePhase, .closed)
        h.state.beginSetAside(.switch)
        h.state.setAsideWithoutNotes()
        XCTAssertEqual(h.state.session.taskID, 2)
        h.state.chooseOtherTask(1)

        XCTAssertEqual(h.state.session.taskID, 1)
        XCTAssertEqual(h.state.gatePhase, .asking, "다음 시작 전에 다시 연다")
        XCTAssertEqual(h.state.gateRecords[1], GateRecord(submissions: 1, passed: false), "남은 횟수 그대로")
        await h.state.requestScores()?.value
    }

    func test_FR13_R310_notchTaskChangeClosesGate() async throws {
        let provider = Self.provider(concrete: 0.3)
        await provider.setAnswer(.success(Self.answer(concrete: 0.8)), for: 2)
        let h = await launched(try harness(count: 2, provider: provider))
        XCTAssertEqual(h.state.gatePhase, .asking)

        h.state.chooseOtherTask(2)

        XCTAssertEqual(h.state.gatePhase, .closed)
        XCTAssertEqual(h.state.gateDraftText, "")
    }

    func test_FR13_R307_saveFailureKeepsAskingAndDoesNotCount() async throws {
        let failing = FailingAfterStartRepository()
        let h = await launched(try harness(count: 1, repository: failing.inner, taskRepository: failing))
        XCTAssertEqual(h.state.gatePhase, .asking)
        failing.failsApply = true

        XCTAssertFalse(h.state.submitFirstAction("가짜 첫 행동"))

        XCTAssertEqual(h.state.gatePhase, .asking)
        XCTAssertTrue(h.state.gateSaveFailed)
        XCTAssertEqual(h.state.gateRecords[1]?.submissions ?? 0, 0, "횟수를 세지 않는다")
        XCTAssertNil(h.state.requestScores())

        failing.failsApply = false
        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동"))
        XCTAssertFalse(h.state.gateSaveFailed)
        await h.state.requestScores()?.value
    }

    func test_FR13_R307_skipClearsSaveFailure() async throws {
        let failing = FailingAfterStartRepository()
        let h = await launched(try harness(count: 1, repository: failing.inner, taskRepository: failing))
        failing.failsApply = true
        XCTAssertFalse(h.state.submitFirstAction("가짜 첫 행동"))
        XCTAssertTrue(h.state.gateSaveFailed)

        h.state.skipGate()

        XCTAssertFalse(h.state.gateSaveFailed)
        XCTAssertEqual(h.state.gatePhase, .closed)
    }

    // MARK: - 기다리는 동안 해시가 바뀜(FR-13 R-308, data-model §3)

    /// 낡은 해시의 답(0.8)은 버리고, 새 해시로 다시 물은 답(0.3)으로만 판정한다.
    private func assertWaitsForNewHash(_ change: (Harness) -> Void) async throws {
        let h = await launched(try harness(count: 1))
        XCTAssertEqual(h.state.gatePhase, .asking)
        await h.provider.setAnswer(.success(Self.answer(concrete: 0.8)), for: 1)
        await h.provider.hold()
        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동"))
        let runner = try XCTUnwrap(h.state.requestScores())
        await h.provider.waitForHeld(count: 1)
        await h.provider.setAnswer(.success(Self.answer(concrete: 0.3)), for: 1)

        change(h)
        XCTAssertEqual(h.state.gatePhase, .checking)
        await h.provider.release(taskID: 1)
        await h.provider.waitForHeld(count: 1)

        XCTAssertEqual(h.state.gatePhase, .checking, "낡은 해시의 답으로는 판정하지 않는다")
        XCTAssertEqual(try h.scoreStore.scores()[1]?.concrete, 0.3, "낡은 해시의 답은 버린다")
        let calls = await h.provider.calls
        XCTAssertEqual(calls, [1, 1, 1], "새 해시로 다시 묻는다")
        await h.provider.releaseAll()
        await runner.value

        XCTAssertEqual(h.state.gatePhase, .asking, "새 해시의 답 0.3으로 판정")
        XCTAssertEqual(h.state.gateRecords[1], GateRecord(submissions: 1, passed: false))
    }

    func test_FR13_R308_editWhileCheckingWaitsForNewHash() async throws {
        try await assertWaitsForNewHash { h in
            XCTAssertTrue(h.state.editTask(1, TaskEdit(title: "가짜 할 일 1 고침")))
        }
    }

    func test_FR13_R308_dayChangeWhileCheckingWaitsForNewHash() async throws {
        try await assertWaitsForNewHash { h in
            h.clock.advance(minutes: 24 * 60)
            h.state.activate()
        }
    }

    // MARK: - 표시(FR-13 R-311)

    func test_FR13_R311_firstActionHiddenWhileGateOpenAndCollapsedNotReshown() async throws {
        let repository = InMemoryTaskRepository()
        _ = try repository.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: AppTestFixture.noon)
        var task = try XCTUnwrap(try repository.tasks().first)
        task.firstAction = "가짜 지난 첫 행동"
        try repository.apply(StoreBatch(updatedTasks: [task]))
        let h = await launched(try harness(count: 0, repository: repository))
        await h.provider.setAnswer(.success(Self.answer(concrete: 0.8)), for: 1)
        XCTAssertEqual(h.state.gatePhase, .asking)
        XCTAssertNil(h.state.firstAction, "묻는 중에는 펼친 화면의 이어서 할 일을 숨긴다")
        XCTAssertTrue(h.state.showsFirstActionCollapsed, "노치가 고른 직후 3초 창 안")
        XCTAssertEqual(h.state.collapsedFirstAction, "가짜 지난 첫 행동", "접힌 3초 표시는 게이트가 열려도 보인다")
        h.clock.advance(seconds: 10)

        await h.provider.hold()
        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동"))
        let runner = try XCTUnwrap(h.state.requestScores())
        await h.provider.waitForHeld(count: 1)
        XCTAssertEqual(h.state.gatePhase, .checking)
        XCTAssertNil(h.state.firstAction, "확인하는 중에도 숨긴다")
        await h.provider.releaseAll()
        await runner.value

        XCTAssertEqual(h.state.gatePhase, .closed)
        XCTAssertEqual(h.state.firstAction, "가짜 첫 행동", "통과 뒤 다시 보인다")
        XCTAssertFalse(h.state.showsFirstActionCollapsed, "통과 때 접힌 3초 표시를 다시 켜지 않는다")
    }

    // MARK: - 첫 행동 두 경로(spec 위험 3)

    func test_FR13_R307_gateThenCheckpointKeepsCheckpointLine() async throws {
        let h = await launched(try harness(count: 2))
        XCTAssertTrue(h.state.submitFirstAction("가짜 게이트 줄"))
        h.state.start()
        h.state.beginSetAside(.switch)
        h.state.editNotes(NotesDraft(done: "가짜 한 일", next: "가짜 다음 줄"))
        h.state.submitSetAside()
        await h.state.requestScores()?.value

        XCTAssertEqual(try h.repository.tasks().first { $0.id == 1 }?.firstAction, "가짜 다음 줄")
    }

    func test_FR13_R307_checkpointThenGateKeepsGateLine() async throws {
        let h = await launched(try harness(count: 2))
        XCTAssertEqual(h.state.gatePhase, .asking)
        h.state.start()
        h.state.beginSetAside(.switch)
        h.state.editNotes(NotesDraft(done: "가짜 한 일", next: "가짜 다음 줄"))
        h.state.submitSetAside()
        XCTAssertEqual(h.state.session.taskID, 2)
        h.state.chooseOtherTask(1)
        XCTAssertEqual(h.state.gatePhase, .asking)

        XCTAssertTrue(h.state.submitFirstAction("가짜 게이트 줄"))
        await h.state.requestScores()?.value

        XCTAssertEqual(try h.repository.tasks().first { $0.id == 1 }?.firstAction, "가짜 게이트 줄")
    }

    // MARK: - 로그 없음과 메모리 기록(FR-13 R-312·R-309)

    func test_FR13_R312_submitAndSkipWriteNoDecisionLog() async throws {
        let h = await launched(try harness(count: 2))
        let before = try h.repository.decisions().count

        XCTAssertTrue(h.state.submitFirstAction("가짜 첫 행동"))
        await h.state.requestScores()?.value
        h.state.skipGate()

        XCTAssertEqual(try h.repository.decisions().count, before)
    }

    func test_FR13_R309_relaunchForgetsGateRecords() async throws {
        let h = await launched(try harness(count: 1))
        h.state.skipGate()
        XCTAssertEqual(h.state.gatePhase, .closed)

        let relaunched = makeState(
            h.repository, clock: h.clock, scores: h.scoreStore,
            decision: DecisionSetup(keyStore: h.keys, provider: h.provider, questions: Self.questions))
        relaunched.launch()

        XCTAssertEqual(relaunched.gatePhase, .asking, "기록은 메모리에만 있다")
        XCTAssertTrue(relaunched.gateRecords.isEmpty)
    }
}
