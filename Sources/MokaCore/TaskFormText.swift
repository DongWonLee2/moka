/// 할 일 시트(새로 만들기·고치기)의 이유 안내와 칸 해석(R-101, 시안 8번). 분기하거나 값을 끼우는 글자라 MokaCore가 정한다(#42).
public enum TaskFormText {
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

    public static func deleteTitle(_ title: String) -> String {
        "\"\(title)\"\(objectParticle(after: title)) 지울까요?"
    }

    public static func deleteMessage(stopsTimer: Bool) -> String {
        let rest = "노치에 다시 뜨지 않아요. 지금까지 남긴 기록은 그대로 둬요."
        return stopsTimer ? "지금 타이머가 도는 할 일이에요. 지우면 타이머가 멈추고 \(rest)" : "지우면 \(rest)"
    }

    public static func firstActionNote(_ firstAction: String) -> String {
        "\(firstAction) · 멈출 때 적어 둔 줄이에요."
    }

    private static let digitsWithFinalConsonant = "013678"

    private static func objectParticle(after text: String) -> String {
        guard let last = text.unicodeScalars.last else { return "을(를)" }
        switch last.value {
        case 0xAC00...0xD7A3:
            return (last.value - 0xAC00) % 28 == 0 ? "를" : "을"
        case 0x30...0x39:
            return digitsWithFinalConsonant.unicodeScalars.contains(last) ? "을" : "를"
        default:
            return "을(를)"
        }
    }

    public static func deadlineLabel(_ deadline: LocalDay?) -> String {
        guard let deadline else { return "마감 없음" }
        return "\(deadline.year)년 \(deadline.month)월 \(deadline.day)일"
    }
}
