import Foundation

/// 판단 API 키 보관함(spec R-214). AppState(MainActor)에서만 부른다. 앱 구현은 Keychain이다.
public protocol KeyStore: AnyObject {
    func hasKey() throws -> Bool
    func read() throws -> String?
    /// 같은 항목이 있으면 덮어쓴다.
    func save(_ key: String) throws
    func delete() throws
}

/// 시험용 메모리 보관함. `failing`에 넣은 동작은 `Failure`를 던지고 아무것도 바꾸지 않는다.
public final class InMemoryKeyStore: KeyStore {
    public enum Operation: Hashable, Sendable { case hasKey, read, save, delete }
    public struct Failure: Error, Equatable, Sendable {
        public init() {}
    }

    public var failing: Set<Operation> = []
    private var key: String?

    public init(key: String? = nil) {
        self.key = key
    }

    public func hasKey() throws -> Bool {
        try check(.hasKey)
        return key != nil
    }

    public func read() throws -> String? {
        try check(.read)
        return key
    }

    public func save(_ key: String) throws {
        try check(.save)
        self.key = key
    }

    public func delete() throws {
        try check(.delete)
        key = nil
    }

    private func check(_ operation: Operation) throws {
        if failing.contains(operation) { throw Failure() }
    }
}
