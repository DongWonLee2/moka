import Foundation

/// 이월 카드·날짜 고르기·접힌 노치의 값을 끼우는 글자(spec 005 data-model §19, 확정 시안 005 1~3·10-1번, #42).
public enum CarryText {
    private static let weekdayNames = ["일", "월", "화", "수", "목", "금", "토"]
    /// 마감이 없는 할 일은 이 문장만 보인다(시안 밖 문구, 사용자 결정 2026-11-17).
    private static let moveNoteTail = "고른 날이 새 마감이 되고, 오늘도 노치에 뜰 수 있어요."

    public static func reason(_ reason: CarryCardReason) -> String {
        switch reason {
        case .touched: "하다 만 할 일이에요"
        case .overdue(let days): "마감이 지난 할 일이에요 · \(ReasonText.deadline(.overdue(days)))"
        }
    }

    public static func left(_ count: Int) -> String {
        "남은 \(count)개"
    }

    public static func collapsed(_ count: Int) -> String {
        "정할 일 \(count)개"
    }

    public static func moveNote(deadline: LocalDay?, calendar: Calendar) -> String {
        guard let deadline else { return moveNoteTail }
        let weekday = weekdayNames[deadline.weekday(calendar: calendar).rawValue - 1]
        return "지금 마감은 \(deadline.month)월 \(deadline.day)일(\(weekday))이에요. \(moveNoteTail)"
    }

    public static func moveConfirm(_ day: LocalDay) -> String {
        "\(day.day)일로 바꿀래요"
    }

    /// 빠른 날짜 셋: 내일, 모레, 오늘 뒤 첫 월요일(오늘이 월요일이면 이레 뒤).
    public static func quickDays(after today: LocalDay, calendar: Calendar) -> [LocalDay] {
        let monday = 2
        let untilMonday = (monday - today.weekday(calendar: calendar).rawValue + 7) % 7
        return [1, 2, untilMonday == 0 ? 7 : untilMonday].map { today.adding(days: $0, calendar: calendar) }
    }
}

/// 날짜 고르기 달력이 보이는 달. 처음엔 고른 날의 달이고, 내일이 든 달보다 앞으로는 가지 않는다.
public struct CarryMonthPage: Equatable, Sendable {
    public private(set) var month: CalendarMonth
    private let firstMonth: CalendarMonth

    public init(selected: LocalDay, today: LocalDay, calendar: Calendar) {
        month = CalendarMonth(containing: selected)
        firstMonth = CalendarMonth(containing: today.adding(days: 1, calendar: calendar))
    }

    public var canGoBack: Bool { Self.index(month) > Self.index(firstMonth) }

    public mutating func previous() {
        if canGoBack { month = month.adding(months: -1) }
    }

    public mutating func next() {
        month = month.adding(months: 1)
    }

    /// 고른 날이 든 달을 보인다. 보이는 달의 칸을 누르면 그대로다.
    public mutating func pick(_ day: LocalDay) {
        month = CalendarMonth(containing: day)
    }

    private static func index(_ month: CalendarMonth) -> Int { month.year * 12 + month.month }
}
