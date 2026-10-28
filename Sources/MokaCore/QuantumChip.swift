public enum QuantumChip {
    public static let presets = Defaults.quantumPresets

    /// `Int(text)`가 1...180이면 값, 아니면 nil(시작 불가).
    public static func parseCustom(_ text: String) -> Int? {
        guard let minutes = Int(text), Defaults.quantumMinRange.contains(minutes) else { return nil }
        return minutes
    }
}

public enum RemainingFormat {
    /// "M:SS", 분은 0을 채우지 않는다.
    public static func string(_ seconds: Int) -> String {
        let secondsPart = seconds % 60
        return "\(seconds / 60):\(secondsPart < 10 ? "0" : "")\(secondsPart)"
    }
}

public func shouldStayExpanded(pinned: Bool, focused: Bool, hovering: Bool) -> Bool {
    pinned || focused || hovering
}
