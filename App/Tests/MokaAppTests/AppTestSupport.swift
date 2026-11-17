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
    contexts: (any ContextStore)? = InMemoryContextStore(), scores: (any ScoreStore)? = nil,
    decision: DecisionSetup? = nil, budgetAnswered: Bool = true
) -> AppState {
    let settings = budgetAnswered ? AnsweredBudgetSettings(inner: settings, clock: clock) : settings
    return AppState(
        clock: clock.mokaClock, calendar: AppTestFixture.seoul,
        storage: AppStorage(settings: settings, repository: repository, contexts: contexts, scores: scores),
        workspaceCenter: workspaceCenter, decision: decision)
}

/// 가용 시간 질문(spec 005 R-419)이 없던 때 쓴 시험이 같은 흐름을 보게 하는 설정 저장소. 오늘 `day_budget`이 없으면
/// 그날 상한 없음(`more: true`)을 답한 것으로 돌려준다. 그래서 이 저장소를 쓰는 시험은 "상한 없는 하루"만 본다.
/// 질문·늘리기·오늘 끝은 `makeState(..., budgetAnswered: false)`를 쓰는 `AppBudgetTests`와 스냅샷이 본다.
final class AnsweredBudgetSettings: SettingsStore {
    private let inner: any SettingsStore
    private let clock: TestClock

    init(inner: any SettingsStore, clock: TestClock) {
        self.inner = inner
        self.clock = clock
    }

    func value(for key: String) throws -> String? {
        let stored = try inner.value(for: key)
        guard key == CoreSettings.dayBudgetKey else { return stored }
        let today = DayBoundary.day(
            containing: clock.mokaClock.now(), dayStart: CoreSettings.readDayStart(from: inner),
            calendar: AppTestFixture.seoul)
        if let stored, DayBudget(json: stored)?.day == today { return stored }
        return DayBudget(day: today, minutes: 0, extendedMinutes: 0, usedSeconds: 0, more: true).json
    }

    func setValue(_ value: String, for key: String) throws {
        try inner.setValue(value, for: key)
    }
}

/// `day_budget` 쓰기만 실패시킬 수 있는 설정 저장소.
final class BudgetWriteFailingSettings: SettingsStore {
    struct Failure: Error {}

    let inner = InMemorySettingsStore()
    var failsBudgetWrite = false

    func value(for key: String) throws -> String? { try inner.value(for: key) }
    func setValue(_ value: String, for key: String) throws {
        if failsBudgetWrite, key == CoreSettings.dayBudgetKey { throw Failure() }
        try inner.setValue(value, for: key)
    }
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

    func advanceToNextDay(hour: Int, minute: Int = 0) {
        let calendar = AppTestFixture.seoul
        current.withLock { now in
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            now = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: nextDay)!
        }
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
    func lastCarryJudgment() throws -> Date? { try inner.lastCarryJudgment() }
    func applyCarryJudgment(_ batch: StoreBatch, judgedAt: Date) throws { throw Failure() }
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
    func lastCarryJudgment() throws -> Date? { try inner.lastCarryJudgment() }
    func applyCarryJudgment(_ batch: StoreBatch, judgedAt: Date) throws {
        if failsApply { throw Failure() }
        try inner.applyCarryJudgment(batch, judgedAt: judgedAt)
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
    func lastCarryJudgment() throws -> Date? { nil }
    func applyCarryJudgment(_ batch: StoreBatch, judgedAt: Date) throws {}
}
