import Foundation

/// 판단 질문 하나(contracts/decision-provider.md "질문 타입").
public enum Question: Equatable, Sendable {
    /// 문장이 참일 확률 하나를 받는 질문.
    case noul(instructions: String)
    /// 낮음→높음 옵션 가운데 어디인지 받는 질문. 옵션 번호는 0부터.
    case score(instructions: String, criteria: [String])

    /// score 옵션 수. noul이면 nil.
    public var optionCount: Int? {
        guard case .score(_, let criteria) = self else { return nil }
        return criteria.count
    }
}

public enum QuestionSetError: Error, Equatable {
    case missingFile
    case malformed
}

/// `questions.json`을 읽은 값(contracts/questions-json.md). 계약과 다르면 읽지 않는다.
public struct QuestionSet: Equatable, Sendable {
    static let scoreNames: Set<String> = ["urgency", "impact"]
    static let noulNames: Set<String> = ["concrete", "avoiding"]

    public let version: String
    public let language: String
    public let model: String
    public let questions: [String: Question]
    /// 모델 ID → 질문 이름 → 임계값.
    public let thresholds: [String: [String: Double]]
    /// `thresholds[model]["avoiding"]`. 읽을 때 있는지 확인했다.
    public let avoidingThreshold: Double

    public init(json: Data) throws(QuestionSetError) {
        let raw: RawSet
        do {
            raw = try JSONDecoder().decode(RawSet.self, from: json)
        } catch {
            throw .malformed
        }
        guard Set(raw.questions.keys) == Self.scoreNames.union(Self.noulNames),
            let modelThresholds = raw.thresholds[raw.model],
            let avoiding = modelThresholds["avoiding"], modelThresholds["concrete"] != nil,
            raw.thresholds.values.allSatisfy({ $0.values.allSatisfy { (0...1).contains($0) } })
        else { throw .malformed }
        var questions: [String: Question] = [:]
        for (name, question) in raw.questions {
            switch question.type {
            case "noul" where Self.noulNames.contains(name) && question.criteria == nil:
                questions[name] = .noul(instructions: question.instructions)
            case "score" where Self.scoreNames.contains(name):
                guard let criteria = question.criteria, (2...10).contains(criteria.count) else { throw .malformed }
                questions[name] = .score(instructions: question.instructions, criteria: criteria)
            default:
                throw .malformed
            }
        }
        version = raw.version
        language = raw.language
        model = raw.model
        self.questions = questions
        thresholds = raw.thresholds
        avoidingThreshold = avoiding
    }

    /// MokaCore 번들의 질문 파일. 번들이 없으면 SwiftPM 생성 코드가 멈추므로 빌드 결함이다(research R19 F4).
    public static func bundled() throws(QuestionSetError) -> QuestionSet {
        guard let url = Bundle.module.url(forResource: "questions", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { throw .missingFile }
        return try QuestionSet(json: data)
    }
}

private struct RawSet: Decodable {
    let version: String
    let language: String
    let model: String
    let questions: [String: RawQuestion]
    let thresholds: [String: [String: Double]]
}

private struct RawQuestion: Decodable {
    let type: String
    let instructions: String
    let criteria: [String]?
}
