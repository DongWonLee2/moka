import Foundation
import MokaCore
import XCTest

/// spec 006 단위 3: 앱 공급자 설정, 공급자별 키, 바꾸기(data-model §6·§7·§8, research R5·R6).
/// 이름이 다른 가짜 공급자(`fake-a`, `fake-b`, `fake-ms`)와 공급자별 메모리 키 보관함, 가짜 `bind`만 쓴다.
/// 실제 판단 API, 실제 Keychain, 앱 DB를 열지 않는다. 가짜 할 일, 가짜 키, 가짜 주소만 쓴다.
/// 기다림은 실행기 `Task`와 붙잡기로 하고 실제 시간을 기다리지 않는다.
@MainActor
final class AppProviderTests: XCTestCase {
    private static let bundled = try! QuestionSet.bundled()
    /// Microsoft 기준 모델 `fake-ms-base`를 더한 시험용 질문 파일.
    private static let withMicrosoft = try! testQuestions(models: [
        "typesafe": "jev-1.13.0", "liquid": "d1-ultra", "microsoft": "fake-ms-base",
    ])
    /// `typesafe` 줄이 없는 시험용 질문 파일.
    private static let withoutTypeSafe = try! testQuestions(models: ["liquid": "d1-ultra"])

    private static func testQuestions(models: [String: String]) throws -> QuestionSet {
        let thresholds = Dictionary(
            uniqueKeysWithValues: Set(models.values).map { ($0, ["concrete": 0.5, "avoiding": 0.7]) })
        let root: [String: Any] = [
            "version": "v2", "language": "ko", "models": models, "provisional": [String](),
            "questions": [
                "urgency": ["type": "score", "instructions": "가짜 지시 1", "criteria": ["a", "b", "c", "d"]],
                "impact": ["type": "score", "instructions": "가짜 지시 2", "criteria": ["a", "b", "c"]],
                "concrete": ["type": "noul", "instructions": "가짜 지시 3"],
                "avoiding": ["type": "noul", "instructions": "가짜 지시 4"],
            ],
            "thresholds": thresholds,
        ]
        return try QuestionSet(json: JSONSerialization.data(withJSONObject: root))
    }

    /// 첫 호출을 확인한 것처럼 `ids`를 연 가짜 공급자 표.
    private static func catalog(opening ids: Set<ProviderID>) -> [ProviderConfig] {
        ProviderCatalog.all.map { row in
            guard ids.contains(row.id) else { return row }
            return ProviderConfig(
                id: row.id, displayName: row.displayName, endpoint: row.endpoint, auth: row.auth, shape: row.shape,
                issueURL: row.issueURL, issueURLConfirmed: row.issueURLConfirmed, firstCallConfirmed: true)
        }
    }

    /// 질문 넷을 모두 채운 가짜 답. `urgency`는 0~3.
    nonisolated private static func answer(urgency: Double = 1) -> DecisionResponse {
        DecisionResponse(
            model: "fake-model",
            answers: [
                "urgency": .score(
                    score: urgency, confidence: 0.7, probabilities: [0: 0.25, 1: 0.25, 2: 0.25, 3: 0.25]),
                "impact": .score(score: 1, confidence: 0.6, probabilities: [0: 0.2, 1: 0.4, 2: 0.4]),
                "concrete": .noul(0.9),
                "avoiding": .noul(0.3),
            ])
    }

    /// 공급자별 가짜 공급자와 키 보관함. `bind`가 받은 값을 기록한다.
    @MainActor private final class Providers {
        let fakes: [ProviderID: FakeDecisionProvider]
        let keys: [ProviderID: InMemoryKeyStore]
        private(set) var bound: [DecisionSelection.Ready] = []

        init(keys: [ProviderID: String] = [:], fakes: [ProviderID: FakeDecisionProvider] = [:]) {
            var all: [ProviderID: FakeDecisionProvider] = [
                .typesafe: FakeDecisionProvider(name: "fake-a", answer: .success(answer())),
                .liquid: FakeDecisionProvider(name: "fake-b", answer: .success(answer())),
                .microsoft: FakeDecisionProvider(name: "fake-ms", answer: .success(answer())),
            ]
            all.merge(fakes) { $1 }
            self.fakes = all
            self.keys = Dictionary(
                uniqueKeysWithValues: ProviderID.allCases.map { ($0, InMemoryKeyStore(key: keys[$0])) })
        }

        func provider(_ id: ProviderID) -> FakeDecisionProvider {
            fakes[id] ?? FakeDecisionProvider(name: "fake-other", answer: .success(answer()))
        }

        func setup(catalog: [ProviderConfig], questions: QuestionSet?) -> DecisionSetup {
            DecisionSetup(
                bind: { ready in
                    self.bound.append(ready)
                    return DecisionBinding(
                        provider: self.provider(ready.config.id), baseModel: ready.baseModel,
                        requestModel: ready.requestModel)
                },
                keyStore: { id in self.keys[id] ?? InMemoryKeyStore() }, catalog: catalog, questions: questions)
        }

        /// 모든 가짜 공급자에 닿은 요청 수.
        func totalCalls() async -> Int {
            var total = 0
            for fake in fakes.values { total += await fake.calls.count }
            return total
        }
    }

    private struct Harness {
        let state: AppState
        let repository: InMemoryTaskRepository
        let scoreStore: InMemoryScoreStore
        let settings: ControlledSettingsStore
        let providers: Providers
        let clock: TestClock
    }

    private func harness(
        count: Int, providers: Providers, settings: [String: String] = [:],
        catalog: [ProviderConfig] = AppProviderTests.catalog(opening: [.liquid]),
        questions: QuestionSet? = AppProviderTests.bundled
    ) throws -> Harness {
        let repository = InMemoryTaskRepository()
        for index in 0..<count {
            _ = try repository.insertTask(
                NewTask(title: "가짜 할 일 \(index + 1)", deadline: nil, estMin: nil, recurrence: .none, weekday: nil),
                cycleDay: nil, at: AppTestFixture.noon)
        }
        let store = ControlledSettingsStore()
        for (key, value) in settings {
            try store.setValue(value, for: key)
        }
        store.resetWritten()
        let scoreStore = InMemoryScoreStore(tasks: repository)
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(
            repository, settings: store, clock: clock, scores: scoreStore,
            decision: providers.setup(catalog: catalog, questions: questions))
        return Harness(
            state: state, repository: repository, scoreStore: scoreStore, settings: store, providers: providers,
            clock: clock)
    }

    private func launched(_ h: Harness) async -> Harness {
        h.state.launch()
        await h.state.requestScores()?.value
        return h
    }

    private static let microsoftSettings = [CoreSettings.decisionProviderKey: "microsoft"]
    private static let microsoftCatalog = catalog(opening: [.microsoft, .liquid])

    // MARK: - T019 설정 없음·고른 공급자·꺼짐(R-613, R-614, R-617, SC-606~SC-608)

    func test_ADR0011_R614_SC607_upgradeWithTypeSafeKeyScoresWithoutAnyAction() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a"])
        let h = await launched(try harness(count: 2, providers: providers))

        XCTAssertEqual(h.state.selectedProvider, .typesafe, "설정이 없으면 Jev")
        XCTAssertNil(h.state.selectionOff)
        XCTAssertTrue(h.state.hasKey)
        XCTAssertEqual(Set(try h.scoreStore.scores().keys), [1, 2])
        XCTAssertEqual(Set(try h.scoreStore.scores().values.map(\.provider)), ["fake-a"])
        XCTAssertEqual(providers.bound.last?.requestModel, "jev-1.13.0")
        XCTAssertEqual(providers.bound.last?.baseModel, "jev-1.13.0")
        XCTAssertEqual(h.state.sendingHost, "api.typesafe.ai")
        XCTAssertTrue(h.settings.written.isEmpty, "업그레이드는 설정을 쓰지 않는다")
    }

    func test_ADR0011_R614_existingThreeArgumentSetupStillWorks() async throws {
        let repository = InMemoryTaskRepository()
        _ = try repository.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: AppTestFixture.noon)
        let scoreStore = InMemoryScoreStore(tasks: repository)
        let provider = FakeDecisionProvider(answer: .success(Self.answer()))
        let state = makeState(
            repository, scores: scoreStore,
            decision: DecisionSetup(
                keyStore: InMemoryKeyStore(key: "fake-key"), provider: provider, questions: Self.bundled))
        state.launch()
        await state.requestScores()?.value

        XCTAssertEqual(try scoreStore.scores()[1]?.provider, "fake")
        XCTAssertEqual(state.selectedProvider, .typesafe)
    }

    func test_ADR0011_R613_SC608_keyGoesOnlyToSelectedProviderStore() async throws {
        let providers = Providers()
        let h = await launched(
            try harness(count: 1, providers: providers, settings: [CoreSettings.decisionProviderKey: "liquid"]))

        XCTAssertEqual(h.state.selectedProvider, .liquid)
        XCTAssertFalse(h.state.hasKey)
        XCTAssertTrue(h.state.saveKey(" fake-key-b "))
        await h.state.requestScores()?.value

        XCTAssertEqual(try providers.keys[.liquid]?.read(), "fake-key-b")
        XCTAssertNil(try providers.keys[.typesafe]?.read(), "다른 공급자 항목에 넣지 않는다")
        XCTAssertTrue(h.state.hasKey)
        XCTAssertEqual(try h.scoreStore.scores()[1]?.provider, "fake-b")
        XCTAssertEqual(providers.bound.last?.requestModel, "d1-ultra")
    }

    func test_ADR0011_R613_SC608_keyValuesAreNotStoredOutsideKeyStores() async throws {
        let secretA = "fake-secret-key-a-7f3a"
        let secretB = "fake-secret-key-b-91c2"
        let providers = Providers()
        let h = try harness(count: 1, providers: providers)
        h.state.launch()
        XCTAssertTrue(
            h.state.finishOnboarding(
                OnboardingValues(context: nil, quantumMin: 25, extendMin: 10, dayStart: Defaults.dayStart)))
        XCTAssertTrue(h.state.saveKey(secretA))
        await h.state.requestScores()?.value
        h.state.selectProvider(.liquid)
        XCTAssertTrue(h.state.saveKey(secretB))
        await h.state.requestScores()?.value
        h.state.start()
        h.clock.advance(minutes: 5)
        h.state.tick()
        h.state.complete()

        XCTAssertFalse(h.settings.written.isEmpty)
        XCTAssertFalse(try h.repository.decisions().isEmpty, "행동 로그가 남았다")
        for secret in [secretA, secretB] {
            for (name, value) in h.settings.written {
                XCTAssertFalse(name.contains(secret) || value.contains(secret), "설정 \(name)")
            }
            XCTAssertFalse(String(describing: try h.scoreStore.scores()).contains(secret), "판단 결과")
            XCTAssertFalse(String(describing: try h.repository.decisions()).contains(secret), "행동 로그")
        }
    }

    func test_ADR0011_R617_SC606_closedProviderInSettingsTurnsJudgingOff() async throws {
        let providers = Providers(keys: [.liquid: "fake-key-b"])
        let h = try harness(
            count: 2, providers: providers, settings: [CoreSettings.decisionProviderKey: "liquid"],
            catalog: ProviderCatalog.all)
        try h.scoreStore.upsertScore(
            TaskScore(
                taskID: 1, questionVersion: "v2", provider: "fake-b", modelSnapshot: "fake-model", urgency: 1,
                impact: 1, concrete: 0.1, avoiding: 0.3, probsJSON: "{}", stateHash: "0000000000000000",
                scoredAt: AppTestFixture.noon))
        let state = await launched(h).state

        XCTAssertEqual(state.selectionOff, .closedProvider(.liquid))
        XCTAssertEqual(state.selectedProvider, .liquid)
        let calls = await providers.totalCalls()
        XCTAssertEqual(calls, 0, "질의를 보내지 않는다")
        XCTAssertEqual(state.ranks, [1: 1, 2: 2], "마감일 순(판단 결과를 쓰지 않음)")
        XCTAssertEqual(state.reasonLine, "마감 없음 · 미룬 0번", "중요도 칸이 없다")
        XCTAssertEqual(state.gatePhase, .closed)
        XCTAssertTrue(state.hasKey, "꺼져 있어도 고른 공급자 항목을 읽는다")
        XCTAssertTrue(state.deleteKey())
        XCTAssertNil(try providers.keys[.liquid]?.read())
        XCTAssertTrue(state.saveKey("fake-key-b2"))
        XCTAssertEqual(try providers.keys[.liquid]?.read(), "fake-key-b2")
    }

    func test_ADR0011_R617_offMicrosoftWithoutEndpointStillHandlesKeys() async throws {
        let providers = Providers()
        let h = await launched(
            try harness(
                count: 1, providers: providers, settings: Self.microsoftSettings, catalog: Self.microsoftCatalog,
                questions: Self.withMicrosoft))

        XCTAssertEqual(h.state.selectionOff, .needsEndpoint)
        XCTAssertNil(h.state.sendingHost, "주소가 없으면 보내는 곳이 없다")
        XCTAssertFalse(h.state.hasKey)
        XCTAssertTrue(h.state.saveKey("fake-key-ms"))
        XCTAssertTrue(h.state.hasKey)
        XCTAssertEqual(try providers.keys[.microsoft]?.read(), "fake-key-ms")
        XCTAssertTrue(h.state.deleteKey())
        XCTAssertFalse(h.state.hasKey)
        let calls = await providers.totalCalls()
        XCTAssertEqual(calls, 0)
    }

    func test_ADR0011_R614_SC606_unknownProviderTurnsKeyActionsOff() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a"])
        let h = await launched(
            try harness(count: 1, providers: providers, settings: [CoreSettings.decisionProviderKey: "fake-unknown"]))

        XCTAssertNil(h.state.selectedProvider)
        XCTAssertEqual(h.state.selectionOff, .unknownProvider)
        XCTAssertFalse(h.state.hasKey)
        XCTAssertFalse(h.state.saveKey("fake-key-x"))
        XCTAssertFalse(h.state.deleteKey())
        XCTAssertEqual(try providers.keys[.typesafe]?.read(), "fake-key-a", "다른 항목을 건드리지 않는다")
        let calls = await providers.totalCalls()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(h.state.sendingHost)
    }

    func test_ADR0011_R609_SC606_missingTypeSafeBaseModelTurnsJudgingOff() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a"])
        let h = await launched(
            try harness(count: 2, providers: providers, catalog: ProviderCatalog.all, questions: Self.withoutTypeSafe))

        XCTAssertEqual(h.state.selectionOff, .closedProvider(.typesafe))
        let calls = await providers.totalCalls()
        XCTAssertEqual(calls, 0, "질문 파일에 기준 모델이 없으면 묻지 않는다")
        XCTAssertTrue(try h.scoreStore.scores().isEmpty)
        XCTAssertEqual(h.state.ranks, [1: 1, 2: 2])
        XCTAssertTrue(h.state.hasKey, "키 칸은 그대로 Jev 항목을 읽는다")
        XCTAssertNil(h.state.requestScores())
    }

    // MARK: - T024 바꾸기(R-615, R-611, SC-605)

    func test_ADR0011_R615_selectingSameProviderDoesNothing() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a"])
        let h = await launched(try harness(count: 2, providers: providers))
        let boundBefore = providers.bound.count

        h.state.selectProvider(.typesafe)

        XCTAssertTrue(h.settings.written.isEmpty)
        XCTAssertEqual(providers.bound.count, boundBefore, "바인딩을 다시 만들지 않는다")
        XCTAssertNil(h.state.requestScores())
        let calls = await providers.provider(.typesafe).calls
        XCTAssertEqual(calls.count, 2)
    }

    func test_ADR0011_R615_R617_selectingClosedProviderDoesNothing() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a"])
        let h = await launched(try harness(count: 1, providers: providers))

        h.state.selectProvider(.perplexity)

        XCTAssertEqual(h.state.selectedProvider, .typesafe)
        XCTAssertTrue(h.settings.written.isEmpty)
        XCTAssertNil(h.state.selectionOff)
    }

    func test_ADR0011_R615_settingsWriteFailureKeepsCurrentProvider() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a", .liquid: "fake-key-b"])
        let h = await launched(try harness(count: 1, providers: providers))
        h.settings.failingKeys = [CoreSettings.decisionProviderKey]

        h.state.selectProvider(.liquid)

        XCTAssertEqual(h.state.selectedProvider, .typesafe)
        XCTAssertEqual(h.state.providerActionFailure, .select)
        XCTAssertNil(h.state.requestScores(), "바꾸지 않았으므로 다시 묻지 않는다")

        h.settings.failingKeys = []
        h.state.selectProvider(.liquid)
        XCTAssertEqual(h.state.selectedProvider, .liquid)
        XCTAssertNil(h.state.providerActionFailure, "다음 성공에 지운다")
        XCTAssertEqual(try h.settings.value(for: CoreSettings.decisionProviderKey), "liquid")
    }

    func test_ADR0011_R615_R611_SC605_switchStopsUsingOldScoresAndAsksEveryTaskAgain() async throws {
        let first = FakeDecisionProvider(name: "fake-a", answer: .success(Self.answer()))
        await first.setAnswer(.success(Self.answer(urgency: 0)), for: 1)
        await first.setAnswer(.success(Self.answer(urgency: 3)), for: 3)
        let providers = Providers(keys: [.typesafe: "fake-key-a", .liquid: "fake-key-b"], fakes: [.typesafe: first])
        let h = await launched(try harness(count: 3, providers: providers))
        XCTAssertEqual(h.state.ranks, [3: 1, 2: 2, 1: 3], "Jev 판단 결과로 순서")

        let second = providers.provider(.liquid)
        await second.hold()
        h.state.selectProvider(.liquid)

        XCTAssertEqual(h.state.ranks, [1: 1, 2: 2, 3: 3], "바꾸면 이전 공급자 판단 결과를 쓰지 않는다")
        let runner = try XCTUnwrap(h.state.requestScores())
        await second.waitForHeld(count: 3)
        await second.releaseAll()
        await runner.value

        let calls = await second.calls
        XCTAssertEqual(Set(calls), [1, 2, 3], "대기 할 일을 모두 새 공급자에 묻는다")
        XCTAssertEqual(Set(try h.scoreStore.scores().values.map(\.provider)), ["fake-b"])
        XCTAssertEqual(try h.settings.value(for: CoreSettings.decisionProviderKey), "liquid")
    }

    func test_ADR0011_R615_switchClearsKeyNoticeAndReadsNewStore() async throws {
        let first = FakeDecisionProvider(name: "fake-a", answer: .failure(.unauthorized))
        let providers = Providers(keys: [.typesafe: "fake-key-a"], fakes: [.typesafe: first])
        let h = await launched(try harness(count: 1, providers: providers))
        XCTAssertTrue(h.state.showsKeyNotice, "401 뒤 키 확인 필요")

        h.state.selectProvider(.liquid)

        XCTAssertFalse(h.state.showsKeyNotice)
        XCTAssertFalse(h.state.hasKey, "새 공급자 항목에는 키가 없다")
        XCTAssertNil(h.state.requestScores(), "키가 없어 묻지 않는다")
    }

    func test_ADR0011_R615_answerSentBeforeSwitchIsNotStored() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a", .liquid: "fake-key-b"])
        let first = providers.provider(.typesafe)
        let second = providers.provider(.liquid)
        await first.hold()
        let h = try harness(count: 2, providers: providers)
        h.state.launch()
        let runner = try XCTUnwrap(h.state.requestScores())
        await first.waitForHeld(count: 2)

        await second.hold()
        h.state.selectProvider(.liquid)
        await first.releaseAll()
        await second.waitForHeld(count: 2)

        XCTAssertTrue(try h.scoreStore.scores().isEmpty, "바꾸기 전 떠난 답은 저장하지 않는다")
        await second.releaseAll()
        await runner.value
        XCTAssertEqual(Set(try h.scoreStore.scores().values.map(\.provider)), ["fake-b"])
    }

    func test_ADR0011_R615_unauthorizedSentBeforeSwitchDoesNotNeedKeyCheck() async throws {
        let first = FakeDecisionProvider(name: "fake-a", answer: .failure(.unauthorized))
        let providers = Providers(keys: [.typesafe: "fake-key-a", .liquid: "fake-key-b"], fakes: [.typesafe: first])
        let second = providers.provider(.liquid)
        await first.hold()
        let h = try harness(count: 1, providers: providers)
        h.state.launch()
        let runner = try XCTUnwrap(h.state.requestScores())
        await first.waitForHeld(count: 1)

        await second.hold()
        h.state.selectProvider(.liquid)
        await first.releaseAll()
        await second.waitForHeld(count: 1)

        XCTAssertFalse(h.state.showsKeyNotice, "이전 공급자의 401로 키 확인 필요를 켜지 않는다")
        await second.releaseAll()
        await runner.value
        XCTAssertFalse(h.state.showsKeyNotice)
        XCTAssertEqual(try h.scoreStore.scores()[1]?.provider, "fake-b")
    }

    /// 이전 공급자의 실패가 새 공급자 장부를 실패로 적으면 활성화 때 그 할 일을 장부에서 빼 한 번 더 보낸다.
    func test_ADR0011_R615_failureSentBeforeSwitchDoesNotMarkNewLedger() async throws {
        let first = FakeDecisionProvider(name: "fake-a", answer: .success(Self.answer()))
        await first.setAnswer(.failure(.rateLimited), for: 2)
        let providers = Providers(keys: [.typesafe: "fake-key-a", .liquid: "fake-key-b"], fakes: [.typesafe: first])
        let second = providers.provider(.liquid)
        await first.hold()
        let h = try harness(count: 3, providers: providers)
        h.state.launch()
        let runner = try XCTUnwrap(h.state.requestScores())
        await first.waitForHeld(count: 3)

        await second.hold()
        h.state.selectProvider(.liquid)
        await first.release(taskID: 1)
        await second.waitForHeld(count: 2)
        await first.release(taskID: 2)
        await second.waitForHeld(count: 3)
        h.state.activate()
        await first.release(taskID: 3)
        await second.releaseAll()
        await first.releaseAll()
        await runner.value
        await h.state.requestScores()?.value

        let calls = await second.calls
        XCTAssertEqual(calls.filter { $0 == 2 }.count, 1, "이전 공급자의 429로 새 장부를 실패로 적지 않는다")
        XCTAssertEqual(Set(try h.scoreStore.scores().values.map(\.provider)), ["fake-b"])
    }

    func test_ADR0011_R613_R615_settingsReadFailureAfterSelectKeepsBindingAndKeyOnSameProvider() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a", .liquid: "fake-key-b"])
        let h = await launched(try harness(count: 1, providers: providers))
        let first = providers.provider(.typesafe)
        let callsBefore = await first.calls.count
        h.settings.failingReads = [CoreSettings.decisionProviderKey]

        h.state.selectProvider(.liquid)
        await h.state.requestScores()?.value

        XCTAssertEqual(h.state.selectedProvider, .liquid)
        XCTAssertEqual(providers.bound.last?.config.id, .liquid, "바인딩도 고른 공급자로 만든다")
        let destination = try XCTUnwrap(providers.bound.last?.url)
        XCTAssertEqual(EndpointRule.host(of: destination), "api.liquid.ai")
        XCTAssertEqual(h.state.sendingHost, "api.liquid.ai")
        let callsAfter = await first.calls.count
        XCTAssertEqual(callsAfter, callsBefore, "Liquid 키가 Jev 공급자로 가지 않는다")
        XCTAssertEqual(try h.scoreStore.scores()[1]?.provider, "fake-b")
    }

    func test_ADR0011_R614_128_settingsReadFailureAtLaunchTurnsJudgingOff() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a", .liquid: "fake-key-b"])
        let repository = InMemoryTaskRepository()
        for (title, deadline) in [("가짜 할 일 1", "2027-01-20"), ("가짜 할 일 2", "2027-01-15")] {
            _ = try repository.insertTask(
                NewTask(
                    title: title, deadline: LocalDay(text: deadline), estMin: nil, recurrence: .none, weekday: nil),
                cycleDay: nil, at: AppTestFixture.noon)
        }
        let settings = ControlledSettingsStore()
        try settings.setValue("liquid", for: CoreSettings.decisionProviderKey)
        settings.failingReads = [CoreSettings.decisionProviderKey]
        let scoreStore = InMemoryScoreStore(tasks: repository)
        let state = makeState(
            repository, settings: settings, scores: scoreStore,
            decision: providers.setup(catalog: Self.catalog(opening: [.liquid]), questions: Self.bundled))
        state.launch()
        await state.requestScores()?.value

        XCTAssertNil(state.selectedProvider)
        XCTAssertEqual(state.selectionOff, .unknownProvider)
        let calls = await providers.totalCalls()
        XCTAssertEqual(calls, 0, "Jev 키가 있어도 묻지 않는다")
        XCTAssertTrue(try scoreStore.scores().isEmpty)
        XCTAssertEqual(state.ranks, [2: 1, 1: 2], "마감이 가까운 순")
        XCTAssertEqual(try providers.keys[.typesafe]?.read(), "fake-key-a", "키를 지우지 않는다")
        XCTAssertEqual(try providers.keys[.liquid]?.read(), "fake-key-b")
        XCTAssertNil(state.decisionField.selected)
        XCTAssertEqual(state.decisionField.offNote, DecisionFieldText.offNote(.unknownProvider), "다시 골라 달라고 안내")
        XCTAssertNil(state.sendingHost)
    }

    func test_ADR0011_R614_R615_128_choosingProviderAfterLaunchReadFailureTurnsJudgingBackOn() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a", .liquid: "fake-key-b"])
        let repository = InMemoryTaskRepository()
        _ = try repository.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: AppTestFixture.noon)
        let settings = ControlledSettingsStore()
        settings.failingReads = [CoreSettings.decisionProviderKey]
        let scoreStore = InMemoryScoreStore(tasks: repository)
        let state = makeState(
            repository, settings: settings, scores: scoreStore,
            decision: providers.setup(catalog: Self.catalog(opening: [.liquid]), questions: Self.bundled))
        state.launch()
        await state.requestScores()?.value
        XCTAssertEqual(state.selectionOff, .unknownProvider)

        state.selectProvider(.liquid)
        await state.requestScores()?.value

        XCTAssertEqual(state.selectedProvider, .liquid)
        XCTAssertNil(state.selectionOff, "다시 고르면 읽기가 계속 실패해도 판단 기능이 켜진다")
        XCTAssertNil(state.decisionField.offNote)
        XCTAssertEqual(state.sendingHost, "api.liquid.ai")
        XCTAssertEqual(try scoreStore.scores()[1]?.provider, "fake-b")
        let typesafeCalls = await providers.provider(.typesafe).calls
        XCTAssertTrue(typesafeCalls.isEmpty)
    }

    func test_ADR0011_R615_switchToOffProviderReadsItsKeyStore() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a", .microsoft: "fake-key-ms"])
        let h = await launched(
            try harness(count: 1, providers: providers, catalog: Self.microsoftCatalog, questions: Self.withMicrosoft))

        h.state.selectProvider(.microsoft)

        XCTAssertEqual(h.state.selectedProvider, .microsoft)
        XCTAssertEqual(h.state.selectionOff, .needsEndpoint)
        XCTAssertTrue(h.state.hasKey, "주소 없는 off 상태에서도 그 항목을 읽는다")
        XCTAssertNil(h.state.requestScores())
    }

    func test_ADR0011_R615_R611_switchingBackReusesEarlierKeyAndScores() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a"])
        let h = await launched(try harness(count: 2, providers: providers))

        h.state.selectProvider(.liquid)
        XCTAssertFalse(h.state.hasKey)
        h.state.selectProvider(.typesafe)
        await h.state.requestScores()?.value

        XCTAssertTrue(h.state.hasKey)
        let first = await providers.provider(.typesafe).calls
        let second = await providers.provider(.liquid).calls
        XCTAssertEqual(first.count, 2, "이전 판단 결과를 다시 쓰고 다시 묻지 않는다")
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(Set(try h.scoreStore.scores().values.map(\.provider)), ["fake-a"])
    }

    // MARK: - T026 Microsoft 칸 저장(R-616, R-623, SC-609)

    private func microsoftHarness(
        count: Int = 1, providers: Providers, settings: [String: String] = AppProviderTests.microsoftSettings
    ) throws -> Harness {
        try harness(
            count: count, providers: providers, settings: settings, catalog: Self.microsoftCatalog,
            questions: Self.withMicrosoft)
    }

    func test_ADR0011_R616_rejectedEndpointIsNotSaved() async throws {
        let h = await launched(try microsoftHarness(providers: Providers()))

        XCTAssertEqual(
            h.state.saveMicrosoft(endpoint: "http://example-resource.invalid", deployment: "fake-deploy"), .scheme)
        XCTAssertEqual(
            h.state.saveMicrosoft(endpoint: "https://example-resource.invalid/openai", deployment: "fake-deploy"),
            .path)
        XCTAssertTrue(h.settings.written.isEmpty)
        XCTAssertEqual(h.state.selectionOff, .needsEndpoint)
    }

    func test_ADR0011_R616_emptyValuesAreNotSaved() async throws {
        let h = await launched(try microsoftHarness(providers: Providers()))

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "  ", deployment: "fake-deploy"))
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: " \n"))
        XCTAssertTrue(h.settings.written.isEmpty)
    }

    func test_ADR0011_R616_SC609_firstSaveKeepsKeyAndTurnsJudgingOn() async throws {
        let providers = Providers()
        let h = await launched(try microsoftHarness(providers: providers))
        XCTAssertTrue(h.state.saveKey("fake-key-ms"), "주소 없는 off 상태에서 먼저 넣은 키")

        XCTAssertNil(
            h.state.saveMicrosoft(endpoint: " https://example-resource.invalid/ ", deployment: " fake-deploy "))
        await h.state.requestScores()?.value

        XCTAssertEqual(try providers.keys[.microsoft]?.read(), "fake-key-ms", "처음 저장에는 키를 지우지 않는다")
        XCTAssertNil(h.state.selectionOff)
        XCTAssertEqual(
            try h.settings.value(for: CoreSettings.microsoftEndpointKey), "https://example-resource.invalid")
        XCTAssertEqual(try h.settings.value(for: CoreSettings.microsoftDeploymentKey), "fake-deploy")
        XCTAssertEqual(providers.bound.last?.requestModel, "fake-deploy")
        XCTAssertEqual(providers.bound.last?.baseModel, "fake-ms-base")
        XCTAssertEqual(
            providers.bound.last?.url, URL(string: "https://example-resource.invalid/providers/microsoft/v1/systemone"))
        XCTAssertEqual(h.state.sendingHost, "example-resource.invalid")
        XCTAssertEqual(try h.scoreStore.scores()[1]?.provider, "fake-ms")
    }

    func test_ADR0011_R616_SC609_changingSavedEndpointDeletesKey() async throws {
        let providers = Providers(keys: [.microsoft: "fake-key-ms"])
        let h = await launched(try microsoftHarness(providers: providers))
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy"))

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy-2"))
        XCTAssertEqual(try providers.keys[.microsoft]?.read(), "fake-key-ms", "주소가 같으면 키를 지우지 않는다")

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://other-resource.invalid", deployment: "fake-deploy-2"))
        XCTAssertNil(try providers.keys[.microsoft]?.read(), "주소를 바꾸면 키를 먼저 지운다")
        XCTAssertFalse(h.state.hasKey)
        XCTAssertEqual(h.state.sendingHost, "other-resource.invalid")
    }

    func test_ADR0011_R616_139_caseOnlyEndpointChangeKeepsKey() async throws {
        let providers = Providers(keys: [.microsoft: "fake-key-ms"])
        let h = await launched(try microsoftHarness(providers: providers))
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://Example-Resource.invalid", deployment: "fake-deploy"))
        XCTAssertEqual(
            try h.settings.value(for: CoreSettings.microsoftEndpointKey), "https://example-resource.invalid",
            "소문자 호스트로 저장한다")

        XCTAssertNil(
            h.state.saveMicrosoft(endpoint: "HTTPS://EXAMPLE-RESOURCE.INVALID", deployment: "fake-deploy-2"))

        XCTAssertEqual(try providers.keys[.microsoft]?.read(), "fake-key-ms", "대소문자만 다르면 키를 지우지 않는다")
        XCTAssertEqual(h.state.decisionField.microsoft?.keyCleared, false)
        XCTAssertEqual(providers.bound.last?.requestModel, "fake-deploy-2")
    }

    func test_ADR0011_R616_139_oldUppercaseSavedEndpointKeepsKey() async throws {
        let providers = Providers(keys: [.microsoft: "fake-key-ms"])
        var settings = Self.microsoftSettings
        settings[CoreSettings.microsoftEndpointKey] = "https://Example-Resource.INVALID"
        settings[CoreSettings.microsoftDeploymentKey] = "fake-deploy"
        let h = await launched(try microsoftHarness(providers: providers, settings: settings))

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy-2"))

        XCTAssertEqual(try providers.keys[.microsoft]?.read(), "fake-key-ms")
        XCTAssertEqual(try h.settings.value(for: CoreSettings.microsoftDeploymentKey), "fake-deploy-2")
    }

    func test_ADR0011_R616_128_savedEndpointReadFailureDeletesKey() async throws {
        let providers = Providers(keys: [.microsoft: "fake-key-ms"])
        let h = await launched(try microsoftHarness(providers: providers))
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy"))
        h.settings.resetWritten()
        h.settings.failingReads = [CoreSettings.microsoftEndpointKey]

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://other-resource.invalid", deployment: "fake-deploy"))

        XCTAssertNil(try providers.keys[.microsoft]?.read(), "옛 키가 새 주소로 가지 않게 지운다")
        XCTAssertFalse(h.state.hasKey)
        XCTAssertTrue(
            h.settings.written.contains { $0 == (CoreSettings.microsoftEndpointKey, "https://other-resource.invalid") })
        XCTAssertEqual(h.state.decisionField.microsoft?.keyCleared, true)
    }

    func test_ADR0011_R616_keyDeleteFailureKeepsOldEndpoint() async throws {
        let providers = Providers(keys: [.microsoft: "fake-key-ms"])
        let h = await launched(try microsoftHarness(providers: providers))
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy"))
        try XCTUnwrap(providers.keys[.microsoft]).failing = [.delete]

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://other-resource.invalid", deployment: "fake-deploy"))

        XCTAssertEqual(
            try h.settings.value(for: CoreSettings.microsoftEndpointKey), "https://example-resource.invalid",
            "옛 키가 새 호스트로 가지 않게 주소를 저장하지 않는다")
        XCTAssertTrue(h.state.keyActionFailed)
        XCTAssertEqual(h.state.sendingHost, "example-resource.invalid")
    }

    func test_ADR0011_R616_settingsWriteFailureKeepsOldBindingAndShowsDeletedKey() async throws {
        let providers = Providers(keys: [.microsoft: "fake-key-ms"])
        let h = await launched(try microsoftHarness(providers: providers))
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy"))
        await h.state.requestScores()?.value
        h.settings.failingKeys = [CoreSettings.microsoftEndpointKey]

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://other-resource.invalid", deployment: "fake-deploy"))

        XCTAssertEqual(h.state.providerActionFailure, .saveMicrosoft)
        XCTAssertEqual(h.state.sendingHost, "example-resource.invalid", "바인딩은 옛 주소 그대로")
        XCTAssertFalse(h.state.hasKey, "이미 지운 키는 키 없음으로 보인다")
        XCTAssertNil(h.state.requestScores(), "키가 없어 옛 주소로도 묻지 않는다")
    }

    func test_ADR0011_R616_deploymentWriteFailureKeepsShownHostEqualToDestination() async throws {
        let providers = Providers(keys: [.microsoft: "fake-key-ms"])
        let h = await launched(try microsoftHarness(providers: providers))
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy"))
        await h.state.requestScores()?.value
        h.settings.failingKeys = [CoreSettings.microsoftDeploymentKey]

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://other-resource.invalid", deployment: "fake-deploy-2"))

        XCTAssertEqual(h.state.providerActionFailure, .saveMicrosoft)
        XCTAssertEqual(
            try h.settings.value(for: CoreSettings.microsoftEndpointKey), "https://other-resource.invalid",
            "주소만 저장됐다")
        let destination = try XCTUnwrap(providers.bound.last?.url)
        XCTAssertEqual(EndpointRule.host(of: destination), "other-resource.invalid", "바인딩을 저장된 값으로 맞춘다")
        XCTAssertEqual(h.state.sendingHost, EndpointRule.host(of: destination), "보이는 곳과 실제 목적지가 같다")
        XCTAssertEqual(providers.bound.last?.requestModel, "fake-deploy", "배포 이름은 저장된 옛 값")
        XCTAssertFalse(h.state.hasKey, "주소가 바뀌어 지운 키는 키 없음으로 보인다")
    }

    func test_ADR0011_R616_writeFailureWhileQueryInFlightAsksAgain() async throws {
        let microsoft = FakeDecisionProvider(name: "fake-ms", answer: .success(Self.answer()))
        let providers = Providers(keys: [.microsoft: "fake-key-ms"], fakes: [.microsoft: microsoft])
        let h = await launched(try microsoftHarness(providers: providers))
        await microsoft.hold()
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy"))
        let runner = try XCTUnwrap(h.state.requestScores())
        await microsoft.waitForHeld(count: 1)
        h.settings.failingKeys = [CoreSettings.microsoftDeploymentKey]

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy-2"))
        XCTAssertEqual(h.state.providerActionFailure, .saveMicrosoft)
        await microsoft.releaseAll()
        await runner.value
        await h.state.requestScores()?.value

        let calls = await microsoft.calls
        XCTAssertEqual(calls, [1, 1], "세대가 바뀌어 버린 답의 할 일을 다시 묻는다")
        XCTAssertEqual(try h.scoreStore.scores()[1]?.provider, "fake-ms")
    }

    func test_ADR0011_R616_saveMicrosoftDoesNothingWhenAnotherProviderIsSelected() async throws {
        let providers = Providers(keys: [.typesafe: "fake-key-a", .microsoft: "fake-key-ms"])
        let h = await launched(
            try harness(count: 1, providers: providers, catalog: Self.microsoftCatalog, questions: Self.withMicrosoft))
        let boundBefore = providers.bound.count

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy"))

        XCTAssertTrue(h.settings.written.isEmpty, "Microsoft를 고르지 않았으면 저장하지 않는다")
        XCTAssertEqual(providers.bound.count, boundBefore, "바인딩을 다시 만들지 않는다")
        XCTAssertEqual(try providers.keys[.microsoft]?.read(), "fake-key-ms")
        XCTAssertEqual(h.state.sendingHost, "api.typesafe.ai")
    }

    func test_ADR0011_R616_saveClearsKeyNoticeAndLedger() async throws {
        let microsoft = FakeDecisionProvider(name: "fake-ms", answer: .failure(.unauthorized))
        let providers = Providers(keys: [.microsoft: "fake-key-ms"], fakes: [.microsoft: microsoft])
        let h = await launched(try microsoftHarness(providers: providers))
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy"))
        await h.state.requestScores()?.value
        XCTAssertTrue(h.state.showsKeyNotice)

        await microsoft.setAnswer(.success(Self.answer()), for: 1)
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy-2"))

        XCTAssertFalse(h.state.showsKeyNotice)
        await h.state.requestScores()?.value
        let calls = await microsoft.calls
        XCTAssertEqual(calls, [1, 1], "장부를 비워 다시 묻는다")
        XCTAssertEqual(try h.scoreStore.scores()[1]?.provider, "fake-ms")
    }

    /// 정규화하면 저장된 값과 같은 주소를 다시 저장하면 아무것도 바꾸지 않는다(PR #136 리뷰 중간 2).
    func test_ADR0011_R616_savingSameNormalizedValuesDoesNothing() async throws {
        let microsoft = FakeDecisionProvider(name: "fake-ms", answer: .failure(.unauthorized))
        let providers = Providers(keys: [.microsoft: "fake-key-ms"], fakes: [.microsoft: microsoft])
        let h = await launched(try microsoftHarness(providers: providers))
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid/", deployment: "fake-deploy"))
        await h.state.requestScores()?.value
        XCTAssertTrue(h.state.showsKeyNotice)
        h.settings.resetWritten()
        let boundCount = providers.bound.count

        XCTAssertNil(
            h.state.saveMicrosoft(endpoint: " https://example-resource.invalid/ ", deployment: " fake-deploy "))

        XCTAssertTrue(h.settings.written.isEmpty, "설정을 다시 쓰지 않는다")
        XCTAssertTrue(h.state.showsKeyNotice, "키 확인 필요를 끄지 않는다")
        XCTAssertEqual(providers.bound.count, boundCount, "바인딩을 다시 만들지 않는다")
        XCTAssertNil(h.state.requestScores(), "장부를 비우지 않아 다시 묻지 않는다")
        XCTAssertEqual(try providers.keys[.microsoft]?.read(), "fake-key-ms")
    }

    func test_ADR0011_R616_deploymentChangeSendsNewNameAndKeepsScores() async throws {
        let microsoft = FakeDecisionProvider(name: "fake-ms", answer: .success(Self.answer()))
        let providers = Providers(keys: [.microsoft: "fake-key-ms"], fakes: [.microsoft: microsoft])
        let h = await launched(try microsoftHarness(count: 2, providers: providers))
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy"))
        await h.state.requestScores()?.value
        let before = try h.scoreStore.scores()

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy-2"))

        XCTAssertNil(h.state.requestScores(), "판단 입력이 같으면 다시 묻지 않는다")
        XCTAssertEqual(try h.scoreStore.scores(), before, "저장된 판단 결과는 그대로 쓴다")
        XCTAssertEqual(h.state.ranks.count, 2)
        XCTAssertEqual(providers.bound.last?.requestModel, "fake-deploy-2", "다음 요청 모델은 새 배포 이름")
    }

    // MARK: - 단위 4 판단 모델 칸 값(R-620~R-623, data-model §9)

    func test_ADR0011_R620_fieldListsFiveProvidersAndOnlyTypeSafeIsOpen() async throws {
        let h = await launched(try harness(count: 1, providers: Providers(), catalog: ProviderCatalog.all))
        let field = h.state.decisionField

        XCTAssertEqual(field.providers.map(\.id), [.typesafe, .microsoft, .liquid, .perplexity, .openai])
        XCTAssertEqual(
            field.providers.map(\.displayName),
            ["TypeSafe Jev", "Microsoft-Decision-1", "Liquid d1-ultra", "Perplexity Decider v1.2", "OpenAI Decisions"])
        XCTAssertEqual(field.providers.filter(\.isOpen).map(\.id), [.typesafe])
        XCTAssertEqual(field.providers.first?.closedNote, nil)
        XCTAssertEqual(Set(field.providers.dropFirst().map(\.closedNote)), [DecisionFieldText.closedNote])
        XCTAssertEqual(field.selected, .typesafe)
        XCTAssertEqual(field.host, "api.typesafe.ai")
        XCTAssertNil(field.issueURL, "발급 링크를 확인하지 않은 공급자는 링크가 없다")
        XCTAssertFalse(field.provisional)
        XCTAssertNil(field.offNote)
        XCTAssertNil(field.microsoft, "Microsoft를 고르지 않으면 주소 칸이 없다")
        XCTAssertEqual(field.keyState, .noKey)
        XCTAssertNil(field.failure)
    }

    func test_ADR0011_R620_issueURLOnlyWhenConfirmed() async throws {
        let confirmed = ProviderCatalog.all.map { row in
            guard row.id == .liquid else { return row }
            return ProviderConfig(
                id: row.id, displayName: row.displayName, endpoint: row.endpoint, auth: row.auth, shape: row.shape,
                issueURL: row.issueURL, issueURLConfirmed: true, firstCallConfirmed: true)
        }
        let unconfirmed = await launched(try harness(count: 1, providers: Providers()))
        unconfirmed.state.selectProvider(.liquid)
        XCTAssertNil(unconfirmed.state.decisionField.issueURL)

        let h = await launched(try harness(count: 1, providers: Providers(), catalog: confirmed))
        h.state.selectProvider(.liquid)
        XCTAssertEqual(h.state.decisionField.issueURL, URL(string: "https://console.liquid.ai"))
        XCTAssertEqual(h.state.decisionField.host, "api.liquid.ai")
    }

    func test_ADR0011_R621_provisionalFollowsSelectedBaseModel() async throws {
        let h = await launched(try harness(count: 1, providers: Providers()))
        XCTAssertFalse(h.state.decisionField.provisional, "Jev 기준값은 잠정값이 아니다")

        h.state.selectProvider(.liquid)

        XCTAssertTrue(h.state.decisionField.provisional, "d1-ultra는 질문 파일 provisional에 있다")
        XCTAssertNil(h.state.decisionField.providers.first { $0.id == .liquid }?.closedNote)
    }

    func test_ADR0011_R615_R620_selectFailureShowsInField() async throws {
        let h = await launched(try harness(count: 1, providers: Providers()))
        h.settings.failingKeys = [CoreSettings.decisionProviderKey]

        h.state.decisionField.onSelect(.liquid)

        XCTAssertEqual(h.state.decisionField.selected, .typesafe)
        XCTAssertEqual(h.state.decisionField.failure, .select)
        h.settings.failingKeys = []
        h.state.decisionField.onSelect(.liquid)
        XCTAssertEqual(h.state.decisionField.selected, .liquid)
        XCTAssertNil(h.state.decisionField.failure)
    }

    func test_ADR0011_R614_unknownProviderFieldAsksToChooseAgain() async throws {
        let h = await launched(
            try harness(count: 1, providers: Providers(), settings: [CoreSettings.decisionProviderKey: "fake-unknown"]))

        XCTAssertNil(h.state.decisionField.selected)
        XCTAssertEqual(h.state.decisionField.offNote, DecisionFieldText.offNote(.unknownProvider))
        XCTAssertNil(h.state.decisionField.host)
    }

    func test_ADR0011_R623_microsoftFieldBeforeAndAfterSave() async throws {
        let h = await launched(try microsoftHarness(providers: Providers()))
        let empty = try XCTUnwrap(h.state.decisionField.microsoft)
        XCTAssertNil(empty.savedEndpoint)
        XCTAssertNil(empty.savedDeployment)
        XCTAssertFalse(empty.showsKeyResetNotice, "처음 저장은 키를 지우지 않는다")
        XCTAssertFalse(empty.keyCleared)
        XCTAssertEqual(h.state.decisionField.offNote, DecisionFieldText.offNote(.needsEndpoint))
        XCTAssertNil(h.state.decisionField.host, "주소가 없으면 가는 곳 줄 대신 안내가 보인다")

        XCTAssertEqual(
            h.state.decisionField.onSaveMicrosoft("http://example-resource.invalid", "fake-deploy"), .scheme)
        XCTAssertNil(h.state.decisionField.onSaveMicrosoft(" https://example-resource.invalid/ ", " fake-deploy "))

        let saved = try XCTUnwrap(h.state.decisionField.microsoft)
        XCTAssertEqual(saved.savedEndpoint, "https://example-resource.invalid")
        XCTAssertEqual(saved.savedDeployment, "fake-deploy")
        XCTAssertTrue(saved.showsKeyResetNotice, "저장된 주소가 있으면 바꾸기 전에 키를 지운다고 안내한다")
        XCTAssertFalse(saved.keyCleared)
        XCTAssertNil(h.state.decisionField.offNote)
        XCTAssertEqual(h.state.decisionField.host, "example-resource.invalid")
    }

    func test_ADR0011_R616_R623_changingEndpointShowsKeyClearedUntilKeySaved() async throws {
        let providers = Providers(keys: [.microsoft: "fake-key-ms"])
        let h = await launched(try microsoftHarness(providers: providers))
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy"))
        XCTAssertEqual(h.state.decisionField.microsoft?.keyCleared, false)

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://other-resource.invalid", deployment: "fake-deploy"))

        let cleared = try XCTUnwrap(h.state.decisionField.microsoft)
        XCTAssertTrue(cleared.keyCleared)
        XCTAssertFalse(cleared.showsKeyResetNotice, "지운 뒤에는 지웠다는 문구로 바뀐다")
        XCTAssertEqual(h.state.decisionField.keyState, .noKey)
        XCTAssertEqual(h.state.decisionField.host, "other-resource.invalid")

        XCTAssertTrue(h.state.saveKey("fake-key-ms2"))
        XCTAssertEqual(h.state.decisionField.microsoft?.keyCleared, false, "키를 다시 넣으면 문구가 사라진다")
        XCTAssertEqual(h.state.decisionField.microsoft?.showsKeyResetNotice, true)
    }

    func test_ADR0011_R623_deploymentOnlyChangeKeepsKeyAndNoClearedNotice() async throws {
        let providers = Providers(keys: [.microsoft: "fake-key-ms"])
        let h = await launched(try microsoftHarness(providers: providers))
        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy"))

        XCTAssertNil(h.state.saveMicrosoft(endpoint: "https://example-resource.invalid", deployment: "fake-deploy-2"))

        XCTAssertEqual(h.state.decisionField.microsoft?.keyCleared, false)
        XCTAssertEqual(h.state.decisionField.microsoft?.savedDeployment, "fake-deploy-2")
        XCTAssertNotEqual(h.state.decisionField.keyState, .noKey)
    }

    func test_ADR0011_R616_saveMicrosoftWriteFailureShowsInField() async throws {
        let h = await launched(try microsoftHarness(providers: Providers()))
        h.settings.failingKeys = [CoreSettings.microsoftDeploymentKey]

        XCTAssertNil(h.state.decisionField.onSaveMicrosoft("https://example-resource.invalid", "fake-deploy"))

        XCTAssertEqual(h.state.decisionField.failure, .saveMicrosoft)
        XCTAssertEqual(h.state.decisionField.microsoft?.savedEndpoint, "https://example-resource.invalid")
        XCTAssertNil(h.state.decisionField.microsoft?.savedDeployment)
    }

    /// US3 시나리오 7, #127: 꺼진 Microsoft라도 저장한 주소가 규칙을 지키면 그 호스트를 보내는 곳으로 보인다.
    func test_ADR0011_R606_US3_7_offMicrosoftWithSavedEndpointShowsItsHost() async throws {
        var settings = Self.microsoftSettings
        settings[CoreSettings.microsoftEndpointKey] = "https://example-resource.invalid"
        let noDeployment = await launched(try microsoftHarness(providers: Providers(), settings: settings))
        XCTAssertEqual(noDeployment.state.selectionOff, .needsDeployment)
        XCTAssertEqual(noDeployment.state.sendingHost, "example-resource.invalid")

        let closed = await launched(
            try harness(
                count: 1, providers: Providers(), settings: settings, catalog: ProviderCatalog.all,
                questions: Self.withMicrosoft))
        XCTAssertEqual(closed.state.selectionOff, .closedProvider(.microsoft))
        XCTAssertEqual(closed.state.sendingHost, "example-resource.invalid")

        settings[CoreSettings.microsoftEndpointKey] = "http://example-resource.invalid"
        let rejected = await launched(try microsoftHarness(providers: Providers(), settings: settings))
        XCTAssertNil(rejected.state.sendingHost, "규칙을 어긴 저장 값은 보내는 곳으로 보이지 않는다")
    }

    // MARK: - 단위 4 할 일 탭 키 확인(R-627)

    func test_FR14_R627_settingsTabRequestIsTakenOnce() async throws {
        let h = await launched(try harness(count: 1, providers: Providers()))
        XCTAssertNil(h.state.takeSettingsTabRequest())

        h.state.requestKeySettings()

        XCTAssertEqual(h.state.takeSettingsTabRequest(), .basic)
        XCTAssertNil(h.state.settingsTabRequest, "한 번 바꾸면 비운다")
        XCTAssertNil(h.state.takeSettingsTabRequest())
    }
}

/// 정한 키의 쓰기만 던지는 설정 저장소. 쓴 값을 기록한다.
final class ControlledSettingsStore: SettingsStore {
    struct Failure: Error {}

    private let inner = InMemorySettingsStore()
    var failingKeys: Set<String> = []
    /// 읽기가 던지는 키.
    var failingReads: Set<String> = []
    private(set) var written: [(String, String)] = []

    func value(for key: String) throws -> String? {
        if failingReads.contains(key) { throw Failure() }
        return try inner.value(for: key)
    }

    func setValue(_ value: String, for key: String) throws {
        if failingKeys.contains(key) { throw Failure() }
        written.append((key, value))
        try inner.setValue(value, for: key)
    }

    func resetWritten() {
        written = []
    }
}
