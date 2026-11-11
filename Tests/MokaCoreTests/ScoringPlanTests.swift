import Foundation
import MokaCore
import Testing

private let today = Fake.day("2027-01-13")

private func state(_ task: MokaTask, day: LocalDay = today, contexts: [MokaContext] = []) -> JudgmentState {
    JudgmentState.build(task: task, contexts: contexts, checkpoints: [], today: day, calendar: Fake.seoul)
}

private func allStates(_ tasks: [MokaTask], day: LocalDay = today) -> [TaskID: JudgmentState] {
    Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, state($0, day: day)) })
}

private func edited(_ task: MokaTask) -> MokaTask {
    var copy = task
    copy.title += " 고침"
    return copy
}

private func score(
    _ task: MokaTask, version: String = "v1", hash: String? = nil, provider: String = "fake"
) -> TaskScore {
    TaskScore(
        taskID: task.id, questionVersion: version, provider: provider, modelSnapshot: "jev-1.13.0", urgency: 0.5,
        impact: 0.5, concrete: 0.5, avoiding: 0.5, probsJSON: "{}", stateHash: hash ?? state(task).hash,
        scoredAt: Fake.noon)
}

private func needsQuery(
    _ tasks: [MokaTask], scores: [TaskScore], states: [TaskID: JudgmentState]? = nil, version: String = "v1",
    provider: String = "fake"
) -> [TaskID] {
    ScoringPlan.needsQuery(
        tasks: tasks, scores: Dictionary(uniqueKeysWithValues: scores.map { ($0.taskID, $0) }),
        states: states ?? allStates(tasks), questionVersion: version, provider: provider)
}

@Suite struct ScoringPlanNeedsQueryTests {
    @Test("FR-03 R-206: 같은 입력으로 매긴 판단 결과가 모두 있으면 다시 물을 할 일이 없다")
    func unchanged() {
        let tasks = Fake.todos(1...3)
        #expect(needsQuery(tasks, scores: tasks.map { score($0) }).isEmpty)
    }

    @Test("FR-03 R-206: 판단 결과가 없는 할 일은 다시 묻는다")
    func noScore() {
        let tasks = Fake.todos(1...3)
        #expect(needsQuery(tasks, scores: [score(tasks[0]), score(tasks[2])]) == [2])
    }

    @Test("FR-03 R-206: 질문 버전이 다른 판단 결과는 다시 묻는다")
    func otherVersion() {
        let tasks = Fake.todos(1...2)
        #expect(needsQuery(tasks, scores: [score(tasks[0], version: "v0"), score(tasks[1])]) == [1])
        #expect(needsQuery(tasks, scores: tasks.map { score($0) }, version: "v2") == [1, 2])
    }

    @Test("FR-03 R-206: 판단 입력 해시가 다르면 다시 묻는다(할 일 고침·일정 변경)")
    func otherHash() {
        let tasks = Fake.todos(1...2)
        let changed = edited(Fake.task(2))
        #expect(needsQuery([tasks[0], changed], scores: tasks.map { score($0) }) == [2])

        let context = MokaContext(id: 1, name: "가짜 일정 A", date: Fake.day("2027-01-20"), impact: .normal)
        let withContext = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, state($0, contexts: [context])) })
        #expect(needsQuery(tasks, scores: tasks.map { score($0) }, states: withContext) == [1, 2])
    }

    @Test("FR-03 R-206: 하루가 바뀌면 대기·진행 중 할 일 전부를 다시 묻는다")
    func dayChange() {
        let tasks = Fake.todos(1...3)
        let tomorrow = allStates(tasks, day: Fake.day("2027-01-14"))
        #expect(needsQuery(tasks, scores: tasks.map { score($0) }, states: tomorrow) == [1, 2, 3])
    }

    @Test("FR-03 R-206: 대기·진행 중만 묻고 완료·버림은 판단 결과가 없어도 묻지 않는다")
    func statuses() {
        let tasks = [
            Fake.task(1, status: .todo), Fake.task(2, status: .active), Fake.task(3, status: .done),
            Fake.task(4, status: .dropped),
        ]
        #expect(needsQuery(tasks, scores: []) == [1, 2])
    }

    @Test("FR-03 R-206: 판단 결과가 없는 할 일이 먼저이고, 각 무리 안에서는 id 오름차순")
    func order() {
        let tasks = Fake.todos(1...6)
        let scores = [
            score(tasks[0], hash: "0000000000000000"), score(tasks[2], version: "v0"),
            score(tasks[4], hash: "0000000000000000"), score(tasks[5]),
        ]
        #expect(needsQuery(tasks.reversed(), scores: scores) == [2, 4, 1, 3, 5])
    }

    @Test("FR-03 R-206: 하루가 바뀐 뒤 전체 재질의 줄에서도 저장한 새 할 일이 앞에 선다")
    func newTaskAheadOfDayChange() {
        let old = Fake.todos(1...4)
        let new = Fake.task(5)
        let tomorrow = allStates(old + [new], day: Fake.day("2027-01-14"))
        #expect(needsQuery(old + [new], scores: old.map { score($0) }, states: tomorrow) == [5, 1, 2, 3, 4])
    }

    @Test("ADR-0011 R-611 SC-605: 판단 결과의 공급자가 지금 공급자와 다르면 다시 묻는다")
    func otherProvider() {
        let tasks = Fake.todos(1...3)
        let scores = [
            score(tasks[0], provider: "fake-a"), score(tasks[1], provider: "fake-b"),
            score(tasks[2], provider: "fake-a"),
        ]
        #expect(needsQuery(tasks, scores: scores, provider: "fake-a") == [2])
        #expect(needsQuery(tasks, scores: scores, provider: "fake-b") == [1, 3])
    }

    @Test("ADR-0011 R-611: 공급자가 다른 판단 결과는 순서에서 판단 결과 있음으로 센다")
    func otherProviderCountsAsScored() {
        let tasks = Fake.todos(1...4)
        let scores = [score(tasks[0], provider: "fake-b"), score(tasks[2], provider: "fake-b")]
        #expect(needsQuery(tasks.reversed(), scores: scores, provider: "fake-a") == [2, 4, 1, 3])
    }

    @Test("FR-03 R-206: 판단 입력이 없는 할 일은 입력이 바뀐 것으로 보고 묻는다")
    func missingState() {
        let tasks = Fake.todos(1...2)
        #expect(needsQuery(tasks, scores: tasks.map { score($0) }, states: allStates([tasks[0]])) == [2])
    }
}

@Suite struct ScoringPlanAcceptsTests {
    @Test(
        "FR-03 R-206: 해시가 요청 때와 같고 대기·진행 중일 때만 답을 받는다",
        arguments: [
            ("a", "a", TaskStatus.todo, true), ("a", "a", .active, true), ("a", "b", .todo, false),
            ("a", "b", .active, false), ("a", "a", .done, false), ("a", "a", .dropped, false),
        ])
    func accepts(requestHash: String, currentHash: String, status: TaskStatus, expected: Bool) {
        #expect(
            ScoringPlan.accepts(requestHash: requestHash, currentHash: currentHash, taskStatus: status) == expected)
    }

    @Test("FR-03 R-206: 질의 중 할 일을 고치면 그 답은 버린다")
    func editedDuringQuery() {
        let task = Fake.task(1)
        let requestHash = state(task).hash
        let changed = edited(Fake.task(1))
        #expect(!ScoringPlan.accepts(requestHash: requestHash, currentHash: state(changed).hash, taskStatus: .todo))
    }

    @Test("FR-03 R-206: 질의 중 일정이 바뀌면 그 답은 버린다")
    func contextChangedDuringQuery() {
        let task = Fake.task(1)
        let context = MokaContext(id: 1, name: "가짜 일정 A", date: Fake.day("2027-01-20"), impact: .critical)
        let current = state(task, contexts: [context]).hash
        #expect(!ScoringPlan.accepts(requestHash: state(task).hash, currentHash: current, taskStatus: .todo))
    }

    @Test("FR-03 R-206: 같은 할 일 질의가 겹치면 지금 입력과 맞는 답만 받는다")
    func overlapping() {
        let before = Fake.task(1)
        let after = edited(Fake.task(1))
        let current = state(after).hash
        let answers = [state(before).hash, state(after).hash].map {
            ScoringPlan.accepts(requestHash: $0, currentHash: current, taskStatus: .todo)
        }
        #expect(answers == [false, true])
    }
}
