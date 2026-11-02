import Foundation
import MokaCore
import Testing

/// 공용 계약 시험의 구현 선택(data-model §3). 시험 안에서 새 저장소를 만든다.
/// `grdb`는 GRDB 구현이 들어오는 단위 2(T015)에서 case와 만들기 분기를 함께 더한다.
enum StoreKind: CaseIterable, Sendable {
    case memory

    func makeStores() throws -> (tasks: any TaskRepository, contexts: any ContextStore) {
        switch self {
        case .memory: (InMemoryTaskRepository(), InMemoryContextStore())
        }
    }
}

private let base = Date(timeIntervalSince1970: 1_793_000_000)  // 2026-10-26T07:33:20Z

private func day(_ text: String) -> LocalDay {
    LocalDay(text: text)!
}

private func newTask(
    _ title: String, recurrence: Recurrence = .none, weekday: Int? = nil, deadline: String? = nil, estMin: Int? = nil
) -> NewTask {
    NewTask(
        title: title, deadline: deadline.map(day), estMin: estMin, recurrence: recurrence,
        weekday: weekday.flatMap(Weekday.init(rawValue:)))
}

private func checkpoint(_ taskID: TaskID, _ trigger: CheckpointTrigger, at: Date, done: String = "", next: String = "")
    -> NewCheckpoint
{
    NewCheckpoint(
        taskID: taskID, notes: CheckpointNotes(doneNote: done, nextNote: next), trigger: trigger, elapsedMin: 5,
        createdAt: at)
}

private func decision(_ taskID: TaskID, _ action: UserAction, at: Date, judgment: Judgment? = nil, snapshot: String? = nil)
    -> NewDecisionLogEntry
{
    NewDecisionLogEntry(
        taskID: taskID, judgment: judgment, modelSnapshot: snapshot, schedulerChoice: .rotateByIDV0, userAction: action,
        createdAt: at)
}

// MARK: - 왕복과 id 순서

@Test("FR-01 R-101: 넣은 할 일은 모든 칸이 그대로 돌아오고 id는 1부터 차례로", arguments: StoreKind.allCases)
func taskInsertRoundTrip(kind: StoreKind) throws {
    let repo = try kind.makeStores().tasks
    let a = try repo.insertTask(newTask("가짜 할 일 A", deadline: "2026-11-30", estMin: 30), cycleDay: nil, at: base)
    let b = try repo.insertTask(newTask("가짜 할 일 B", recurrence: .daily), cycleDay: day("2026-10-26"), at: base)
    let c = try repo.insertTask(
        newTask("가짜 할 일 C", recurrence: .weekly, weekday: 4), cycleDay: day("2026-10-21"), at: base.addingTimeInterval(60))

    #expect(
        a
            == MokaTask(
                id: 1, title: "가짜 할 일 A", deadline: day("2026-11-30"), estMin: 30, recurrence: .none, weekday: nil,
                cycleDay: nil, firstAction: nil, status: .todo, skipCount: 0, streak: 0, createdAt: base))
    #expect(b.id == 2 && b.recurrence == .daily && b.cycleDay == day("2026-10-26") && b.weekday == nil)
    #expect(c.id == 3 && c.weekday == Weekday(rawValue: 4) && c.createdAt == base.addingTimeInterval(60))
    #expect(try repo.tasks() == [a, b, c])
}

@Test("FR-01 R-101: apply로 덮어쓴 할 일은 모든 칸이 돌아오고 id·created_at은 바뀌지 않는다", arguments: StoreKind.allCases)
func taskUpdateRoundTrip(kind: StoreKind) throws {
    let repo = try kind.makeStores().tasks
    let original = try repo.insertTask(newTask("가짜 할 일 A"), cycleDay: nil, at: base)
    var updated = original
    updated.title = "가짜 할 일 A 고침"
    updated.deadline = day("2026-12-01")
    updated.estMin = 45
    updated.recurrence = .weekly
    updated.weekday = Weekday(rawValue: 7)
    updated.cycleDay = day("2026-10-24")
    updated.firstAction = "가짜 첫 행동"
    updated.status = .active
    updated.skipCount = 2
    updated.streak = 3
    var sent = updated
    sent.createdAt = base.addingTimeInterval(3_600)
    try repo.apply(StoreBatch(updatedTasks: [sent], newCheckpoints: [], newDecisions: []))
    #expect(try repo.tasks() == [updated])
}

@Test("FR-01 R-101: 목록은 버린 할 일을 포함해 id 오름차순", arguments: StoreKind.allCases)
func tasksIncludeDropped(kind: StoreKind) throws {
    let repo = try kind.makeStores().tasks
    var tasks = try (1...3).map { try repo.insertTask(newTask("가짜 할 일 \($0)"), cycleDay: nil, at: base) }
    tasks[1].status = .dropped
    tasks[2].status = .done
    try repo.apply(StoreBatch(updatedTasks: [tasks[2], tasks[1]], newCheckpoints: [], newDecisions: []))
    #expect(try repo.tasks() == tasks)
    #expect(try repo.tasks().map(\.id) == [1, 2, 3])
}

@Test("FR-07 R-108 FR-11 R-112: 체크포인트와 행동 로그는 모든 칸이 돌아오고 id 오름차순", arguments: StoreKind.allCases)
func checkpointAndDecisionRoundTrip(kind: StoreKind) throws {
    let repo = try kind.makeStores().tasks
    let task = try repo.insertTask(newTask("가짜 할 일 A"), cycleDay: nil, at: base)
    let fallback = Judgment(provider: "fallback", questionVersion: nil, probsJSON: nil, stateHash: nil)
    try repo.apply(
        StoreBatch(
            updatedTasks: [],
            newCheckpoints: [
                checkpoint(task.id, .switch, at: base, done: "가짜 한 일", next: "가짜 다음 일"),
                checkpoint(task.id, .dayEnd, at: base.addingTimeInterval(1)),
            ],
            newDecisions: [
                decision(task.id, .switch, at: base),
                decision(task.id, .done, at: base.addingTimeInterval(1), judgment: fallback, snapshot: "가짜-모델"),
            ]))

    #expect(
        try repo.checkpoints() == [
            Checkpoint(
                id: 1, taskID: task.id, notes: CheckpointNotes(doneNote: "가짜 한 일", nextNote: "가짜 다음 일"),
                trigger: .switch, elapsedMin: 5, createdAt: base),
            Checkpoint(
                id: 2, taskID: task.id, notes: .empty, trigger: .dayEnd, elapsedMin: 5,
                createdAt: base.addingTimeInterval(1)),
        ])
    #expect(
        try repo.decisions() == [
            DecisionLogEntry(
                id: 1, taskID: task.id, judgment: nil, modelSnapshot: nil, schedulerChoice: .rotateByIDV0,
                userAction: .switch, createdAt: base),
            DecisionLogEntry(
                id: 2, taskID: task.id, judgment: fallback, modelSnapshot: "가짜-모델", schedulerChoice: .rotateByIDV0,
                userAction: .done, createdAt: base.addingTimeInterval(1)),
        ])
}

// MARK: - 초 아래 시각

@Test("FR-01 R-101: 초 아래가 있는 시각은 초 단위로 내려 저장하고 돌려준다", arguments: StoreKind.allCases)
func subSecondDatesAreFloored(kind: StoreKind) throws {
    let repo = try kind.makeStores().tasks
    let fine = base.addingTimeInterval(0.987)
    let task = try repo.insertTask(newTask("가짜 할 일 A"), cycleDay: nil, at: fine)
    #expect(task.createdAt == base)
    try repo.apply(
        StoreBatch(
            updatedTasks: [],
            newCheckpoints: [checkpoint(task.id, .quantum, at: base.addingTimeInterval(10.5))],
            newDecisions: [decision(task.id, .done, at: base.addingTimeInterval(20.999))]))
    #expect(try repo.tasks().map(\.createdAt) == [base])
    #expect(try repo.checkpoints().map(\.createdAt) == [base.addingTimeInterval(10)])
    #expect(try repo.decisions().map(\.createdAt) == [base.addingTimeInterval(20)])
}

// MARK: - 묶음 여러 번

@Test("FR-07 R-108 FR-11 R-112: 묶음 셋 이상을 차례로 적용하면 id 순서와 값이 쌓인다", arguments: StoreKind.allCases)
func sequentialBatchesKeepOrder(kind: StoreKind) throws {
    let repo = try kind.makeStores().tasks
    var a = try repo.insertTask(newTask("가짜 할 일 A"), cycleDay: nil, at: base)
    var b = try repo.insertTask(newTask("가짜 할 일 B"), cycleDay: nil, at: base)

    a.status = .active
    try repo.apply(StoreBatch(updatedTasks: [a], newCheckpoints: [], newDecisions: []))
    a.status = .todo
    a.skipCount = 1
    try repo.apply(
        StoreBatch(
            updatedTasks: [a], newCheckpoints: [checkpoint(a.id, .skip, at: base.addingTimeInterval(60), next: "가짜 이어서 A")],
            newDecisions: [decision(a.id, .skip, at: base.addingTimeInterval(60))]))
    b.status = .done
    try repo.apply(
        StoreBatch(
            updatedTasks: [b], newCheckpoints: [checkpoint(b.id, .quantum, at: base.addingTimeInterval(120))],
            newDecisions: [decision(b.id, .done, at: base.addingTimeInterval(120))]))
    a.status = .done
    try repo.apply(
        StoreBatch(
            updatedTasks: [a],
            newCheckpoints: [
                checkpoint(a.id, .quit, at: base.addingTimeInterval(180)),
                checkpoint(a.id, .sleep, at: base.addingTimeInterval(181)),
            ],
            newDecisions: [decision(a.id, .done, at: base.addingTimeInterval(180))]))

    #expect(try repo.tasks() == [a, b])
    #expect(try repo.checkpoints().map(\.id) == [1, 2, 3, 4])
    #expect(try repo.checkpoints().map(\.taskID) == [a.id, b.id, a.id, a.id])
    #expect(try repo.checkpoints().map(\.trigger) == [.skip, .quantum, .quit, .sleep])
    #expect(try repo.checkpoints().first?.notes == CheckpointNotes(doneNote: "", nextNote: "가짜 이어서 A"))
    #expect(try repo.decisions().map(\.id) == [1, 2, 3])
    #expect(try repo.decisions().map(\.userAction) == [.skip, .done, .done])
    #expect(try repo.decisions().map(\.taskID) == [a.id, b.id, a.id])
}

// MARK: - 원자성과 없는 할 일

@Test("FR-01 R-101: apply 도중 실패하면 아무것도 남지 않는다", arguments: StoreKind.allCases)
func applyIsAtomic(kind: StoreKind) throws {
    let repo = try kind.makeStores().tasks
    let original = try repo.insertTask(newTask("가짜 할 일 A"), cycleDay: nil, at: base)
    var changed = original
    changed.status = .done

    let missingCheckpoint = StoreBatch(
        updatedTasks: [changed], newCheckpoints: [checkpoint(original.id, .quantum, at: base), checkpoint(99, .quantum, at: base)],
        newDecisions: [decision(original.id, .done, at: base)])
    #expect(throws: StoreError.taskNotFound(99)) { try repo.apply(missingCheckpoint) }

    let missingDecision = StoreBatch(
        updatedTasks: [changed], newCheckpoints: [checkpoint(original.id, .quantum, at: base)],
        newDecisions: [decision(original.id, .done, at: base), decision(42, .done, at: base)])
    #expect(throws: StoreError.taskNotFound(42)) { try repo.apply(missingDecision) }

    var ghost = changed
    ghost.id = 7
    let missingTask = StoreBatch(updatedTasks: [changed, ghost], newCheckpoints: [], newDecisions: [])
    #expect(throws: StoreError.taskNotFound(7)) { try repo.apply(missingTask) }

    #expect(try repo.tasks() == [original])
    #expect(try repo.checkpoints().isEmpty)
    #expect(try repo.decisions().isEmpty)

    // 실패한 묶음이 id를 쓰지 않는다.
    try repo.apply(StoreBatch(updatedTasks: [], newCheckpoints: [checkpoint(original.id, .quantum, at: base)], newDecisions: []))
    #expect(try repo.checkpoints().map(\.id) == [1])
}

@Test("FR-01 R-101: 빈 묶음은 아무것도 바꾸지 않는다", arguments: StoreKind.allCases)
func emptyBatchChangesNothing(kind: StoreKind) throws {
    let repo = try kind.makeStores().tasks
    let task = try repo.insertTask(newTask("가짜 할 일 A"), cycleDay: nil, at: base)
    try repo.apply(.empty)
    #expect(try repo.tasks() == [task])
    #expect(try repo.checkpoints().isEmpty)
    #expect(try repo.decisions().isEmpty)
}

// MARK: - 짝 규칙(§7 CHECK와 같은 규칙)

@Test("FR-09 R-113: 반복인데 cycle_day가 없거나 반복 없음인데 있으면 거부", arguments: StoreKind.allCases)
func cycleDayPairsWithRecurrence(kind: StoreKind) throws {
    let repo = try kind.makeStores().tasks
    #expect(throws: StoreError.invalidValue(column: "cycle_day")) {
        try repo.insertTask(newTask("가짜 할 일 A", recurrence: .daily), cycleDay: nil, at: base)
    }
    #expect(throws: StoreError.invalidValue(column: "cycle_day")) {
        try repo.insertTask(newTask("가짜 할 일 B"), cycleDay: day("2026-10-26"), at: base)
    }
    #expect(try repo.tasks().isEmpty)

    let task = try repo.insertTask(newTask("가짜 할 일 C", recurrence: .daily), cycleDay: day("2026-10-26"), at: base)
    var broken = task
    broken.cycleDay = nil
    #expect(throws: StoreError.invalidValue(column: "cycle_day")) {
        try repo.apply(StoreBatch(updatedTasks: [broken], newCheckpoints: [], newDecisions: []))
    }
    #expect(try repo.tasks() == [task])
}

@Test("FR-01 R-101: 요일은 매주일 때만 있어야 저장된다", arguments: StoreKind.allCases)
func weekdayPairsWithWeeklyInStore(kind: StoreKind) throws {
    let repo = try kind.makeStores().tasks
    #expect(throws: StoreError.invalidValue(column: "weekday")) {
        try repo.insertTask(newTask("가짜 할 일 A", recurrence: .weekly), cycleDay: day("2026-10-26"), at: base)
    }
    #expect(throws: StoreError.invalidValue(column: "weekday")) {
        try repo.insertTask(newTask("가짜 할 일 B", recurrence: .daily, weekday: 2), cycleDay: day("2026-10-26"), at: base)
    }
    #expect(try repo.tasks().isEmpty)
}

@Test("FR-11 R-112: 판단 공급자 없이 model_snapshot이 있는 줄은 거부하고, 공급자만 있는 폴백 줄은 받는다", arguments: StoreKind.allCases)
func judgmentColumnsNeedProvider(kind: StoreKind) throws {
    let repo = try kind.makeStores().tasks
    let task = try repo.insertTask(newTask("가짜 할 일 A"), cycleDay: nil, at: base)
    #expect(throws: StoreError.invalidValue(column: "model_snapshot")) {
        try repo.apply(
            StoreBatch(updatedTasks: [], newCheckpoints: [], newDecisions: [decision(task.id, .done, at: base, snapshot: "가짜-모델")]))
    }
    #expect(try repo.decisions().isEmpty)

    let fallback = Judgment(provider: "fallback", questionVersion: nil, probsJSON: nil, stateHash: nil)
    try repo.apply(
        StoreBatch(updatedTasks: [], newCheckpoints: [], newDecisions: [decision(task.id, .done, at: base, judgment: fallback)]))
    #expect(try repo.decisions().map(\.judgment) == [fallback])
}

// MARK: - 컨텍스트

@Test("FR-02 R-115: 컨텍스트는 모든 칸이 돌아오고 날짜 오름차순, 같으면 id 순", arguments: StoreKind.allCases)
func contextRoundTripAndOrder(kind: StoreKind) throws {
    let store = try kind.makeStores().contexts
    let a = try store.insertContext(NewContext(name: "가짜 일정 A", date: day("2026-11-20"), impact: .critical))
    let b = try store.insertContext(NewContext(name: "가짜 일정 B", date: day("2026-11-05"), impact: .normal))
    let c = try store.insertContext(NewContext(name: "가짜 일정 C", date: day("2026-11-20"), impact: .high))
    #expect(a == MokaContext(id: 1, name: "가짜 일정 A", date: day("2026-11-20"), impact: .critical))
    #expect(b.id == 2 && c.id == 3)
    #expect(try store.contexts() == [b, a, c])
}

@Test("FR-02 R-115: 컨텍스트를 지우면 목록에서 빠지고, 없는 id는 contextNotFound", arguments: StoreKind.allCases)
func contextDelete(kind: StoreKind) throws {
    let store = try kind.makeStores().contexts
    let a = try store.insertContext(NewContext(name: "가짜 일정 A", date: day("2026-11-20"), impact: .normal))
    let b = try store.insertContext(NewContext(name: "가짜 일정 B", date: day("2026-11-21"), impact: .normal))
    try store.deleteContext(id: a.id)
    #expect(try store.contexts() == [b])
    #expect(throws: StoreError.contextNotFound(a.id)) { try store.deleteContext(id: a.id) }
    #expect(throws: StoreError.contextNotFound(99)) { try store.deleteContext(id: 99) }
    #expect(try store.contexts() == [b])
}
