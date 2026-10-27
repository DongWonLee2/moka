import GRDB

public enum MokaDatabase {
    /// 테스트와 `moka-sim`이 쓰는 메모리 DB. 실제 앱 DB 경로는 여기서 열지 않는다(ADR-0004).
    public static func inMemory() throws -> DatabaseQueue {
        try DatabaseQueue()
    }

    public static func healthCheck(_ db: DatabaseQueue) throws -> Bool {
        false
    }
}
