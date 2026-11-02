import GRDB
import MokaCore

/// `contexts` 표(data-model §3·§7). 날짜는 `LocalDay`로만 쓰고 읽는다.
public final class GRDBContextStore: ContextStore {
    private let db: DatabaseQueue

    public init(_ db: DatabaseQueue) {
        self.db = db
    }

    public func contexts() throws -> [MokaContext] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM contexts ORDER BY date, id").map { row in
                guard let date = try row.localDay("date") else { throw StoreError.invalidValue(column: "date") }
                return MokaContext(id: row["id"], name: row["name"], date: date, impact: try row.enumValue("impact"))
            }
        }
    }

    public func insertContext(_ context: NewContext) throws -> MokaContext {
        let id = try db.write { db in
            try db.execute(
                sql: "INSERT INTO contexts(name, date, impact) VALUES (?, ?, ?)",
                arguments: [context.name, context.date.text, context.impact.rawValue])
            return db.lastInsertedRowID
        }
        return MokaContext(id: id, name: context.name, date: context.date, impact: context.impact)
    }

    /// 실제로 지운다(research R4).
    public func deleteContext(id: ContextID) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM contexts WHERE id = ?", arguments: [id])
            guard db.changesCount > 0 else { throw StoreError.contextNotFound(id) }
        }
    }
}
