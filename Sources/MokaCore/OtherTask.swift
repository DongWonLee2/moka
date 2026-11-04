import Foundation

/// 시작 전 화면 "다른 할 일" 목록(R-104, 2026-11-04 사용자 결정). 노치가 처음 고르는 규칙(`RotateByIDRule`)과 무관하다.
public enum OtherTaskList {
    /// 지금 할 일을 뺀 대기 할 일. 할 일 탭 마감 순(§5.7)과 같은 순서다.
    public static func rows(_ tasks: [MokaTask], current: TaskID?, today: LocalDay, calendar: Calendar) -> [MokaTask] {
        TaskListView.rows(tasks, scope: .all, order: .deadline, today: today, calendar: calendar)
            .filter { $0.status == .todo && $0.id != current }
    }
}

/// "다른 할 일" 줄 오른쪽 보조 글자(#42).
public enum OtherTaskText {
    public enum Tone: Sendable { case overdue, soon, plain }

    private static let weekdayNames = ["일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]

    public static func note(_ task: MokaTask, today: LocalDay, calendar: Calendar) -> (text: String, tone: Tone) {
        if let deadline = task.deadline {
            if deadline < today { return ("마감 지남", .overdue) }
            if deadline == today { return ("오늘 마감", .soon) }
            if deadline == today.adding(days: 1, calendar: calendar) { return ("내일 마감", .soon) }
            return ("\(deadline.month)월 \(deadline.day)일", .plain)
        }
        switch task.recurrence {
        case .daily: return ("매일", .plain)
        case .weekly: return (task.weekday.map { "매주 \(weekdayNames[$0.rawValue - 1])" } ?? "", .plain)
        case .none: return ("", .plain)
        }
    }
}
