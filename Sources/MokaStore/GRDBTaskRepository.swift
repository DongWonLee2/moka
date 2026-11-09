import Foundation
import GRDB
import MokaCore

/// `tasks`·`checkpoints`·`decisions_log` 표(data-model §3·§7). 시각은 `UTCTimestamp`, 날짜는 `LocalDay`로만 쓰고 읽는다.
public final class GRDBTaskRepository: TaskRepository {
    private let db: DatabaseQueue

    public init(_ db: DatabaseQueue) {
        self.db = db
    }

    public func tasks() throws -> [MokaTask] {
        try db.read { try Row.fetchAll($0, sql: "SELECT * FROM tasks ORDER BY id").map(Self.task) }
    }

    public func insertTask(_ task: NewTask, cycleDay: LocalDay?, at: Date) throws -> MokaTask {
        var inserted = MokaTask(
            id: 0, title: task.title, deadline: task.deadline, estMin: task.estMin, recurrence: task.recurrence,
            weekday: task.weekday, cycleDay: cycleDay, firstAction: nil, status: .todo, skipCount: 0, streak: 0,
            createdAt: UTCTimestamp.floorToSecond(at))
        try Self.check(inserted)
        let row = inserted
        inserted.id = try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tasks(title, deadline, est_min, recurrence, weekday, cycle_day, first_action, status, \
                    skip_count, streak, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: Self.columns(of: row) + [UTCTimestamp.format(row.createdAt)])
            return db.lastInsertedRowID
        }
        return inserted
    }

    public func checkpoints() throws -> [Checkpoint] {
        try db.read { try Row.fetchAll($0, sql: "SELECT * FROM checkpoints ORDER BY id").map(Self.checkpoint) }
    }

    public func decisions() throws -> [DecisionLogEntry] {
        try db.read { try Row.fetchAll($0, sql: "SELECT * FROM decisions_log ORDER BY id").map(Self.decision) }
    }

    /// 묶음 전체를 `write` 한 트랜잭션으로 적용한다. 도중에 던지면 GRDB가 되돌린다.
    public func apply(_ batch: StoreBatch) throws {
        try db.write { db in
            for task in batch.updatedTasks {
                guard try Self.taskExists(task.id, db) else { throw StoreError.taskNotFound(task.id) }
                try Self.check(task)
                try db.execute(
                    sql: """
                        UPDATE tasks SET title = ?, deadline = ?, est_min = ?, recurrence = ?, weekday = ?, \
                        cycle_day = ?, first_action = ?, status = ?, skip_count = ?, streak = ? WHERE id = ?
                        """,
                    arguments: Self.columns(of: task) + [task.id])
            }
            for new in batch.newCheckpoints {
                guard try Self.taskExists(new.taskID, db) else { throw StoreError.taskNotFound(new.taskID) }
                try db.execute(
                    sql: """
                        INSERT INTO checkpoints(task_id, done_note, next_note, trigger, elapsed_min, created_at) \
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        new.taskID, new.notes.doneNote, new.notes.nextNote, new.trigger.rawValue, new.elapsedMin,
                        UTCTimestamp.format(new.createdAt),
                    ])
            }
            for new in batch.newDecisions {
                guard try Self.taskExists(new.taskID, db) else { throw StoreError.taskNotFound(new.taskID) }
                if new.judgment == nil, new.modelSnapshot != nil {
                    throw StoreError.invalidValue(column: "model_snapshot")
                }
                try db.execute(
                    sql: """
                        INSERT INTO decisions_log(task_id, question_version, provider, probs_json, state_hash, \
                        model_snapshot, scheduler_choice, user_action, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        new.taskID, new.judgment?.questionVersion, new.judgment?.provider, new.judgment?.probsJSON,
                        new.judgment?.stateHash, new.modelSnapshot, new.schedulerChoice.rawValue,
                        new.userAction.rawValue, UTCTimestamp.format(new.createdAt),
                    ])
            }
        }
    }

    // MARK: - 쓰기

    /// `created_at`을 뺀 `tasks` 열(INSERT와 UPDATE가 같은 순서로 쓴다).
    private static func columns(of task: MokaTask) -> StatementArguments {
        [
            task.title, task.deadline?.text, task.estMin, task.recurrence.rawValue, task.weekday?.rawValue,
            task.cycleDay?.text, task.firstAction, task.status.rawValue, task.skipCount, task.streak,
        ]
    }

    static func taskExists(_ id: TaskID, _ db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM tasks WHERE id = ?)", arguments: [id]) ?? false
    }

    /// `tasks` 표 CHECK의 짝 규칙(data-model §7). 메모리 구현과 같은 오류를 내려고 SQL 전에 확인한다.
    private static func check(_ task: MokaTask) throws {
        guard MokaTask.isValidWeekday(task.weekday, recurrence: task.recurrence) else {
            throw StoreError.invalidValue(column: "weekday")
        }
        guard (task.recurrence == .none) == (task.cycleDay == nil) else {
            throw StoreError.invalidValue(column: "cycle_day")
        }
    }

    // MARK: - 읽기

    private static func task(_ row: Row) throws -> MokaTask {
        let weekday: Weekday?
        if let raw: Int = row["weekday"] {
            guard let value = Weekday(rawValue: raw) else { throw StoreError.invalidValue(column: "weekday") }
            weekday = value
        } else {
            weekday = nil
        }
        return MokaTask(
            id: row["id"], title: row["title"], deadline: try row.localDay("deadline"), estMin: row["est_min"],
            recurrence: try row.enumValue("recurrence"), weekday: weekday, cycleDay: try row.localDay("cycle_day"),
            firstAction: row["first_action"], status: try row.enumValue("status"), skipCount: row["skip_count"],
            streak: row["streak"], createdAt: try row.timestamp("created_at"))
    }

    private static func checkpoint(_ row: Row) throws -> Checkpoint {
        Checkpoint(
            id: row["id"], taskID: row["task_id"],
            notes: CheckpointNotes(doneNote: row["done_note"], nextNote: row["next_note"]),
            trigger: try row.enumValue("trigger"), elapsedMin: row["elapsed_min"],
            createdAt: try row.timestamp("created_at"))
    }

    private static func decision(_ row: Row) throws -> DecisionLogEntry {
        let provider: String? = row["provider"]
        return DecisionLogEntry(
            id: row["id"], taskID: row["task_id"],
            judgment: provider.map {
                Judgment(
                    provider: $0, questionVersion: row["question_version"], probsJSON: row["probs_json"],
                    stateHash: row["state_hash"])
            },
            modelSnapshot: row["model_snapshot"], schedulerChoice: try row.enumValue("scheduler_choice"),
            userAction: try row.enumValue("user_action"), createdAt: try row.timestamp("created_at"))
    }
}

/// 저장 문자열 → MokaCore 값. 틀리면 `StoreError`(data-model §3, P3).
extension Row {
    func enumValue<Value: RawRepresentable>(_ column: String) throws -> Value where Value.RawValue == String {
        let raw: String = self[column]
        guard let value = Value(rawValue: raw) else { throw StoreError.unknownValue(column: column, value: raw) }
        return value
    }

    func localDay(_ column: String) throws -> LocalDay? {
        guard let text: String = self[column] else { return nil }
        guard let day = LocalDay(text: text) else { throw StoreError.invalidValue(column: column) }
        return day
    }

    func timestamp(_ column: String) throws -> Date {
        let text: String = self[column]
        guard let date = UTCTimestamp.parse(text) else { throw StoreError.invalidValue(column: column) }
        return date
    }
}
