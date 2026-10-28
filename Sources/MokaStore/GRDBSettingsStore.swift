import GRDB
import MokaCore

public final class GRDBSettingsStore: SettingsStore {
    private let db: DatabaseQueue

    public init(_ db: DatabaseQueue) {
        self.db = db
    }

    public func value(for key: String) throws -> String? {
        try db.read { try String.fetchOne($0, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key]) }
    }

    public func setValue(_ value: String, for key: String) throws {
        try db.write {
            try $0.execute(
                sql: """
                    INSERT INTO settings(key, value) VALUES (?, ?) \
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [key, value])
        }
    }
}
