import Foundation
import MokaCore
import XCTest
import os

/// spec 002 단위 5: 앱 수명 연결(#58). `AppState`가 저장소를 잇는 순서만 본다. 순수 규칙은 MokaCore 시험이 맡는다.
/// 저장소는 메모리 구현과 가짜만 쓴다. 실제 앱 DB를 열지 않는다(ADR-0006). 가짜 할 일만 쓴다.
@MainActor
final class AppLifecycleTests: XCTestCase {
    private static let seoul = GregorianCalendar.make(timeZone: TimeZone(identifier: "Asia/Seoul")!)

    /// 2027-01-13(수) 12:00 서울.
    private static let noon = at(2027, 1, 13, 12, 0)

    private static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        seoul.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeState(
        _ repository: (any TaskRepository)?, settings: any SettingsStore = InMemorySettingsStore(),
        clock: TestClock = TestClock(noon), workspaceCenter: NotificationCenter = NotificationCenter()
    ) -> AppState {
        AppState(
            clock: clock.mokaClock, calendar: Self.seoul,
            storage: AppStorage(settings: settings, repository: repository, contexts: InMemoryContextStore()),
            workspaceCenter: workspaceCenter)
    }

    private static func seeded(_ count: Int) throws -> InMemoryTaskRepository {
        let repository = InMemoryTaskRepository()
        for index in 0..<count {
            _ = try repository.insertTask(
                NewTask(title: "가짜 할 일 \(index + 1)", deadline: nil, estMin: nil, recurrence: .none, weekday: nil),
                cycleDay: nil, at: noon)
        }
        return repository
    }

    // MARK: - R-119 DB 열기 실패

    func test_FR11_R119_openFailureKeepsSettingsInMemoryAndMakesNoTaskStore() throws {
        var attempts = 0
        let storage = AppStorage.open {
            attempts += 1
            throw OpenFailure()
        }

        XCTAssertEqual(attempts, 1, "실패한 뒤 다시 열거나 새로 만들지 않는다")
        XCTAssertNil(storage.repository, "할 일 저장소를 메모리로 대체하지 않는다")
        XCTAssertNil(storage.contexts, "일정 저장소를 메모리로 대체하지 않는다")
        XCTAssertTrue(storage.isUnavailable)
        try storage.settings.setValue("40", for: QuantumSettings.key)
        XCTAssertEqual(QuantumSettings.readDefault(from: storage.settings), 40, "설정만 메모리로 동작한다")
    }

    func test_FR11_R119_openSuccessHandsOutTheSameStores() {
        let repository = InMemoryTaskRepository()
        let contexts = InMemoryContextStore()
        let storage = AppStorage.open {
            AppStorage(settings: InMemorySettingsStore(), repository: repository, contexts: contexts)
        }

        XCTAssertTrue(storage.repository === repository)
        XCTAssertTrue(storage.contexts === contexts)
        XCTAssertFalse(storage.isUnavailable)
    }

    func test_FR11_R119_unavailableStorageRunsTimerOnly() {
        let state = makeState(nil)
        state.launch()

        XCTAssertTrue(state.storageUnavailable)
        state.enterTitle("가짜 할 일 A")
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 A", chipMin: 25)))
        XCTAssertNil(state.session.taskID)
        state.start()
        guard case .running = state.timer else { return XCTFail("저장할 수 없어도 spec 001 타이머는 돈다: \(state.timer)") }
    }

    func test_FR11_R119_failedWriteKeepsSessionAndTasks() throws {
        let repository = ApplyFailingRepository()
        _ = try repository.inner.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: Self.noon)
        let state = makeState(repository)
        state.launch()
        let before = state.session

        state.start()

        XCTAssertEqual(state.session, before, "쓰기가 실패하면 세션을 바꾸지 않는다")
        XCTAssertEqual(state.tasks.map(\.status), [.todo])
    }

    // MARK: - R-111 켤 때 복구 → 하루 판정 → 고르기

    func test_FR07_R111_launchRevertsActiveTaskThenPicks() throws {
        let repository = try Self.seeded(3)
        var active = try repository.tasks()[1]
        active.status = .active
        try repository.apply(StoreBatch(updatedTasks: [active]))
        let state = makeState(repository)

        state.launch()

        XCTAssertEqual(try repository.tasks().map(\.status), [.todo, .todo, .todo])
        XCTAssertEqual(state.tasks.map(\.status), [.todo, .todo, .todo])
        XCTAssertEqual(state.session.taskID, 1)
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 1", chipMin: 25)))
        XCTAssertEqual(state.pickedAt, Self.noon)
    }

    func test_FR07_R111_launchWithoutTasksStaysEmpty() {
        let state = makeState(InMemoryTaskRepository())
        state.launch()

        XCTAssertFalse(state.storageUnavailable)
        XCTAssertEqual(state.session, .initial)
        XCTAssertNil(state.pickedAt)
    }

    // MARK: - R-113 활성화 판정

    func test_FR09_R113_launchActivationResetsDailyTaskDoneYesterday() throws {
        let repository = InMemoryTaskRepository()
        var daily = try repository.insertTask(
            NewTask(title: "가짜 매일 할 일", deadline: nil, estMin: nil, recurrence: .daily, weekday: nil),
            cycleDay: LocalDay(text: "2027-01-12"), at: Self.noon)
        daily.status = .done
        daily.streak = 1
        try repository.apply(StoreBatch(updatedTasks: [daily]))
        let state = makeState(repository)

        state.launch()

        let reset = try XCTUnwrap(try repository.tasks().first)
        XCTAssertEqual(reset.status, .todo)
        XCTAssertEqual(reset.streak, 1, "어제 몫을 끝냈으면 연속 기록을 잇는다")
        XCTAssertEqual(reset.cycleDay, LocalDay(text: "2027-01-13"))
        XCTAssertEqual(state.session.taskID, reset.id, "빈 상태에서 판정이 돈 뒤 고른다")
    }

    func test_FR09_R113_activateAgainOnSameDayChangesNothing() throws {
        let repository = InMemoryTaskRepository()
        _ = try repository.insertTask(
            NewTask(title: "가짜 매일 할 일", deadline: nil, estMin: nil, recurrence: .daily, weekday: nil),
            cycleDay: LocalDay(text: "2027-01-10"), at: Self.noon)
        let state = makeState(repository)
        state.launch()
        let afterLaunch = try repository.tasks()

        state.activate()

        XCTAssertEqual(try repository.tasks(), afterLaunch)
    }

    // MARK: - 실제 연결 경로(알림·노치 펼침)

    /// 오늘(2027-01-13) 몫을 이미 끝낸 매일 할 일 하나. 켤 때는 판정 대상이 아니다.
    private static func doneDailyToday() throws -> InMemoryTaskRepository {
        let repository = InMemoryTaskRepository()
        var daily = try repository.insertTask(
            NewTask(title: "가짜 매일 할 일", deadline: nil, estMin: nil, recurrence: .daily, weekday: nil),
            cycleDay: LocalDay(text: "2027-01-13"), at: noon)
        daily.status = .done
        daily.streak = 1
        try repository.apply(StoreBatch(updatedTasks: [daily]))
        return repository
    }

    func test_FR09_R113_wakeNotificationRunsActivationAfterDayBoundary() throws {
        let repository = try Self.doneDailyToday()
        let clock = TestClock(Self.noon)
        let center = NotificationCenter()
        let state = makeState(repository, clock: clock, workspaceCenter: center)
        state.launch()
        XCTAssertEqual(state.tasks.map(\.status), [.done])

        clock.advance(minutes: 19 * 60)  // 2027-01-14 07:00
        center.post(name: NSWorkspace.didWakeNotification, object: nil)

        let reset = try XCTUnwrap(try repository.tasks().first)
        XCTAssertEqual(reset.status, .todo)
        XCTAssertEqual(reset.cycleDay, LocalDay(text: "2027-01-14"))
        XCTAssertEqual(state.session.taskID, reset.id)
    }

    func test_FR07_R110_willSleepNotificationSavesSleepCheckpoint() throws {
        let repository = try Self.seeded(1)
        let clock = TestClock(Self.noon)
        let center = NotificationCenter()
        let state = makeState(repository, clock: clock, workspaceCenter: center)
        state.launch()
        state.start()
        clock.advance(minutes: 4)

        center.post(name: NSWorkspace.willSleepNotification, object: nil)

        XCTAssertEqual(try repository.checkpoints().map(\.trigger), [.sleep])
        XCTAssertEqual(try repository.checkpoints().map(\.elapsedMin), [4])
        guard case .running = state.timer else { return XCTFail("잠자기는 타이머를 그대로 둔다: \(state.timer)") }
    }

    func test_FR09_R113_notchExpansionRunsActivationAfterDayBoundary() throws {
        let repository = try Self.doneDailyToday()
        let clock = TestClock(Self.noon)
        let state = makeState(repository, clock: clock)
        state.launch()

        clock.advance(minutes: 18 * 60 + 1)  // 2027-01-14 06:01
        state.setHovering(true)

        XCTAssertTrue(state.isExpanded)
        let reset = try XCTUnwrap(try repository.tasks().first)
        XCTAssertEqual(reset.status, .todo)
        XCTAssertEqual(reset.streak, 1)
        XCTAssertEqual(state.session.taskID, reset.id)
    }

    // MARK: - R-104 버튼 뒤 다시 읽고 고르기

    func test_FR05_R104_completeRereadsTasksAndPicksNext() throws {
        let repository = try Self.seeded(2)
        let clock = TestClock(Self.noon)
        let state = makeState(repository, clock: clock)
        state.launch()
        state.start()
        XCTAssertEqual(try repository.tasks().map(\.status), [.active, .todo])

        clock.advance(minutes: 10)
        state.complete()

        XCTAssertEqual(try repository.tasks().map(\.status), [.done, .todo])
        XCTAssertEqual(state.tasks.map(\.status), [.done, .todo])
        XCTAssertEqual(try repository.decisions().map(\.userAction), [.done])
        XCTAssertEqual(state.session.taskID, 2)
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 2", chipMin: 25)))
        XCTAssertEqual(state.pickedAt, Self.noon.addingTimeInterval(600))
    }

    // MARK: - R-103 빠른 입력

    func test_FR01_R103_quickEntryInsertsTaskAndDraftsIt() throws {
        let repository = InMemoryTaskRepository()
        let state = makeState(repository)
        state.launch()

        state.enterTitle("  가짜 할 일 A ")

        let inserted = try XCTUnwrap(try repository.tasks().first)
        XCTAssertEqual(inserted.title, "가짜 할 일 A")
        XCTAssertEqual(state.session.taskID, inserted.id)
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 A", chipMin: 25)))
        XCTAssertEqual(state.tasks, [inserted])
    }

    func test_FR01_R103_blankQuickEntryWritesNothing() throws {
        let repository = InMemoryTaskRepository()
        let state = makeState(repository)
        state.launch()

        state.enterTitle("   ")

        XCTAssertEqual(try repository.tasks(), [])
        XCTAssertEqual(state.session, .initial)
    }

    // MARK: - R-110 종료·잠자기 체크포인트

    func test_FR07_R110_quitWhileRunningSavesEmptyCheckpointAndKeepsState() throws {
        let repository = try Self.seeded(1)
        let clock = TestClock(Self.noon)
        let state = makeState(repository, clock: clock)
        state.launch()
        state.start()
        clock.advance(minutes: 7)

        state.lifecycleCheckpoint(.quit)

        let checkpoint = try XCTUnwrap(try repository.checkpoints().first)
        XCTAssertEqual(checkpoint.trigger, .quit)
        XCTAssertEqual(checkpoint.elapsedMin, 7)
        XCTAssertEqual(checkpoint.notes, .empty)
        XCTAssertEqual(try repository.tasks().map(\.status), [.active], "종료는 상태를 바꾸지 않는다")
        guard case .running = state.timer else { return XCTFail("타이머는 그대로: \(state.timer)") }
    }

    func test_FR07_R110_sleepWhileRunningSavesSleepCheckpoint() throws {
        let repository = try Self.seeded(1)
        let clock = TestClock(Self.noon)
        let state = makeState(repository, clock: clock)
        state.launch()
        state.start()
        clock.advance(minutes: 3)

        state.lifecycleCheckpoint(.sleep)

        XCTAssertEqual(try repository.checkpoints().map(\.trigger), [.sleep])
        XCTAssertEqual(try repository.checkpoints().map(\.elapsedMin), [3])
    }

    func test_FR07_R110_noCheckpointUnlessRunning() throws {
        let repository = try Self.seeded(1)
        let clock = TestClock(Self.noon)
        let state = makeState(repository, clock: clock)
        state.launch()
        state.lifecycleCheckpoint(.quit)
        state.start()
        clock.advance(minutes: 26)
        state.lifecycleCheckpoint(.sleep)

        XCTAssertEqual(try repository.checkpoints(), [], "초안·시간 끝에서는 남기지 않는다")
    }

    // MARK: - #35 tick마다 설정을 읽지 않음

    func test_issue35_tickDoesNotReadSettings() throws {
        let settings = CountingSettingsStore()
        let repository = try Self.seeded(1)
        let clock = TestClock(Self.noon)
        let state = makeState(repository, settings: settings, clock: clock)
        state.launch()
        state.start()
        let reads = settings.quantumReads

        for _ in 0..<5 {
            clock.advance(minutes: 1)
            state.tick()
        }

        XCTAssertEqual(settings.quantumReads, reads)
    }

    func test_issue35_defaultQuantumChangeIsReadOnceAndUsed() throws {
        let settings = CountingSettingsStore()
        let state = makeState(try Self.seeded(2), settings: settings)
        state.launch()
        let reads = settings.quantumReads

        try QuantumSettings.writeDefault(40, to: settings)
        state.defaultQuantumChanged()

        XCTAssertEqual(settings.quantumReads, reads + 1)
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 1", chipMin: 40)))
    }

    // MARK: - R-102·R-118 할 일 탭

    func test_FR01_R118_taskListStartsAllCreatedWithNextMark() throws {
        let state = makeState(try Self.seeded(3))
        state.launch()

        XCTAssertEqual(state.taskListScope, .all)
        XCTAssertEqual(state.taskListOrder, .created)
        XCTAssertEqual(state.taskListRows.map(\.title), ["가짜 할 일 1", "가짜 할 일 2", "가짜 할 일 3"])
        XCTAssertEqual(state.nextMarkID, state.taskListRows.first?.id, "초안이면 노치의 할 일에 다음 표시")
    }

    func test_FR01_R118_scopeChangesRowsButNotNextMark() throws {
        let state = makeState(try Self.seeded(2))
        state.launch()
        let mark = state.nextMarkID
        let before = state.session

        state.taskListScope = .today
        XCTAssertEqual(state.taskListRows, [], "마감 없는 일반 할 일은 전체에만")
        XCTAssertEqual(state.nextMarkID, mark, "보기는 노치 고르기를 바꾸지 않는다")
        XCTAssertEqual(state.session, before)
    }

    /// 오늘 보기는 하루 시작 시각(06:00) 기준이다(R-114). 05:59는 아직 어제라 오늘 마감 할 일은 빠진다.
    func test_FR01_R118_todayScopeFollowsDayStart() throws {
        let repository = InMemoryTaskRepository()
        for (title, deadline) in [("가짜 할 일 어제 마감", "2027-01-12"), ("가짜 할 일 오늘 마감", "2027-01-13")] {
            _ = try repository.insertTask(
                NewTask(
                    title: title, deadline: LocalDay(text: deadline), estMin: nil, recurrence: .none, weekday: nil),
                cycleDay: nil, at: Self.at(2027, 1, 12, 9, 0))
        }
        let clock = TestClock(Self.at(2027, 1, 13, 5, 59))
        let state = makeState(repository, clock: clock)
        state.launch()
        state.taskListScope = .today

        XCTAssertEqual(state.taskListRows.map(\.title), ["가짜 할 일 어제 마감"])
        clock.advance(minutes: 1)
        XCTAssertEqual(state.taskListRows.map(\.title), ["가짜 할 일 어제 마감", "가짜 할 일 오늘 마감"])
    }

    // MARK: - #37 알림 처리기 해제

    func test_issue37_observationStopsWhenReleased() {
        let center = NotificationCenter()
        let name = Notification.Name("dev.dongwon.moka.test")
        var calls = 0
        var observation: NotificationObservation? = NotificationObservation(center: center, name: name) {
            calls += 1
        }
        center.post(name: name, object: nil)
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(observation)

        observation = nil
        center.post(name: name, object: nil)

        XCTAssertEqual(calls, 1)
    }
}

private struct OpenFailure: Error {}

/// 시험이 시각을 앞으로 돌리는 시계. 실제 시간을 기다리지 않는다.
private final class TestClock: Sendable {
    private let current: OSAllocatedUnfairLock<Date>

    init(_ start: Date) {
        current = OSAllocatedUnfairLock(initialState: start)
    }

    var mokaClock: MokaClock {
        MokaClock { [current] in current.withLock { $0 } }
    }

    func advance(minutes: Int) {
        current.withLock { $0 += TimeInterval(minutes * 60) }
    }
}

/// `apply`가 늘 throw하는 가짜 저장소. 읽기와 넣기는 안쪽 메모리 저장소를 쓴다.
private final class ApplyFailingRepository: TaskRepository {
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

/// 기본 작업 시간 읽기 횟수를 센다.
private final class CountingSettingsStore: SettingsStore {
    private let inner = InMemorySettingsStore()
    private(set) var quantumReads = 0

    func value(for key: String) throws -> String? {
        if key == QuantumSettings.key {
            quantumReads += 1
        }
        return try inner.value(for: key)
    }

    func setValue(_ value: String, for key: String) throws {
        try inner.setValue(value, for: key)
    }
}
