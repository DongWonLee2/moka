import Foundation

public struct Draft: Equatable, Sendable {
    public var title: String
    public var chipMin: Int
    /// 사용자가 칩을 직접 골랐는지. false면 기본값으로 채운 칩이라 기본값 변경을 따른다(R-013).
    public var chipPicked: Bool

    public init(title: String, chipMin: Int, chipPicked: Bool = false) {
        self.title = title
        self.chipMin = chipMin
        self.chipPicked = chipPicked
    }
}

public enum NotchTimer: Equatable, Sendable {
    case empty(draft: Draft?)
    case running(title: String, quantumMin: Int, startedAt: Date, endsAt: Date)
    case expired(title: String, chipMin: Int, chipPicked: Bool = false)
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
            self = .empty(
                draft: Draft(
                    title: title, chipMin: draft?.chipMin ?? defaultQuantumMin, chipPicked: draft?.chipPicked ?? false))
            return .applied

        case (.empty(.some(var draft)), .chooseQuantum(let minutes)):
            guard Defaults.quantumMinRange.contains(minutes) else { return .rejected(.quantumOutOfRange) }
            draft.chipMin = minutes
            draft.chipPicked = true
            self = .empty(draft: draft)
            return .applied

        case (.expired(let title, _, _), .chooseQuantum(let minutes)):
            guard Defaults.quantumMinRange.contains(minutes) else { return .rejected(.quantumOutOfRange) }
            self = .expired(title: title, chipMin: minutes, chipPicked: true)
            return .applied

        case (.empty(.some(let draft)), .start):
            self = .started(title: draft.title, quantumMin: draft.chipMin, at: now)
            return .applied

        case (.expired(let title, let chipMin, _), .start):
            self = .started(title: title, quantumMin: chipMin, at: now)
            return .applied

        case (.running, .complete), (.expired, .complete):
            self = .empty(draft: nil)
            return .applied

        default:
            return .rejected(.notAllowedInPhase)
        }
    }

    /// 기본값이 바뀌었다(R-013). 타이머 이벤트가 아니라 거부되지 않는다. 칩을 직접 고르지 않았고 직접 입력 중이
    /// 아닌 초안·시간 끝의 칩만 새 기본값으로 바꾼다. 도는 타이머와 빈 상태는 그대로다.
    public mutating func applyDefaultQuantumChange(_ defaultQuantumMin: Int, isEditingCustom: Bool) {
        guard !isEditingCustom else { return }
        switch self {
        case .empty(.some(var draft)) where !draft.chipPicked:
            draft.chipMin = defaultQuantumMin
            self = .empty(draft: draft)
        case .expired(let title, _, false):
            self = .expired(title: title, chipMin: defaultQuantumMin)
        case .empty, .running, .expired:
            return
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
        case .expired(let title, let chipMin, _):
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
