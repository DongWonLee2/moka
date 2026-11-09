import Foundation
import MokaCore
import Testing

@Suite struct InMemoryKeyStoreTests {
    @Test("FR-16 R-214: 키가 없으면 hasKey는 false, read는 nil")
    func empty() throws {
        let store = InMemoryKeyStore()
        #expect(try !store.hasKey())
        #expect(try store.read() == nil)
    }

    @Test("FR-16 R-214: 저장한 키를 읽고, 다시 저장하면 덮어쓴다")
    func saveOverwrites() throws {
        let store = InMemoryKeyStore()
        try store.save("fake-key-1")
        #expect(try store.hasKey())
        #expect(try store.read() == "fake-key-1")
        try store.save("fake-key-2")
        #expect(try store.read() == "fake-key-2")
    }

    @Test("FR-16 R-214: 지우면 키가 없고, 없는 키를 지워도 던지지 않는다")
    func delete() throws {
        let store = InMemoryKeyStore(key: "fake-key")
        #expect(try store.read() == "fake-key")
        try store.delete()
        #expect(try !store.hasKey())
        try store.delete()
        #expect(try store.read() == nil)
    }

    @Test(
        "FR-16 R-214: 정한 동작만 오류를 던지고, 실패한 저장·지우기는 키를 바꾸지 않는다",
        arguments: [InMemoryKeyStore.Operation.hasKey, .read, .save, .delete])
    func failing(operation: InMemoryKeyStore.Operation) throws {
        let store = InMemoryKeyStore(key: "fake-key")
        store.failing = [operation]
        #expect(throws: InMemoryKeyStore.Failure()) {
            switch operation {
            case .hasKey: _ = try store.hasKey()
            case .read: _ = try store.read()
            case .save: try store.save("fake-key-new")
            case .delete: try store.delete()
            }
        }
        if operation != .hasKey { #expect(try store.hasKey()) }
        store.failing = []
        #expect(try store.read() == "fake-key")
    }
}
