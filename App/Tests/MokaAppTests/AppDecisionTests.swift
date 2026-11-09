import Foundation
import MokaCore
import XCTest

/// spec 003 단위 4a: 앱 질의 연결(data-model §6·§9). 가짜 공급자·메모리 키 보관함·메모리 판단 결과 저장소만 쓴다.
/// 실제 판단 API, 실제 Keychain, 앱 DB를 열지 않는다(SC-207). 가짜 할 일만 쓴다. 기다림은 `requestScores()`가 돌려준
/// 실행기 `Task`와 붙잡기(`hold`)로 하고 실제 시간을 기다리지 않는다. 함께 떠난 질의는 공급자에 닿는 순서가 정해져 있지
/// 않아 집합으로 비교한다.
@MainActor
final class AppDecisionTests: XCTestCase {
    private static let questions = try! QuestionSet.bundled()

    /// 질문 넷을 모두 채운 가짜 답. `urgency`는 0~3.
    private static func answer(urgency: Double) -> DecisionResponse {
        DecisionResponse(
            model: "jev-1.13.0",
            answers: [
                "urgency": .score(
                    score: urgency, confidence: 0.7, probabilities: [0: 0.25, 1: 0.25, 2: 0.25, 3: 0.25]),
                "impact": .score(score: 1, confidence: 0.6, probabilities: [0: 0.2, 1: 0.4, 2: 0.4]),
                "concrete": .noul(0.9),
                "avoiding": .noul(0.3),
            ])
    }

    private static func ok() -> FakeDecisionProvider {
        FakeDecisionProvider(answer: .success(answer(urgency: 1)))
    }

    private struct Harness {
        let state: AppState
        let repository: InMemoryTaskRepository
        let scoreStore: InMemoryScoreStore
        let provider: FakeDecisionProvider
        let keys: InMemoryKeyStore
        let clock: TestClock
    }

    /// 할 일 `count`개를 넣은 상태. `deadlines`가 모자라면 마감 없음.
    private func harness(
        count: Int, key: String? = "fake-key", deadlines: [LocalDay?] = [],
        provider: FakeDecisionProvider = AppDecisionTests.ok()
    ) throws -> Harness {
        let repository = InMemoryTaskRepository()
        for index in 0..<count {
            _ = try repository.insertTask(
                NewTask(
                    title: "가짜 할 일 \(index + 1)", deadline: index < deadlines.count ? deadlines[index] : nil,
                    estMin: nil, recurrence: .none, weekday: nil),
                cycleDay: nil, at: AppTestFixture.noon)
        }
        let scoreStore = InMemoryScoreStore(tasks: repository)
        let keys = InMemoryKeyStore(key: key)
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(
            repository, clock: clock, scores: scoreStore,
            decision: DecisionSetup(keyStore: keys, provider: provider, questions: Self.questions))
        return Harness(
            state: state, repository: repository, scoreStore: scoreStore, provider: provider, keys: keys, clock: clock)
    }

    /// 할 일 하나와 정한 저장소·키 보관함·질문 세트로 만든 상태.
    private func single(
        scores: (any ScoreStore)?, keyStore: any KeyStore = InMemoryKeyStore(key: "fake-key"),
        questions: QuestionSet? = AppDecisionTests.questions, provider: FakeDecisionProvider
    ) throws -> AppState {
        let repository = InMemoryTaskRepository()
        _ = try repository.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: AppTestFixture.noon)
        return makeState(
            repository, scores: scores,
            decision: DecisionSetup(keyStore: keyStore, provider: provider, questions: questions))
    }

    /// 앱을 켜고 첫 질의가 끝날 때까지 기다린다.
    private func launched(_ harness: Harness) async -> Harness {
        harness.state.launch()
        await harness.state.requestScores()?.value
        return harness
    }

    private static func day(_ text: String) -> LocalDay { LocalDay(text: text)! }

    private static func newTask(_ title: String) -> NewTask {
        NewTask(title: title, deadline: nil, estMin: nil, recurrence: .none, weekday: nil)
    }

    // MARK: - T022 묻는 때와 장부(FR-01 R-207, FR-03 R-206, SC-201, SC-206)

    func test_FR01_R207_launchAsksEveryOpenTaskOnceAndStores() async throws {
        let h = await launched(try harness(count: 3))

        let calls = await h.provider.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(Set(calls), [1, 2, 3])
        XCTAssertEqual(Set(try h.scoreStore.scores().keys), [1, 2, 3])
        XCTAssertEqual(Set(h.state.scores.keys), [1, 2, 3], "답을 저장한 뒤 다시 읽는다")
        XCTAssertNil(h.state.requestScores(), "같은 입력은 다시 보내지 않는다")
    }

    func test_FR01_R207_settingsEditAsksOnlyThatTask() async throws {
        let h = await launched(try harness(count: 3))

        XCTAssertTrue(h.state.editTask(2, TaskEdit(title: "가짜 할 일 2 고침")))
        await h.state.requestScores()?.value

        let calls = await h.provider.calls
        XCTAssertEqual(Array(calls.dropFirst(3)), [2])
    }

    func test_FR01_R207_settingsAddAsksOnlyNewTask() async throws {
        let h = await launched(try harness(count: 2))

        XCTAssertTrue(h.state.addTask(Self.newTask("가짜 새 할 일")))
        await h.state.requestScores()?.value

        let calls = await h.provider.calls
        XCTAssertEqual(Array(calls.dropFirst(2)), [3])
    }

    func test_FR01_R207_quickEntryAsksOnlyNewTask() async throws {
        let h = await launched(try harness(count: 2))

        h.state.enterTitle("가짜 빠른 할 일")
        await h.state.requestScores()?.value

        let calls = await h.provider.calls
        XCTAssertEqual(Array(calls.dropFirst(2)), [3])
    }

    func test_FR01_R207_buttonWithNotesAsksOnlyThatTask() async throws {
        let h = await launched(try harness(count: 2))
        XCTAssertEqual(h.state.session.taskID, 1)

        h.state.start()
        XCTAssertNil(h.state.requestScores(), "시작은 판단 입력을 바꾸지 않는다")
        h.state.beginSetAside(.switch)
        h.state.editNotes(NotesDraft(done: "가짜 한 일", next: "가짜 다음 줄"))
        h.state.submitSetAside()
        await h.state.requestScores()?.value

        let calls = await h.provider.calls
        XCTAssertEqual(Array(calls.dropFirst(2)), [1], "체크포인트·첫 행동이 바뀐 할 일만")
    }

    func test_FR01_R207_contextChangeAsksAllOpenTasks() async throws {
        let h = await launched(try harness(count: 2))

        XCTAssertTrue(h.state.addContext(NewContext(name: "가짜 시험", date: Self.day("2027-01-20"), impact: .high)))
        await h.state.requestScores()?.value

        let calls = await h.provider.calls
        XCTAssertEqual(calls.count, 4)
        XCTAssertEqual(Set(calls.dropFirst(2)), [1, 2])
    }

    func test_FR01_R207_activationWithoutChangeAsksNothing() async throws {
        let h = await launched(try harness(count: 2))

        h.state.activate()

        XCTAssertNil(h.state.requestScores())
        let calls = await h.provider.calls
        XCTAssertEqual(calls.count, 2)
    }

    func test_FR01_R206_activationAfterDayChangeAsksAllOpenTasks() async throws {
        let h = await launched(try harness(count: 2))

        h.clock.advance(minutes: 24 * 60)
        h.state.activate()
        await h.state.requestScores()?.value

        let calls = await h.provider.calls
        XCTAssertEqual(calls.count, 4)
        XCTAssertEqual(Set(calls.dropFirst(2)), [1, 2], "판단 입력의 오늘이 바뀌었다")
    }

    func test_FR01_R207_keySaveAsksTasks() async throws {
        let h = await launched(try harness(count: 2, key: nil))
        XCTAssertFalse(h.state.hasKey)
        let before = await h.provider.calls
        XCTAssertEqual(before, [], "키가 없으면 묻지 않는다")

        XCTAssertTrue(h.state.saveKey("  fake-key\n"))
        await h.state.requestScores()?.value

        XCTAssertTrue(h.state.hasKey)
        XCTAssertEqual(try h.keys.read(), "fake-key", "앞뒤 공백·줄바꿈을 지운다")
        let calls = await h.provider.calls
        XCTAssertEqual(Set(calls), [1, 2])
        XCTAssertEqual(calls.count, 2)
    }

    func test_FR01_R207_relaunchDoesNotResendScoredTasks() async throws {
        let h = await launched(try harness(count: 2))

        let relaunched = makeState(
            h.repository, clock: h.clock, scores: h.scoreStore,
            decision: DecisionSetup(keyStore: h.keys, provider: h.provider, questions: Self.questions))
        relaunched.launch()

        XCTAssertEqual(Set(relaunched.scores.keys), [1, 2], "켤 때 저장된 판단 결과를 읽는다")
        XCTAssertNil(relaunched.requestScores())
        let calls = await h.provider.calls
        XCTAssertEqual(calls.count, 2)
    }

    func test_FR01_R207_concurrentQueriesNeverExceedFour() async throws {
        let provider = Self.ok()
        await provider.hold()
        let h = try harness(count: 6, provider: provider)

        h.state.launch()
        let runner = try XCTUnwrap(h.state.requestScores())
        await provider.waitForHeld(count: 4)

        let heldMax = await provider.maxInFlight
        let heldCalls = await provider.calls
        XCTAssertEqual(heldMax, 4)
        XCTAssertEqual(Set(heldCalls), [1, 2, 3, 4])
        await provider.releaseAll()
        await runner.value

        let max = await provider.maxInFlight
        let calls = await provider.calls
        XCTAssertEqual(max, 4)
        XCTAssertEqual(calls.count, 6)
        XCTAssertEqual(try h.scoreStore.scores().count, 6)
    }

    /// 트리거마다 작업 그룹을 따로 만드는 구현이면 할 일 저장 때 새 그룹이 5·6·7을 함께 보내 동시 7이 되고,
    /// 두 번째 `requestScores()`가 다른 `Task`를 돌려준다.
    func test_FR01_R207_overlappingTriggersShareOneRunner() async throws {
        let provider = Self.ok()
        let h = await launched(try harness(count: 6, provider: provider))

        await provider.hold()
        h.clock.advance(minutes: 24 * 60)
        h.state.activate()
        let runner = try XCTUnwrap(h.state.requestScores())
        await provider.waitForHeld(count: 4)
        XCTAssertTrue(h.state.addTask(Self.newTask("가짜 새 할 일")))

        XCTAssertEqual(h.state.requestScores(), runner, "실행 중이면 같은 Task를 돌려준다")
        let held = await provider.heldCount
        XCTAssertEqual(held, 4)
        let first = await provider.calls.dropFirst(6)
        XCTAssertEqual(Set(first), [1, 2, 3, 4])
        await provider.release(taskID: 1)
        await provider.waitForHeld(count: 4)
        let fifth = await provider.calls.dropFirst(10)
        XCTAssertEqual(Array(fifth), [7], "저장한 새 할 일이 남은 할 일보다 먼저")
        await provider.releaseAll()
        await runner.value

        let max = await provider.maxInFlight
        let second = await provider.calls.dropFirst(6)
        XCTAssertLessThanOrEqual(max, 4)
        XCTAssertEqual(second.count, 7)
        XCTAssertEqual(Set(second), [1, 2, 3, 4, 5, 6, 7], "같은 해시는 한 번만 보낸다")
    }

    func test_FR01_R207_triggerWhileRunnerFinishingIsNotLost() async throws {
        let provider = Self.ok()
        let h = await launched(try harness(count: 2, provider: provider))

        await provider.hold()
        XCTAssertTrue(h.state.editTask(1, TaskEdit(title: "가짜 할 일 1 고침")))
        let runner = try XCTUnwrap(h.state.requestScores())
        await provider.waitForHeld(count: 1)
        await provider.releaseAll()
        XCTAssertTrue(h.state.editTask(2, TaskEdit(title: "가짜 할 일 2 고침")))
        await h.state.requestScores()?.value
        await runner.value
        await h.state.requestScores()?.value

        let calls = await provider.calls
        XCTAssertEqual(Array(calls.dropFirst(2)), [1, 2])
        XCTAssertNil(h.state.requestScores(), "두 할 일 모두 지금 입력으로 저장됐다")
    }

    func test_FR01_R207_editedOrDroppedWhileHeldIsNotSentWithStaleHash() async throws {
        let provider = Self.ok()
        await provider.hold()
        let h = try harness(count: 6, provider: provider)

        h.state.launch()
        let runner = try XCTUnwrap(h.state.requestScores())
        await provider.waitForHeld(count: 4)
        XCTAssertTrue(h.state.editTask(5, TaskEdit(title: "가짜 할 일 5 고침")))
        XCTAssertTrue(h.state.dropTask(6))
        await provider.releaseAll()
        await runner.value

        let calls = await provider.calls
        XCTAssertEqual(calls.filter { $0 == 5 }.count, 1)
        XCTAssertEqual(calls.filter { $0 == 6 }.count, 0, "버린 할 일은 보내지 않는다")
        XCTAssertNil(h.state.requestScores(), "5는 고친 입력의 해시로 저장됐다")
    }

    func test_FR05_R209_answerChangesNextMark() async throws {
        let provider = FakeDecisionProvider(answer: .success(Self.answer(urgency: 0)))
        await provider.setAnswer(.success(Self.answer(urgency: 3)), for: 3)
        let h = try harness(count: 3, provider: provider)

        h.state.launch()
        h.state.start()
        XCTAssertEqual(h.state.nextMarkID, 2, "판단 결과가 없으면 마감 순(같으면 id)")
        await h.state.requestScores()?.value

        XCTAssertEqual(try h.scoreStore.scores().count, 3)
        XCTAssertEqual(h.state.nextMarkID, 3, "급하다는 답을 받은 할 일이 다음")
        XCTAssertEqual(h.state.ranks, [3: 1, 2: 2])
    }

    func test_FR01_R207_answerForEditedInputIsDiscarded() async throws {
        let provider = FakeDecisionProvider(answer: .success(Self.answer(urgency: 0)))
        await provider.hold()
        let h = try harness(count: 1, provider: provider)

        h.state.launch()
        let runner = try XCTUnwrap(h.state.requestScores())
        await provider.waitForHeld(count: 1)
        XCTAssertTrue(h.state.editTask(1, TaskEdit(title: "가짜 할 일 1 고침")))
        await provider.setAnswer(.success(Self.answer(urgency: 3)), for: 1)
        await provider.release(taskID: 1)
        await provider.waitForHeld(count: 1)

        XCTAssertTrue(try h.scoreStore.scores().isEmpty, "고치기 전 입력의 답은 버린다")
        await provider.releaseAll()
        await runner.value

        let calls = await provider.calls
        XCTAssertEqual(calls, [1, 1])
        XCTAssertEqual(try h.scoreStore.scores()[1]?.urgency, 1, "고친 입력의 답만 남는다")
    }

    func test_FR01_R207_noDecisionSetupAsksNothing() throws {
        let repository = InMemoryTaskRepository()
        _ = try repository.insertTask(Self.newTask("가짜 할 일 1"), cycleDay: nil, at: AppTestFixture.noon)
        let state = makeState(repository, scores: InMemoryScoreStore(tasks: repository))

        state.launch()

        XCTAssertNil(state.requestScores())
        XCTAssertFalse(state.hasKey)
        XCTAssertFalse(state.canRetryScores)
        XCTAssertEqual(state.session.taskID, 1, "기존 동작 그대로")
    }

    // MARK: - T033 실패와 폴백(FR-14 R-211, FR-01 R-207, SC-204, SC-205)

    func test_FR14_R211_failuresStoreNothingAndKeepNotch() async throws {
        let errors: [DecisionError] = [
            .missingKey, .unauthorized, .timeout, .rateLimited, .overloaded, .server(status: 500), .network, .malformed,
        ]
        for error in errors {
            let h = try harness(count: 2, provider: FakeDecisionProvider(answer: .failure(error)))
            h.state.launch()
            let session = h.state.session
            await h.state.requestScores()?.value

            XCTAssertTrue(try h.scoreStore.scores().isEmpty, "\(error)")
            XCTAssertTrue(h.state.scores.isEmpty, "\(error)")
            XCTAssertEqual(h.state.session, session, "\(error)")
            XCTAssertEqual(h.state.ranks, [1: 1, 2: 2], "\(error): 마감 순")
        }
    }

    func test_FR14_R211_unreadableAnswerIsMalformedFailure() async throws {
        let bad = DecisionResponse(model: "jev-1.13.0", answers: ["concrete": .noul(0.5)])
        let h = await launched(try harness(count: 1, provider: FakeDecisionProvider(answer: .success(bad))))

        XCTAssertTrue(try h.scoreStore.scores().isEmpty)
        XCTAssertNil(h.state.requestScores(), "실패한 할 일은 활성화 전에는 다시 보내지 않는다")
        h.state.activate()
        await h.state.requestScores()?.value
        let calls = await h.provider.calls
        XCTAssertEqual(calls, [1, 1])
    }

    func test_FR01_R207_failedTaskIsResentOncePerActivation() async throws {
        let provider = Self.ok()
        await provider.setAnswer(.failure(.timeout), for: 1)
        let h = await launched(try harness(count: 2, provider: provider))

        XCTAssertTrue(h.state.editTask(2, TaskEdit(title: "가짜 할 일 2 고침")))
        await h.state.requestScores()?.value
        let afterEdit = await provider.calls
        XCTAssertEqual(afterEdit.filter { $0 == 1 }.count, 1, "활성화가 아니면 실패한 할 일은 다시 보내지 않는다")
        XCTAssertEqual(afterEdit.last, 2)

        h.state.activate()
        await h.state.requestScores()?.value
        let afterFirst = await provider.calls
        XCTAssertEqual(Array(afterFirst.dropFirst(3)), [1])
        XCTAssertNil(h.state.requestScores(), "한 활성화에 한 번")

        h.state.activate()
        await h.state.requestScores()?.value
        let afterSecond = await provider.calls
        XCTAssertEqual(Array(afterSecond.dropFirst(3)), [1, 1])
    }

    func test_FR01_R207_failedStoreWriteCountsAsFailure() async throws {
        let provider = Self.ok()
        let state = try single(scores: UpsertFailingScoreStore(), provider: provider)

        state.launch()
        await state.requestScores()?.value
        XCTAssertNil(state.requestScores())
        state.activate()
        await state.requestScores()?.value

        let calls = await provider.calls
        XCTAssertEqual(calls, [1, 1], "저장이 실패한 할 일은 다음 활성화 때 다시")
        XCTAssertTrue(state.scores.isEmpty)
    }

    func test_FR14_R211_unauthorizedStopsQueriesUntilKeySaved() async throws {
        let provider = FakeDecisionProvider(answer: .failure(.unauthorized))
        await provider.hold()
        let h = try harness(count: 6, provider: provider)

        h.state.launch()
        let runner = try XCTUnwrap(h.state.requestScores())
        await provider.waitForHeld(count: 4)
        await provider.releaseAll()
        await runner.value

        XCTAssertTrue(h.state.keyNeedsCheck)
        let stopped = await provider.calls
        XCTAssertEqual(Set(stopped), [1, 2, 3, 4], "아직 보내지 않은 대상은 보내지 않는다")
        XCTAssertFalse(h.state.canRetryScores)
        XCTAssertNil(h.state.retryScores())
        XCTAssertTrue(h.state.editTask(5, TaskEdit(title: "가짜 할 일 5 고침")))
        h.state.activate()
        XCTAssertNil(h.state.requestScores())
        let still = await provider.calls
        XCTAssertEqual(still.count, 4)

        for id: TaskID in 1...6 { await provider.setAnswer(.success(Self.answer(urgency: 1)), for: id) }
        XCTAssertTrue(h.state.saveKey("fake-key-2"))
        XCTAssertFalse(h.state.keyNeedsCheck)
        await h.state.requestScores()?.value

        let resumed = await provider.calls.dropFirst(4)
        XCTAssertEqual(Set(resumed), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(try h.scoreStore.scores().count, 6)
    }

    func test_FR14_R211_deletingKeyClearsKeyNeedsCheck() async throws {
        let h = await launched(try harness(count: 1, provider: FakeDecisionProvider(answer: .failure(.unauthorized))))
        XCTAssertTrue(h.state.keyNeedsCheck)

        XCTAssertTrue(h.state.deleteKey())

        XCTAssertFalse(h.state.keyNeedsCheck)
        XCTAssertFalse(h.state.hasKey)
        XCTAssertFalse(h.state.keyActionFailed)
    }

    func test_FR01_R207_retryClearsLedgerAndAsksAgain() async throws {
        let provider = Self.ok()
        await provider.setAnswer(.failure(.server(status: 500)), for: 1)
        let h = await launched(try harness(count: 2, provider: provider))
        XCTAssertTrue(h.state.canRetryScores, "다시 물을 할 일이 있다")

        await provider.setAnswer(.success(Self.answer(urgency: 1)), for: 1)
        await h.state.retryScores()?.value

        let calls = await provider.calls
        XCTAssertEqual(Array(calls.dropFirst(2)), [1])
        XCTAssertEqual(try h.scoreStore.scores().count, 2)
        XCTAssertFalse(h.state.canRetryScores, "다시 물을 할 일이 없으면 꺼짐")
    }

    func test_FR14_R211_deletingKeyFallsBackToDeadlineOrder() async throws {
        let provider = FakeDecisionProvider(answer: .success(Self.answer(urgency: 0)))
        await provider.setAnswer(.success(Self.answer(urgency: 3)), for: 3)
        let h = await launched(
            try harness(
                count: 3, deadlines: [Self.day("2027-01-20"), Self.day("2027-01-21"), Self.day("2027-01-22")],
                provider: provider))
        XCTAssertEqual(h.state.ranks, [3: 1, 1: 2, 2: 3])

        XCTAssertTrue(h.state.deleteKey())

        XCTAssertFalse(h.state.hasKey)
        XCTAssertEqual(h.state.ranks, [1: 1, 2: 2, 3: 3], "키를 지우면 마감 순")
        XCTAssertEqual(try h.scoreStore.scores().count, 3, "판단 결과는 지우지 않는다")
    }

    func test_FR14_R211_keyReadFailureSendsNothing() async throws {
        let h = try harness(count: 2)
        h.keys.failing = [.read]

        h.state.launch()
        XCTAssertTrue(h.state.hasKey)
        await h.state.requestScores()?.value

        let calls = await h.provider.calls
        XCTAssertEqual(calls, [])
        XCTAssertFalse(h.state.hasKey, "키를 읽지 못하면 없는 것으로 고친다")
    }

    func test_FR14_R211_keyReadNilSendsNothing() async throws {
        let provider = Self.ok()
        let state = try single(
            scores: InMemoryScoreStore(tasks: InMemoryTaskRepository()), keyStore: PresentButEmptyKeyStore(),
            provider: provider)

        state.launch()
        await state.requestScores()?.value

        let calls = await provider.calls
        XCTAssertEqual(calls, [])
        XCTAssertFalse(state.hasKey)
    }

    func test_FR14_R211_hasKeyFailureMeansNoKey() async throws {
        let h = try harness(count: 1)
        h.keys.failing = [.hasKey]

        h.state.launch()
        await h.state.requestScores()?.value

        XCTAssertFalse(h.state.hasKey)
        let calls = await h.provider.calls
        XCTAssertEqual(calls, [])
    }

    func test_FR01_R207_missingQuestionsAsksNothing() async throws {
        let provider = Self.ok()
        let state = try single(
            scores: InMemoryScoreStore(tasks: InMemoryTaskRepository()), questions: nil, provider: provider)

        state.launch()

        XCTAssertNil(state.requestScores())
        XCTAssertFalse(state.canRetryScores)
        XCTAssertEqual(state.session.taskID, 1)
        let calls = await provider.calls
        XCTAssertEqual(calls, [])
    }

    func test_FR03_R206_missingScoreStoreAsksNothing() async throws {
        let provider = Self.ok()
        let state = try single(scores: nil, provider: provider)

        state.launch()

        XCTAssertNil(state.requestScores())
        XCTAssertFalse(state.canRetryScores)
        let calls = await provider.calls
        XCTAssertEqual(calls, [])
    }

    func test_FR14_R211_buttonsWorkWhileQueryHeld() async throws {
        let provider = Self.ok()
        await provider.hold()
        let h = try harness(count: 2, provider: provider)

        h.state.launch()
        let runner = try XCTUnwrap(h.state.requestScores())
        await provider.waitForHeld(count: 2)
        h.state.start()
        guard case .running = h.state.timer else { return XCTFail("질의 중에도 시작한다: \(h.state.timer)") }
        h.state.complete()

        XCTAssertEqual(h.state.tasks.map(\.status), [.done, .todo])
        await provider.releaseAll()
        await runner.value
        XCTAssertNil(try h.scoreStore.scores()[1], "끝낸 할 일의 답은 버린다")
    }

    func test_FR14_R211_oneHourWithFailingProviderKeepsButtonsWorking() async throws {
        let h = try harness(count: 3, provider: FakeDecisionProvider(answer: .failure(.timeout)))
        h.state.launch()
        await h.state.requestScores()?.value

        h.state.start()
        h.clock.advance(minutes: 20)
        h.state.tick()
        h.state.beginSetAside(.switch)
        h.state.setAsideWithoutNotes()
        XCTAssertEqual(h.state.session.taskID, 2, "바꾸기 뒤 다음 순위")
        await h.state.requestScores()?.value

        h.state.start()
        h.clock.advance(minutes: 25)
        h.state.tick()
        guard case .expired = h.state.timer else { return XCTFail("시간 끝: \(h.state.timer)") }
        h.state.complete()
        await h.state.requestScores()?.value

        h.clock.advance(minutes: 15)
        h.state.activate()
        await h.state.requestScores()?.value
        h.state.start()
        h.clock.advance(minutes: 5)
        h.state.tick()
        h.state.complete()

        XCTAssertEqual(h.state.tasks.map(\.status), [.done, .done, .todo])
        XCTAssertTrue(try h.scoreStore.scores().isEmpty)
    }

    // MARK: - 키 저장·지우기 실패 표시(data-model §9, 화면은 단위 4b)

    func test_FR16_R213_keyActionFailureIsShownUntilNextSuccess() throws {
        let h = try harness(count: 1, key: nil)
        h.state.launch()
        h.keys.failing = [.save]

        XCTAssertFalse(h.state.saveKey("fake-key"))
        XCTAssertTrue(h.state.keyActionFailed)
        XCTAssertFalse(h.state.hasKey)
        XCTAssertFalse(h.state.saveKey("   "), "비면 저장하지 않는다")

        h.keys.failing = []
        XCTAssertTrue(h.state.saveKey("fake-key"))
        XCTAssertFalse(h.state.keyActionFailed)
        XCTAssertTrue(h.state.hasKey)

        h.keys.failing = [.delete]
        XCTAssertFalse(h.state.deleteKey())
        XCTAssertTrue(h.state.keyActionFailed)
        XCTAssertTrue(h.state.hasKey)
    }
}

/// `upsertScore`가 늘 던지는 판단 결과 저장소.
private final class UpsertFailingScoreStore: ScoreStore {
    struct Failure: Error {}

    func scores() throws -> [TaskID: TaskScore] { [:] }
    func upsertScore(_ score: TaskScore) throws { throw Failure() }
}

/// 항목은 있다고 하지만 값을 읽으면 nil인 키 보관함.
private final class PresentButEmptyKeyStore: KeyStore {
    func hasKey() throws -> Bool { true }
    func read() throws -> String? { nil }
    func save(_ key: String) throws {}
    func delete() throws {}
}
