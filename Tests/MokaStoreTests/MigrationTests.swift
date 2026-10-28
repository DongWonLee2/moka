import Foundation
import GRDB
import MokaStore
import Testing

@Test("ADR-0004 FR-16: 등록된 마이그레이션 이름은 고정 목록과 같다(덧붙이기만 허용)")
func migrationNamesAreFixed() {
    #expect(MokaMigrations.migrator.migrations == ["v1_settings"])
}

@Test("ADR-0004 FR-16: 마이그레이션 뒤 스키마가 schema/moka-schema.sql 스냅샷과 같다")
func schemaMatchesSnapshot() throws {
    let db = try TestDatabase.migratedInMemory()
    let actual = try MokaDatabase.schemaSQL(db)
    let snapshotURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("schema/moka-schema.sql")
    let expected = try? String(contentsOf: snapshotURL, encoding: .utf8)
    if actual != expected {
        Issue.record("스키마 스냅샷이 다르다. 아래 텍스트를 schema/moka-schema.sql로 옮긴다:\n\(actual)")
    }
}

@Test("ADR-0004: 시험 DB 경로는 메모리이거나 임시 디렉터리 아래이고 앱 DB 경로가 아니다")
func testDatabasePathsAreSafe() throws {
    let memory = try TestDatabase.migratedInMemory()
    #expect(memory.path == ":memory:")

    let url = TestDatabase.freshFileURL()
    defer { TestDatabase.removeTestFolder(of: url) }
    let file = try TestDatabase.open(at: url)
    #expect(TestDatabase.isSafe(file.path))
    #expect(!file.path.contains("dev.dongwon.moka"))

    let appLike = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/dev.dongwon.moka/moka.sqlite")
    #expect(!TestDatabase.isSafe(appLike.path))
    #expect(throws: TestDatabase.UnsafePath.self) { try TestDatabase.open(at: appLike) }
    let tempButNamed = FileManager.default.temporaryDirectory
        .appendingPathComponent("dev.dongwon.moka/moka.sqlite")
    #expect(!TestDatabase.isSafe(tempButNamed.path))
}
