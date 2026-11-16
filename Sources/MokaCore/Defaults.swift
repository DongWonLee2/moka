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
    /// 구체화 게이트가 할 일 하나에 받는 제출 수. 이 횟수의 재판정 뒤에는 미만이어도 통과다(spec 004 R-309).
    public static let concreteGateMaxSubmissions = 3

    // 스케줄러(spec 005 data-model §14).
    /// aging에서 이월 횟수에 곱한다(R-402).
    public static let carryAgingWeight = 0.5
    /// 아침 워밍업 후보의 concrete 하한과 다 하는 데 걸릴 시간 상한(R-406).
    public static let warmupConcreteMin = 0.8
    public static let warmupEstMaxMin = 30
    /// 가중 순환 창의 크기(R-403).
    public static let rotationWidth = 3
    /// 창에 점수 없는 할 일이 있을 때 순위 몫(R-403).
    public static let rotationRankShares = [5, 3, 2]
    /// priority가 0에 가까운 후보도 굶지 않게 하는 최소 몫(spec Edge Cases).
    public static let rotationMinWeight = 0.05
    /// 같은 할 일을 잇달아 고르는 상한(R-404).
    public static let consecutiveCap = 2
    /// 가용 시간 질문의 선택지(시간, R-419).
    public static let availableHoursChoices = [1, 2, 4, 6, 8]
    /// 가용 시간 직접 적기의 범위와 단위(분, R-419).
    public static let customBudgetMinutesRange = 30...960
    public static let customBudgetStepMinutes = 30
    /// 3초 뒤 자동 시작(R-410).
    public static let autoStartDelay: TimeInterval = 3
}
