import Foundation
import GRDB

public enum MokaDatabase {
    /// 테스트와 `moka-sim`이 쓰는 메모리 DB. 실제 앱 DB 경로는 여기서 열지 않는다(ADR-0004).
    public static func inMemory() throws -> DatabaseQueue {
        try DatabaseQueue()
    }

    public static func healthCheck(_ db: DatabaseQueue) throws -> Bool {
        try db.read { try Int.fetchOne($0, sql: "SELECT 1") } == 1
    }

    /// 받은 경로를 그대로 연다. 상위 폴더가 없으면 만들고, 마이그레이션을 끝까지 돌린다.
    public static func open(at url: URL) throws -> DatabaseQueue {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: url.path)
        try MokaMigrations.migrator.migrate(db)
        return db
    }

    /// `schema/moka-schema.sql`과 비교하는 스키마 텍스트. 각 문장 뒤에 `;\n`(spec 001 data-model §4).
    public static func schemaSQL(_ db: DatabaseQueue) throws -> String {
        let statements = try db.read {
            try String.fetchAll(
                $0,
                sql: """
                    SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' \
                    AND name <> 'grdb_migrations' ORDER BY name
                    """)
        }
        return statements.map { $0 + ";\n" }.joined()
    }
}
