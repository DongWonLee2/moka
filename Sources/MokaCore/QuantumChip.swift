/// 직접 입력을 받지 않는 이유(R-004). 화면 문구는 앱이 정한다.
public enum CustomQuantumIssue: Equatable, Sendable {
    /// 180분을 넘는다(자릿수가 너무 커 `Int`로 못 읽는 숫자도 포함).
    case aboveMax
    /// 1분보다 작다.
    case belowMin
    /// 정수로 읽을 수 없다(숫자 아님, 소수, 앞뒤 공백).
    case notInteger
}

public enum QuantumChip {
    public static let presets = Defaults.quantumPresets

    /// `Int(text)`가 1...180이면 값, 아니면 nil(시작 불가).
    public static func parseCustom(_ text: String) -> Int? {
        guard let minutes = Int(text), Defaults.quantumMinRange.contains(minutes) else { return nil }
        return minutes
    }

    /// 직접 입력을 받지 않는 이유. 받는 값과 빈칸은 nil(빈칸은 시작만 막고 이유는 보이지 않는다).
    /// nil이 아닌 값이 나오는 입력은 `parseCustom`도 nil이다.
    public static func customIssue(_ text: String) -> CustomQuantumIssue? {
        guard !text.isEmpty else { return nil }
        guard let value = Int(text) else {
            let digitsOnly = text.allSatisfy { $0.isASCII && $0.isNumber }
            return digitsOnly ? .aboveMax : .notInteger
        }
        if value > Defaults.quantumMinRange.upperBound { return .aboveMax }
        if value < Defaults.quantumMinRange.lowerBound { return .belowMin }
        return nil
    }

    /// 시작할 수 있는가. `customText`가 nil이면 직접 입력을 쓰지 않아 칩 값으로 시작한다(R-003),
    /// 직접 입력 중이면 `parseCustom`이 값을 낼 때만(R-004).
    public static func startAllowed(customText: String?) -> Bool {
        guard let customText else { return true }
        return parseCustom(customText) != nil
    }
}

public enum RemainingFormat {
    /// 60분 미만은 "M:SS", 이상은 "H:MM:SS". 맨 앞 자리는 0을 채우지 않는다. 음수는 0으로 자른다.
    public static func string(_ seconds: Int) -> String {
        let clamped = max(seconds, 0)
        let hours = clamped / 3600
        let minutes = clamped / 60 % 60
        let secs = clamped % 60
        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(secs))"
        }
        return "\(minutes):\(twoDigits(secs))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

public func shouldStayExpanded(pinned: Bool, focused: Bool, hovering: Bool) -> Bool {
    pinned || focused || hovering
}

/// 이벤트를 적용한 뒤의 시간 끝 고정 여부(R-009). `running`에서 `expired`로 바뀌면 고정하고,
/// 시작·완료가 적용되면 푼다. 그 밖에는 이전 값을 그대로 둔다.
public func pinnedOpenAfter(
    _ event: TimerEvent, result: TransitionResult, from before: NotchTimer, to after: NotchTimer, wasPinned: Bool
) -> Bool {
    if result == .applied, event == .start || event == .complete {
        return false
    }
    if case .running = before, case .expired = after {
        return true
    }
    return wasPinned
}
