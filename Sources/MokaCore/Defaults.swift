import Foundation

public enum Defaults {
    public static let quantumMin = 25
    public static let quantumMinRange = 1...180
    public static let quantumPresets = [15, 25, 45, 60]
    public static let extendMin = 10
    public static let extendMinRange = 1...180
    public static let dayStart = DayStart(hour: 6, minute: 0)

    // 판단 결과 priority 식의 가중치(PRD 7장, spec 003 R-204). 질문 임계값은 `questions.json`.
    public static let weightUrgency = 1.0
    public static let weightImpact = 0.7
    public static let weightAging = 0.8
    /// avoiding이 임계값 이상이면 미룬 횟수에 곱한다.
    public static let avoidingAgingFactor = 1.5
    /// 판단 질의 한 번의 상한(R-211).
    public static let decisionTimeout: TimeInterval = 3
    /// 동시에 보내는 판단 질의 수(R-207, research R17 E2).
    public static let maxConcurrentDecisions = 4
}
