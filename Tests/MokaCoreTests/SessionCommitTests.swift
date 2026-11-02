import Foundation
import MokaCore
import Testing

// data-model §4.2 SessionCommit(R-119).

@Suite struct SessionCommitTests {
    @Test("FR-11 R-119: apply가 throw하면 같은 오류를 다시 던지고 저장소에 아무것도 남지 않는다")
    func rethrowsAndLeavesNothing() throws {
        let repository = FailingTaskRepository()
        _ = try repository.insertTask(
            NewTask(title: "가짜 할 일 A", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: Fake.noon)
        let before = try repository.tasks()
        let drafted = NotchSession.initial.picked(Fake.input(before))
        let step = try drafted.start(Fake.input(before))

        #expect(throws: FailingTaskRepository.Failure()) { try SessionCommit.commit(step, to: repository) }
        #expect(try repository.tasks() == before)
        #expect(try repository.checkpoints().isEmpty)
        #expect(try repository.decisions().isEmpty)
    }

    @Test("FR-11 R-119: 메모리 저장소가 묶음을 거부하면 그 오류를 던지고 묶음의 어느 것도 남지 않는다")
    func memoryRejectionIsAtomic() throws {
        let repository = try InMemoryTaskRepository.seeded(1)
        let before = try repository.tasks()
        var active = before[0]
        active.status = .active
        // 없는 할 일(id 99)을 가리키는 체크포인트가 섞인 묶음.
        let step = SessionStep(
            session: .initial,
            batch: StoreBatch(
                updatedTasks: [active],
                newCheckpoints: [
                    NewCheckpoint(taskID: 99, notes: .empty, trigger: .skip, elapsedMin: 1, createdAt: Fake.noon)
                ]))

        #expect(throws: StoreError.taskNotFound(99)) { try SessionCommit.commit(step, to: repository) }
        #expect(try repository.tasks() == before)
        #expect(try repository.checkpoints().isEmpty)
    }

    @Test("FR-11 R-119: apply가 성공하면 step.session을 돌려주고 묶음이 저장된다")
    func returnsSessionOnSuccess() throws {
        let repository = try InMemoryTaskRepository.seeded(2)
        let drafted = NotchSession.initial.picked(Fake.input(try repository.tasks()))
        let step = try drafted.start(Fake.input(try repository.tasks()))
        let session = try SessionCommit.commit(step, to: repository)
        #expect(session == step.session)
        #expect(try repository.tasks().map(\.status) == [.active, .todo])
    }
}
