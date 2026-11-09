import Foundation
import MokaCore
import Testing

private let questions = try! QuestionSet(json: questionsJSON())
private let answerA = DecisionResponse(model: "jev-1.13.0", answers: ["concrete": .noul(0.1)])
private let answerB = DecisionResponse(model: "jev-1.13.0", answers: ["concrete": .noul(0.8)])

private func request(_ taskID: TaskID) -> DecisionRequest {
    DecisionRequest(taskID: taskID, model: questions.model, state: Array("{}".utf8), questions: questions)
}

@Suite struct FakeDecisionProviderTests {
    @Test("FR-14 R-210: 가짜 공급자는 할 일별로 정한 답을, 정하지 않은 할 일에는 기본 답을 돌려준다")
    func answers() async throws {
        let fake = FakeDecisionProvider(answer: .success(answerA))
        await fake.setAnswer(.success(answerB), for: 2)
        #expect(try await fake.decide(request(1), key: "fake-key") == answerA)
        #expect(try await fake.decide(request(2), key: "fake-key") == answerB)
        #expect(fake.name == "fake")
    }

    @Test(
        "FR-14 R-211: 가짜 공급자는 할 일별로 정한 오류를 던진다",
        arguments: [
            DecisionError.unauthorized, .rateLimited, .overloaded, .timeout, .network, .server(status: 500),
            .malformed,
        ])
    func errors(error: DecisionError) async {
        let fake = FakeDecisionProvider(name: "fake-other", answer: .success(answerA))
        await fake.setAnswer(.failure(error), for: 3)
        await #expect(throws: error) { try await fake.decide(request(3), key: "fake-key") }
        #expect(fake.name == "fake-other")
    }

    @Test("FR-14 R-211: 빈 키를 받으면 missingKey")
    func emptyKey() async {
        let fake = FakeDecisionProvider(answer: .success(answerA))
        await #expect(throws: DecisionError.missingKey) { try await fake.decide(request(1), key: "") }
    }

    @Test("FR-14 R-210: calls는 받은 요청의 할 일 id를 받은 순서대로 적는다")
    func calls() async throws {
        let fake = FakeDecisionProvider(answer: .success(answerA))
        for id: TaskID in [3, 1, 3] { _ = try await fake.decide(request(id), key: "fake-key") }
        #expect(await fake.calls == [3, 1, 3])
        #expect(await fake.maxInFlight == 1)
    }

    @Test("FR-14 R-210: 붙잡으면 답을 돌려주지 않고, 풀어 준 할 일만 돌아온다")
    func holdAndRelease() async throws {
        let fake = FakeDecisionProvider(answer: .success(answerA))
        await fake.hold()
        let tasks = (1...3).map { id in Task { try await fake.decide(request(TaskID(id)), key: "fake-key") } }
        await fake.waitForHeld(count: 3)
        #expect(await fake.maxInFlight == 3)
        #expect(Set(await fake.calls) == [1, 2, 3])

        await fake.release(taskID: 2)
        #expect(try await tasks[1].value == answerA)
        #expect(await fake.heldCount == 2)

        await fake.releaseAll()
        #expect(try await tasks[0].value == answerA)
        #expect(try await tasks[2].value == answerA)
        #expect(await fake.heldCount == 0)
        #expect(await fake.maxInFlight == 3)
    }

    @Test("FR-14 R-210: 같은 할 일 요청이 겹치면 풀 때마다 먼저 온 것부터 하나씩 돌아온다")
    func overlappingSameTask() async throws {
        let fake = FakeDecisionProvider(answer: .success(answerA))
        await fake.hold()
        let first = Task { try await fake.decide(request(5), key: "fake-key") }
        await fake.waitForHeld(count: 1)
        await fake.setAnswer(.success(answerB), for: 5)
        let second = Task { try await fake.decide(request(5), key: "fake-key") }
        await fake.waitForHeld(count: 2)

        await fake.release(taskID: 5)
        #expect(try await first.value == answerA)
        #expect(await fake.heldCount == 1)
        await fake.release(taskID: 5)
        #expect(try await second.value == answerB)
    }

    /// 깨우지 못하는 구현에서도 시험이 멈추지 않게 끝난 기다림의 수만 본다.
    @Test("FR-14 R-210: releaseAll은 도달하지 못한 waitForHeld 기다림을 깨우고, 그 뒤 기다림은 바로 돌아온다")
    func releaseAllWakesWaiters() async throws {
        let fake = FakeDecisionProvider(answer: .success(answerA))
        await fake.hold()
        let request = Task { try await fake.decide(request(1), key: "fake-key") }
        await fake.waitForHeld(count: 1)
        let finished = FinishCounter()
        _ = Task {
            await fake.waitForHeld(count: 2)
            await finished.add()
        }
        await fake.releaseAll()
        _ = Task {
            await fake.waitForHeld(count: 1)
            await finished.add()
        }
        #expect(try await request.value == answerA)
        for _ in 0..<1000 where await finished.count < 2 { await Task.yield() }

        #expect(await finished.count == 2)
    }

    @Test("FR-14 R-210: releaseAll 뒤에는 붙잡지 않는다")
    func releaseAllEndsHold() async throws {
        let fake = FakeDecisionProvider(answer: .success(answerA))
        await fake.hold()
        await fake.releaseAll()
        #expect(try await fake.decide(request(1), key: "fake-key") == answerA)
    }
}

private actor FinishCounter {
    private(set) var count = 0
    func add() { count += 1 }
}
