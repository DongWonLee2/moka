import Foundation
import MokaCore
import Testing

// contracts/questions-json-v2.md. 가짜 지시·가짜 모델 이름만 쓴다.

/// 버전별 고정값(research R13). 같은 `version`을 다른 `models`·`thresholds`로 다시 쓰지 않게 지킨다.
/// v1 줄은 v1 `model`을 공급자 `typesafe`로 읽은 기록이다(ADR-0011 결정 6). 새 버전을 만들면 줄을 덧붙인다.
private let fixedValues: [String: (models: [String: String], thresholds: [String: [String: Double]])] = [
    "v1": (
        models: ["typesafe": "jev-1.13.0"],
        thresholds: ["jev-1.13.0": ["concrete": 0.5, "avoiding": 0.7]]
    ),
    "v2": (
        models: [
            "typesafe": "jev-1.13.0", "liquid": "d1-ultra", "perplexity": "pplx-decider-v1.2",
            "openai": "gpt-6-luna",
        ],
        thresholds: [
            "jev-1.13.0": ["concrete": 0.5, "avoiding": 0.7],
            "d1-ultra": ["concrete": 0.5, "avoiding": 0.7],
            "pplx-decider-v1.2": ["concrete": 0.5, "avoiding": 0.7],
            "gpt-6-luna": ["concrete": 0.5, "avoiding": 0.7],
        ]
    ),
]

/// 기준 모델 둘(가짜 이름)과 잠정 하나를 둔 v2 모양.
private func twoModelsJSON(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
    try questionsJSON { root in
        root["models"] = ["typesafe": "jev-1.13.0", "liquid": "fake-base-b"]
        root["provisional"] = ["fake-base-b"]
        root["thresholds"] = [
            "jev-1.13.0": ["concrete": 0.5, "avoiding": 0.7],
            "fake-base-b": ["concrete": 0.4, "avoiding": 0.6],
        ]
        edit(&root)
    }
}

@Suite struct QuestionSetV2Tests {
    @Test("ADR-0011 R-607: 번들 질문 파일은 v2이고 models·provisional이 제안 내용 그대로다")
    func bundledV2() throws {
        let set = try QuestionSet.bundled()
        #expect(set.version == "v2")
        #expect(
            set.models == [
                "typesafe": "jev-1.13.0", "liquid": "d1-ultra", "perplexity": "pplx-decider-v1.2",
                "openai": "gpt-6-luna",
            ])
        #expect(set.models["microsoft"] == nil)
        #expect(set.provisional == ["d1-ultra", "pplx-decider-v1.2", "gpt-6-luna"])
    }

    @Test("ADR-0011 R-608 SC-604: 지금 파일의 version은 버전별 고정값에 있고 models·thresholds가 같다")
    func matchesFixedValues() throws {
        let set = try QuestionSet.bundled()
        let fixed = try #require(fixedValues[set.version], "고정값에 없는 버전 \(set.version). 새 버전이면 고정값을 덧붙인다")
        #expect(set.models == fixed.models)
        #expect(set.thresholds == fixed.thresholds)
    }

    @Test("ADR-0011 R-609: moka-sim 가짜 공급자의 기준 모델은 번들 질문 파일에 임계값이 있다")
    func simBaseModelHasThresholds() throws {
        let set = try QuestionSet.bundled()
        #expect(set.thresholds(for: SimRunner.fakeBaseModel) != nil)
    }

    @Test("ADR-0011 R-607: models·provisional을 읽고 thresholds(for:)가 기준 모델의 두 임계값을 꺼낸다")
    func readsModelsAndThresholds() throws {
        let set = try QuestionSet(json: twoModelsJSON())
        #expect(set.models == ["typesafe": "jev-1.13.0", "liquid": "fake-base-b"])
        #expect(set.provisional == ["fake-base-b"])
        #expect(set.thresholds(for: "jev-1.13.0") == ModelThresholds(concrete: 0.5, avoiding: 0.7))
        #expect(set.thresholds(for: "fake-base-b") == ModelThresholds(concrete: 0.4, avoiding: 0.6))
    }

    @Test("ADR-0011 R-609: thresholds(for:)는 질문 파일에 없는 기준 모델이면 nil이다")
    func unknownBaseModel() throws {
        let set = try QuestionSet(json: twoModelsJSON())
        #expect(set.thresholds(for: "fake-unknown") == nil)
        #expect(set.thresholds(for: "") == nil)
    }

    @Test(
        "ADR-0011 R-608 SC-604: 읽기 규칙 2·4를 어기면 읽지 않는다",
        arguments: [
            "기준 모델 임계값 없음", "concrete 없음", "avoiding 없음", "다른 기준 모델 범위 밖", "provisional이 models 밖",
            "provisional 중복", "models 없음", "provisional 없음", "v1 모양(model 한 칸)",
        ])
    func rejects(caseName: String) throws {
        let data = try twoModelsJSON { root in
            switch caseName {
            case "기준 모델 임계값 없음":
                root["thresholds"] = ["jev-1.13.0": ["concrete": 0.5, "avoiding": 0.7]]
                root["provisional"] = [String]()
            case "concrete 없음":
                root["thresholds"] = [
                    "jev-1.13.0": ["concrete": 0.5, "avoiding": 0.7], "fake-base-b": ["avoiding": 0.6],
                ]
            case "avoiding 없음":
                root["thresholds"] = [
                    "jev-1.13.0": ["concrete": 0.5, "avoiding": 0.7], "fake-base-b": ["concrete": 0.4],
                ]
            case "다른 기준 모델 범위 밖":
                root["thresholds"] = [
                    "jev-1.13.0": ["concrete": 0.5, "avoiding": 0.7],
                    "fake-base-b": ["concrete": 1.2, "avoiding": 0.6],
                ]
            case "provisional이 models 밖": root["provisional"] = ["fake-base-c"]
            case "provisional 중복": root["provisional"] = ["fake-base-b", "fake-base-b"]
            case "models 없음": root["models"] = nil
            case "provisional 없음": root["provisional"] = nil
            case "v1 모양(model 한 칸)":
                root["models"] = nil
                root["provisional"] = nil
                root["model"] = "jev-1.13.0"
            default: Issue.record("모르는 경우 \(caseName)")
            }
        }
        #expect(throws: QuestionSetError.self) { try QuestionSet(json: data) }
    }

    @Test("ADR-0011 R-608: models에 없는 기준 모델의 임계값 항목이 더 있어도 읽는다")
    func extraThresholdEntry() throws {
        let data = try twoModelsJSON { root in
            var thresholds = root["thresholds"] as? [String: Any] ?? [:]
            thresholds["fake-old-model"] = ["concrete": 0.3, "avoiding": 0.3]
            root["thresholds"] = thresholds
        }
        let set = try QuestionSet(json: data)
        #expect(set.thresholds(for: "fake-old-model") == ModelThresholds(concrete: 0.3, avoiding: 0.3))
    }
}
