import GRDB

/// 배포한 마이그레이션은 고치지 않고 덧붙이기만 한다. `eraseDatabaseOnSchemaChange`는 켜지 않는다(ADR-0004).
public enum MokaMigrations {
    public static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_settings") { db in
            try db.execute(sql: "CREATE TABLE settings(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)")
        }
        // data-model §7. 문장을 한 줄 문자열로 두어 sqlite_master에 그대로 남긴다(스냅샷과 바이트 비교).
        migrator.registerMigration("v2_tasks_contexts_checkpoints_log") { db in
            try db.execute(
                sql:
                    "CREATE TABLE tasks(id INTEGER PRIMARY KEY NOT NULL, title TEXT NOT NULL, deadline TEXT, est_min INTEGER, recurrence TEXT NOT NULL CHECK(recurrence IN ('none', 'daily', 'weekly')), weekday INTEGER CHECK(weekday BETWEEN 1 AND 7), cycle_day TEXT, first_action TEXT, status TEXT NOT NULL CHECK(status IN ('todo', 'active', 'done', 'dropped')), skip_count INTEGER NOT NULL, streak INTEGER NOT NULL, created_at TEXT NOT NULL, CHECK((recurrence = 'weekly') = (weekday IS NOT NULL)), CHECK((recurrence = 'none') = (cycle_day IS NULL)))"
            )
            try db.execute(
                sql:
                    "CREATE TABLE contexts(id INTEGER PRIMARY KEY NOT NULL, name TEXT NOT NULL, date TEXT NOT NULL, impact TEXT NOT NULL CHECK(impact IN ('normal', 'high', 'critical')))"
            )
            try db.execute(
                sql:
                    "CREATE TABLE checkpoints(id INTEGER PRIMARY KEY NOT NULL, task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE RESTRICT, done_note TEXT NOT NULL, next_note TEXT NOT NULL, trigger TEXT NOT NULL CHECK(trigger IN ('quantum', 'switch', 'skip', 'urgent', 'pause', 'quit', 'sleep', 'day_end')), elapsed_min INTEGER NOT NULL, created_at TEXT NOT NULL)"
            )
            try db.execute(
                sql:
                    "CREATE TABLE decisions_log(id INTEGER PRIMARY KEY NOT NULL, task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE RESTRICT, question_version TEXT, provider TEXT, probs_json TEXT, state_hash TEXT, model_snapshot TEXT, scheduler_choice TEXT NOT NULL, user_action TEXT NOT NULL, created_at TEXT NOT NULL, CHECK(provider IS NOT NULL OR (question_version IS NULL AND probs_json IS NULL AND state_hash IS NULL)), CHECK(model_snapshot IS NULL OR provider IS NOT NULL))"
            )
        }
        migrator.registerMigration("v3_scores") { db in
            try db.execute(
                sql:
                    "CREATE TABLE scores(task_id INTEGER PRIMARY KEY NOT NULL REFERENCES tasks(id) ON DELETE RESTRICT, question_version TEXT NOT NULL, provider TEXT NOT NULL, model_snapshot TEXT, urgency REAL NOT NULL, impact REAL NOT NULL, concrete REAL NOT NULL, avoiding REAL NOT NULL, probs_json TEXT NOT NULL, state_hash TEXT NOT NULL, scored_at TEXT NOT NULL)"
            )
        }
        return migrator
    }()
}
