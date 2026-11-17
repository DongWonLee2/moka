import GRDB
import MokaCore

/// 이월 판정 시각 키는 `GRDBTaskRepository`만 다루므로 거부한다(spec 005 data-model §9).
public final class GRDBSettingsStore: SettingsStore {
    private let db: DatabaseQueue

    public init(_ db: DatabaseQueue) {
        self.db = db
    }

    public func value(for key: String) throws -> String? {
        guard key != CarryJudgmentStorage.settingsKey else { throw StoreError.invalidValue(column: "key") }
        return try db.read { try String.fetchOne($0, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key]) }
    }

    public func setValue(_ value: String, for key: String) throws {
        guard key != CarryJudgmentStorage.settingsKey else { throw StoreError.invalidValue(column: "key") }
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
