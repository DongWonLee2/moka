public enum QuantumChip {
    public static let presets = Defaults.quantumPresets

    /// `Int(text)`가 1...180이면 값, 아니면 nil(시작 불가).
    public static func parseCustom(_ text: String) -> Int? {
        guard let minutes = Int(text), Defaults.quantumMinRange.contains(minutes) else { return nil }
        return minutes
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
