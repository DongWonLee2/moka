import Foundation

enum SimEventKind: Equatable {
    case enterTitle(String)
    case chooseQuantum(Int)
    /// 두 줄은 storage 모드에서만 온다(시간 끝 다시 시작).
    case start(CheckpointNotes?)
    case tick
    /// 두 줄은 storage 모드에서만 온다(시간 끝 완료).
    case complete(CheckpointNotes?)
    case setDefaultQuantum(Int)
    // storage 모드에서만
    case addTask(NewTask)
    case skip(CheckpointNotes)
    case switchTask(CheckpointNotes)
    case quit
    case relaunch
    case activate
    // spec 003 storage 모드에서만
    case judge(SimJudge)
    case key(present: Bool)

    var name: String {
        switch self {
        case .enterTitle: "enter_title"
        case .chooseQuantum: "choose_quantum"
        case .start: "start"
        case .tick: "tick"
        case .complete: "complete"
        case .setDefaultQuantum: "set_default_quantum"
        case .addTask: "add_task"
        case .skip: "skip"
        case .switchTask: "switch"
        case .quit: "quit"
        case .relaunch: "relaunch"
        case .activate: "activate"
        case .judge: "judge"
        case .key: "key"
        }
    }
}

/// `judge` 이벤트의 값(contracts/moka-sim-v1-additions-003.md). 범위는 디코딩에서 확인했다.
struct SimJudge: Equatable {
    var taskID: TaskID
    /// 0~3, score 답.
    var urgency: Double
    /// 0~2, score 답.
    var impact: Double
    /// 0~1, noul 답.
    var concrete: Double
    /// 0~1, noul 답.
    var avoiding: Double
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
    /// 최상위 `storage`. 없으면 false.
    var storage: Bool
    /// `settings.day_start`(storage 모드에서만). 없으면 nil(설정 규칙대로 06:00).
    var dayStart: DayStart?
    var events: [SimEvent]
}

extension SimScenario {
    private typealias Object = [(key: String, value: SimJSON)]

    private static let topKeys: Set<String> = ["version", "timezone", "storage", "settings", "events"]
    private static let settingsKeys: Set<String> = ["default_quantum_min", "day_start"]
    private static let noteKeys = ["done_note", "next_note"]
    /// 원본 v1 이벤트의 추가 필드.
    private static let timerEventKeys: [String: [String]] = [
        "enter_title": ["title"], "choose_quantum": ["quantum_min"], "set_default_quantum": ["quantum_min"],
        "start": [], "tick": [], "complete": [],
    ]
    /// storage 모드에서만 받는 이벤트의 추가 필드.
    private static let storageEventKeys: [String: [String]] = [
        "add_task": ["title", "deadline", "recurrence", "weekday", "est_min"], "skip": noteKeys, "switch": noteKeys,
        "quit": [], "relaunch": [], "activate": [],
        "judge": ["task", "urgency", "impact", "concrete", "avoiding"], "key": ["present"],
    ]

    static func decode(_ data: Data) throws(SimError) -> SimScenario {
        let root = try object(SimJSONParser.parse(data), path: "최상위", seq: nil)

        let version = try integer(require(root, "version", path: "version", seq: nil), path: "version", seq: nil)
        guard version == 1 else { throw SimError(kind: .unknownVersion, seq: nil, message: "모르는 version \(version)") }
        try checkKeys(root, allowed: topKeys, path: "최상위", seq: nil)

        let zoneName = try string(require(root, "timezone", path: "timezone", seq: nil), path: "timezone", seq: nil)
        guard let timezone = TimeZone(identifier: zoneName) else {
            throw SimError(kind: .unknownTimezone, seq: nil, message: "모르는 timezone \(SimError.quoted(zoneName))")
        }

        var storage = false
        if let value = field(root, "storage") {
            guard case .bool(let flag) = value else {
                throw SimError(kind: .wrongType, seq: nil, message: "storage는 JSON 불리언이어야 한다")
            }
            storage = flag
        }

        var defaultQuantumMin: Int?
        var dayStart: DayStart?
        if let value = field(root, "settings") {
            let settings = try object(value, path: "settings", seq: nil)
            if !storage, field(settings, "day_start") != nil {
                throw storageOnly("settings.day_start", seq: nil)
            }
            try checkKeys(settings, allowed: settingsKeys, path: "settings", seq: nil)
            if let minutes = field(settings, "default_quantum_min") {
                defaultQuantumMin = try quantum(minutes, path: "settings.default_quantum_min", seq: nil)
            }
            if let value = field(settings, "day_start") {
                let text = try string(value, path: "settings.day_start", seq: nil)
                guard let parsed = DayStart(text: text) else {
                    throw SimError(
                        kind: .invalidDayStart, seq: nil,
                        message: "settings.day_start \(SimError.quoted(text))는 HH:MM(00:00~23:59)이 아니다")
                }
                dayStart = parsed
            }
        }

        guard case .array(let items) = try require(root, "events", path: "events", seq: nil) else {
            throw SimError(kind: .wrongType, seq: nil, message: "events는 배열이어야 한다")
        }
        var events: [SimEvent] = []
        for (offset, item) in items.enumerated() {
            let event = try decodeEvent(item, seq: offset + 1, storage: storage)
            if let previous = events.last, event.epochSeconds < previous.epochSeconds {
                throw SimError(kind: .timeReversed, seq: event.seq, message: "at이 이전 이벤트보다 이르다")
            }
            events.append(event)
        }
        return SimScenario(
            timezone: timezone, defaultQuantumMin: defaultQuantumMin, storage: storage, dayStart: dayStart,
            events: events)
    }

    private static func decodeEvent(_ value: SimJSON, seq: Int, storage: Bool) throws(SimError) -> SimEvent {
        let event = try object(value, path: "events[\(seq - 1)]", seq: seq)
        let atText = try string(require(event, "at", path: "at", seq: seq), path: "at", seq: seq)
        let type = try string(require(event, "type", path: "type", seq: seq), path: "type", seq: seq)

        var extra: [String]
        if let keys = timerEventKeys[type] {
            extra = keys
            if type == "start" || type == "complete" {
                if storage {
                    extra += noteKeys
                } else if let note = noteKeys.first(where: { field(event, $0) != nil }) {
                    throw storageOnly("\(type)의 \(note)", seq: seq)
                }
            }
        } else if let keys = storageEventKeys[type] {
            guard storage else { throw storageOnly("type \(SimError.quoted(type))", seq: seq) }
            extra = keys
        } else {
            throw SimError(kind: .unknownType, seq: seq, message: "모르는 type \(SimError.quoted(type))")
        }
        try checkKeys(event, allowed: Set(["at", "type"] + extra), path: type, seq: seq)

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
        case "start": kind = .start(try optionalNotes(event, seq: seq))
        case "tick": kind = .tick
        case "complete": kind = .complete(try optionalNotes(event, seq: seq))
        case "add_task": kind = .addTask(try newTask(event, seq: seq))
        case "skip": kind = .skip(try notes(event, seq: seq))
        case "switch": kind = .switchTask(try notes(event, seq: seq))
        case "quit": kind = .quit
        case "relaunch": kind = .relaunch
        case "judge": kind = .judge(try judge(event, seq: seq))
        case "key":
            guard case .bool(let present) = try require(event, "present", path: "present", seq: seq) else {
                throw SimError(kind: .wrongType, seq: seq, message: "present는 JSON 불리언이어야 한다")
            }
            kind = .key(present: present)
        default: kind = .activate
        }
        return SimEvent(seq: seq, epochSeconds: epochSeconds, kind: kind)
    }

    private static func storageOnly(_ what: String, seq: Int?) -> SimError {
        SimError(kind: .storageOnly, seq: seq, message: "\(what)는 \"storage\": true일 때만 받는다")
    }

    /// 두 줄. 없는 줄은 빈 줄.
    private static func notes(_ event: Object, seq: Int) throws(SimError) -> CheckpointNotes {
        var lines: [String] = []
        for key in noteKeys {
            if let value = field(event, key) {
                lines.append(try string(value, path: key, seq: seq))
            } else {
                lines.append("")
            }
        }
        return CheckpointNotes(doneNote: lines[0], nextNote: lines[1])
    }

    /// 두 줄 필드가 하나도 없으면 nil.
    private static func optionalNotes(_ event: Object, seq: Int) throws(SimError) -> CheckpointNotes? {
        guard noteKeys.contains(where: { field(event, $0) != nil }) else { return nil }
        return try notes(event, seq: seq)
    }

    /// `add_task`. 값 검증은 data-model §5.6과 같고, 채우기(요일·주기)는 실행 때 `TaskWriteRules.prepareNew`가 한다.
    private static func newTask(_ event: Object, seq: Int) throws(SimError) -> NewTask {
        let title = try string(require(event, "title", path: "title", seq: seq), path: "title", seq: seq)
        guard MokaTask.normalizedTitle(title) != nil else {
            throw SimError(kind: .emptyTitle, seq: seq, message: "앞뒤 공백을 뺀 title이 비어 있다")
        }

        var deadline: LocalDay?
        if let value = field(event, "deadline") {
            let text = try string(value, path: "deadline", seq: seq)
            guard let day = LocalDay(text: text) else {
                throw SimError(
                    kind: .invalidDate, seq: seq, message: "deadline \(SimError.quoted(text))는 있는 날짜의 YYYY-MM-DD가 아니다")
            }
            deadline = day
        }

        var recurrence = Recurrence.none
        if let value = field(event, "recurrence") {
            let text = try string(value, path: "recurrence", seq: seq)
            guard let parsed = Recurrence(rawValue: text) else {
                throw SimError(
                    kind: .outOfRange, seq: seq, message: "recurrence \(SimError.quoted(text))는 none/daily/weekly가 아니다")
            }
            recurrence = parsed
        }
        guard recurrence == .none || deadline == nil else {
            throw SimError(kind: .deadlineOnRecurring, seq: seq, message: "recurrence가 none이 아닌데 deadline이 있다")
        }

        var weekday: Weekday?
        if let value = field(event, "weekday") {
            let number = try integer(value, path: "weekday", seq: seq)
            guard let parsed = Weekday(rawValue: number) else {
                throw SimError(kind: .outOfRange, seq: seq, message: "weekday \(number)이 1...7 밖이다")
            }
            guard recurrence == .weekly else {
                throw SimError(kind: .weekdayNotWeekly, seq: seq, message: "recurrence가 weekly가 아닌데 weekday가 있다")
            }
            weekday = parsed
        }

        var estMin: Int?
        if let value = field(event, "est_min") {
            let minutes = try integer(value, path: "est_min", seq: seq)
            guard MokaTask.isValidEstMin(minutes) else {
                throw SimError(kind: .outOfRange, seq: seq, message: "est_min \(minutes)이 1 이상이 아니다")
            }
            estMin = minutes
        }
        return NewTask(title: title, deadline: deadline, estMin: estMin, recurrence: recurrence, weekday: weekday)
    }

    /// `judge`. 할 일이 있는지, 대기·진행 중인지는 실행 때 본다.
    private static func judge(_ event: Object, seq: Int) throws(SimError) -> SimJudge {
        func answer(_ key: String, upTo top: Double) throws(SimError) -> Double {
            try number(require(event, key, path: key, seq: seq), path: key, range: 0...top, seq: seq)
        }
        let task = try integer(require(event, "task", path: "task", seq: seq), path: "task", seq: seq)
        return SimJudge(
            taskID: TaskID(task), urgency: try answer("urgency", upTo: 3), impact: try answer("impact", upTo: 2),
            concrete: try answer("concrete", upTo: 1), avoiding: try answer("avoiding", upTo: 1))
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

    /// 정수 또는 실수.
    private static func number(_ value: SimJSON, path: String, range: ClosedRange<Double>, seq: Int?)
        throws(SimError) -> Double
    {
        guard case .number(let raw) = value, let number = Double(raw) else {
            throw SimError(kind: .wrongType, seq: seq, message: "\(path)는 JSON 수여야 한다")
        }
        guard range.contains(number) else {
            throw SimError(kind: .outOfRange, seq: seq, message: "\(path) \(raw)이 \(range) 밖이다")
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

        guard (1...12).contains(month), (1...GregorianCivil.daysInMonth(year: year, month: month)).contains(day),
            hour < 24, minute < 60, second < 60
        else { throw invalid() }

        let days = GregorianCivil.daysFromCivil(year: year, month: month, day: day)
        let epochSeconds = days * 86_400 + hour * 3600 + minute * 60 + second - offsetSeconds
        guard epochSeconds >= minEpochSeconds, epochSeconds <= maxEpochSeconds else {
            throw SimError(
                kind: .invalidTimestamp, seq: seq, message: "at \(SimError.quoted(text))의 UTC 연도가 1...9999 밖이다")
        }
        return epochSeconds
    }

    /// 출력 `at`이 4자리 연도를 지키는 범위: UTC 0001-01-01T00:00:00Z ... 9999-12-31T23:59:59Z.
    private static let minEpochSeconds = GregorianCivil.daysFromCivil(year: 1, month: 1, day: 1) * 86_400
    private static let maxEpochSeconds = GregorianCivil.daysFromCivil(year: 10_000, month: 1, day: 1) * 86_400 - 1

    /// UTC `YYYY-MM-DDTHH:MM:SSZ`.
    static func formatUTC(_ epochSeconds: Int) -> String {
        GregorianCivil.formatUTC(epochSeconds)
    }
}
