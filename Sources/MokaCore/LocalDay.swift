import Foundation

/// 지역 날짜 `YYYY-MM-DD`(그레고리력, 시간대 없음). 마감, 컨텍스트 날짜, 주기 날짜에 쓴다.
public struct LocalDay: Comparable, Hashable, Sendable {
    public let year: Int, month: Int, day: Int

    /// 형식·달력 날짜가 틀리면 nil. 연도는 0001~9999.
    public init?(text: String) {
        let b = Array(text.utf8)
        guard b.count == 10, b[4] == UInt8(ascii: "-"), b[7] == UInt8(ascii: "-"),
            let year = GregorianCivil.digits(b, 0, 4), let month = GregorianCivil.digits(b, 5, 2),
            let day = GregorianCivil.digits(b, 8, 2), GregorianCivil.isValidDate(year: year, month: month, day: day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    private init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var text: String {
        GregorianCivil.formatDate(year: year, month: month, day: day)
    }

    /// 그레고리력 날짜 산술로 더한다. `calendar`는 ADR-0010대로 그레고리력이라 결과가 같다.
    public func adding(days: Int, calendar: Calendar) -> LocalDay {
        let (year, month, day) = GregorianCivil.civilFromDays(daysSinceEpoch + days)
        return LocalDay(year: year, month: month, day: day)
    }

    /// 1(일)~7(토). 1970-01-01은 목요일(5).
    public func weekday(calendar: Calendar) -> Weekday {
        let index = ((daysSinceEpoch + 4) % 7 + 7) % 7
        return Weekday(rawValue: index + 1)!
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(date: Date, calendar: Calendar) {
        self = LocalDay.containing(date, calendar: calendar)
    }

    /// 날짜 고르기에 넘길 시각. 그 날짜의 정오라 시간대가 바뀌어도 날짜가 밀리지 않는다.
    public func date(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// 주입한 달력의 지역 날짜(시간대는 `calendar.timeZone`).
    static func containing(_ instant: Date, calendar: Calendar) -> LocalDay {
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return LocalDay(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    private var daysSinceEpoch: Int {
        GregorianCivil.daysFromCivil(year: year, month: month, day: day)
    }
}

/// 하루 시작 시각 `HH:MM`(24시간, 두 자리). 00:00~23:59.
public struct DayStart: Equatable, Sendable {
    public let hour: Int, minute: Int

    public init?(text: String) {
        let b = Array(text.utf8)
        guard b.count == 5, b[2] == UInt8(ascii: ":"), let hour = GregorianCivil.digits(b, 0, 2),
            let minute = GregorianCivil.digits(b, 3, 2), hour < 24, minute < 60
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    /// `Defaults.dayStart`처럼 범위를 아는 상수만 쓴다.
    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var text: String {
        twoDigits(hour) + ":" + twoDigits(minute)
    }

    /// 시각 고르기(`DatePicker`)가 낸 시각의 시·분. 초는 버린다.
    public init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// 시각 고르기에 넘길 시각. 시·분만 의미가 있고 날짜는 2001-01-01로 둔다.
    public func date(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute))!
    }

    private func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

/// 달력 만들기(ADR-0010). 앱은 시간대만 넘긴다.
public enum GregorianCalendar {
    public static func make(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// 하루 경계(R-114, data-model §5.4). 하루는 그 날짜의 `dayStart` 시·분에 시작한다.
public enum DayBoundary {
    public static func day(containing instant: Date, dayStart: DayStart, calendar: Calendar) -> LocalDay {
        let civil = LocalDay.containing(instant, calendar: calendar)
        return instant >= start(of: civil, dayStart: dayStart, calendar: calendar)
            ? civil : civil.adding(days: -1, calendar: calendar)
    }

    /// 없는 시각(일광절약시간 시작)은 다음에 오는 시각, 두 번 있는 시각은 앞의 것.
    public static func start(of day: LocalDay, dayStart: DayStart, calendar: Calendar) -> Date {
        let noon = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
        let midnight = calendar.startOfDay(for: noon)
        return calendar.date(
            bySettingHour: dayStart.hour, minute: dayStart.minute, second: 0, of: midnight,
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)!
    }
}
