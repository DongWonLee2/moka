import MokaStore
import Testing

@Test("health: 메모리 DB를 열고 질의할 수 있다")
func storeHealth() throws {
    let db = try MokaDatabase.inMemory()
    #expect(db.path == ":memory:")
    #expect(try MokaDatabase.healthCheck(db))
}
