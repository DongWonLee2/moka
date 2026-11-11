import Foundation

/// OpenAI 모양 요청 본문 조립과 응답 해석(spec 006 contracts/decision-provider-v2.md "OpenAI 모양").
/// 응답을 System One과 같은 `DecisionResponse`로 바꾸고, 질문 파일과 맞는지는 `ScoreRules.score`가 본다.
public enum OpenAIDecisionsCodec {
    /// `{"model","input","questions"}`. `input`은 정준 바이트를 그대로 끼운다. 질문은 이름 순 배열이다.
    public static func body(_ request: DecisionRequest) -> Data {
        let questions = request.questions.questions.sorted { $0.key < $1.key }.map { name, question in
            switch question {
            case .noul(let instructions):
                return object([
                    ("name", quoted(name)), ("type", quoted("predicate")), ("instructions", quoted(instructions)),
                ])
            case .score(let instructions, let criteria):
                return object([
                    ("name", quoted(name)), ("type", quoted("score")), ("instructions", quoted(instructions)),
                    ("criteria", "[" + criteria.map(quoted).joined(separator: ",") + "]"),
                ])
            }
        }
        var bytes = Array(#"{"model":\#(quoted(request.model)),"input":"#.utf8)
        bytes += request.state
        bytes += Array(#","questions":[\#(questions.joined(separator: ","))]}"#.utf8)
        return Data(bytes)
    }

    /// HTTP 상태와 본문을 답 또는 오류로 바꾼다. 상태 코드 표는 System One과 같다.
    public static func decode(status: Int, body: Data) throws(DecisionError) -> DecisionResponse {
        guard status == 200 else { throw DecisionWire.failure(status: status) }
        return try response(body)
    }

    /// 읽는 칸은 `model`, `answers[]`의 `name`·`type`·`probability`·`score`·`confidence`·`probabilities[].value`·
    /// `probabilities[].probability`다. 모르는 칸과 모르는 타입의 답은 무시한다.
    public static func response(_ data: Data) throws(DecisionError) -> DecisionResponse {
        let raw: RawOpenAIResponse
        do {
            raw = try JSONDecoder().decode(RawOpenAIResponse.self, from: data)
        } catch {
            throw .malformed
        }
        var names: Set<String> = []
        var answers: [String: Answer] = [:]
        for answer in raw.answers {
            guard names.insert(answer.name).inserted else { throw .malformed }
            switch answer.type {
            case "predicate":
                guard let p = answer.probability else { throw .malformed }
                answers[answer.name] = .noul(p)
            case "score":
                guard let score = answer.score, let confidence = answer.confidence,
                    let options = answer.probabilities
                else { throw .malformed }
                var probabilities: [Int: Double] = [:]
                for option in options {
                    guard probabilities[option.value] == nil else { throw .malformed }
                    probabilities[option.value] = option.probability
                }
                answers[answer.name] = .score(score: score, confidence: confidence, probabilities: probabilities)
            default:
                continue
            }
        }
        return DecisionResponse(model: raw.model, answers: answers)
    }

    private static func quoted(_ text: String) -> String {
        JudgmentState.quoted(text)
    }

    private static func object(_ fields: [(String, String)]) -> String {
        "{" + fields.map { quoted($0.0) + ":" + $0.1 }.joined(separator: ",") + "}"
    }
}

private struct RawOpenAIResponse: Decodable {
    let model: String?
    let answers: [RawOpenAIAnswer]
}

private struct RawOpenAIAnswer: Decodable {
    let name: String
    let type: String
    let probability: Double?
    let score: Double?
    let confidence: Double?
    let probabilities: [RawOpenAIOption]?
}

private struct RawOpenAIOption: Decodable {
    let value: Int
    let probability: Double
}
