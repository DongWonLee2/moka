import Foundation

public enum StoreError: Error, Equatable, Sendable {
    /// 열거형에 없는 값을 읽음(P3).
    case unknownValue(column: String, value: String)
    /// 형식이 틀린 날짜·시각 등.
    case invalidValue(column: String)
    case taskNotFound(TaskID)
    case contextNotFound(ContextID)
}

/// 버튼 한 번(또는 설정 창 고침·지움 한 번)의 쓰기 묶음. 저장소가 한 트랜잭션으로 적용한다. 하나라도 실패하면 아무것도 남지 않는다.
public struct StoreBatch: Equatable, Sendable {
    /// id 기준으로 통째로 덮어씀(id, created_at은 바꾸지 않음).
    public var updatedTasks: [MokaTask]
    public var newCheckpoints: [NewCheckpoint]
    public var newDecisions: [NewDecisionLogEntry]

    public static let empty = StoreBatch()

    public init(
        updatedTasks: [MokaTask] = [], newCheckpoints: [NewCheckpoint] = [], newDecisions: [NewDecisionLogEntry] = []
    ) {
        self.updatedTasks = updatedTasks
        self.newCheckpoints = newCheckpoints
        self.newDecisions = newDecisions
    }
}

public protocol TaskRepository: AnyObject {
    /// 버림 포함, id 오름차순.
    func tasks() throws -> [MokaTask]
    func insertTask(_ task: NewTask, cycleDay: LocalDay?, at: Date) throws -> MokaTask
    /// id 오름차순.
    func checkpoints() throws -> [Checkpoint]
    /// id 오름차순.
    func decisions() throws -> [DecisionLogEntry]
    func apply(_ batch: StoreBatch) throws
}

public protocol ContextStore: AnyObject {
    /// date 오름차순, 같으면 id.
    func contexts() throws -> [MokaContext]
    func insertContext(_ context: NewContext) throws -> MokaContext
    /// 실제로 지운다(research R4).
    func deleteContext(id: ContextID) throws
}

// MARK: - 메모리 구현(시험·`moka-sim`). GRDB 구현과 같은 규칙(data-model §3, §7 CHECK)을 지킨다.

public final class InMemoryTaskRepository: TaskRepository {
    private var storedTasks: [MokaTask] = []
    private var storedCheckpoints: [Checkpoint] = []
    private var storedDecisions: [DecisionLogEntry] = []

    public init() {}

    public func tasks() throws -> [MokaTask] {
        storedTasks
    }

    public func insertTask(_ task: NewTask, cycleDay: LocalDay?, at: Date) throws -> MokaTask {
        let inserted = MokaTask(
            id: (storedTasks.last?.id ?? 0) + 1, title: task.title, deadline: task.deadline, estMin: task.estMin,
            recurrence: task.recurrence, weekday: task.weekday, cycleDay: cycleDay, firstAction: nil, status: .todo,
            skipCount: 0, streak: 0, createdAt: UTCTimestamp.floorToSecond(at))
        try Self.check(inserted)
        storedTasks.append(inserted)
        return inserted
    }

    public func checkpoints() throws -> [Checkpoint] {
        storedCheckpoints
    }

    public func decisions() throws -> [DecisionLogEntry] {
        storedDecisions
    }

    /// 사본에 모두 적용한 뒤 끝까지 성공했을 때만 바꾼다(되돌림).
    public func apply(_ batch: StoreBatch) throws {
        var tasks = storedTasks
        var checkpoints = storedCheckpoints
        var decisions = storedDecisions

        for update in batch.updatedTasks {
            guard let index = tasks.firstIndex(where: { $0.id == update.id }) else {
                throw StoreError.taskNotFound(update.id)
            }
            try Self.check(update)
            var replaced = update
            replaced.createdAt = tasks[index].createdAt
            tasks[index] = replaced
        }
        for new in batch.newCheckpoints {
            guard tasks.contains(where: { $0.id == new.taskID }) else { throw StoreError.taskNotFound(new.taskID) }
            checkpoints.append(
                Checkpoint(
                    id: (checkpoints.last?.id ?? 0) + 1, taskID: new.taskID, notes: new.notes, trigger: new.trigger,
                    elapsedMin: new.elapsedMin, createdAt: UTCTimestamp.floorToSecond(new.createdAt)))
        }
        for new in batch.newDecisions {
            guard tasks.contains(where: { $0.id == new.taskID }) else { throw StoreError.taskNotFound(new.taskID) }
            if new.judgment == nil, new.modelSnapshot != nil { throw StoreError.invalidValue(column: "model_snapshot") }
            decisions.append(
                DecisionLogEntry(
                    id: (decisions.last?.id ?? 0) + 1, taskID: new.taskID, judgment: new.judgment,
                    modelSnapshot: new.modelSnapshot, schedulerChoice: new.schedulerChoice, userAction: new.userAction,
                    createdAt: UTCTimestamp.floorToSecond(new.createdAt)))
        }

        storedTasks = tasks
        storedCheckpoints = checkpoints
        storedDecisions = decisions
    }

    /// `tasks` 표 CHECK의 짝 규칙(data-model §7).
    private static func check(_ task: MokaTask) throws {
        guard MokaTask.isValidWeekday(task.weekday, recurrence: task.recurrence) else {
            throw StoreError.invalidValue(column: "weekday")
        }
        guard (task.recurrence == .none) == (task.cycleDay == nil) else {
            throw StoreError.invalidValue(column: "cycle_day")
        }
    }
}

public final class InMemoryContextStore: ContextStore {
    private var stored: [MokaContext] = []

    public init() {}

    public func contexts() throws -> [MokaContext] {
        stored.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    /// id는 SQLite `INTEGER PRIMARY KEY`처럼 지금 있는 가장 큰 id + 1.
    public func insertContext(_ context: NewContext) throws -> MokaContext {
        let inserted = MokaContext(
            id: (stored.map(\.id).max() ?? 0) + 1, name: context.name, date: context.date, impact: context.impact)
        stored.append(inserted)
        return inserted
    }

    public func deleteContext(id: ContextID) throws {
        guard let index = stored.firstIndex(where: { $0.id == id }) else { throw StoreError.contextNotFound(id) }
        stored.remove(at: index)
    }
}
