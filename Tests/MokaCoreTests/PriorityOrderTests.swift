import Foundation
import MokaCore
import Testing

// data-model §7. 가짜 할 일·가짜 판단 결과만 쓴다.

private let questions = try! QuestionSet.bundled()
private let today = Fake.day("2027-01-13")

/// 마감이 없고 미룬 횟수가 0이면 priority = urgency + 0.7 × impact.
private func score(_ taskID: TaskID, urgency: Double, impact: Double = 1, avoiding: Double = 0.3) -> TaskScore {
    TaskScore(
        taskID: taskID, questionVersion: "v1", provider: "fake", modelSnapshot: "jev-1.13.0", urgency: urgency,
        impact: impact, concrete: 0.9, avoiding: avoiding, probsJSON: "{}", stateHash: "0123456789abcdef",
        scoredAt: Fake.noon)
}

private func order(_ tasks: [MokaTask], _ usable: [TaskID: TaskScore]) -> [TaskID] {
    PriorityOrder.order(tasks: tasks, usable: usable, questions: questions, today: today, calendar: Fake.seoul)
        .map(\.id)
}

/// spec US1의 A(1.2)·B(0.9)·C(1.5). id는 A 1, B 2, C 3.
private let abc: [TaskID: TaskScore] = [
    1: score(1, urgency: 0.5), 2: score(2, urgency: 0.2), 3: score(3, urgency: 0.8),
]

@Suite struct PriorityOrderTests {
    @Test("FR-05 R-208: 점수 있는 대기 할 일은 priority 높은 순")
    func scoredByPriority() {
        #expect(order(Fake.todos(1...3), abc) == [3, 1, 2])
    }

    @Test("FR-05 R-208: priority가 같으면 마감이 이른 순, 그다음 만든 순(id)")
    func scoredTieBreaksByDeadlineThenID() {
        let tasks = [
            Fake.task(1), Fake.task(2, deadline: Fake.day("2027-01-20")), Fake.task(3),
            Fake.task(4, deadline: Fake.day("2027-01-18")),
        ]
        let same: [TaskID: TaskScore] = [
            1: score(1, urgency: 0.5), 2: score(2, urgency: 0.5), 3: score(3, urgency: 0.5),
            4: score(4, urgency: 0.5),
        ]
        #expect(order(tasks, same) == [4, 2, 1, 3])
    }

    @Test("FR-05 R-208: 점수 없는 대기 할 일은 점수 있는 할 일 뒤에 마감 순(마감 없음 맨 뒤, 같으면 id)")
    func unscoredAfterScoredByDeadline() {
        let tasks = [
            Fake.task(1), Fake.task(2, deadline: Fake.day("2027-01-25")),
            Fake.task(3, deadline: Fake.day("2027-01-15")),
            Fake.task(4), Fake.task(5, deadline: Fake.day("2027-01-15")),
            Fake.task(6, deadline: Fake.day("2027-01-30")),
        ]
        let usable: [TaskID: TaskScore] = [6: score(6, urgency: 0.1, impact: 0)]
        #expect(order(tasks, usable) == [6, 3, 5, 2, 1, 4])
    }

    @Test("FR-05 R-208: 쓸 판단 결과가 없으면(키 없음) 모든 대기 할 일이 마감 순")
    func emptyUsableIsDeadlineOrder() {
        let tasks = [
            Fake.task(1), Fake.task(2, deadline: Fake.day("2027-01-20")),
            Fake.task(3, deadline: Fake.day("2027-01-14")),
        ]
        #expect(order(tasks, [:]) == [3, 2, 1])
    }

    @Test("FR-05 R-208: 대기 할 일만 순서에 들고, 대기 아닌 할 일의 판단 결과는 무시한다")
    func onlyTodo() {
        let tasks = [
            Fake.task(1, status: .active), Fake.task(2, status: .done), Fake.task(3, status: .dropped), Fake.task(4),
            Fake.task(5),
        ]
        let usable: [TaskID: TaskScore] = [
            1: score(1, urgency: 1), 2: score(2, urgency: 1), 3: score(3, urgency: 1), 9: score(9, urgency: 1),
        ]
        #expect(order(tasks, usable) == [4, 5])
        #expect(order([], usable) == [])
    }

    @Test("FR-05 R-208: priority는 고르는 날 기준 urgency 하한과 미룬 횟수를 반영한다")
    func priorityUsesFloorAndAging() {
        let tasks = [
            Fake.task(1), Fake.task(2, deadline: Fake.day("2027-01-14")), Fake.task(3, skipCount: 3),
        ]
        // 1: 0.9 + 0.7 = 1.6, 2: 마감 내일이라 urgency 1 → 1.0, 3: 0.8 × 3 = 2.4
        let usable: [TaskID: TaskScore] = [
            1: score(1, urgency: 0.9), 2: score(2, urgency: 0.1, impact: 0), 3: score(3, urgency: 0, impact: 0),
        ]
        #expect(order(tasks, usable) == [3, 1, 2])
        // 1: 0.2, 2: 하한으로 1.0(하한이 없으면 0.1이라 1보다 뒤), 3: 2.4
        let low: [TaskID: TaskScore] = [
            1: score(1, urgency: 0.2, impact: 0), 2: score(2, urgency: 0.1, impact: 0),
            3: score(3, urgency: 0, impact: 0),
        ]
        #expect(order(tasks, low) == [3, 2, 1])
    }

    @Test("FR-05 R-208: SessionInput의 scoring이 nil이면 마감 순, 있으면 그 판단 결과로 순서")
    func orderFromInput() {
        let tasks = [Fake.task(1), Fake.task(2, deadline: Fake.day("2027-01-20")), Fake.task(3)]
        #expect(PriorityOrder.order(Fake.input(tasks)).map(\.id) == [2, 1, 3])
        var input = Fake.input(tasks)
        input.scoring = SessionScoring(usable: abc, questions: questions, today: today)
        #expect(PriorityOrder.order(input).map(\.id) == [3, 1, 2])
    }
}

@Suite struct PriorityRotateRuleTests {
    @Test("FR-05 R-209: 고른 규칙 이름은 priority_rotate_v0")
    func choiceName() {
        #expect(PriorityRotateRule.choice == .priorityRotateV0)
        #expect(PriorityRotateRule.choice.rawValue == "priority_rotate_v0")
    }

    @Test("FR-05 R-209: 처음(커서 없음)이면 1위")
    func firstIsTop() {
        let tasks = [Fake.task(1), Fake.task(2), Fake.task(3)]
        #expect(PriorityRotateRule.pick(order: [tasks[2], tasks[0], tasks[1]], after: nil)?.id == 3)
    }

    @Test("FR-05 R-209: 커서가 순서에 있으면 그다음, 끝이면 1위")
    func nextThenWrap() {
        let ordered = [Fake.task(3), Fake.task(1), Fake.task(2)]
        #expect(PriorityRotateRule.pick(order: ordered, after: 3)?.id == 1)
        #expect(PriorityRotateRule.pick(order: ordered, after: 1)?.id == 2)
        #expect(PriorityRotateRule.pick(order: ordered, after: 2)?.id == 3)
    }

    @Test("FR-05 R-209: 커서가 순서에 없으면(완료·버림) 1위")
    func missingCursorIsTop() {
        let ordered = [Fake.task(3), Fake.task(1)]
        #expect(PriorityRotateRule.pick(order: ordered, after: 2)?.id == 3)
    }

    @Test("FR-05 R-209: 후보가 하나면 커서가 그 할 일이어도 그것, 없으면 nil")
    func singleAndEmpty() {
        #expect(PriorityRotateRule.pick(order: [Fake.task(5)], after: 5)?.id == 5)
        #expect(PriorityRotateRule.pick(order: [Fake.task(5)], after: nil)?.id == 5)
        #expect(PriorityRotateRule.pick(order: [], after: nil) == nil)
        #expect(PriorityRotateRule.pick(order: [], after: 5) == nil)
    }

    @Test("FR-05 R-209: spec US1-3 C 뒤 바꾸기면 A, A 뒤 B, B 뒤 처음 C")
    func rotatesThroughABC() {
        let ordered = PriorityOrder.order(
            tasks: Fake.todos(1...3), usable: abc, questions: questions, today: today, calendar: Fake.seoul)
        var cursor: TaskID?
        var picked: [TaskID] = []
        for _ in 0..<4 {
            cursor = PriorityRotateRule.pick(order: ordered, after: cursor)?.id
            picked.append(cursor!)
        }
        #expect(picked == [3, 1, 2, 3])
    }

    @Test("FR-05 R-209: spec US1-4 A를 미루면 다시 계산한 순서에서 A의 다음(C)을 고른다")
    func skipReordersBeforePick() {
        // 미루기 뒤 A는 1.2 + 0.8 = 2.0이 되어 A, C, B 순. 미루기 전 순서였다면 B였다.
        let tasks = [Fake.task(1, skipCount: 1), Fake.task(2), Fake.task(3)]
        let ordered = PriorityOrder.order(
            tasks: tasks, usable: abc, questions: questions, today: today, calendar: Fake.seoul)
        #expect(ordered.map(\.id) == [1, 3, 2])
        #expect(PriorityRotateRule.pick(order: ordered, after: 1)?.id == 3)
    }
}
