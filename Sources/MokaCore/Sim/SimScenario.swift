import Foundation

enum SimEventKind: Equatable {
    case enterTitle(String)
    case chooseQuantum(Int)
    case start
    case tick
    case complete
    case setDefaultQuantum(Int)

    var name: String {
        switch self {
        case .enterTitle: "enter_title"
        case .chooseQuantum: "choose_quantum"
        case .start: "start"
        case .tick: "tick"
        case .complete: "complete"
        case .setDefaultQuantum: "set_default_quantum"
        }
    }
}

struct SimEvent: Equatable {
    var seq: Int
    /// 1970-01-01T00:00:00Z부터의 초. 출력 시각을 부동소수 없이 만든다.
    var epochSeconds: Int
    var kind: SimEventKind

    var at: Date { Date(timeIntervalSince1970: TimeInterval(epochSeconds)) }
}

struct SimScenario {
    var timezone: TimeZone
    /// `settings.default_quantum_min`. 없으면 nil(설정 규칙대로 25).
    var defaultQuantumMin: Int?
    var events: [SimEvent]
}

extension SimScenario {
    private typealias Object = [(key: String, value: SimJSON)]

    private static let topKeys: Set<String> = ["version", "timezone", "settings", "events"]
    private static let settingsKeys: Set<String> = ["default_quantum_min"]

    static func decode(_ data: Data) throws(SimError) -> SimScenario {
        let root = try object(SimJSONParser.parse(data), path: "최상위", seq: nil)

        let version = try integer(require(root, "version", path: "version", seq: nil), path: "version", seq: nil)
        guard version == 1 else { throw SimError(kind: .unknownVersion, seq: nil, message: "모르는 version \(version)") }
        try checkKeys(root, allowed: topKeys, path: "최상위", seq: nil)

        let zoneName = try string(require(root, "timezone", path: "timezone", seq: nil), path: "timezone", seq: nil)
        guard let timezone = TimeZone(identifier: zoneName) else {
            throw SimError(kind: .unknownTimezone, seq: nil, message: "모르는 timezone \(SimError.quoted(zoneName))")
        }

        var defaultQuantumMin: Int?
        if let value = field(root, "settings") {
            let settings = try object(value, path: "settings", seq: nil)
            try checkKeys(settings, allowed: settingsKeys, path: "settings", seq: nil)
            if let minutes = field(settings, "default_quantum_min") {
                defaultQuantumMin = try quantum(minutes, path: "settings.default_quantum_min", seq: nil)
            }
        }

        guard case .array(let items) = try require(root, "events", path: "events", seq: nil) else {
            throw SimError(kind: .wrongType, seq: nil, message: "events는 배열이어야 한다")
        }
        var events: [SimEvent] = []
        for (offset, item) in items.enumerated() {
            let event = try decodeEvent(item, seq: offset + 1)
            if let previous = events.last, event.epochSeconds < previous.epochSeconds {
                throw SimError(kind: .timeReversed, seq: event.seq, message: "at이 이전 이벤트보다 이르다")
            }
            events.append(event)
        }
        return SimScenario(timezone: timezone, defaultQuantumMin: defaultQuantumMin, events: events)
    }

    private static func decodeEvent(_ value: SimJSON, seq: Int) throws(SimError) -> SimEvent {
        let event = try object(value, path: "events[\(seq - 1)]", seq: seq)
        let atText = try string(require(event, "at", path: "at", seq: seq), path: "at", seq: seq)
        let type = try string(require(event, "type", path: "type", seq: seq), path: "type", seq: seq)

        let extra: String?
        switch type {
        case "enter_title": extra = "title"
        case "choose_quantum", "set_default_quantum": extra = "quantum_min"
        case "start", "tick", "complete": extra = nil
        default: throw SimError(kind: .unknownType, seq: seq, message: "모르는 type \(SimError.quoted(type))")
        }
        try checkKeys(event, allowed: Set(["at", "type"] + (extra.map { [$0] } ?? [])), path: type, seq: seq)

        let epochSeconds = try SimTimestamp.parse(atText, seq: seq)
        let kind: SimEventKind
        switch type {
        case "enter_title":
            kind = .enterTitle(try string(require(event, "title", path: "title", seq: seq), path: "title", seq: seq))
        case "choose_quantum":
            kind = .chooseQuantum(
                try quantum(require(event, "quantum_min", path: "quantum_min", seq: seq), path: "quantum_min", seq: seq)
            )
        case "set_default_quantum":
            kind = .setDefaultQuantum(
                try quantum(require(event, "quantum_min", path: "quantum_min", seq: seq), path: "quantum_min", seq: seq)
            )
        case "start": kind = .start
        case "tick": kind = .tick
        default: kind = .complete
        }
        return SimEvent(seq: seq, epochSeconds: epochSeconds, kind: kind)
    }

    private static func field(_ object: Object, _ key: String) -> SimJSON? {
        object.first { $0.key == key }?.value
    }

    private static func require(_ object: Object, _ key: String, path: String, seq: Int?) throws(SimError) -> SimJSON {
        guard let value = field(object, key) else {
            throw SimError(kind: .missingField, seq: seq, message: "필수 필드 \(path) 없음")
        }
        return value
    }

    private static func checkKeys(_ object: Object, allowed: Set<String>, path: String, seq: Int?) throws(SimError) {
        if let unknown = object.first(where: { !allowed.contains($0.key) }) {
            throw SimError(kind: .unknownKey, seq: seq, message: "\(path)에 모르는 키 \(SimError.quoted(unknown.key))")
        }
    }

    private static func object(_ value: SimJSON, path: String, seq: Int?) throws(SimError) -> Object {
        guard case .object(let members) = value else {
            throw SimError(kind: .wrongType, seq: seq, message: "\(path)는 객체여야 한다")
        }
        return members
    }

    private static func string(_ value: SimJSON, path: String, seq: Int?) throws(SimError) -> String {
        guard case .string(let text) = value else {
            throw SimError(kind: .wrongType, seq: seq, message: "\(path)는 문자열이어야 한다")
        }
        return text
    }

    /// 원문 토큰이 `-?(0|[1-9][0-9]*)`일 때만 정수다. `45.0`, `4.5e1`은 타입 틀림.
    private static func integer(_ value: SimJSON, path: String, seq: Int?) throws(SimError) -> Int {
        guard case .number(let raw) = value, !raw.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }) else {
            throw SimError(kind: .wrongType, seq: seq, message: "\(path)는 JSON 정수여야 한다")
        }
        guard let number = Int(raw) else {
            throw SimError(kind: .outOfRange, seq: seq, message: "\(path) \(raw)이 정수 범위 밖이다")
        }
        return number
    }

    private static func quantum(_ value: SimJSON, path: String, seq: Int?) throws(SimError) -> Int {
        let minutes = try integer(value, path: path, seq: seq)
        guard Defaults.quantumMinRange.contains(minutes) else {
            throw SimError(kind: .outOfRange, seq: seq, message: "\(path) \(minutes)이 1...180 밖이다")
        }
        return minutes
    }
}

/// `YYYY-MM-DDTHH:MM:SS` + `Z` 또는 `±HH:MM`만 받는다. 시스템 시간대·`Calendar`를 쓰지 않는다.
enum SimTimestamp {
    static func parse(_ text: String, seq: Int) throws(SimError) -> Int {
        let b = Array(text.utf8)
        func invalid() -> SimError {
            SimError(
                kind: .invalidTimestamp, seq: seq, message: "at \(SimError.quoted(text))는 오프셋이 있는 초 단위 ISO 8601이 아니다")
        }
        func number(_ start: Int, _ count: Int) -> Int? {
            guard start + count <= b.count else { return nil }
            var value = 0
            for byte in b[start..<start + count] {
                guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            return value
        }
        func byte(_ at: Int, is char: Character) -> Bool {
            at < b.count && b[at] == char.asciiValue
        }

        guard let year = number(0, 4), byte(4, is: "-"), let month = number(5, 2), byte(7, is: "-"),
            let day = number(8, 2), byte(10, is: "T"), let hour = number(11, 2), byte(13, is: ":"),
            let minute = number(14, 2), byte(16, is: ":"), let second = number(17, 2)
        else { throw invalid() }
        if byte(19, is: ".") {
            throw SimError(kind: .fractionalSeconds, seq: seq, message: "at \(SimError.quoted(text))에 소수 초가 있다")
        }

        let offsetSeconds: Int
        if byte(19, is: "Z"), b.count == 20 {
            offsetSeconds = 0
        } else if byte(19, is: "+") || byte(19, is: "-"), b.count == 25, let offsetHour = number(20, 2),
            byte(22, is: ":"), let offsetMinute = number(23, 2), offsetHour < 24, offsetMinute < 60
        {
            offsetSeconds = (byte(19, is: "-") ? -1 : 1) * (offsetHour * 3600 + offsetMinute * 60)
        } else {
            throw invalid()
        }

        guard (1...12).contains(month), (1...daysInMonth(year: year, month: month)).contains(day), hour < 24,
            minute < 60, second < 60
        else { throw invalid() }

        let days = daysFromCivil(year: year, month: month, day: day)
        let epochSeconds = days * 86_400 + hour * 3600 + minute * 60 + second - offsetSeconds
        guard epochSeconds >= minEpochSeconds, epochSeconds <= maxEpochSeconds else {
            throw SimError(
                kind: .invalidTimestamp, seq: seq, message: "at \(SimError.quoted(text))의 UTC 연도가 1...9999 밖이다")
        }
        return epochSeconds
    }

    /// 출력 `at`이 4자리 연도를 지키는 범위: UTC 0001-01-01T00:00:00Z ... 9999-12-31T23:59:59Z.
    private static let minEpochSeconds = daysFromCivil(year: 1, month: 1, day: 1) * 86_400
    private static let maxEpochSeconds = daysFromCivil(year: 10_000, month: 1, day: 1) * 86_400 - 1

    /// UTC `YYYY-MM-DDTHH:MM:SSZ`.
    static func formatUTC(_ epochSeconds: Int) -> String {
        let days = epochSeconds >= 0 ? epochSeconds / 86_400 : (epochSeconds - 86_399) / 86_400
        let secondsOfDay = epochSeconds - days * 86_400
        let (year, month, day) = civilFromDays(days)
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T\(pad(secondsOfDay / 3600, 2)):"
            + "\(pad(secondsOfDay % 3600 / 60, 2)):\(pad(secondsOfDay % 60, 2))Z"
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    // Howard Hinnant의 days_from_civil / civil_from_days(그레고리력, 1970-01-01 = 0).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func civilFromDays(_ days: Int) -> (Int, Int, Int) {
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
}
