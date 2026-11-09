import Foundation
import MokaCore
import XCTest
import os

/// 앱 시험이 같이 쓰는 시각·상태·가짜 저장소. 실제 앱 DB를 열지 않는다(ADR-0006). 가짜 할 일만 쓴다.
enum AppTestFixture {
    static let seoul = GregorianCalendar.make(timeZone: TimeZone(identifier: "Asia/Seoul")!)

    /// 2027-01-13(수) 12:00 서울.
    static let noon = at(2027, 1, 13, 12, 0)

    static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        seoul.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

@MainActor
func makeState(
    _ repository: (any TaskRepository)?, settings: any SettingsStore = InMemorySettingsStore(),
    clock: TestClock = TestClock(AppTestFixture.noon), workspaceCenter: NotificationCenter = NotificationCenter(),
    contexts: (any ContextStore)? = InMemoryContextStore()
) -> AppState {
    AppState(
        clock: clock.mokaClock, calendar: AppTestFixture.seoul,
        storage: AppStorage(settings: settings, repository: repository, contexts: contexts),
        workspaceCenter: workspaceCenter)
}

/// 시험이 시각을 앞으로 돌리는 시계. 실제 시간을 기다리지 않는다.
final class TestClock: Sendable {
    private let current: OSAllocatedUnfairLock<Date>

    init(_ start: Date) {
        current = OSAllocatedUnfairLock(initialState: start)
    }

    var mokaClock: MokaClock {
        MokaClock { [current] in current.withLock { $0 } }
    }

    func advance(minutes: Int) {
        advance(seconds: TimeInterval(minutes * 60))
    }

    func advance(seconds: TimeInterval) {
        current.withLock { $0 += seconds }
    }
}

/// `apply`가 늘 throw하는 가짜 저장소. 읽기와 넣기는 안쪽 메모리 저장소를 쓴다.
final class ApplyFailingRepository: TaskRepository {
    struct Failure: Error {}

    let inner = InMemoryTaskRepository()

    func tasks() throws -> [MokaTask] { try inner.tasks() }
    func insertTask(_ task: NewTask, cycleDay: LocalDay?, at: Date) throws -> MokaTask {
        try inner.insertTask(task, cycleDay: cycleDay, at: at)
    }
    func checkpoints() throws -> [Checkpoint] { try inner.checkpoints() }
    func decisions() throws -> [DecisionLogEntry] { try inner.decisions() }
    func apply(_ batch: StoreBatch) throws { throw Failure() }
}

final class FailingAfterStartRepository: TaskRepository {
    struct Failure: Error {}

    let inner = InMemoryTaskRepository()
    var failsApply = false

    func tasks() throws -> [MokaTask] { try inner.tasks() }
    func insertTask(_ task: NewTask, cycleDay: LocalDay?, at: Date) throws -> MokaTask {
        try inner.insertTask(task, cycleDay: cycleDay, at: at)
    }
    func checkpoints() throws -> [Checkpoint] { try inner.checkpoints() }
    func decisions() throws -> [DecisionLogEntry] { try inner.decisions() }
    func apply(_ batch: StoreBatch) throws {
        if failsApply { throw Failure() }
        try inner.apply(batch)
    }
}

final class FailingContextStore: ContextStore {
    struct Failure: Error {}

    func contexts() throws -> [MokaContext] { [] }
    func insertContext(_ context: NewContext) throws -> MokaContext { throw Failure() }
    func deleteContext(id: ContextID) throws { throw Failure() }
    func updateContext(_ context: MokaContext) throws { throw Failure() }
}

final class InsertFailingRepository: TaskRepository {
    struct Failure: Error {}

    func tasks() throws -> [MokaTask] { [] }
    func insertTask(_ task: NewTask, cycleDay: LocalDay?, at: Date) throws -> MokaTask { throw Failure() }
    func checkpoints() throws -> [Checkpoint] { [] }
    func decisions() throws -> [DecisionLogEntry] { [] }
    func apply(_ batch: StoreBatch) throws {}
}
