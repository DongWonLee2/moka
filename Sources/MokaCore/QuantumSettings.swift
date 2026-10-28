public protocol SettingsStore {
    func value(for key: String) throws -> String?
    func setValue(_ value: String, for key: String) throws
}

public enum QuantumSettingsError: Error, Equatable {
    case outOfRange
}

public enum QuantumSettings {
    public static let key = "default_quantum_min"

    /// 없거나 읽기 실패·정수 아님·범위 밖이면 25.
    public static func readDefault(from store: some SettingsStore) -> Int {
        guard let text = try? store.value(for: key),
            let minutes = Int(text),
            Defaults.quantumMinRange.contains(minutes)
        else { return Defaults.quantumMin }
        return minutes
    }

    public static func writeDefault(_ minutes: Int, to store: some SettingsStore) throws {
        guard Defaults.quantumMinRange.contains(minutes) else { throw QuantumSettingsError.outOfRange }
        try store.setValue(String(minutes), for: key)
    }
}

public final class InMemorySettingsStore: SettingsStore {
    private var values: [String: String] = [:]

    public init() {}

    public func value(for key: String) throws -> String? {
        values[key]
    }

    public func setValue(_ value: String, for key: String) throws {
        values[key] = value
    }
}
