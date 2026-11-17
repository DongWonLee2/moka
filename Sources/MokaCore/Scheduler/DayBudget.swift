import Foundation

/// 오늘의 가용 시간 기록(spec 005 data-model §11). 설정 키 `day_budget`의 JSON이다.
public struct DayBudget: Decodable, Equatable, Sendable {
    public var day: LocalDay
    /// 가용 시간(분). 처음 답 + 늘린 분.
    public var minutes: Int
    /// 시작 전 화면에서 늘린 분의 합.
    public var extendedMinutes: Int
    /// 쓴 시간(초). 시작 때 고른 분을 더하고 일찍 끝나면 남은 초를 돌려준 값이다(Q4-B).
    public var usedSeconds: Int
    /// "더 할래요"를 누름. 참이면 그날 상한이 없다.
    public var more: Bool

    public init(day: LocalDay, minutes: Int, extendedMinutes: Int, usedSeconds: Int, more: Bool) {
        self.day = day
        self.minutes = minutes
        self.extendedMinutes = extendedMinutes
        self.usedSeconds = usedSeconds
        self.more = more
    }

    /// 가용 시간 답(선택지나 직접 적기).
    public static func answered(day: LocalDay, minutes: Int) -> DayBudget {
        DayBudget(day: day, minutes: minutes, extendedMinutes: 0, usedSeconds: 0, more: false)
    }

    /// 선택지 다섯의 분.
    public static let choiceMinutes = Defaults.availableHoursChoices.map { $0 * 60 }

    /// `day`의 기록. 다른 하루의 기록은 없는 것으로 본다(지우지는 않는다).
    public static func record(_ stored: DayBudget?, for day: LocalDay) -> DayBudget? {
        stored?.day == day ? stored : nil
    }

    /// 상한이 걸렸으면 남은 분, 기록이 없거나 "더 할래요" 뒤면 nil.
    public static func capMinutes(_ record: DayBudget?) -> Int? {
        guard let record, !record.more else { return nil }
        return record.remainingMinutes
    }

    /// 끝 시각 전에 끝낸 작업 시간이 돌려줄 초. 0 이상, 초 아래는 버린다.
    public static func refundSeconds(endsAt: Date, now: Date) -> Int {
        max(0, Int(endsAt.timeIntervalSince(now).rounded(.down)))
    }

    public var remainingSeconds: Int { minutes * 60 - usedSeconds }

    public var remainingMinutes: Int { max(0, remainingSeconds) / 60 }

    /// 그 하루의 기록이면 쓴 시간을 바꾸고, 다른 하루면 그대로 둔다.
    public func applying(_ use: BudgetUse) -> DayBudget {
        guard use.day == day else { return self }
        var next = self
        next.usedSeconds = max(0, usedSeconds + use.seconds)
        return next
    }

    /// 시작 전 화면의 늘리기(R-421). 가용 시간과 늘린 분을 함께 늘린다.
    public func extended(by extra: Int) -> DayBudget {
        var next = self
        next.minutes += extra
        next.extendedMinutes += extra
        return next
    }

    /// "더 할래요"(R-422). 그날 상한을 푼다.
    public func withMore() -> DayBudget {
        var next = self
        next.more = true
        return next
    }

    /// 키 순서를 고정한 JSON 글자(키 이름 순).
    public var json: String {
        #"{"day":"\#(day.text)","extended_min":\#(extendedMinutes),"minutes":\#(minutes),"more":\#(more),"#
            + #""used_s":\#(usedSeconds)}"#
    }

    /// 형식이 틀리면 nil.
    public init?(json: String) {
        guard let value = try? JSONDecoder().decode(DayBudget.self, from: Data(json.utf8)) else { return nil }
        self = value
    }

    private enum CodingKeys: String, CodingKey {
        case day
        case extendedMinutes = "extended_min"
        case minutes
        case more
        case usedSeconds = "used_s"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .day)
        guard let day = LocalDay(text: text) else {
            throw DecodingError.dataCorruptedError(forKey: .day, in: container, debugDescription: "YYYY-MM-DD가 아니다")
        }
        self.init(
            day: day, minutes: try container.decode(Int.self, forKey: .minutes),
            extendedMinutes: try container.decode(Int.self, forKey: .extendedMinutes),
            usedSeconds: try container.decode(Int.self, forKey: .usedSeconds),
            more: try container.decode(Bool.self, forKey: .more))
    }
}

/// 쓴 시간 바꿈. 작업 시간의 하루(`RunInfo.budgetDay`) 기록에 더한다. 음수면 돌려준다.
public struct BudgetUse: Equatable, Sendable {
    public var day: LocalDay
    public var seconds: Int

    public init(day: LocalDay, seconds: Int) {
        self.day = day
        self.seconds = seconds
    }
}

/// 가용 시간 직접 적기를 받지 않는 이유(R-419). `empty`는 문구 없이 답만 막는다.
public enum BudgetInputIssue: Equatable, Sendable, Error {
    case empty
    case notNumber
    case notHalfHour
    case belowMin
    case aboveMax

    public var message: String? {
        switch self {
        case .empty: nil
        case .notNumber: "시간은 숫자로 적어 주세요. 예: 1.5"
        case .notHalfHour: "30분 단위로 적어 주세요. 예: 2 또는 2.5"
        case .belowMin: "30분(0.5)부터 정할 수 있어요"
        case .aboveMax: "16시간까지 정할 수 있어요"
        }
    }
}

public enum BudgetInput {
    /// 받지 않는 이유. 받는 값이면 nil.
    public static func issue(_ text: String) -> BudgetInputIssue? {
        if case .failure(let issue) = parse(text) { return issue }
        return nil
    }

    /// 시간 단위 글자를 분으로. 앞뒤 공백은 빼고, 쉼표 소수점은 받지 않는다.
    public static func parse(_ text: String) -> Result<Int, BudgetInputIssue> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
            let hours = Double(trimmed)
        else { return .failure(.notNumber) }
        let steps = hours * 60 / Double(Defaults.customBudgetStepMinutes)
        guard steps == steps.rounded() else { return .failure(.notHalfHour) }
        let minutes = hours * 60
        if minutes < Double(Defaults.customBudgetMinutesRange.lowerBound) { return .failure(.belowMin) }
        if minutes > Double(Defaults.customBudgetMinutesRange.upperBound) { return .failure(.aboveMax) }
        return .success(Int(minutes))
    }
}
