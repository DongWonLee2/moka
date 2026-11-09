import Foundation
import GRDB
import MokaCore

/// `scores` 표(spec 003 data-model §2). 할 일마다 최신 판단 결과 한 줄이고, 다시 저장하면 덮어쓴다.
public final class GRDBScoreStore: ScoreStore {
    private let db: DatabaseQueue

    public init(_ db: DatabaseQueue) {
        self.db = db
    }

    public func scores() throws -> [TaskID: TaskScore] {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM scores ORDER BY task_id")
            return try Dictionary(
                uniqueKeysWithValues: rows.map { row in
                    let score = try Self.score(of: row)
                    return (score.taskID, score)
                })
        }
    }

    public func upsertScore(_ score: TaskScore) throws {
        try db.write { db in
            guard try GRDBTaskRepository.taskExists(score.taskID, db) else {
                throw StoreError.taskNotFound(score.taskID)
            }
            try db.execute(
                sql: """
                    INSERT INTO scores(task_id, question_version, provider, model_snapshot, urgency, impact, concrete, \
                    avoiding, probs_json, state_hash, scored_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
                    ON CONFLICT(task_id) DO UPDATE SET question_version = excluded.question_version, \
                    provider = excluded.provider, model_snapshot = excluded.model_snapshot, urgency = excluded.urgency, \
                    impact = excluded.impact, concrete = excluded.concrete, avoiding = excluded.avoiding, \
                    probs_json = excluded.probs_json, state_hash = excluded.state_hash, scored_at = excluded.scored_at
                    """,
                arguments: [
                    score.taskID, score.questionVersion, score.provider, score.modelSnapshot, score.urgency,
                    score.impact, score.concrete, score.avoiding, score.probsJSON, score.stateHash,
                    UTCTimestamp.format(score.scoredAt),
                ])
        }
    }

    private static func score(of row: Row) throws -> TaskScore {
        TaskScore(
            taskID: row["task_id"], questionVersion: row["question_version"], provider: row["provider"],
            modelSnapshot: row["model_snapshot"], urgency: row["urgency"], impact: row["impact"],
            concrete: row["concrete"], avoiding: row["avoiding"], probsJSON: row["probs_json"],
            stateHash: row["state_hash"], scoredAt: try row.timestamp("scored_at"))
    }
}
