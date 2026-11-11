import Foundation

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

/// 기준 모델 하나의 임계값 둘(spec 006 data-model §1).
public struct ModelThresholds: Equatable, Sendable {
    public let concrete: Double
    public let avoiding: Double

    public init(concrete: Double, avoiding: Double) {
        self.concrete = concrete
        self.avoiding = avoiding
    }
}

/// `questions.json` v2를 읽은 값(spec 006 contracts/questions-json-v2.md). 읽기 규칙을 어기면 읽지 않는다.
public struct QuestionSet: Equatable, Sendable {
    static let scoreNames: Set<String> = ["urgency", "impact"]
    static let noulNames: Set<String> = ["concrete", "avoiding"]

    public let version: String
    public let language: String
    /// 공급자 ID → 기준 모델 ID.
    public let models: [String: String]
    /// 잠정 임계값을 쓰는 기준 모델 ID.
    public let provisional: Set<String>
    public let questions: [String: Question]
    /// 기준 모델 ID → 질문 이름 → 임계값.
    public let thresholds: [String: [String: Double]]

    public init(json: Data) throws(QuestionSetError) {
        let raw: RawSet
        do {
            raw = try JSONDecoder().decode(RawSet.self, from: json)
        } catch {
            throw .malformed
        }
        let baseModels = Set(raw.models.values)
        guard Set(raw.questions.keys) == Self.scoreNames.union(Self.noulNames),
            baseModels.allSatisfy({ raw.thresholds[$0]?["concrete"] != nil && raw.thresholds[$0]?["avoiding"] != nil }),
            raw.thresholds.values.allSatisfy({ $0.values.allSatisfy { (0...1).contains($0) } }),
            Set(raw.provisional).count == raw.provisional.count, Set(raw.provisional).isSubset(of: baseModels)
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
        models = raw.models
        provisional = Set(raw.provisional)
        self.questions = questions
        thresholds = raw.thresholds
    }

    /// `thresholds[baseModel]`의 `concrete`·`avoiding`. 둘 중 하나라도 없으면 `nil`이다.
    public func thresholds(for baseModel: String) -> ModelThresholds? {
        guard let entry = thresholds[baseModel], let concrete = entry["concrete"], let avoiding = entry["avoiding"]
        else { return nil }
        return ModelThresholds(concrete: concrete, avoiding: avoiding)
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
    let models: [String: String]
    let provisional: [String]
    let questions: [String: RawQuestion]
    let thresholds: [String: [String: Double]]
}

private struct RawQuestion: Decodable {
    let type: String
    let instructions: String
    let criteria: [String]?
}
