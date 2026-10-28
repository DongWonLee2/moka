import GRDB

/// 배포한 마이그레이션은 고치지 않고 덧붙이기만 한다. `eraseDatabaseOnSchemaChange`는 켜지 않는다(ADR-0004).
public enum MokaMigrations {
    public static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_settings") { db in
            try db.execute(sql: "CREATE TABLE settings(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)")
        }
        return migrator
    }()
}
