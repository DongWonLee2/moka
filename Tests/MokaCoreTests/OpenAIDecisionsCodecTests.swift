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

private let request = DecisionRequest(taskID: 1, model: "gpt-6-luna", state: state.bytes, questions: questions)

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

private func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard haystack.count >= needle.count else { return false }
    return (0...(haystack.count - needle.count)).contains { Array(haystack[$0..<($0 + needle.count)]) == needle }
}

/// 같은 답 넷을 OpenAI 응답 글자로 쓰고, 한 답만 바꿔 끼운다.
private func answersText(replacing name: String? = nil, with replacement: String? = nil, extra: String? = nil)
    -> String
{
    var entries: [(String, String)] = [
        (
            "urgency",
            #"{"name":"urgency","type":"score","score":2.1,"confidence":0.7,"probabilities":[{"label":"a","value":0,"probability":0.05},{"label":"b","value":1,"probability":0.15},{"label":"c","value":2,"probability":0.4},{"label":"d","value":3,"probability":0.4}]}"#
        ),
        (
            "impact",
            #"{"name":"impact","type":"score","score":1.2,"confidence":0.6,"probabilities":[{"label":"a","value":0,"probability":0.2},{"label":"b","value":1,"probability":0.4},{"label":"c","value":2,"probability":0.4}]}"#
        ),
        ("concrete", #"{"name":"concrete","type":"predicate","probability":0.9}"#),
        ("avoiding", #"{"name":"avoiding","type":"predicate","probability":0.3}"#),
    ]
    if let name, let index = entries.firstIndex(where: { $0.0 == name }) {
        if let replacement {
            entries[index].1 = replacement
        } else {
            entries.remove(at: index)
        }
    }
    var parts = entries.map(\.1)
    if let extra { parts.append(extra) }
    return #"{"model":"gpt-6-luna","answers":["# + parts.joined(separator: ",") + "]}"
}

@Suite struct OpenAIBodyTests {
    @Test("ADR-0011 R-603: 요청 본문은 model, input, questions 셋이다")
    func bodyKeys() throws {
        let body = try jsonObject(OpenAIDecisionsCodec.body(request))
        #expect(Set(body.keys) == ["model", "input", "questions"])
        #expect(body["model"] as? String == "gpt-6-luna")
    }

    @Test("ADR-0011 R-603: 질문 사전은 이름 순 배열이고 noul은 predicate, score는 score로 간다")
    func questionsArray() throws {
        let body = try jsonObject(OpenAIDecisionsCodec.body(request))
        let array = try #require(body["questions"] as? [[String: Any]])
        #expect(array.compactMap { $0["name"] as? String } == ["avoiding", "concrete", "impact", "urgency"])
        let source = try #require(try jsonObject(questionsJSON())["questions"] as? [String: [String: Any]])
        for entry in array {
            let name = try #require(entry["name"] as? String)
            let original = try #require(source[name])
            #expect(entry["instructions"] as? String == original["instructions"] as? String)
            switch original["type"] as? String {
            case "noul":
                #expect(Set(entry.keys) == ["name", "type", "instructions"])
                #expect(entry["type"] as? String == "predicate")
            case "score":
                #expect(Set(entry.keys) == ["name", "type", "instructions", "criteria"])
                #expect(entry["type"] as? String == "score")
                #expect(entry["criteria"] as? [String] == original["criteria"] as? [String])
            default:
                Issue.record("질문 파일에 모르는 타입: \(name)")
            }
        }
    }

    @Test("ADR-0011 R-603: input은 System One state와 같은 정준 바이트를 그대로 끼운다")
    func inputBytesVerbatim() throws {
        let body = [UInt8](OpenAIDecisionsCodec.body(request))
        #expect(contains(body, Array(#""input":"#.utf8) + state.bytes))
        let systemOne = [UInt8](SystemOneCodec.body(request))
        #expect(contains(systemOne, Array(#""state":"#.utf8) + state.bytes))
        let input = try #require(try jsonObject(OpenAIDecisionsCodec.body(request))["input"] as? NSDictionary)
        #expect(input == (try jsonObject(Data(state.bytes)) as NSDictionary))
    }

    @Test("ADR-0011 R-603: 할 일 id와 키는 본문에 넣지 않는다")
    func noTaskIDOrKey() {
        let other = DecisionRequest(taskID: 987_654, model: "gpt-6-luna", state: state.bytes, questions: questions)
        #expect(OpenAIDecisionsCodec.body(other) == OpenAIDecisionsCodec.body(request))
        let text = String(decoding: OpenAIDecisionsCodec.body(other), as: UTF8.self)
        #expect(!text.contains("987654"))
        #expect(!text.contains("fake-key"))
    }

    @Test("ADR-0011 R-603: OpenAI 모양 본문은 DecisionWire에서도 같은 바이트다")
    func wireBody() {
        #expect(DecisionWire.body(request, shape: .openAI) == OpenAIDecisionsCodec.body(request))
        #expect(DecisionWire.body(request, shape: .openAI) != DecisionWire.body(request, shape: .systemOne))
    }
}

@Suite struct OpenAIResponseTests {
    @Test("ADR-0011 R-603: 답 배열은 이름 사전이 되고 predicate 확률과 score 옵션 확률로 읽는다")
    func ok() throws {
        let response = try OpenAIDecisionsCodec.response(fixture("openai-ok"))
        #expect(response == DecisionResponse(model: "gpt-6-luna", answers: okAnswers))
        #expect(scored(response) != nil)
    }

    @Test("ADR-0011 R-603: 답 순서, 옵션 순서, 모르는 칸, 모르는 타입의 답은 결과에 닿지 않는다")
    func unknownFieldsAndOrder() throws {
        let response = try OpenAIDecisionsCodec.response(fixture("openai-unknown-fields"))
        #expect(response == DecisionResponse(model: "gpt-6-luna", answers: okAnswers))
    }

    @Test("ADR-0011 R-603: label은 읽지 않고 value를 옵션 번호로 삼는다")
    func labelIgnored() throws {
        let text = answersText(
            replacing: "impact",
            with:
                #"{"name":"impact","type":"score","score":1.2,"confidence":0.6,"probabilities":[{"label":"x","value":2,"probability":0.4},{"value":0,"probability":0.2},{"label":"x","value":1,"probability":0.4}]}"#
        )
        let response = try OpenAIDecisionsCodec.response(Data(text.utf8))
        #expect(response == DecisionResponse(model: "gpt-6-luna", answers: okAnswers))
    }

    @Test("ADR-0011 R-603: 응답에 model이 없으면 모델 이름을 비우고 판단 결과는 만든다")
    func noModel() throws {
        let text = answersText().replacingOccurrences(of: #""model":"gpt-6-luna","#, with: "")
        let response = try OpenAIDecisionsCodec.response(Data(text.utf8))
        #expect(response == DecisionResponse(model: nil, answers: okAnswers))
        #expect(try #require(scored(response)).modelSnapshot == nil)
    }

    @Test("ADR-0011 R-603: 같은 name이 둘이면 malformed")
    func duplicateName() {
        let text = answersText(extra: #"{"name":"concrete","type":"predicate","probability":0.1}"#)
        #expect(throws: DecisionError.malformed) { try OpenAIDecisionsCodec.response(Data(text.utf8)) }
    }

    @Test("ADR-0011 R-603: 한 score 답에 같은 value가 둘이면 malformed")
    func duplicateValue() {
        let text = answersText(
            replacing: "impact",
            with:
                #"{"name":"impact","type":"score","score":1.2,"confidence":0.6,"probabilities":[{"label":"a","value":0,"probability":0.2},{"label":"b","value":1,"probability":0.4},{"label":"c","value":1,"probability":0.4}]}"#
        )
        #expect(throws: DecisionError.malformed) { try OpenAIDecisionsCodec.response(Data(text.utf8)) }
    }

    @Test(
        "ADR-0011 R-603: score 답에 score나 confidence가 없으면 malformed",
        arguments: [
            #"{"name":"urgency","type":"score","confidence":0.7,"probabilities":[{"label":"a","value":0,"probability":0.5},{"label":"b","value":1,"probability":0.5}]}"#,
            #"{"name":"urgency","type":"score","score":1,"probabilities":[{"label":"a","value":0,"probability":0.5},{"label":"b","value":1,"probability":0.5}]}"#,
        ])
    func missingScoreOrConfidence(answer: String) {
        let text = answersText(replacing: "urgency", with: answer)
        #expect(throws: DecisionError.malformed) { try OpenAIDecisionsCodec.response(Data(text.utf8)) }
    }

    @Test(
        "ADR-0011 R-603: 질문 빠짐·타입 다름·범위 밖·옵션 번호 어긋남은 읽히지만 판단 결과를 만들지 않는다(호출하는 쪽이 malformed로 본다)",
        arguments: [
            answersText(replacing: "avoiding"),
            answersText(
                replacing: "concrete",
                with:
                    #"{"name":"concrete","type":"score","score":1,"confidence":0.5,"probabilities":[{"label":"a","value":0,"probability":0.5},{"label":"b","value":1,"probability":0.5}]}"#
            ),
            answersText(replacing: "concrete", with: #"{"name":"concrete","type":"predicate","probability":1.5}"#),
            answersText(
                replacing: "impact",
                with:
                    #"{"name":"impact","type":"score","score":1.2,"confidence":0.6,"probabilities":[{"label":"a","value":1,"probability":0.2},{"label":"b","value":2,"probability":0.4},{"label":"c","value":3,"probability":0.4}]}"#
            ),
            answersText(
                replacing: "impact",
                with:
                    #"{"name":"impact","type":"score","score":1.2,"confidence":1.6,"probabilities":[{"label":"a","value":0,"probability":0.2},{"label":"b","value":1,"probability":0.4},{"label":"c","value":2,"probability":0.4}]}"#
            ),
        ])
    func rejectedByScoreRules(text: String) throws {
        let response = try OpenAIDecisionsCodec.response(Data(text.utf8))
        #expect(scored(response) == nil)
    }

    @Test("ADR-0011 R-603: score 값이 범위 밖인 픽스처는 판단 결과를 만들지 않는다")
    func outOfRangeFixture() throws {
        let response = try OpenAIDecisionsCodec.response(fixture("openai-out-of-range"))
        #expect(scored(response) == nil)
    }

    @Test(
        "ADR-0011 R-603: 응답 모양이 틀리면 malformed",
        arguments: [
            "", "not json", "[]", #"{"model":"gpt-6-luna"}"#, #"{"answers":{}}"#, #"{"answers":[1]}"#,
            #"{"model":1,"answers":[]}"#, #"{"answers":[{"type":"predicate","probability":0.5}]}"#,
            #"{"answers":[{"name":"a","probability":0.5}]}"#, #"{"answers":[{"name":"a","type":"predicate"}]}"#,
            #"{"answers":[{"name":"a","type":"predicate","probability":"0.5"}]}"#,
            #"{"answers":[{"name":"a","type":"score","score":0,"confidence":0.5}]}"#,
            #"{"answers":[{"name":"a","type":"score","score":0,"confidence":0.5,"probabilities":{"0":1}}]}"#,
            #"{"answers":[{"name":"a","type":"score","score":0,"confidence":0.5,"probabilities":[{"value":"0","probability":1}]}]}"#,
            #"{"answers":[{"name":"a","type":"score","score":0,"confidence":0.5,"probabilities":[{"value":0.5,"probability":1}]}]}"#,
            #"{"answers":[{"name":"a","type":"score","score":0,"confidence":0.5,"probabilities":[{"probability":1}]}]}"#,
            #"{"answers":[{"name":"a","type":"score","score":0,"confidence":0.5,"probabilities":[{"value":0}]}]}"#,
        ])
    func malformed(text: String) {
        #expect(throws: DecisionError.malformed) { try OpenAIDecisionsCodec.response(Data(text.utf8)) }
    }
}

@Suite struct OpenAIStatusTests {
    @Test("ADR-0011 R-603: 200이면 본문을 답으로 읽는다")
    func ok() throws {
        let response = try OpenAIDecisionsCodec.decode(status: 200, body: fixture("openai-ok"))
        #expect(response == DecisionResponse(model: "gpt-6-luna", answers: okAnswers))
        let wire = try DecisionWire.decode(status: 200, body: fixture("openai-ok"), shape: .openAI)
        #expect(wire == response)
    }

    @Test("ADR-0011 R-603: 200인데 본문을 읽지 못하면 malformed")
    func okButMalformed() {
        #expect(throws: DecisionError.malformed) { try OpenAIDecisionsCodec.decode(status: 200, body: Data("x".utf8)) }
    }

    @Test(
        "ADR-0011 R-604: 두 요청 모양이 같은 상태 코드 표를 쓴다(3xx와 200이 아닌 2xx는 server)",
        arguments: [
            (401, DecisionError.unauthorized), (403, .unauthorized), (429, .rateLimited), (529, .overloaded),
            (100, .server(status: 100)), (201, .server(status: 201)), (204, .server(status: 204)),
            (301, .server(status: 301)), (302, .server(status: 302)), (304, .server(status: 304)),
            (307, .server(status: 307)), (308, .server(status: 308)), (400, .server(status: 400)),
            (404, .server(status: 404)), (500, .server(status: 500)), (502, .server(status: 502)),
            (503, .server(status: 503)),
        ])
    func sameStatusTable(status: Int, expected: DecisionError) throws {
        let systemOneBody = try fixture("ok")
        let openAIBody = try fixture("openai-ok")
        #expect(throws: expected) { try OpenAIDecisionsCodec.decode(status: status, body: openAIBody) }
        #expect(throws: expected) { try DecisionWire.decode(status: status, body: openAIBody, shape: .openAI) }
        #expect(throws: expected) { try DecisionWire.decode(status: status, body: systemOneBody, shape: .systemOne) }
    }
}
