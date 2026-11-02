import Foundation

public typealias TaskID = Int64

public enum TaskStatus: String, CaseIterable, Sendable { case todo, active, done, dropped }
public enum Recurrence: String, CaseIterable, Sendable { case none, daily, weekly }

/// 1(일)~7(토). Foundation `Calendar.component(.weekday, from:)`와 같은 번호.
public struct Weekday: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int

    /// 1...7 밖이면 nil.
    public init?(rawValue: Int) {
        guard (1...7).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }
}

public struct MokaTask: Equatable, Sendable {
    public var id: TaskID
    /// 앞뒤 공백을 뺀 값, 비어 있지 않음(R-101).
    public var title: String
    public var deadline: LocalDay?
    /// 1 이상.
    public var estMin: Int?
    public var recurrence: Recurrence
    /// recurrence == .weekly일 때만 값.
    public var weekday: Weekday?
    /// recurrence != .none일 때만 값(data-model §5.3).
    public var cycleDay: LocalDay?
    /// 비어 있지 않거나 nil(R-109).
    public var firstAction: String?
    public var status: TaskStatus
    /// 0 이상.
    public var skipCount: Int
    /// 0 이상, 반복 할 일만 움직임.
    public var streak: Int
    /// 초 단위로 내린 값(data-model §3).
    public var createdAt: Date

    public init(
        id: TaskID, title: String, deadline: LocalDay?, estMin: Int?, recurrence: Recurrence, weekday: Weekday?,
        cycleDay: LocalDay?, firstAction: String?, status: TaskStatus, skipCount: Int, streak: Int, createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.deadline = deadline
        self.estMin = estMin
        self.recurrence = recurrence
        self.weekday = weekday
        self.cycleDay = cycleDay
        self.firstAction = firstAction
        self.status = status
        self.skipCount = skipCount
        self.streak = streak
        self.createdAt = createdAt
    }
}

/// 새 할 일 입력. 저장 전에 data-model §5.8 `TaskWriteRules.prepareNew`를 거친다.
public struct NewTask: Equatable, Sendable {
    public var title: String
    public var deadline: LocalDay?
    public var estMin: Int?
    public var recurrence: Recurrence
    /// .weekly인데 nil이면 prepareNew가 채운다(data-model §5.8).
    public var weekday: Weekday?

    public init(title: String, deadline: LocalDay?, estMin: Int?, recurrence: Recurrence, weekday: Weekday?) {
        self.title = title
        self.deadline = deadline
        self.estMin = estMin
        self.recurrence = recurrence
        self.weekday = weekday
    }
}

/// 설정 창 고침 입력. nil인 칸은 그대로 둔다. 마감·예상 소요를 비우려면 `.clear`.
public struct TaskEdit: Equatable, Sendable {
    public enum Field<Value: Equatable & Sendable>: Equatable, Sendable {
        case keep
        case set(Value)
        case clear
    }

    public var title: String?
    public var deadline: Field<LocalDay>
    public var estMin: Field<Int>
    public var recurrence: Recurrence?
    public var weekday: Weekday?

    public init(
        title: String? = nil, deadline: Field<LocalDay> = .keep, estMin: Field<Int> = .keep,
        recurrence: Recurrence? = nil, weekday: Weekday? = nil
    ) {
        self.title = title
        self.deadline = deadline
        self.estMin = estMin
        self.recurrence = recurrence
        self.weekday = weekday
    }
}

// MARK: - 값 검증(data-model §5.6)

extension MokaTask {
    /// 앞뒤 공백을 뺀 제목. 비면 nil(저장 안 함).
    public static func normalizedTitle(_ raw: String) -> String? {
        nonBlank(raw)
    }

    /// nil 또는 1 이상.
    public static func isValidEstMin(_ minutes: Int?) -> Bool {
        minutes.map { $0 >= 1 } ?? true
    }

    /// `.weekly`면 요일이 있어야 하고, 아니면 nil이어야 한다.
    public static func isValidWeekday(_ weekday: Weekday?, recurrence: Recurrence) -> Bool {
        (recurrence == .weekly) == (weekday != nil)
    }
}

/// 앞뒤 공백을 뺀 값. 비면 nil.
func nonBlank(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
