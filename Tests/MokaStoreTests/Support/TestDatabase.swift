import Foundation
import GRDB
import MokaStore

/// MokaStore 시험이 DB를 여는 유일한 길. 메모리 DB이거나 임시 디렉터리 아래 경로만 연다(ADR-0004 가드 테스트).
enum TestDatabase {
    struct UnsafePath: Error {
        let path: String
    }

    static func migratedInMemory() throws -> DatabaseQueue {
        let db = try MokaDatabase.inMemory()
        try MokaMigrations.migrator.migrate(db)
        return db
    }

    /// 아직 없는 하위 폴더 아래의 DB 파일 경로. 폴더는 만들지 않는다.
    static func freshFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("moka-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("moka.sqlite")
    }

    static func open(at url: URL) throws -> DatabaseQueue {
        guard isSafe(url.path) else { throw UnsafePath(path: url.path) }
        let db = try MokaDatabase.open(at: url)
        guard isSafe(db.path) else { throw UnsafePath(path: db.path) }
        return db
    }

    static func isSafe(_ path: String) -> Bool {
        if path.contains("dev.dongwon.moka") { return false }
        if path == ":memory:" { return true }
        let temp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.path
        let prefix = temp.hasSuffix("/") ? temp : temp + "/"
        return candidate.hasPrefix(prefix)
    }

    /// `freshFileURL`이 만든 최상위 임시 폴더를 지운다.
    static func removeTestFolder(of url: URL) {
        let root = url.deletingLastPathComponent().deletingLastPathComponent()
        guard isSafe(root.path), root.lastPathComponent.hasPrefix("moka-tests-") else { return }
        try? FileManager.default.removeItem(at: root)
    }
}
