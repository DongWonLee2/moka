import Foundation

public enum TaskListScope: Sendable { case all, today, thisWeek }
public enum TaskListOrder: Sendable { case created, deadline }

/// 할 일 목록 보기(R-118, data-model §5.7). 노치 고르기(§5.1)와 무관하다.
public enum TaskListView {
    /// 버린(`dropped`) 할 일은 늘 빼고, 완료한 할 일은 정렬 순서를 지킨 채 아래로 모은다(R-118).
    /// `today`는 호출자가 `DayBoundary`(§5.4)로 구해 넘긴다.
    public static func rows(
        _ tasks: [MokaTask], scope: TaskListScope, order: TaskListOrder, today: LocalDay, calendar: Calendar
    ) -> [MokaTask] {
        let todayWeekday = today.weekday(calendar: calendar)
        // 주는 일요일(1) 시작이라 이번 주 토요일은 오늘에서 7 − 요일 번호만큼 뒤다.
        let saturday = today.adding(days: 7 - todayWeekday.rawValue, calendar: calendar)
        let shown = tasks.filter { task in
            guard task.status != .dropped else { return false }
            switch scope {
            case .all:
                return true
            case .today:
                return task.deadline.map { $0 <= today } == true || task.recurrence == .daily
                    || (task.recurrence == .weekly && task.weekday == todayWeekday)
            case .thisWeek:
                return task.deadline.map { $0 <= saturday } == true || task.recurrence != .none
            }
        }
        let sorted: [MokaTask]
        switch order {
        case .created:
            sorted = shown.sorted { $0.id < $1.id }
        case .deadline:
            sorted = shown.sorted { lhs, rhs in
                switch (lhs.deadline, rhs.deadline) {
                case (let left?, let right?) where left != right: return left < right
                case (.some, .none): return true
                case (.none, .some): return false
                default: return lhs.id < rhs.id
                }
            }
        }
        return sorted.filter { $0.status != .done } + sorted.filter { $0.status == .done }
    }
}
