import Foundation

public struct Draft: Equatable, Sendable {
    public var title: String
    public var chipMin: Int

    public init(title: String, chipMin: Int) {
        self.title = title
        self.chipMin = chipMin
    }
}

public enum NotchTimer: Equatable, Sendable {
    case empty(draft: Draft?)
    case running(title: String, quantumMin: Int, startedAt: Date, endsAt: Date)
    case expired(title: String, chipMin: Int)
}

public enum TimerEvent: Equatable, Sendable {
    case enterTitle(String)
    case chooseQuantum(Int)
    case start
    case tick
    case complete
}

public enum RejectReason: Equatable, Sendable {
    case notAllowedInPhase
    case emptyTitle
    case quantumOutOfRange
}

public enum TransitionResult: Equatable, Sendable {
    case applied
    case rejected(RejectReason)
}

extension NotchTimer {
    /// 처리 전에 암묵 tick(끝 시각이 지난 running → expired)을 먼저 적용한다. 이벤트가 rejected여도 그 결과는 남는다.
    public mutating func apply(_ event: TimerEvent, at now: Date, defaultQuantumMin: Int) -> TransitionResult {
        if case .running(let title, _, _, let endsAt) = self, now >= endsAt {
            self = .expired(title: title, chipMin: defaultQuantumMin)
        }

        switch (self, event) {
        case (_, .tick):
            return .applied

        case (.empty(let draft), .enterTitle(let text)):
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return .rejected(.emptyTitle) }
            self = .empty(draft: Draft(title: title, chipMin: draft?.chipMin ?? defaultQuantumMin))
            return .applied

        case (.empty(.some(var draft)), .chooseQuantum(let minutes)):
            guard Defaults.quantumMinRange.contains(minutes) else { return .rejected(.quantumOutOfRange) }
            draft.chipMin = minutes
            self = .empty(draft: draft)
            return .applied

        case (.expired(let title, _), .chooseQuantum(let minutes)):
            guard Defaults.quantumMinRange.contains(minutes) else { return .rejected(.quantumOutOfRange) }
            self = .expired(title: title, chipMin: minutes)
            return .applied

        case (.empty(.some(let draft)), .start):
            self = .started(title: draft.title, quantumMin: draft.chipMin, at: now)
            return .applied

        case (.expired(let title, let chipMin), .start):
            self = .started(title: title, quantumMin: chipMin, at: now)
            return .applied

        case (.running, .complete), (.expired, .complete):
            self = .empty(draft: nil)
            return .applied

        default:
            return .rejected(.notAllowedInPhase)
        }
    }

    public func remainingSeconds(at now: Date) -> Int? {
        switch self {
        case .empty:
            return nil
        case .running(_, let quantumMin, _, let endsAt):
            let untilEnd = Int(endsAt.timeIntervalSince(now).rounded(.up))
            return min(untilEnd, quantumMin * 60)
        case .expired:
            return 0
        }
    }

    public func invariantViolation(at now: Date) -> String? {
        switch self {
        case .empty(nil):
            return nil
        case .empty(.some(let draft)):
            return Self.titleViolation(draft.title) ?? Self.minutesViolation("chipMin", draft.chipMin)
        case .running(let title, let quantumMin, let startedAt, let endsAt):
            if endsAt <= startedAt { return "endsAt가 startedAt보다 늦지 않다" }
            if now >= endsAt { return "끝 시각이 지났는데 running이다(남은 초 1 미만)" }
            return Self.titleViolation(title) ?? Self.minutesViolation("quantumMin", quantumMin)
        case .expired(let title, let chipMin):
            return Self.titleViolation(title) ?? Self.minutesViolation("chipMin", chipMin)
        }
    }

    private static func started(title: String, quantumMin: Int, at now: Date) -> NotchTimer {
        .running(
            title: title, quantumMin: quantumMin, startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(quantumMin * 60)))
    }

    private static func titleViolation(_ title: String) -> String? {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "제목이 비어 있다" : nil
    }

    private static func minutesViolation(_ name: String, _ minutes: Int) -> String? {
        Defaults.quantumMinRange.contains(minutes) ? nil : "\(name) \(minutes)이 1...180 밖이다"
    }
}
