/// 할 일 시트(새로 만들기·고치기)의 이유 안내와 칸 해석(R-101, 시안 8번). 분기하거나 값을 끼우는 글자라 MokaCore가 정한다(#42).
public enum TaskFormText {
    private static let weekdayShortNames = ["일", "월", "화", "수", "목", "금", "토"]

    /// 제목이 비었거나 공백뿐이면 저장을 막는 이유.
    public static func titleIssue(_ title: String) -> String? {
        MokaTask.normalizedTitle(title) == nil ? "제목을 넣어 주세요." : nil
    }

    /// 예상 소요 칸. 비우면 없음, 1 이상 정수면 그 값, 그 밖은 nil.
    public static func estMin(_ text: String) -> Int? {
        guard let minutes = Int(text), MokaTask.isValidEstMin(minutes) else { return nil }
        return minutes
    }

    /// 비우지 않았는데 1 이상 정수가 아니면 이유.
    public static func estMinIssue(_ text: String) -> String? {
        text.isEmpty || estMin(text) != nil ? nil : "1분 이상으로 넣어 주세요."
    }

    /// 매주를 고르면 요일 줄 아래 안내. `today`는 등록 순간이 속한 하루(§5.8)의 요일이다.
    public static func weekdayHint(today: Weekday) -> String {
        "오늘(\(weekdayShortNames[today.rawValue - 1]))이 먼저 골라져 있어요. 하나만 고를 수 있어요."
    }
}
