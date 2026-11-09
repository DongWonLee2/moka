import Foundation

/// TypeSafe 요청 본문 조립과 응답 해석(contracts/decision-provider.md). HTTP는 앱 `TypeSafeProvider`가 보낸다.
public enum TypeSafeCodec {
    /// `{"model","state","questions"}`. `state`는 정준 바이트를 그대로 끼운다. 할 일 id와 키는 넣지 않는다.
    public static func body(_ request: DecisionRequest) -> Data {
        let questions = request.questions.questions.sorted { $0.key < $1.key }.map { name, question in
            let fields: [(String, String)]
            switch question {
            case .noul(let instructions):
                fields = [("type", quoted("noul")), ("instructions", quoted(instructions))]
            case .score(let instructions, let criteria):
                fields = [
                    ("type", quoted("score")), ("instructions", quoted(instructions)),
                    ("criteria", "[" + criteria.map(quoted).joined(separator: ",") + "]"),
                ]
            }
            return quoted(name) + ":" + object(fields)
        }
        var bytes = Array(#"{"model":\#(quoted(request.model)),"state":"#.utf8)
        bytes += request.state
        bytes += Array(#","questions":{\#(questions.joined(separator: ","))}}"#.utf8)
        return Data(bytes)
    }

    /// HTTP 상태와 본문을 답 또는 오류로 바꾼다.
    public static func decode(status: Int, body: Data) throws(DecisionError) -> DecisionResponse {
        switch status {
        case 200: return try response(body)
        case 401, 403: throw .unauthorized
        case 429: throw .rateLimited
        case 529: throw .overloaded
        default: throw .server(status: status)
        }
    }

    /// 읽는 칸은 `model`, `answers.<이름>`의 `type`·`noul`·`score`·`confidence`·`probabilities`다.
    /// 모르는 칸과 모르는 타입의 답은 무시한다. 질문 파일과 맞는지는 `ScoreRules.score`가 본다.
    public static func response(_ data: Data) throws(DecisionError) -> DecisionResponse {
        let raw: RawResponse
        do {
            raw = try JSONDecoder().decode(RawResponse.self, from: data)
        } catch {
            throw .malformed
        }
        var answers: [String: Answer] = [:]
        for (name, answer) in raw.answers {
            switch answer.type {
            case "noul":
                guard let p = answer.noul else { throw .malformed }
                answers[name] = .noul(p)
            case "score":
                guard let score = answer.score, let rawProbabilities = answer.probabilities else { throw .malformed }
                var probabilities: [Int: Double] = [:]
                for (key, value) in rawProbabilities {
                    guard let option = Int(key), probabilities[option] == nil else { throw .malformed }
                    probabilities[option] = value
                }
                answers[name] = .score(score: score, confidence: answer.confidence, probabilities: probabilities)
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

private struct RawResponse: Decodable {
    let model: String?
    let answers: [String: RawAnswer]
}

private struct RawAnswer: Decodable {
    let type: String
    let noul: Double?
    let score: Double?
    let confidence: Double?
    let probabilities: [String: Double]?
}
