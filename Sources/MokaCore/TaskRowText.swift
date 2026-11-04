/// 설정 창 할 일 탭 한 줄의 글자(R-102, 시안 7번). 값을 끼우거나 분기하는 글자라 MokaCore가 정한다(#42).
public enum TaskRowText {
    private static let weekdayNames = ["일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]

    /// 보조 줄: 마감 · 예상 · 반복 · 미룬 횟수. 보일 것이 없으면 "—".
    public static func meta(_ task: MokaTask) -> String {
        var parts: [String] = []
        if let deadline = task.deadline {
            parts.append("마감 \(deadline.month)월 \(deadline.day)일")
        }
        if let estMin = task.estMin {
            parts.append("예상 \(estMin)분")
        }
        switch task.recurrence {
        case .none:
            break
        case .daily:
            parts.append("매일")
        case .weekly:
            if let weekday = task.weekday {
                parts.append("매주 \(weekdayNames[weekday.rawValue - 1])")
            }
        }
        if task.skipCount > 0 {
            parts.append("\(task.skipCount)번 미뤘어요")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// 반복 할 일의 연속 기록 배지. 0이거나 반복이 아니면 nil.
    public static func streakBadge(_ task: MokaTask) -> String? {
        guard task.streak > 0 else { return nil }
        switch task.recurrence {
        case .none: return nil
        case .daily: return "\(task.streak)일 연속 진행"
        case .weekly: return "\(task.streak)주 연속 진행"
        }
    }

    /// 상태 배지. 버린 할 일은 목록에 나오지 않는다(`TaskListView.rows`).
    public static func status(_ status: TaskStatus) -> String {
        switch status {
        case .todo: "대기"
        case .active: "진행 중"
        case .done: "완료"
        case .dropped: "버림"
        }
    }
}
