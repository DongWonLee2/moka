import Foundation
import GRDB
import MokaCore
import MokaStore
import Testing

/// GRDB 전용 시험: data-model §7의 CHECK·외래 키를 원시 SQL로 직접 시험한다.
/// 리눅스 CI(`swift:6.3.3-noble`의 libsqlite3)에서도 돌아 `trigger` 열 이름과 CHECK 기대값을 확인한다(plan 위험 6).

private let createdAt = "2026-10-26T07:33:20Z"

/// 원시 SQL 한 줄과 SQLite가 받아야 하는지.
struct RawRow: Sendable, CustomTestStringConvertible {
    let label: String
    let sql: String
    let allowed: Bool

    var testDescription: String { "\(allowed ? "허용" : "거부"): \(label)" }
}

private func taskRow(
    _ label: String, recurrence: String = "'none'", weekday: String = "NULL", cycleDay: String = "NULL",
    status: String = "'todo'", allowed: Bool
) -> RawRow {
    RawRow(
        label: label,
        sql: """
            INSERT INTO tasks(title, deadline, est_min, recurrence, weekday, cycle_day, first_action, status, \
            skip_count, streak, created_at) VALUES ('가짜 할 일', NULL, NULL, \(recurrence), \(weekday), \
            \(cycleDay), NULL, \(status), 0, 0, '\(createdAt)')
            """,
        allowed: allowed)
}

private let taskRows: [RawRow] = [
    taskRow("반복 없음", allowed: true),
    taskRow("매일 + cycle_day", recurrence: "'daily'", cycleDay: "'2026-10-26'", allowed: true),
    taskRow("매주 1 + cycle_day", recurrence: "'weekly'", weekday: "1", cycleDay: "'2026-10-25'", allowed: true),
    taskRow("매주 7 + cycle_day", recurrence: "'weekly'", weekday: "7", cycleDay: "'2026-10-24'", allowed: true),
    taskRow("모르는 recurrence", recurrence: "'monthly'", allowed: false),
    taskRow("status active", status: "'active'", allowed: true),
    taskRow("status done", status: "'done'", allowed: true),
    taskRow("status dropped", status: "'dropped'", allowed: true),
    taskRow("모르는 status", status: "'archived'", allowed: false),
    taskRow("매주 weekday 0", recurrence: "'weekly'", weekday: "0", cycleDay: "'2026-10-26'", allowed: false),
    taskRow("매주 weekday 8", recurrence: "'weekly'", weekday: "8", cycleDay: "'2026-10-26'", allowed: false),
    taskRow("매주인데 weekday 없음", recurrence: "'weekly'", cycleDay: "'2026-10-26'", allowed: false),
    taskRow("매일인데 weekday 있음", recurrence: "'daily'", weekday: "2", cycleDay: "'2026-10-26'", allowed: false),
    taskRow("반복 없음인데 weekday 있음", weekday: "2", allowed: false),
    taskRow("매일인데 cycle_day 없음", recurrence: "'daily'", allowed: false),
    taskRow("매주인데 cycle_day 없음", recurrence: "'weekly'", weekday: "3", allowed: false),
    taskRow("반복 없음인데 cycle_day 있음", cycleDay: "'2026-10-26'", allowed: false),
]

private let contextRows: [RawRow] = ["normal", "high", "critical", "low"].map { impact in
    RawRow(
        label: "impact \(impact)",
        sql: "INSERT INTO contexts(name, date, impact) VALUES ('가짜 일정', '2026-11-20', '\(impact)')",
        allowed: impact != "low")
}

private let checkpointRows: [RawRow] =
    ["quantum", "switch", "skip", "urgent", "pause", "quit", "sleep", "day_end", "nap"].map { trigger in
        RawRow(
            label: "trigger \(trigger)",
            sql: """
                INSERT INTO checkpoints(task_id, done_note, next_note, trigger, elapsed_min, created_at) \
                VALUES (1, '', '', '\(trigger)', 0, '\(createdAt)')
                """,
            allowed: trigger != "nap")
    }

private func decisionRow(
    _ label: String, provider: String = "NULL", questionVersion: String = "NULL", probs: String = "NULL",
    stateHash: String = "NULL", snapshot: String = "NULL", allowed: Bool
) -> RawRow {
    RawRow(
        label: label,
        sql: """
            INSERT INTO decisions_log(task_id, question_version, provider, probs_json, state_hash, model_snapshot, \
            scheduler_choice, user_action, created_at) VALUES (1, \(questionVersion), \(provider), \(probs), \
            \(stateHash), \(snapshot), 'rotate_by_id_v0', 'done', '\(createdAt)')
            """,
        allowed: allowed)
}

private let decisionRows: [RawRow] = [
    decisionRow("판단 칸 모두 NULL", allowed: true),
    decisionRow("공급자만 있는 폴백 줄", provider: "'fallback'", allowed: true),
    decisionRow(
        "판단 칸 모두 값", provider: "'fake'", questionVersion: "'v0'", probs: "'{}'", stateHash: "'h'",
        snapshot: "'fake-model'", allowed: true),
    decisionRow("공급자 없이 question_version", questionVersion: "'v0'", allowed: false),
    decisionRow("공급자 없이 probs_json", probs: "'{}'", allowed: false),
    decisionRow("공급자 없이 state_hash", stateHash: "'h'", allowed: false),
    decisionRow("공급자 없이 model_snapshot", snapshot: "'fake-model'", allowed: false),
]

private let insertParentTask = taskRow("부모 할 일", allowed: true).sql

private let carryRows: [RawRow] = [
    ("carry_count 0", "0", "0", true), ("carry_count 3", "3", "0", true), ("carry_count -1", "-1", "0", false),
    ("due_decision 1", "0", "1", true), ("due_decision 2", "0", "2", false), ("due_decision -1", "0", "-1", false),
].map { label, count, due, allowed in
    RawRow(
        label: label, sql: "UPDATE tasks SET carry_count = \(count), due_decision = \(due) WHERE id = 1",
        allowed: allowed)
}

private func expectRow(_ row: RawRow) throws {
    let db = try TestDatabase.migratedInMemory()
    try db.write { try $0.execute(sql: insertParentTask) }
    if row.allowed {
        try db.write { try $0.execute(sql: row.sql) }
    } else {
        let error = #expect(throws: DatabaseError.self) { try db.write { try $0.execute(sql: row.sql) } }
        #expect(error?.extendedResultCode == .SQLITE_CONSTRAINT_CHECK)
    }
}

@Test("FR-01 R-101 FR-09 R-113: tasks 표 CHECK(recurrence·status·weekday 범위와 매주 짝·cycle_day 반복 짝)", arguments: taskRows)
func tasksTableChecks(row: RawRow) throws {
    try expectRow(row)
}

@Test("FR-02 R-115: contexts 표 impact CHECK", arguments: contextRows)
func contextsTableChecks(row: RawRow) throws {
    try expectRow(row)
}

@Test("FR-07 R-108: checkpoints 표 trigger CHECK와 따옴표 없는 trigger 열 이름", arguments: checkpointRows)
func checkpointsTableChecks(row: RawRow) throws {
    try expectRow(row)
}

@Test("FR-11 R-112: decisions_log 판단 칸 CHECK(공급자 기준)", arguments: decisionRows)
func decisionsLogTableChecks(row: RawRow) throws {
    try expectRow(row)
}

@Test("FR-08 R-412 R-415: tasks 표 carry_count >= 0, due_decision IN (0, 1) CHECK", arguments: carryRows)
func tasksCarryChecks(row: RawRow) throws {
    try expectRow(row)
}

// MARK: - 외래 키

@Test("FR-07 R-108 FR-11 R-112: 외래 키가 켜져 있고 기록이 가리키는 할 일은 지울 수 없다(ON DELETE RESTRICT)")
func foreignKeysRestrictDelete() throws {
    let db = try TestDatabase.migratedInMemory()
    #expect(try db.read { try Int.fetchOne($0, sql: "PRAGMA foreign_keys") } == 1)
    try db.write { db in
        try db.execute(sql: insertParentTask)
        try db.execute(sql: insertParentTask)
        try db.execute(sql: checkpointRows[0].sql)
        try db.execute(sql: decisionRows[0].sql.replacingOccurrences(of: "VALUES (1,", with: "VALUES (2,"))
    }
    for id in [1, 2] {
        let error = #expect(throws: DatabaseError.self) {
            try db.write { try $0.execute(sql: "DELETE FROM tasks WHERE id = ?", arguments: [id]) }
        }
        // SQLite는 RESTRICT 위반을 확장 코드 SQLITE_CONSTRAINT_TRIGGER(1811)로 알린다. 문구로 외래 키임을 확인한다.
        #expect(error?.resultCode == .SQLITE_CONSTRAINT)
        #expect(error?.message == "FOREIGN KEY constraint failed")
    }
    #expect(try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM tasks") } == 2)

    let orphanSQL = checkpointRows[0].sql.replacingOccurrences(of: "VALUES (1,", with: "VALUES (99,")
    let orphan = #expect(throws: DatabaseError.self) { try db.write { try $0.execute(sql: orphanSQL) } }
    #expect(orphan?.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY)
}

// MARK: - 모르는 값 읽기

@Test(
    "FR-11 R-112: 모르는 user_action·scheduler_choice가 든 줄을 읽으면 unknownValue",
    arguments: [
        ("user_action", "rotate_by_id_v0", "nap"),
        ("scheduler_choice", "rotate_by_id_v9", "done"),
    ])
func unknownDecisionValuesFailToRead(column: String, schedulerChoice: String, userAction: String) throws {
    let db = try TestDatabase.migratedInMemory()
    try db.write { db in
        try db.execute(sql: insertParentTask)
        try db.execute(
            sql: """
                INSERT INTO decisions_log(task_id, scheduler_choice, user_action, created_at) VALUES (1, ?, ?, ?)
                """,
            arguments: [schedulerChoice, userAction, createdAt])
    }
    let repo = GRDBTaskRepository(db)
    let value = column == "user_action" ? userAction : schedulerChoice
    #expect(throws: StoreError.unknownValue(column: column, value: value)) { try repo.decisions() }
}

@Test("FR-08 R-416: 이월 답 값은 읽히고 모르는 carry 값은 unknownValue")
func carryDecisionValuesRead() throws {
    let db = try TestDatabase.migratedInMemory()
    try db.write { db in
        try db.execute(sql: insertParentTask)
        for action in ["carry_today", "carry_drop", "carry_move"] {
            try db.execute(
                sql: """
                    INSERT INTO decisions_log(task_id, scheduler_choice, user_action, created_at) VALUES (1, ?, ?, ?)
                    """,
                arguments: ["carry_card_v1", action, createdAt])
        }
    }
    let repo = GRDBTaskRepository(db)
    #expect(try repo.decisions().map(\.userAction) == [.carryToday, .carryDrop, .carryMove])
    #expect(try repo.decisions().map(\.schedulerChoice) == [.carryCardV1, .carryCardV1, .carryCardV1])

    try db.write {
        try $0.execute(
            sql: "INSERT INTO decisions_log(task_id, scheduler_choice, user_action, created_at) VALUES (1, ?, ?, ?)",
            arguments: ["carry_card_v1", "carry_later", createdAt])
    }
    #expect(throws: StoreError.unknownValue(column: "user_action", value: "carry_later")) { try repo.decisions() }
}

@Test("FR-01 R-101: 형식이 틀린 created_at·deadline이 든 할 일을 읽으면 invalidValue", arguments: ["created_at", "deadline"])
func malformedTextFailsToRead(column: String) throws {
    let db = try TestDatabase.migratedInMemory()
    try db.write { db in
        try db.execute(sql: insertParentTask)
        try db.execute(sql: "UPDATE tasks SET \(column) = '2026-02-30 bad'")
    }
    let repo = GRDBTaskRepository(db)
    #expect(throws: StoreError.invalidValue(column: column)) { try repo.tasks() }
}

@Test("FR-01 R-101 #66: 형식이 틀린 cycle_day가 든 반복 할 일을 읽으면 invalidValue")
func malformedCycleDayFailsToRead() throws {
    let db = try TestDatabase.migratedInMemory()
    try db.write { db in
        try db.execute(sql: insertParentTask)
        try db.execute(sql: "UPDATE tasks SET recurrence = 'daily', cycle_day = '2026-02-30 bad'")
    }
    #expect(throws: StoreError.invalidValue(column: "cycle_day")) { try GRDBTaskRepository(db).tasks() }
}

@Test("FR-01 R-101 #66: 형식이 틀린 contexts.date가 든 일정을 읽으면 invalidValue")
func malformedContextDateFailsToRead() throws {
    let db = try TestDatabase.migratedInMemory()
    try db.write {
        try $0.execute(sql: "INSERT INTO contexts(name, date, impact) VALUES ('가짜 일정', '2026-02-30', 'normal')")
    }
    #expect(throws: StoreError.invalidValue(column: "date")) { try GRDBContextStore(db).contexts() }
}

@Test("FR-01 R-101 #66: 형식이 틀린 created_at이 든 checkpoints·decisions_log 줄을 읽으면 invalidValue")
func malformedLogCreatedAtFailsToRead() throws {
    let db = try TestDatabase.migratedInMemory()
    try db.write { db in
        try db.execute(sql: insertParentTask)
        try db.execute(sql: checkpointRows[0].sql.replacingOccurrences(of: createdAt, with: "2026-10-26 07:33:20"))
        try db.execute(sql: decisionRows[0].sql.replacingOccurrences(of: createdAt, with: "2026-10-26 07:33:20"))
    }
    let repo = GRDBTaskRepository(db)
    #expect(throws: StoreError.invalidValue(column: "created_at")) { try repo.checkpoints() }
    #expect(throws: StoreError.invalidValue(column: "created_at")) { try repo.decisions() }
}

@Test("FR-11 R-112 #66: 공급자가 있고 판단 칸이 일부만 찬 decisions_log 줄은 빈 칸을 nil로 읽는다")
func partialJudgmentReads() throws {
    let db = try TestDatabase.migratedInMemory()
    try db.write { db in
        try db.execute(sql: insertParentTask)
        try db.execute(
            sql: decisionRow("공급자 + question_version만", provider: "'fake'", questionVersion: "'v0'", allowed: true).sql)
    }
    let entry = try #require(try GRDBTaskRepository(db).decisions().first)
    #expect(entry.judgment == Judgment(provider: "fake", questionVersion: "v0", probsJSON: nil, stateHash: nil))
    #expect(entry.modelSnapshot == nil)
}
