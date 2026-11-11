import Foundation

/// 노치 후보 순서(spec 003 R-208, data-model §7). 스케줄러(마일스톤 4) 전 임시 규칙이다.
public enum PriorityOrder {
    /// 점수 있는 대기 할 일을 priority 내림차순으로 앞에, 점수 없는 대기 할 일을 마감 순으로 뒤에 둔다.
    /// priority가 같으면 마감 순으로 가른다.
    public static func order(
        tasks: [MokaTask], usable: [TaskID: TaskScore], thresholds: ModelThresholds?, today: LocalDay,
        calendar: Calendar
    ) -> [MokaTask] {
        let todo = tasks.filter { $0.status == .todo }
        let scored = todo.compactMap { task in
            usable[task.id].map {
                (task, ScoreRules.priority($0, task: task, today: today, thresholds: thresholds, calendar: calendar))
            }
        }
        .sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 > rhs.1 : TaskListView.deadlineFirst(lhs.0, rhs.0)
        }
        .map(\.0)
        let unscored = todo.filter { usable[$0.id] == nil }.sorted(by: TaskListView.deadlineFirst)
        return scored + unscored
    }

    /// `input.scoring`이 nil이면 모든 대기 할 일이 점수 없음(마감 순)이다.
    public static func order(_ input: SessionInput) -> [MokaTask] {
        guard let scoring = input.scoring else {
            return input.tasks.filter { $0.status == .todo }.sorted(by: TaskListView.deadlineFirst)
        }
        return order(
            tasks: input.tasks, usable: scoring.usable, thresholds: scoring.thresholds, today: scoring.today,
            calendar: input.calendar)
    }
}

/// 노치 고르기(spec 003 R-209, data-model §7). spec 002 `RotateByIDRule`을 대신한다.
public enum PriorityRotateRule {
    public static let choice = SchedulerChoice.priorityRotateV0

    /// `after`가 없거나 순서에 없으면 1위, 있으면 그다음(끝이면 1위).
    public static func pick(order: [MokaTask], after previous: TaskID?) -> MokaTask? {
        guard let previous, let index = order.firstIndex(where: { $0.id == previous }) else { return order.first }
        return order.indices.contains(index + 1) ? order[index + 1] : order.first
    }
}
