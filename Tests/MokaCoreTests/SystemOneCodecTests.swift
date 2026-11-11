import Foundation
import MokaCore
import Testing

private let decisionFixturesURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/decision", isDirectory: true)

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: decisionFixturesURL.appendingPathComponent("\(name).json"))
}

private let questions = try! QuestionSet(json: questionsJSON())

private let state = JudgmentState.build(
    task: Fake.task(1, deadline: Fake.day("2027-01-15"), estMin: 30, firstAction: "가짜 첫 행동"),
    contexts: [MokaContext(id: 1, name: "가짜 일정 A", date: Fake.day("2027-01-20"), impact: .high)],
    checkpoints: [], today: Fake.day("2027-01-13"), calendar: Fake.seoul)

private let request = DecisionRequest(taskID: 1, model: questions.model, state: state.bytes, questions: questions)

private let okAnswers: [String: Answer] = [
    "urgency": .score(score: 2.1, confidence: 0.7, probabilities: [0: 0.05, 1: 0.15, 2: 0.4, 3: 0.4]),
    "impact": .score(score: 1.2, confidence: 0.6, probabilities: [0: 0.2, 1: 0.4, 2: 0.4]),
    "concrete": .noul(0.9),
    "avoiding": .noul(0.3),
]

private func scored(_ response: DecisionResponse) -> TaskScore? {
    ScoreRules.score(
        taskID: 1, response: response, questions: questions, provider: "fake", stateHash: state.hash, now: Fake.noon)
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite struct SystemOneBodyTests {
    @Test("FR-14 R-210: 요청 본문은 model, state, questions 셋이고 구조가 질문 파일과 같다")
    func bodyStructure() throws {
        let body = try jsonObject(SystemOneCodec.body(request))
        #expect(Set(body.keys) == ["model", "state", "questions"])
        #expect(body["model"] as? String == "jev-1.13.0")
        let expectedQuestions = try #require(try jsonObject(questionsJSON())["questions"] as? NSDictionary)
        #expect(body["questions"] as? NSDictionary == expectedQuestions)
        let expectedState = try jsonObject(Data(state.bytes)) as NSDictionary
        #expect(body["state"] as? NSDictionary == expectedState)
    }

    @Test("FR-14 R-210: 본문의 state는 정준 바이트를 그대로 끼운다")
    func stateBytesVerbatim() throws {
        let body = [UInt8](SystemOneCodec.body(request))
        let needle = Array(#""state":"#.utf8) + state.bytes
        let found = (0...(body.count - needle.count)).contains { Array(body[$0..<($0 + needle.count)]) == needle }
        #expect(found)
    }

    @Test("FR-14 R-210: 할 일 id는 본문에 넣지 않는다")
    func noTaskID() throws {
        let other = DecisionRequest(taskID: 987_654, model: questions.model, state: state.bytes, questions: questions)
        #expect(SystemOneCodec.body(other) == SystemOneCodec.body(request))
        #expect(!String(decoding: SystemOneCodec.body(other), as: UTF8.self).contains("987654"))
    }

    @Test("FR-16 R-214: 키는 요청에 담지 않으므로 본문에 나오지 않는다")
    func noKeyInBody() async throws {
        let key = "fake-key-should-not-appear"
        let provider = FakeDecisionProvider(answer: .success(DecisionResponse(model: nil, answers: okAnswers)))
        _ = try await provider.decide(request, key: key)
        #expect(!String(decoding: SystemOneCodec.body(request), as: UTF8.self).contains(key))
    }
}

@Suite struct SystemOneResponseTests {
    @Test("FR-14 R-210: 정상 응답은 모델 이름과 답 넷으로 읽고 legend·usage는 읽지 않는다")
    func ok() throws {
        let response = try SystemOneCodec.response(fixture("ok"))
        #expect(response == DecisionResponse(model: "jev-1.13.0", answers: okAnswers))
        #expect(scored(response) != nil)
    }

    @Test("FR-14 R-210: 응답에 model이 없으면 모델 이름을 비우고 판단 결과는 만든다")
    func noModel() throws {
        let response = try SystemOneCodec.response(fixture("no-model"))
        #expect(response == DecisionResponse(model: nil, answers: okAnswers))
        #expect(try #require(scored(response)).modelSnapshot == nil)
    }

    @Test("FR-14 R-210: 모르는 칸과 모르는 타입의 답은 무시한다")
    func unknownFields() throws {
        let response = try SystemOneCodec.response(fixture("unknown-fields"))
        #expect(response == DecisionResponse(model: "jev-1.13.0", answers: okAnswers))
    }

    @Test(
        "FR-14 R-211: 질문 빠짐·타입 다름·범위 밖 응답은 읽히지만 판단 결과를 만들지 않는다(호출하는 쪽이 malformed로 본다)",
        arguments: ["missing-question", "wrong-type", "out-of-range"])
    func rejectedByScoreRules(name: String) throws {
        let response = try SystemOneCodec.response(fixture(name))
        #expect(scored(response) == nil)
    }

    @Test("FR-14 R-211: score 답에 confidence가 없으면 읽되 판단 결과는 만들지 않는다")
    func missingConfidence() throws {
        let data = Data(
            #"{"answers":{"urgency":{"type":"score","score":1,"probabilities":{"0":0.5,"1":0.5}}}}"#.utf8)
        let response = try SystemOneCodec.response(data)
        #expect(response.answers["urgency"] == .score(score: 1, confidence: nil, probabilities: [0: 0.5, 1: 0.5]))
    }

    @Test(
        "FR-14 R-211: 응답 모양이 틀리면 malformed",
        arguments: [
            "", "not json", "[]", #"{"model":"jev-1.13.0"}"#, #"{"answers":[]}"#, #"{"answers":{"a":1}}"#,
            #"{"model":1,"answers":{}}"#, #"{"answers":{"a":{"noul":0.5}}}"#, #"{"answers":{"a":{"type":"noul"}}}"#,
            #"{"answers":{"a":{"type":"noul","noul":"0.5"}}}"#,
            #"{"answers":{"a":{"type":"score","confidence":0.5,"probabilities":{"0":1}}}}"#,
            #"{"answers":{"a":{"type":"score","score":0,"confidence":0.5}}}"#,
            #"{"answers":{"a":{"type":"score","score":0,"confidence":0.5,"probabilities":{"x":1}}}}"#,
            #"{"answers":{"a":{"type":"score","score":0,"confidence":0.5,"probabilities":{"1":0.5,"01":0.5}}}}"#,
        ])
    func malformed(text: String) {
        #expect(throws: DecisionError.malformed) { try SystemOneCodec.response(Data(text.utf8)) }
    }
}

@Suite struct SystemOneStatusTests {
    @Test("FR-14 R-210: 200이면 본문을 답으로 읽는다")
    func ok() throws {
        let response = try SystemOneCodec.decode(status: 200, body: fixture("ok"))
        #expect(response == DecisionResponse(model: "jev-1.13.0", answers: okAnswers))
    }

    @Test("FR-14 R-211: 200인데 본문을 읽지 못하면 malformed")
    func okButMalformed() {
        #expect(throws: DecisionError.malformed) { try SystemOneCodec.decode(status: 200, body: Data("x".utf8)) }
    }

    @Test(
        "FR-14 R-211: 상태 코드를 오류 종류로 바꾼다",
        arguments: [
            (401, DecisionError.unauthorized), (403, .unauthorized), (429, .rateLimited), (529, .overloaded),
            (100, .server(status: 100)), (201, .server(status: 201)), (204, .server(status: 204)),
            (301, .server(status: 301)), (304, .server(status: 304)), (400, .server(status: 400)),
            (404, .server(status: 404)), (500, .server(status: 500)), (502, .server(status: 502)),
            (503, .server(status: 503)),
        ])
    func statusErrors(status: Int, expected: DecisionError) throws {
        #expect(throws: expected) { try SystemOneCodec.decode(status: status, body: fixture("ok")) }
    }
}

@Suite struct SystemOneWireTests {
    @Test("ADR-0011 R-602: System One 모양 본문은 SystemOneCodec 본문과 같은 바이트다")
    func bodyIsSystemOne() {
        #expect(DecisionWire.body(request, shape: .systemOne) == SystemOneCodec.body(request))
    }

    @Test("ADR-0011 R-602: System One 모양 200 응답은 SystemOneCodec 해석과 같다")
    func okIsSystemOne() throws {
        let response = try DecisionWire.decode(status: 200, body: fixture("ok"), shape: .systemOne)
        #expect(response == DecisionResponse(model: "jev-1.13.0", answers: okAnswers))
    }

    @Test(
        "ADR-0011 R-604: 리디렉트(3xx)를 포함한 System One 상태 코드 표",
        arguments: [
            (301, DecisionError.server(status: 301)), (302, .server(status: 302)), (307, .server(status: 307)),
            (308, .server(status: 308)), (401, .unauthorized), (403, .unauthorized), (429, .rateLimited),
            (529, .overloaded), (201, .server(status: 201)), (500, .server(status: 500)),
        ])
    func statusTable(status: Int, expected: DecisionError) throws {
        #expect(throws: expected) { try DecisionWire.decode(status: status, body: fixture("ok"), shape: .systemOne) }
    }
}
