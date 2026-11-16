import Foundation

/// storage 모드에서 이벤트 하나를 적용한 뒤의 상태. 불변식 검사와 출력이 읽는다.
public struct SimStorageState: Equatable, Sendable {
    /// nil이면 꺼짐(`quit` 뒤).
    public var session: NotchSession?
    /// 버림 포함, id 오름차순.
    public var tasks: [MokaTask]
    public var checkpoints: [Checkpoint]
    public var decisions: [DecisionLogEntry]
    /// 이월·가용 시간이 켜진 시나리오에서만 값(spec 005 Q3-C).
    public var schedule: SimSchedule?

    public init(
        session: NotchSession?, tasks: [MokaTask], checkpoints: [Checkpoint], decisions: [DecisionLogEntry],
        schedule: SimSchedule? = nil
    ) {
        self.session = session
        self.tasks = tasks
        self.checkpoints = checkpoints
        self.decisions = decisions
        self.schedule = schedule
    }
}

/// 이월·가용 시간 상태(spec 005 data-model §11·§12). 출력과 불변식이 읽는다.
public struct SimSchedule: Equatable, Sendable {
    public var mode: NotchMode
    /// 저장된 가용 시간 기록(어느 하루든). 출력은 `today`의 기록만 낸다.
    public var budget: DayBudget?
    public var today: LocalDay

    public init(mode: NotchMode, budget: DayBudget?, today: LocalDay) {
        self.mode = mode
        self.budget = budget
        self.today = today
    }
}
