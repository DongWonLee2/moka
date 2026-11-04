import Foundation

/// 마감 달력의 한 달(R-101 "날짜 고르기로만"). 주는 일요일 시작이다.
public struct CalendarMonth: Equatable, Sendable {
    public let year: Int, month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(containing day: LocalDay) {
        self.init(year: day.year, month: day.month)
    }

    public func adding(months: Int) -> CalendarMonth {
        let index = year * 12 + (month - 1) + months
        let year = Int((Double(index) / 12).rounded(.down))
        return CalendarMonth(year: year, month: index - year * 12 + 1)
    }

    public func cells(calendar: Calendar) -> [LocalDay?] {
        let first = LocalDay(text: GregorianCivil.formatDate(year: year, month: month, day: 1))!
        let blanks = first.weekday(calendar: calendar).rawValue - 1
        let days = (0..<GregorianCivil.daysInMonth(year: year, month: month)).map {
            first.adding(days: $0, calendar: calendar)
        }
        return Array(repeating: nil, count: blanks) + days
    }
}
