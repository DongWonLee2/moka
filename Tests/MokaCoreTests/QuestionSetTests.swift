import Foundation
import MokaCore
import Testing

func questionsJSON(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
    var root: [String: Any] = [
        "version": "v2", "language": "ko", "models": ["typesafe": "jev-1.13.0"], "provisional": [String](),
        "questions": [
            "urgency": ["type": "score", "instructions": "가짜 지시 1", "criteria": ["a", "b", "c", "d"]],
            "impact": ["type": "score", "instructions": "가짜 지시 2", "criteria": ["a", "b", "c"]],
            "concrete": ["type": "noul", "instructions": "가짜 지시 3"],
            "avoiding": ["type": "noul", "instructions": "가짜 지시 4"],
        ],
        "thresholds": ["jev-1.13.0": ["concrete": 0.5, "avoiding": 0.7]],
    ]
    edit(&root)
    return try JSONSerialization.data(withJSONObject: root)
}

func editQuestions(_ root: inout [String: Any], _ edit: (inout [String: Any]) -> Void) {
    var questions = root["questions"] as! [String: Any]
    edit(&questions)
    root["questions"] = questions
}

@Suite struct QuestionSetTests {
    @Test("FR-03 R-202: 번들 질문 파일은 질문 넷과 Jev 기준 모델의 임계값을 읽는다")
    func bundled() throws {
        let set = try QuestionSet.bundled()
        #expect(set.language == "ko")
        #expect(set.models["typesafe"] == "jev-1.13.0")
        #expect(Set(set.questions.keys) == ["urgency", "impact", "concrete", "avoiding"])
        guard case .score(_, let urgency) = set.questions["urgency"],
            case .score(_, let impact) = set.questions["impact"],
            case .noul = set.questions["concrete"], case .noul = set.questions["avoiding"]
        else {
            Issue.record("질문 타입이 계약과 다름")
            return
        }
        #expect(urgency == ["여유", "이번주", "급함", "오늘안에"])
        #expect(impact == ["조금", "꽤", "아주"])
        #expect(set.thresholds["jev-1.13.0"] == ["concrete": 0.5, "avoiding": 0.7])
        #expect(set.thresholds(for: "jev-1.13.0") == ModelThresholds(concrete: 0.5, avoiding: 0.7))
    }

    @Test("FR-03 R-203: 판단 질문에 blocked가 없다")
    func noBlocked() throws {
        let set = try QuestionSet.bundled()
        #expect(set.questions["blocked"] == nil)
        #expect(set.thresholds.values.allSatisfy { $0["blocked"] == nil })
    }

    @Test("FR-03 R-202: 계약 모양이면 읽고, 옵션 수를 안다")
    func readsContractShape() throws {
        let set = try QuestionSet(json: questionsJSON())
        #expect(set.questions["urgency"]?.optionCount == 4)
        #expect(set.questions["impact"]?.optionCount == 3)
        #expect(set.questions["concrete"]?.optionCount == nil)
    }

    @Test(
        "FR-03 R-202: 질문 넷이 아니거나 타입·옵션·임계값이 계약과 다르면 읽지 않는다",
        arguments: [
            "질문 빠짐", "blocked 더함", "타입 다름", "모르는 타입", "옵션 하나", "옵션 열하나",
            "모델 임계값 없음", "avoiding 임계값 없음", "concrete 임계값 없음", "임계값 범위 밖", "임계값 음수", "버전 없음",
        ])
    func rejects(caseName: String) throws {
        let data = try questionsJSON { root in
            switch caseName {
            case "질문 빠짐": editQuestions(&root) { $0["avoiding"] = nil }
            case "blocked 더함":
                editQuestions(&root) { $0["blocked"] = ["type": "noul", "instructions": "가짜 지시"] }
            case "타입 다름":
                editQuestions(&root) {
                    $0["concrete"] = ["type": "score", "instructions": "가짜", "criteria": ["a", "b"]]
                }
            case "모르는 타입": editQuestions(&root) { $0["concrete"] = ["type": "choice", "instructions": "가짜"] }
            case "옵션 하나":
                editQuestions(&root) { $0["impact"] = ["type": "score", "instructions": "가짜", "criteria": ["a"]] }
            case "옵션 열하나":
                editQuestions(&root) {
                    $0["impact"] = ["type": "score", "instructions": "가짜", "criteria": (0..<11).map { "\($0)" }]
                }
            case "모델 임계값 없음": root["thresholds"] = ["jev-other": ["concrete": 0.5, "avoiding": 0.7]]
            case "avoiding 임계값 없음": root["thresholds"] = ["jev-1.13.0": ["concrete": 0.5]]
            case "concrete 임계값 없음": root["thresholds"] = ["jev-1.13.0": ["avoiding": 0.7]]
            case "임계값 음수": root["thresholds"] = ["jev-1.13.0": ["concrete": -0.1, "avoiding": 0.7]]
            case "임계값 범위 밖": root["thresholds"] = ["jev-1.13.0": ["concrete": 0.5, "avoiding": 1.5]]
            case "버전 없음": root["version"] = nil
            default: Issue.record("모르는 경우 \(caseName)")
            }
        }
        #expect(throws: QuestionSetError.self) { try QuestionSet(json: data) }
    }

    @Test("FR-03 R-202: urgency·impact는 score, concrete·avoiding은 noul이어야 한다")
    func rejectsSwappedTypes() throws {
        let data = try questionsJSON { root in
            editQuestions(&root) { $0["urgency"] = ["type": "noul", "instructions": "가짜"] }
        }
        #expect(throws: QuestionSetError.self) { try QuestionSet(json: data) }
    }
}
