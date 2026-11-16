import Foundation

public struct CarryJudgmentInput: Sendable {
    public var tasks: [MokaTask]
    public var checkpoints: [Checkpoint]
    public var decisions: [DecisionLogEntry]
    /// 지난 판정 시각. 없으면 처음 판정이다.
    public var lastJudgedAt: Date?
    /// 이번 앱 시작에서 R-111이 대기로 되돌린 할 일(저장하지 않음, Q2-A).
    public var revertedIDs: Set<TaskID>
    public var now: Date
    public var dayStart: DayStart
    public var calendar: Calendar

    public init(
        tasks: [MokaTask], checkpoints: [Checkpoint], decisions: [DecisionLogEntry], lastJudgedAt: Date?,
        revertedIDs: Set<TaskID>, now: Date, dayStart: DayStart, calendar: Calendar
    ) {
        self.tasks = tasks
        self.checkpoints = checkpoints
        self.decisions = decisions
        self.lastJudgedAt = lastJudgedAt
        self.revertedIDs = revertedIDs
        self.now = now
        self.dayStart = dayStart
        self.calendar = calendar
    }
}

/// 이월 판정(spec 005 R-412, data-model §9). 순수 함수이고 쓰지 않는다.
public enum CarryJudgment {
    /// 처음 판정이거나 지난 판정의 하루가 오늘보다 앞이면 참.
    public static func needsRun(lastJudgedAt: Date?, now: Date, dayStart: DayStart, calendar: Calendar) -> Bool {
        guard let lastJudgedAt else { return true }
        return DayBoundary.day(containing: lastJudgedAt, dayStart: dayStart, calendar: calendar)
            < DayBoundary.day(containing: now, dayStart: dayStart, calendar: calendar)
    }

    /// 반복 없는 대기·진행 중 할 일 가운데 지난 판정 뒤 손댄 할 일과 마감이 지난 할 일.
    /// 저장 시각은 초 아래를 버리므로 구간 시작도 초로 내려 경계를 포함해 비교한다.
    public static func targets(_ input: CarryJudgmentInput) -> Set<TaskID> {
        let today = DayBoundary.day(containing: input.now, dayStart: input.dayStart, calendar: input.calendar)
        let since = UTCTimestamp.floorToSecond(
            input.lastJudgedAt
                ?? DayBoundary.start(
                    of: today.adding(days: -1, calendar: input.calendar), dayStart: input.dayStart,
                    calendar: input.calendar))
        func inWindow(_ date: Date) -> Bool { UTCTimestamp.floorToSecond(date) >= since }
        let carryAnswers: Set<UserAction> = [.carryToday, .carryDrop, .carryMove]
        let touched = Set(input.checkpoints.filter { inWindow($0.createdAt) }.map(\.taskID))
            .union(
                input.decisions.filter { inWindow($0.createdAt) && !carryAnswers.contains($0.userAction) }.map(\.taskID)
            )
            .union(input.revertedIDs)
        let targets = input.tasks.filter { task in
            guard task.recurrence == .none, task.status == .todo || task.status == .active else { return false }
            let overdue = task.deadline.map { $0 < today } ?? false
            return task.status == .active || touched.contains(task.id) || overdue
        }
        return Set(targets.map(\.id))
    }

    /// 대상 가운데 아직 표시가 없는 할 일에 이월 답 대기를 붙이는 갱신. 이미 붙은 표시는 건드리지 않는다.
    public static func marking(_ targets: Set<TaskID>, in tasks: [MokaTask]) -> StoreBatch {
        StoreBatch(
            updatedTasks: tasks.filter { targets.contains($0.id) && !$0.dueDecision }.map { task in
                var marked = task
                marked.dueDecision = true
                return marked
            })
    }
}
