import Foundation

/// 할 일 하나의 게이트 기록. AppState 메모리에만 있고 앱을 다시 켜면 사라진다(spec 004 R-309).
public struct GateRecord: Equatable, Sendable {
    public var submissions: Int
    public var passed: Bool

    public init(submissions: Int = 0, passed: Bool = false) {
        self.submissions = submissions
        self.passed = passed
    }
}

/// 노치에 보일 게이트 단계.
public enum GatePhase: Equatable, Sendable {
    case asking
    case checking
    case closed
}

/// 구체화 게이트 판정(spec 004 R-306·R-308·R-309, data-model §3). AppState는 값을 모아 넘기고 결과를 반영한다.
public enum ConcreteGate {
    /// 판정에 쓰는 값. 뜻은 data-model §3 입력 값 표다.
    public struct Facts: Equatable, Sendable {
        public var isDraft: Bool
        public var canQuery: Bool
        /// 그 할 일의 쓰는 판단 결과(`usable[taskID]`).
        public var score: TaskScore?
        public var currentHash: String
        /// 보내기 장부에 그 할 일이 실패로 적힌 해시.
        public var failedHash: String?
        public var threshold: Double
        public var record: GateRecord
        /// 제출 뒤 판정을 기다리는 중이다.
        public var waiting: Bool

        public init(
            isDraft: Bool, canQuery: Bool, score: TaskScore?, currentHash: String, failedHash: String?,
            threshold: Double, record: GateRecord, waiting: Bool
        ) {
            self.isDraft = isDraft
            self.canQuery = canQuery
            self.score = score
            self.currentHash = currentHash
            self.failedHash = failedHash
            self.threshold = threshold
            self.record = record
            self.waiting = waiting
        }
    }

    /// `thresholds[model]["concrete"]`. `QuestionSet`이 읽을 때 있는지 확인했다.
    public static func threshold(_ questions: QuestionSet) -> Double {
        questions.thresholds[questions.model]!["concrete"]!
    }

    /// 보일 단계. 기다림은 `checking`일 때만 이어지고, 그 밖의 단계가 나오면 끝낸다.
    public static func phase(_ facts: Facts) -> GatePhase {
        judge(facts).phase
    }

    /// 판정을 반영한 기록. 기다리던 제출이 통과로 끝나면 `passed`가 켜진다.
    public static func afterAnswer(_ facts: Facts) -> GateRecord {
        var record = facts.record
        if judge(facts).passes {
            record.passed = true
        }
        return record
    }

    private static func judge(_ facts: Facts) -> (phase: GatePhase, passes: Bool) {
        guard facts.isDraft, !facts.record.passed else { return (.closed, false) }
        guard facts.waiting else {
            let low = facts.canQuery && facts.score.map { $0.concrete < facts.threshold } == true
            return (low ? .asking : .closed, false)
        }
        guard facts.canQuery, facts.failedHash != facts.currentHash else { return (.closed, true) }
        guard let score = facts.score, score.stateHash == facts.currentHash else { return (.checking, false) }
        if score.concrete >= facts.threshold || facts.record.submissions >= Defaults.concreteGateMaxSubmissions {
            return (.closed, true)
        }
        return (.asking, false)
    }
}
