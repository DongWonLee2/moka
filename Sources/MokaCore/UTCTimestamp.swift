import Foundation

/// 저장 시각 문자열 UTC `YYYY-MM-DDTHH:MM:SSZ`(research R13). 시스템 시간대·`Calendar`를 쓰지 않는다.
public enum UTCTimestamp {
    /// 초 아래는 버린다.
    public static func format(_ date: Date) -> String {
        GregorianCivil.formatUTC(epochSeconds(of: date))
    }

    /// `format`이 만드는 형식만 받는다. 틀리면 nil.
    public static func parse(_ text: String) -> Date? {
        let b = Array(text.utf8)
        guard b.count == 20, b[4] == UInt8(ascii: "-"), b[7] == UInt8(ascii: "-"), b[10] == UInt8(ascii: "T"),
            b[13] == UInt8(ascii: ":"), b[16] == UInt8(ascii: ":"), b[19] == UInt8(ascii: "Z"),
            let year = GregorianCivil.digits(b, 0, 4), let month = GregorianCivil.digits(b, 5, 2),
            let day = GregorianCivil.digits(b, 8, 2), let hour = GregorianCivil.digits(b, 11, 2),
            let minute = GregorianCivil.digits(b, 14, 2), let second = GregorianCivil.digits(b, 17, 2),
            GregorianCivil.isValidDate(year: year, month: month, day: day), hour < 24, minute < 60, second < 60
        else { return nil }
        let days = GregorianCivil.daysFromCivil(year: year, month: month, day: day)
        return Date(timeIntervalSince1970: TimeInterval(days * 86_400 + hour * 3600 + minute * 60 + second))
    }

    public static func floorToSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: TimeInterval(epochSeconds(of: date)))
    }

    private static func epochSeconds(of date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }
}

/// 그레고리력 날짜 계산. `SimTimestamp`, `UTCTimestamp`, `LocalDay`가 함께 쓴다(data-model §2.1).
enum GregorianCivil {
    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// 연도 1...9999, 월 1...12, 그 달에 있는 날.
    static func isValidDate(year: Int, month: Int, day: Int) -> Bool {
        (1...9999).contains(year) && (1...12).contains(month)
            && (1...daysInMonth(year: year, month: month)).contains(day)
    }

    // Howard Hinnant의 days_from_civil / civil_from_days(그레고리력, 1970-01-01 = 0).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civilFromDays(_ days: Int) -> (Int, Int, Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// UTC `YYYY-MM-DDTHH:MM:SSZ`.
    static func formatUTC(_ epochSeconds: Int) -> String {
        let days = epochSeconds >= 0 ? epochSeconds / 86_400 : (epochSeconds - 86_399) / 86_400
        let secondsOfDay = epochSeconds - days * 86_400
        let (year, month, day) = civilFromDays(days)
        return "\(formatDate(year: year, month: month, day: day))T\(pad(secondsOfDay / 3600, 2)):"
            + "\(pad(secondsOfDay % 3600 / 60, 2)):\(pad(secondsOfDay % 60, 2))Z"
    }

    /// `YYYY-MM-DD`.
    static func formatDate(year: Int, month: Int, day: Int) -> String {
        "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    /// `bytes[start..<start+count]`가 모두 ASCII 숫자일 때 그 값.
    static func digits(_ bytes: [UInt8], _ start: Int, _ count: Int) -> Int? {
        guard start + count <= bytes.count else { return nil }
        var value = 0
        for byte in bytes[start..<start + count] {
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        return value
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
