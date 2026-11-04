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

    /// 설정 창 기본 작업 시간 칸에 제출한 글자. `QuantumChip.parseCustom`이 받으면 저장하고, 아니면 저장하지 않는다.
    public static func commitField(_ text: String, to store: some SettingsStore) -> FieldCommit {
        FieldCommit.commit(text, read: { readDefault(from: store) }, write: { try writeDefault($0, to: store) })
    }

    /// 스테퍼가 고른 값을 저장한다. 실패해도 던지지 않고 칸에는 저장된 값을 보인다.
    public static func saveField(_ minutes: Int, to store: some SettingsStore) -> FieldCommit {
        FieldCommit.save(minutes, read: { readDefault(from: store) }, write: { try writeDefault($0, to: store) })
    }
}

/// 설정 창 분 칸을 제출한 결과(#35).
public struct FieldCommit: Sendable {
    /// 칸에 다시 보일 글자. 언제나 저장된 값이다.
    public let shown: String
    /// 저장을 시도했는가. 시도했으면 앱은 펼친 판의 고르지 않은 칩을 새 기본값에 맞춘다(R-013).
    public let attempted: Bool
    /// 저장 실패 이유. 앱이 기록한다.
    public let error: (any Error)?

    static func commit(_ text: String, read: () -> Int, write: (Int) throws -> Void) -> FieldCommit {
        guard let minutes = QuantumChip.parseCustom(text) else {
            return FieldCommit(shown: String(read()), attempted: false, error: nil)
        }
        return save(minutes, read: read, write: write)
    }

    static func save(_ minutes: Int, read: () -> Int, write: (Int) throws -> Void) -> FieldCommit {
        var failure: (any Error)?
        do {
            try write(minutes)
        } catch {
            failure = error
        }
        return FieldCommit(shown: String(read()), attempted: true, error: failure)
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
