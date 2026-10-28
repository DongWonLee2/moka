public enum QuantumChip {
    public static let presets = Defaults.quantumPresets

    /// `Int(text)`가 1...180이면 값, 아니면 nil(시작 불가).
    public static func parseCustom(_ text: String) -> Int? {
        guard let minutes = Int(text), Defaults.quantumMinRange.contains(minutes) else { return nil }
        return minutes
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
