import Foundation
import GRDB
import MokaCore
import MokaStore
import Testing

@Test("ADR-0004 FR-16: 등록된 마이그레이션 이름은 고정 목록과 같다(덧붙이기만 허용)")
func migrationNamesAreFixed() {
    #expect(
        MokaMigrations.migrator.migrations == [
            "v1_settings", "v2_tasks_contexts_checkpoints_log", "v3_scores", "v4_tasks_carry",
        ])
}

@Test("ADR-0004 FR-08 R-412 R-416: v4_tasks_carry 뒤 tasks 표 끝에 carry_count·due_decision이 기본값 0으로 붙는다")
func tasksCarryColumns() throws {
    let db = try TestDatabase.migratedInMemory()
    let columns = try db.read { db in
        try Row.fetchAll(db, sql: "PRAGMA table_info(tasks)").map {
            ($0["name"] as String, $0["dflt_value"] as String?)
        }
    }
    #expect(columns.suffix(2).map(\.0) == ["carry_count", "due_decision"])
    #expect(columns.suffix(2).map(\.1) == ["0", "0"])
}

@Test("ADR-0004 FR-08 R-412 R-416: v3까지 마이그레이션한 DB의 할 일은 v4를 돌린 뒤 이월 횟수 0, 이월 답 대기 거짓으로 읽힌다")
func upgradeFromV3KeepsTasksWithCarryDefaults() throws {
    let db = try TestDatabase.migratedInMemory(upTo: "v3_scores")
    try db.write { db in
        try db.execute(
            sql: """
                INSERT INTO tasks(title, deadline, est_min, recurrence, weekday, cycle_day, first_action, status, \
                skip_count, streak, created_at) VALUES ('가짜 할 일 A', '2026-11-30', 30, 'none', NULL, NULL, \
                '가짜 첫 행동', 'todo', 2, 0, '2026-10-26T07:33:20Z')
                """)
    }
    try MokaMigrations.migrator.migrate(db)

    let stored = try db.read { db in
        try Row.fetchOne(db, sql: "SELECT carry_count, due_decision FROM tasks").map {
            [$0["carry_count"] as Int, $0["due_decision"] as Int]
        }
    }
    #expect(stored == [0, 0])
    let task = try #require(try GRDBTaskRepository(db).tasks().first)
    #expect(task.title == "가짜 할 일 A")
    #expect(task.skipCount == 2)
    #expect(task.firstAction == "가짜 첫 행동")
    #expect(task.carryCount == 0)
    #expect(task.dueDecision == false)
}

@Test("ADR-0004 FR-04 R-205: v3_scores 뒤 scores 표의 열은 data-model §2 순서와 같다")
func scoresTableColumns() throws {
    let db = try TestDatabase.migratedInMemory()
    let columns = try db.read { db in
        try Row.fetchAll(db, sql: "PRAGMA table_info(scores)").map { $0["name"] as String }
    }
    #expect(
        columns == [
            "task_id", "question_version", "provider", "model_snapshot", "urgency", "impact", "concrete", "avoiding",
            "probs_json", "state_hash", "scored_at",
        ])
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
    // 가드가 깨졌을 때 앱 경로를 실제로 열지 않도록 open(at:)에는 넘기지 않는다.
    #expect(!TestDatabase.isSafe(appLike.path))
    // 임시 디렉터리 아래라 가드가 깨져도 임시 폴더만 생긴다. open(at:)의 거부까지 확인한다.
    let tempButNamed = FileManager.default.temporaryDirectory
        .appendingPathComponent("moka-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("dev.dongwon.moka", isDirectory: true)
        .appendingPathComponent("moka.sqlite")
    defer { TestDatabase.removeTestFolder(of: tempButNamed) }
    #expect(!TestDatabase.isSafe(tempButNamed.path))
    #expect(throws: TestDatabase.UnsafePath.self) { try TestDatabase.open(at: tempButNamed) }
}
