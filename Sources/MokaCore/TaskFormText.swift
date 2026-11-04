/// 할 일 시트(새로 만들기·고치기)의 이유 안내와 칸 해석(R-101, 시안 8번). 분기하거나 값을 끼우는 글자라 MokaCore가 정한다(#42).
public enum TaskFormText {
    private static let weekdayShortNames = ["일", "월", "화", "수", "목", "금", "토"]

    public static func titleIssue(_ title: String) -> String? {
        MokaTask.normalizedTitle(title) == nil ? "제목을 넣어 주세요." : nil
    }

    /// 예상 소요 칸. 비우면 없음, 1 이상 정수면 그 값, 그 밖은 nil.
    public static func estMin(_ text: String) -> Int? {
        guard let minutes = Int(text), MokaTask.isValidEstMin(minutes) else { return nil }
        return minutes
    }

    public static func estMinIssue(_ text: String) -> String? {
        text.isEmpty || estMin(text) != nil ? nil : "1분 이상으로 넣어 주세요."
    }

    public static func deadlineLabel(_ deadline: LocalDay?) -> String {
        guard let deadline else { return "마감 없음" }
        return "\(deadline.year)년 \(deadline.month)월 \(deadline.day)일"
    }

    public static func weekdayHint(today: Weekday) -> String {
        "오늘(\(weekdayShortNames[today.rawValue - 1]))이 먼저 골라져 있어요. 하나만 고를 수 있어요."
    }
}
