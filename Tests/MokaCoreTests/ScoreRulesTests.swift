import Foundation
import MokaCore
import Testing

private let questions = try! QuestionSet.bundled()
private let now = Fake.noon
private let today = Fake.day("2027-01-13")

private let validAnswers: [String: Answer] = [
    "urgency": .score(score: 2.1, confidence: 0.7, probabilities: [0: 0.05, 1: 0.15, 2: 0.4, 3: 0.4]),
    "impact": .score(score: 1.2, confidence: 0.6, probabilities: [0: 0.2, 1: 0.4, 2: 0.4]),
    "concrete": .noul(0.9),
    "avoiding": .noul(0.3),
]

private func score(
    _ answers: [String: Answer] = validAnswers, model: String? = "jev-1.13.0", set: QuestionSet = questions
) -> TaskScore? {
    ScoreRules.score(
        taskID: 1, response: DecisionResponse(model: model, answers: answers), questions: set,
        provider: "fake", stateHash: "0123456789abcdef", now: now)
}

private func stored(
    _ taskID: TaskID = 1, urgency: Double = 0.5, impact: Double = 0.5, avoiding: Double = 0.3,
    version: String = "v1", hash: String = "0123456789abcdef"
) -> TaskScore {
    TaskScore(
        taskID: taskID, questionVersion: version, provider: "fake", modelSnapshot: "jev-1.13.0",
        urgency: urgency, impact: impact, concrete: 0.9, avoiding: avoiding, probsJSON: "{}", stateHash: hash,
        scoredAt: now)
}

private func priority(_ score: TaskScore, _ task: MokaTask) -> Double {
    ScoreRules.priority(score, task: task, today: today, questions: questions, calendar: Fake.seoul)
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

@Suite struct ScoreRulesParseTests {
    @Test("FR-04 R-204: 응답을 판단 결과로 바꾸고 urgency·impact는 옵션 수로 0~1에 맞춘다")
    func parsesAndNormalizes() throws {
        let result = try #require(score())
        #expect(result.taskID == 1)
        #expect(result.questionVersion == "v1")
        #expect(result.provider == "fake")
        #expect(result.modelSnapshot == "jev-1.13.0")
        #expect(near(result.urgency, 2.1 / 3))
        #expect(near(result.impact, 1.2 / 2))
        #expect(result.concrete == 0.9)
        #expect(result.avoiding == 0.3)
        #expect(result.stateHash == "0123456789abcdef")
        #expect(result.scoredAt == now)
    }

    @Test("FR-04 R-205: 응답에 모델 이름이 없으면 응답 모델 칸을 비운다")
    func missingModel() throws {
        #expect(try #require(score(model: nil)).modelSnapshot == nil)
    }

    @Test("FR-04 R-204: 정규화 분모는 질문 파일의 옵션 수에서 온다")
    func denominatorFromOptions() throws {
        let five = try QuestionSet(
            json: questionsJSON { root in
                editQuestions(&root) {
                    $0["urgency"] = ["type": "score", "instructions": "가짜", "criteria": ["a", "b", "c", "d", "e"]]
                }
            })
        var answers = validAnswers
        answers["urgency"] = .score(score: 2, confidence: 0.5, probabilities: [0: 0, 1: 0, 2: 1, 3: 0, 4: 0])
        #expect(near(try #require(score(answers, set: five)).urgency, 0.5))
    }

    @Test(
        "FR-04 R-204: 질문 빠짐·타입 다름·범위 밖·신뢰도 없음·옵션 확률 키가 다르면 판단 결과를 만들지 않는다",
        arguments: [
            "avoiding 빠짐", "concrete가 score", "urgency가 noul", "noul 1 초과", "noul 음수", "score 상한 초과",
            "score 음수", "confidence 없음", "confidence 범위 밖", "확률 키 모자람", "확률 키 남음", "확률 값 범위 밖",
        ])
    func malformed(caseName: String) {
        var answers = validAnswers
        switch caseName {
        case "avoiding 빠짐": answers["avoiding"] = nil
        case "concrete가 score":
            answers["concrete"] = .score(score: 1, confidence: 0.5, probabilities: [0: 0.5, 1: 0.5])
        case "urgency가 noul": answers["urgency"] = .noul(0.5)
        case "noul 1 초과": answers["concrete"] = .noul(1.2)
        case "noul 음수": answers["avoiding"] = .noul(-0.1)
        case "score 상한 초과":
            answers["urgency"] = .score(score: 3.5, confidence: 0.7, probabilities: [0: 0.1, 1: 0.1, 2: 0.4, 3: 0.4])
        case "score 음수":
            answers["impact"] = .score(score: -0.1, confidence: 0.6, probabilities: [0: 0.2, 1: 0.4, 2: 0.4])
        case "confidence 없음":
            answers["impact"] = .score(score: 1, confidence: nil, probabilities: [0: 0.2, 1: 0.4, 2: 0.4])
        case "confidence 범위 밖":
            answers["impact"] = .score(score: 1, confidence: 1.1, probabilities: [0: 0.2, 1: 0.4, 2: 0.4])
        case "확률 키 모자람":
            answers["urgency"] = .score(score: 2, confidence: 0.7, probabilities: [0: 0.1, 1: 0.5, 2: 0.4])
        case "확률 키 남음":
            answers["impact"] = .score(score: 1, confidence: 0.6, probabilities: [0: 0.2, 1: 0.4, 2: 0.3, 3: 0.1])
        case "확률 값 범위 밖":
            answers["impact"] = .score(score: 1, confidence: 0.6, probabilities: [0: -0.2, 1: 0.8, 2: 0.4])
        default: Issue.record("모르는 경우 \(caseName)")
        }
        #expect(score(answers) == nil)
    }

    @Test("FR-04 R-205: probs_json은 질문 이름 순, 옵션 번호 순, Swift 최단 숫자 표기(golden)")
    func probsJSONGolden() throws {
        #expect(
            try #require(score()).probsJSON
                == #"{"avoiding":{"noul":0.3},"concrete":{"noul":0.9},"#
                + #""impact":{"score":1.2,"confidence":0.6,"probabilities":{"0":0.2,"1":0.4,"2":0.4}},"#
                + #""urgency":{"score":2.1,"confidence":0.7,"probabilities":{"0":0.05,"1":0.15,"2":0.4,"3":0.4}}}"#)
    }

    @Test("FR-04 R-205: probs_json 숫자는 1.0·1e-05처럼 적는다")
    func probsJSONNumbers() throws {
        var answers = validAnswers
        answers["concrete"] = .noul(1)
        answers["avoiding"] = .noul(0.00001)
        let json = try #require(score(answers)).probsJSON
        #expect(json.hasPrefix(#"{"avoiding":{"noul":1e-05},"concrete":{"noul":1.0},"#))
    }
}

@Suite struct ScoreRulesPriorityTests {
    @Test("FR-04 R-204: priority = 1.0·urgency + 0.7·impact + 0.8·aging")
    func formula() {
        #expect(near(priority(stored(urgency: 0.5, impact: 0.4), Fake.task(1)), 0.5 + 0.7 * 0.4))
    }

    @Test(
        "FR-04 R-204: 마감이 내일까지(지난 마감 포함)면 urgency를 1로 본다",
        arguments: [("2027-01-12", true), ("2027-01-13", true), ("2027-01-14", true), ("2027-01-15", false)])
    func urgencyFloor(deadline: String, floored: Bool) {
        let value = priority(stored(urgency: 0.2, impact: 0), Fake.task(1, deadline: Fake.day(deadline)))
        #expect(near(value, floored ? 1 : 0.2))
    }

    @Test("FR-04 R-205: 저장하는 urgency는 하한을 적용하기 전 값이다")
    func storedUrgencyIsBeforeFloor() throws {
        let result = try #require(score())
        #expect(near(result.urgency, 0.7))
        #expect(near(priority(result, Fake.task(1, deadline: today)) - 0.7 * result.impact, 1))
    }

    @Test(
        "FR-04 R-204: aging = 미룬 횟수 × (avoiding이 임계값 이상이면 1.5, 아니면 1)",
        arguments: [(0.7, 1.5), (0.71, 1.5), (0.69, 1.0)])
    func aging(avoiding: Double, factor: Double) {
        let value = priority(stored(urgency: 0, impact: 0, avoiding: avoiding), Fake.task(1, skipCount: 2))
        #expect(near(value, 0.8 * 2 * factor))
    }

    @Test("FR-04 R-204: 가중치 초기값은 Defaults 한 곳에 있다")
    func defaults() {
        #expect(Defaults.weightUrgency == 1.0)
        #expect(Defaults.weightImpact == 0.7)
        #expect(Defaults.weightAging == 0.8)
        #expect(Defaults.avoidingAgingFactor == 1.5)
        #expect(Defaults.decisionTimeout == 3)
        #expect(Defaults.maxConcurrentDecisions == 4)
    }
}

@Suite struct ScoreRulesUsableTests {
    @Test("FR-05 R-208: 키가 없으면 쓰는 판단 결과가 없다")
    func noKey() {
        #expect(ScoreRules.usable(scores: [1: stored()], hasKey: false, questionVersion: "v1").isEmpty)
    }

    @Test("FR-03 R-206: 질문 버전이 다른 판단 결과는 쓰지 않고, 판단 입력 해시가 달라도 다시 묻기 전까지 쓴다")
    func versionAndHash() {
        let scores: [TaskID: TaskScore] = [
            1: stored(1, version: "v0"), 2: stored(2, hash: "ffffffffffffffff"), 3: stored(3),
        ]
        #expect(Set(ScoreRules.usable(scores: scores, hasKey: true, questionVersion: "v1").keys) == [2, 3])
    }
}

@Suite struct PriorityTextTests {
    @Test(
        "FR-04 R-215: priority 칸은 소수 둘째 자리까지, 점수가 없으면 빈칸",
        arguments: [(1.2, "1.20"), (0.0, "0.00"), (2.456, "2.46"), (12.3, "12.30"), (0.994, "0.99"), (0.996, "1.00")])
    func formats(value: Double, expected: String) {
        #expect(TaskRowText.priority(value) == expected)
    }

    @Test("FR-04 R-215: 점수가 없으면 빈칸")
    func empty() {
        #expect(TaskRowText.priority(nil) == "")
    }
}
