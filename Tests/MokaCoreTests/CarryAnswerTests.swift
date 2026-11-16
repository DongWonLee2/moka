import Foundation
import MokaCore
import Testing

// spec 005 data-model §10. 가짜 할 일만 쓴다.

private let today = Fake.day("2027-01-13")
private let questions = try! QuestionSet.bundled()

private func scoring(_ usable: [TaskID: TaskScore] = [:]) -> SessionScoring {
    SessionScoring(usable: usable, questions: questions, thresholds: nil, today: today)
}

private func answerInput(_ usable: [TaskID: TaskScore] = [:]) -> SessionInput {
    var input = Fake.input([])
    input.scoring = scoring(usable)
    return input
}

private let due = Fake.task(1, deadline: Fake.day("2027-01-10"), skipCount: 2, carryCount: 1, dueDecision: true)

@Suite struct CarryAnswerTests {
    @Test("FR-08 R-415 R-416: 오늘 할래요는 이월 횟수 +1, 표시를 풀고, carry_today 한 줄(판단 없으면 fallback)")
    func answerToday() throws {
        let batch = try CarryAnswer.apply(.today, task: due, today: today, input: answerInput())
        var expected = due
        expected.carryCount = 2
        expected.dueDecision = false
        #expect(batch.updatedTasks == [expected])
        #expect(batch.newCheckpoints.isEmpty)
        #expect(
            batch.newDecisions == [
                NewDecisionLogEntry(
                    taskID: 1,
                    judgment: Judgment(provider: "fallback", questionVersion: nil, probsJSON: nil, stateHash: nil),
                    modelSnapshot: nil, schedulerChoice: .carryCardV1, userAction: .carryToday, createdAt: Fake.noon)
            ])
    }

    @Test("FR-08 R-415 R-416: 버릴래요는 버림, 표시를 풀고, carry_drop 한 줄")
    func answerDrop() throws {
        let batch = try CarryAnswer.apply(.drop, task: due, today: today, input: answerInput())
        var expected = due
        expected.status = .dropped
        expected.dueDecision = false
        #expect(batch.updatedTasks == [expected])
        #expect(batch.newDecisions.map(\.userAction) == [.carryDrop])
        #expect(batch.newDecisions.map(\.schedulerChoice) == [.carryCardV1])
    }

    @Test("FR-08 R-415 R-416: 날짜 바꿀래요는 마감을 고른 날로, 이월 횟수는 그대로, carry_move 한 줄")
    func answerMove() throws {
        let day = Fake.day("2027-01-16")
        let batch = try CarryAnswer.apply(.move(day), task: due, today: today, input: answerInput())
        var expected = due
        expected.deadline = day
        expected.dueDecision = false
        #expect(batch.updatedTasks == [expected])
        #expect(batch.newDecisions.map(\.userAction) == [.carryMove])
    }

    @Test("FR-08 R-415: 날짜는 내일부터, 오늘이나 지난 날이면 아무것도 쓰지 않는다", arguments: ["2027-01-13", "2027-01-01"])
    func moveNeedsFuture(day: String) {
        #expect(throws: CarryAnswerError.dateNotAfterToday) {
            try CarryAnswer.apply(.move(Fake.day(day)), task: due, today: today, input: answerInput())
        }
        #expect(
            (try? CarryAnswer.apply(.move(Fake.day("2027-01-14")), task: due, today: today, input: answerInput()))
                != nil)
    }

    @Test("FR-08 R-417: 진행 중이거나 표시가 없는 할 일에는 답할 수 없다")
    func notOnCard() {
        for task in [Fake.task(1, status: .active, dueDecision: true), Fake.task(1)] {
            #expect(throws: CarryAnswerError.notOnCard) {
                try CarryAnswer.apply(.today, task: task, today: today, input: answerInput())
            }
        }
    }

    @Test("FR-08 R-416: 판단 결과가 있으면 그 결과를 로그 줄 판단 칸에 남긴다(spec 003 R-212)")
    func judgmentFromScore() throws {
        let score = TaskScore(
            taskID: 1, questionVersion: "v3", provider: "fake", modelSnapshot: "가짜-모델-1", urgency: 0.5, impact: 0.5,
            concrete: 0.5, avoiding: 0.1, probsJSON: "{\"a\":1}", stateHash: "0123456789abcdef", scoredAt: Fake.noon)
        let batch = try CarryAnswer.apply(.today, task: due, today: today, input: answerInput([1: score]))
        #expect(
            batch.newDecisions.first?.judgment
                == Judgment(
                    provider: "fake", questionVersion: "v3", probsJSON: "{\"a\":1}", stateHash: "0123456789abcdef"))
        #expect(batch.newDecisions.first?.modelSnapshot == "가짜-모델-1")
    }
}

@Suite struct CarryCardTests {
    @Test("FR-08 R-414: 카드에 오르는 할 일은 이월 답 대기인 대기 할 일, 마감 순(지난 → 가까운 → 없음, 동점은 id)")
    func cardOrder() {
        let tasks = [
            Fake.task(1, dueDecision: true), Fake.task(2, deadline: Fake.day("2027-01-20"), dueDecision: true),
            Fake.task(3, deadline: Fake.day("2027-01-10"), dueDecision: true), Fake.task(4),
            Fake.task(5, status: .active, dueDecision: true), Fake.task(6, dueDecision: true),
        ]
        #expect(CarryAnswer.cards(tasks).map(\.id) == [3, 2, 1, 6])
    }

    @Test("FR-08 R-414: 카드 까닭은 마감이 지났으면 지난 날 수, 아니면 손댐")
    func reason() {
        #expect(
            CarryCardReason.of(task: Fake.task(1, deadline: Fake.day("2027-01-10")), today: today) == .overdue(days: 3))
        #expect(
            CarryCardReason.of(task: Fake.task(1, deadline: Fake.day("2027-01-12")), today: today) == .overdue(days: 1))
        #expect(CarryCardReason.of(task: Fake.task(1, deadline: today), today: today) == .touched)
        #expect(CarryCardReason.of(task: Fake.task(1), today: today) == .touched)
    }
}
