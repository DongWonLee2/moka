import Foundation

/// 판단 모델 답 하나. score 옵션 확률의 키는 옵션 번호다.
public enum Answer: Equatable, Sendable {
    case noul(Double)
    /// `confidence`가 없으면 해석하지 않는다(data-model §3).
    case score(score: Double, confidence: Double?, probabilities: [Int: Double])
}

public struct DecisionResponse: Equatable, Sendable {
    public let model: String?
    public let answers: [String: Answer]

    public init(model: String?, answers: [String: Answer]) {
        self.model = model
        self.answers = answers
    }
}

/// 할 일 하나의 최신 판단 결과(`scores` 한 줄, data-model §1). priority는 저장하지 않는다.
public struct TaskScore: Equatable, Sendable {
    public var taskID: TaskID
    public var questionVersion: String
    public var provider: String
    public var modelSnapshot: String?
    /// 0~1, 마감 하한을 적용하기 전 값.
    public var urgency: Double
    public var impact: Double
    public var concrete: Double
    public var avoiding: Double
    public var probsJSON: String
    public var stateHash: String
    public var scoredAt: Date

    public init(
        taskID: TaskID, questionVersion: String, provider: String, modelSnapshot: String?, urgency: Double,
        impact: Double, concrete: Double, avoiding: Double, probsJSON: String, stateHash: String, scoredAt: Date
    ) {
        self.taskID = taskID
        self.questionVersion = questionVersion
        self.provider = provider
        self.modelSnapshot = modelSnapshot
        self.urgency = urgency
        self.impact = impact
        self.concrete = concrete
        self.avoiding = avoiding
        self.probsJSON = probsJSON
        self.stateHash = stateHash
        self.scoredAt = scoredAt
    }
}

/// 판단 결과 규칙(spec R-204·R-205, data-model §3).
public enum ScoreRules {
    /// 답을 판단 결과로 바꾼다. 질문 파일과 맞지 않으면(malformed) nil.
    public static func score(
        taskID: TaskID, response: DecisionResponse, questions: QuestionSet, provider: String, stateHash: String,
        now: Date
    ) -> TaskScore? {
        var values: [String: Double] = [:]
        var parts: [String] = []
        for name in questions.questions.keys.sorted() {
            guard let question = questions.questions[name], let answer = response.answers[name] else { return nil }
            switch (question, answer) {
            case (.noul, .noul(let p)):
                guard (0...1).contains(p) else { return nil }
                values[name] = p
                parts.append(#""\#(name)":{"noul":\#(p)}"#)
            case (.score(_, let criteria), .score(let score, let confidence, let probabilities)):
                let top = criteria.count - 1
                guard (0...Double(top)).contains(score), let confidence, (0...1).contains(confidence),
                    Set(probabilities.keys) == Set(0...top), probabilities.values.allSatisfy({ (0...1).contains($0) })
                else { return nil }
                values[name] = score / Double(top)
                let options = probabilities.keys.sorted().map { #""\#($0)":\#(probabilities[$0]!)"# }
                parts.append(
                    #""\#(name)":{"score":\#(score),"confidence":\#(confidence),"probabilities":{"#
                        + options.joined(separator: ",") + "}}")
            default:
                return nil
            }
        }
        return TaskScore(
            taskID: taskID, questionVersion: questions.version, provider: provider, modelSnapshot: response.model,
            urgency: values["urgency"]!, impact: values["impact"]!, concrete: values["concrete"]!,
            avoiding: values["avoiding"]!, probsJSON: "{" + parts.joined(separator: ",") + "}", stateHash: stateHash,
            scoredAt: now)
    }

    /// 고를 때마다 계산한다. 마감이 내일까지(지난 마감 포함)면 urgency를 1로 본다.
    /// `thresholds`는 기준 모델의 임계값이고, `nil`이면 avoiding을 임계값 미만(배율 1)으로 본다(spec 006 R-609).
    public static func priority(
        _ score: TaskScore, task: MokaTask, today: LocalDay, thresholds: ModelThresholds?, calendar: Calendar
    ) -> Double {
        let dueSoon = task.deadline.map { $0 <= today.adding(days: 1, calendar: calendar) } ?? false
        let urgency = dueSoon ? 1 : score.urgency
        let avoids = thresholds.map { score.avoiding >= $0.avoiding } ?? false
        let agingFactor = avoids ? Defaults.avoidingAgingFactor : 1
        let aging = Double(task.skipCount) * agingFactor
        return Defaults.weightUrgency * urgency + Defaults.weightImpact * score.impact + Defaults.weightAging * aging
    }

    /// 키가 있고 질문 버전이 같고 공급자가 지금 주입된 공급자 이름과 같은 판단 결과만(spec 006 R-611).
    /// 판단 입력이 바뀐 결과도 다시 묻기 전까지는 쓴다.
    public static func usable(
        scores: [TaskID: TaskScore], hasKey: Bool, questionVersion: String, provider: String
    ) -> [TaskID: TaskScore] {
        guard hasKey else { return [:] }
        return scores.filter { $0.value.questionVersion == questionVersion && $0.value.provider == provider }
    }
}
