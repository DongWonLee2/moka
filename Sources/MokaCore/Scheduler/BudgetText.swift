import Foundation

/// 가용 시간 질문·늘리기·오늘 끝의 값을 끼우는 글자(spec 005 data-model §19, 확정 시안 005 4~9번, #42).
/// 하루 경계 뒤 끈 이유(`crossDayOff`)는 시안 밖 문구다(사용자 결정 2026-11-17).
public enum BudgetText {
    /// "2시간", "2시간 15분", "30분". 0인 쪽은 뺀다.
    public static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest)분"
        case (_, 0): return "\(hours)시간"
        default: return "\(hours)시간 \(rest)분"
        }
    }

    public static let choices = Defaults.availableHoursChoices.map { "\($0)시간" }

    public static func capNote(minutes: Int, expired: Bool) -> String {
        expired
            ? "오늘 남은 시간이 \(minutes)분이라 \(minutes)분까지 이어 갈 수 있어요."
            : "오늘 남은 시간은 \(minutes)분이에요. 더 길게 고르면 오늘 시간을 늘릴지 물어요."
    }

    public static func extendTitle(extra: Int, chip: Int) -> String {
        "오늘 시간을 \(extra)분 늘려서 \(chip)분 할까요?"
    }

    public static func extendDetail(remaining: Int, newTotal: Int) -> String {
        "오늘 남은 시간은 \(remaining)분이에요. 늘리면 오늘 정한 시간이 \(duration(minutes: newTotal))이 돼요."
    }

    public static func keepRemaining(minutes: Int) -> String {
        "\(minutes)분만 할래요"
    }

    public static func dayEndOff(minutes: Int) -> String {
        "오늘 정한 \(duration(minutes: minutes))을 다 써서 더 이어 갈 수 없어요. 두 줄을 적고 버튼을 눌러 주세요."
    }

    public static func crossDayOff(minutes: Int) -> String {
        "어제 정한 \(duration(minutes: minutes))을 다 썼어요."
    }

    public static func dayEndTitle(minutes: Int) -> String {
        "오늘 정한 \(duration(minutes: minutes))을 다 썼어요"
    }

    /// 오늘 쓴 시간. 가까운 분으로 반올림한다.
    public static func used(seconds: Int) -> String {
        duration(minutes: (seconds + 30) / 60)
    }

    /// 오늘 쓴 시간 막대의 채움(0~1).
    public static func usedFraction(_ record: DayBudget) -> Double {
        guard record.minutes > 0 else { return 1 }
        return min(1, max(0, Double(record.usedSeconds) / Double(record.minutes * 60)))
    }
}
