import Foundation
import MokaCore
import Testing

private func score(
    _ taskID: TaskID, urgency: Double = 0.5, modelSnapshot: String? = "jev-1.13.0", at: Date = Fake.noon
) -> TaskScore {
    TaskScore(
        taskID: taskID, questionVersion: "v1", provider: "fake", modelSnapshot: modelSnapshot, urgency: urgency,
        impact: 0.25, concrete: 0.9, avoiding: 0.3, probsJSON: #"{"concrete":{"noul":0.9}}"#,
        stateHash: "0123456789abcdef", scoredAt: at)
}

/// 단위 3에서 `StoreKind.makeStores()`의 공용 계약으로 옮겨 GRDB 구현에도 돌린다(T009).
@Suite struct InMemoryScoreStoreTests {
    private func makeStore() throws -> InMemoryScoreStore {
        InMemoryScoreStore(tasks: try InMemoryTaskRepository.seeded(3))
    }

    @Test("FR-04 R-205: 저장한 판단 결과를 그대로 다시 읽는다")
    func roundTrip() throws {
        let store = try makeStore()
        #expect(try store.scores().isEmpty)
        try store.upsertScore(score(1))
        try store.upsertScore(score(3))
        #expect(try store.scores() == [1: score(1), 3: score(3)])
    }

    @Test("FR-04 R-205: 같은 할 일을 다시 저장하면 덮어쓰고 이전 값은 남기지 않는다")
    func overwrite() throws {
        let store = try makeStore()
        try store.upsertScore(score(2, urgency: 0.1))
        try store.upsertScore(score(2, urgency: 0.9, modelSnapshot: "jev-1.14.0"))
        #expect(try store.scores() == [2: score(2, urgency: 0.9, modelSnapshot: "jev-1.14.0")])
    }

    @Test("FR-04 R-205: 매긴 시각은 초 아래를 버리고 저장한다")
    func subSecond() throws {
        let store = try makeStore()
        try store.upsertScore(score(1, at: Fake.noon.addingTimeInterval(0.75)))
        #expect(try store.scores()[1]?.scoredAt == Fake.noon)
    }

    @Test("FR-04 R-205: 응답 모델 이름이 없는 판단 결과도 저장한다")
    func noModelSnapshot() throws {
        let store = try makeStore()
        try store.upsertScore(score(1, modelSnapshot: nil))
        #expect(try store.scores()[1]?.modelSnapshot == nil)
        #expect(try store.scores()[1] == score(1, modelSnapshot: nil))
    }

    @Test("FR-04 R-205: 없는 할 일의 판단 결과는 taskNotFound로 막고 남기지 않는다")
    func unknownTask() throws {
        let store = try makeStore()
        #expect(throws: StoreError.taskNotFound(9)) { try store.upsertScore(score(9)) }
        #expect(try store.scores().isEmpty)
    }
}
