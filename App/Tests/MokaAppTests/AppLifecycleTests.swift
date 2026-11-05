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

    // MARK: - R-101·R-102 설정 창 할 일 추가(#70)

    func test_FR01_R102_addFromSettingsPicksWhenEmpty() throws {
        let repository = InMemoryTaskRepository()
        let state = makeState(repository)
        state.launch()

        XCTAssertTrue(
            state.addTask(NewTask(title: " 가짜 할 일 새것 ", deadline: nil, estMin: 30, recurrence: .none, weekday: nil)))
        XCTAssertEqual(try repository.tasks().map(\.title), ["가짜 할 일 새것"])
        XCTAssertEqual(state.tasks.map(\.title), ["가짜 할 일 새것"], "추가 뒤 tasks()를 다시 읽는다")
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 새것", chipMin: 25)), "빈 상태면 고른다")
        XCTAssertEqual(state.pickedAt, Self.noon)
    }

    func test_FR01_R102_addFromSettingsKeepsDraft() throws {
        let state = makeState(try Self.seeded(1))
        state.launch()
        let before = state.session

        XCTAssertTrue(
            state.addTask(NewTask(title: "가짜 할 일 2", deadline: nil, estMin: nil, recurrence: .daily, weekday: nil)))
        XCTAssertEqual(state.tasks.count, 2)
        XCTAssertEqual(state.session, before, "초안이 있으면 그대로(#70)")
    }

    func test_FR01_R101_addFromSettingsRejectsBlankTitle() throws {
        let repository = InMemoryTaskRepository()
        let state = makeState(repository)
        state.launch()

        XCTAssertFalse(
            state.addTask(NewTask(title: "  ", deadline: nil, estMin: nil, recurrence: .none, weekday: nil)))
        XCTAssertEqual(try repository.tasks(), [])
    }

    func test_FR01_R102_addFromSettingsKeepsRunningTimer() throws {
        let state = makeState(try Self.seeded(1))
        state.launch()
        state.start()
        let before = state.session
        let pickedAt = state.pickedAt

        XCTAssertTrue(
            state.addTask(NewTask(title: "가짜 할 일 2", deadline: nil, estMin: nil, recurrence: .none, weekday: nil)))
        XCTAssertEqual(state.tasks.count, 2)
        XCTAssertEqual(state.session, before, "도는 중이면 그대로(#70)")
        XCTAssertEqual(state.pickedAt, pickedAt)
    }

    func test_FR11_R119_addFromSettingsFailsWhenInsertThrows() throws {
        let state = makeState(InsertFailingRepository())
        state.launch()
        let before = state.session

        XCTAssertFalse(
            state.addTask(NewTask(title: "가짜 할 일", deadline: nil, estMin: nil, recurrence: .none, weekday: nil)))
        XCTAssertEqual(state.tasks, [])
        XCTAssertEqual(state.session, before)
    }

    // MARK: - R-102 설정 창 고침·지움(§4.2)

    func test_FR01_R102_editNotchTaskRenamesDraft() throws {
        let state = makeState(try Self.seeded(2))
        state.launch()
        let id = try XCTUnwrap(state.session.taskID)

        XCTAssertTrue(state.editTask(id, TaskEdit(title: "가짜 할 일 고친 것", estMin: .set(40))))
        XCTAssertEqual(state.tasks.first { $0.id == id }?.estMin, 40, "고친 뒤 tasks()를 다시 읽는다")
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 고친 것", chipMin: 25)), "노치 제목 사본을 맞춘다")
    }

    func test_FR01_R102_editRunningTaskKeepsTimer() throws {
        let state = makeState(try Self.seeded(1))
        state.launch()
        state.start()
        let id = try XCTUnwrap(state.session.taskID)
        guard case .running(_, let quantumMin, let startedAt, let endsAt) = state.timer else {
            return XCTFail("도는 중이어야 한다")
        }

        XCTAssertTrue(state.editTask(id, TaskEdit(title: "가짜 할 일 새 제목")))
        XCTAssertEqual(
            state.timer,
            .running(title: "가짜 할 일 새 제목", quantumMin: quantumMin, startedAt: startedAt, endsAt: endsAt))
    }

    func test_FR01_R102_editRejectsBlankTitle() throws {
        let state = makeState(try Self.seeded(1))
        state.launch()
        let id = try XCTUnwrap(state.session.taskID)
        let before = state.tasks

        XCTAssertFalse(state.editTask(id, TaskEdit(title: "  ")))
        XCTAssertEqual(state.tasks, before)
    }

    func test_FR01_R102_dropRunningTaskStopsAndPicksNext() throws {
        let repository = try Self.seeded(2)
        let state = makeState(repository)
        state.launch()
        state.start()
        let id = try XCTUnwrap(state.session.taskID)

        XCTAssertTrue(state.dropTask(id))
        XCTAssertEqual(state.tasks.first { $0.id == id }?.status, .dropped, "행을 지우지 않고 버림으로(research R4)")
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 2", chipMin: 25)), "타이머를 멈추고 다음 할 일을 고른다")
        XCTAssertFalse(state.taskListRows.contains { $0.id == id }, "버린 할 일은 목록에 없다")
        XCTAssertEqual(try repository.checkpoints(), [], "지운 회차의 경과 분은 남지 않는다(Edge Case, research R4)")
        XCTAssertEqual(try repository.decisions(), [])
    }

    func test_FR01_R102_dropExpiredTaskClearsCustomAndPin() throws {
        let clock = TestClock(Self.noon)
        let state = makeState(try Self.seeded(2), clock: clock)
        state.launch()
        state.start()
        clock.advance(minutes: 25)
        state.tick()
        guard case .expired = state.timer else { return XCTFail("시간 끝이어야 한다") }
        state.beginCustom()
        XCTAssertNotNil(state.customText)
        XCTAssertTrue(state.isPinnedOpen)
        let id = try XCTUnwrap(state.session.taskID)

        XCTAssertTrue(state.dropTask(id))
        XCTAssertNil(state.customText, "직접 입력을 닫는다")
        XCTAssertFalse(state.isPinnedOpen, "시간 끝 고정 펼침을 푼다")
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 2", chipMin: 25)))
        XCTAssertNil(state.remainingSeconds)
    }

    func test_FR01_R102_dropOtherTaskKeepsSession() throws {
        let state = makeState(try Self.seeded(2))
        state.launch()
        let before = state.session
        let other = try XCTUnwrap(state.tasks.first { $0.id != before.taskID }?.id)

        XCTAssertTrue(state.dropTask(other))
        XCTAssertEqual(state.session, before)
        XCTAssertEqual(state.taskListRows.count, 1)
    }

    // MARK: - R-104 다른 할 일(T028)

    func test_FR05_R104_otherTaskPickerListsAndChooses() throws {
        let clock = TestClock(Self.noon)
        let state = makeState(try Self.seeded(3), clock: clock)
        state.launch()
        state.chooseQuantum(45)
        let first = state.session.taskID

        state.beginOtherTask()
        XCTAssertTrue(state.isPickingOtherTask)
        XCTAssertEqual(state.otherTaskItems.map(\.title), ["가짜 할 일 2", "가짜 할 일 3"], "지금 할 일은 빼고 급한 순")
        clock.advance(minutes: 1)
        let third = try XCTUnwrap(state.otherTaskItems.last?.id)
        state.chooseOtherTask(third)
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 3", chipMin: 45, chipPicked: true)))
        XCTAssertEqual(state.session.previousTaskID, first, "커서 = 그때의 초안 할 일(§4.2)")
        XCTAssertEqual(state.pickedAt, Self.noon.addingTimeInterval(60), "고른 시각")
        XCTAssertFalse(state.isPickingOtherTask, "고르면 목록을 닫는다")
        XCTAssertTrue(state.tasks.allSatisfy { $0.status == .todo }, "기록하지 않는다")
    }

    func test_FR05_R104_otherTaskPickerEmptyWithOneTask() throws {
        let state = makeState(try Self.seeded(1))
        state.launch()

        state.beginOtherTask()
        XCTAssertTrue(state.isPickingOtherTask)
        XCTAssertEqual(state.otherTaskItems, [], "할 일이 하나뿐이면 목록이 빈다(Edge Case)")
    }

    func test_FR05_R104_otherTaskPickerAndNewTitleAreExclusive() throws {
        let state = makeState(try Self.seeded(2))
        state.launch()

        state.beginNewTitle()
        state.beginOtherTask()
        XCTAssertTrue(state.isPickingOtherTask)
        XCTAssertFalse(state.isEnteringNewTitle)
        state.beginNewTitle()
        XCTAssertFalse(state.isPickingOtherTask)
        state.cancelNewTitle()
        state.beginOtherTask()
        state.cancelOtherTask()
        XCTAssertFalse(state.isPickingOtherTask)
        state.beginOtherTask()
        state.start()
        XCTAssertFalse(state.isPickingOtherTask, "시작하면 닫는다")
    }

    func test_FR05_R103_quickInputInDraftKeepsOriginalAndChip() throws {
        let repository = try Self.seeded(1)
        let state = makeState(repository)
        state.launch()
        state.chooseQuantum(45)
        state.beginNewTitle()

        state.enterTitle("가짜 할 일 새것")
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 새것", chipMin: 45, chipPicked: true)))
        XCTAssertEqual(try repository.tasks().map(\.status), [.todo, .todo], "원래 할 일은 대기에 남는다(R-103)")
        XCTAssertFalse(state.isEnteringNewTitle, "저장하면 칸을 닫는다")
    }

    func test_FR05_R103_newTitleEntryClosesWhenDraftChanges() throws {
        let state = makeState(try Self.seeded(2))
        state.launch()

        state.beginNewTitle()
        XCTAssertTrue(state.isEnteringNewTitle)
        state.chooseOtherTask(try XCTUnwrap(state.otherTaskItems.first?.id))
        XCTAssertFalse(state.isEnteringNewTitle, "다른 할 일로 바꾸면 닫는다")

        state.beginNewTitle()
        state.start()
        XCTAssertFalse(state.isEnteringNewTitle, "시작하면 닫는다")
        state.complete()
        guard case .empty(.some) = state.timer else { return XCTFail("완료 뒤 다음 초안") }
        XCTAssertFalse(state.isEnteringNewTitle, "다음 초안은 제목으로 보인다(R-104)")

        state.beginNewTitle()
        state.cancelNewTitle()
        XCTAssertFalse(state.isEnteringNewTitle)
    }

    func test_FR11_R119_newTitleEntryClosesWithoutStorage() throws {
        let state = makeState(nil)
        state.launch()
        state.enterTitle("가짜 할 일 A")
        state.beginNewTitle()

        state.enterTitle("가짜 할 일 B")
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 B", chipMin: 25)))
        XCTAssertFalse(state.isEnteringNewTitle, "저장할 수 없어도 제목을 바꾸면 칸을 닫는다")
    }

    // MARK: - R-109 이어서 할 일

    private static func seededWithFirstAction(_ firstAction: String) throws -> InMemoryTaskRepository {
        let repository = try seeded(1)
        var task = try XCTUnwrap(repository.tasks().first)
        task.firstAction = firstAction
        try repository.apply(StoreBatch(updatedTasks: [task]))
        return repository
    }

    func test_FR07_R109_pickedTaskShowsFirstActionCollapsedForThreeSeconds() throws {
        let clock = TestClock(Self.noon)
        let state = makeState(try Self.seededWithFirstAction("서론 첫 문장 고치기"), clock: clock)
        state.launch()

        XCTAssertEqual(state.firstAction, "서론 첫 문장 고치기", "펼친 화면은 늘 보인다")
        XCTAssertTrue(state.showsFirstActionCollapsed, "고른 순간")
        clock.advance(seconds: 2.5)
        XCTAssertTrue(state.showsFirstActionCollapsed)
        clock.advance(seconds: 0.5)
        XCTAssertFalse(state.showsFirstActionCollapsed, "3초가 지나면 접힌 화면에서 사라진다")
        XCTAssertEqual(state.firstAction, "서론 첫 문장 고치기")
    }

    func test_FR07_R109_choosingOtherTaskShowsFirstActionAgain() throws {
        let clock = TestClock(Self.noon)
        let repository = try Self.seeded(2)
        var second = try XCTUnwrap(repository.tasks().last)
        second.firstAction = "목차 다시 보기"
        try repository.apply(StoreBatch(updatedTasks: [second]))
        let state = makeState(repository, clock: clock)
        state.launch()
        XCTAssertFalse(state.showsFirstActionCollapsed, "첫 할 일은 첫 행동이 없다")

        clock.advance(seconds: 5)
        state.chooseOtherTask(second.id)
        XCTAssertEqual(state.firstAction, "목차 다시 보기")
        XCTAssertTrue(state.showsFirstActionCollapsed, "목록에서 고른 순간부터 다시 3초")
        clock.advance(seconds: 3)
        XCTAssertFalse(state.showsFirstActionCollapsed)
    }

    func test_FR07_R109_taskWithoutFirstActionShowsNothing() throws {
        let state = makeState(try Self.seeded(1))
        state.launch()

        XCTAssertNil(state.firstAction)
        XCTAssertFalse(state.showsFirstActionCollapsed, "첫 행동이 없으면 바로 회색 점·제목")
    }

    func test_FR07_R109_runningKeepsFirstActionOnlyExpanded() throws {
        let state = makeState(try Self.seededWithFirstAction("서론 첫 문장 고치기"))
        state.launch()

        state.start()
        XCTAssertEqual(state.firstAction, "서론 첫 문장 고치기", "도는 중 펼친 화면에도 보인다(시안 3번)")
        XCTAssertFalse(state.showsFirstActionCollapsed, "도는 중 접힌 화면은 spec 001 그대로")
    }

    func test_FR07_R109_noStorageHasNoFirstAction() {
        let state = makeState(nil)
        state.enterTitle("가짜 할 일")

        XCTAssertNil(state.firstAction)
        XCTAssertFalse(state.showsFirstActionCollapsed)
    }

    // MARK: - R-105·R-106 미루기·바꾸기와 두 줄 입력

    private func runningFor18Minutes(
        _ repository: any TaskRepository, clock: TestClock
    ) -> AppState {
        let state = makeState(repository, clock: clock)
        state.launch()
        state.start()
        clock.advance(minutes: 18)
        state.tick()
        return state
    }

    func test_FR07_R106_skipWithNotesWritesCheckpointLogAndPicksNext() throws {
        let repository = try Self.seeded(2)
        let clock = TestClock(Self.noon)
        let state = runningFor18Minutes(repository, clock: clock)

        state.beginSetAside(.skip)
        XCTAssertEqual(state.pendingAction, .skip)
        XCTAssertEqual(state.elapsedMinutes, 18, "제목 줄 오른쪽 경과")
        state.editNotes(NotesDraft(done: "가짜 한 일", next: "가짜 다음 일"))
        state.submitSetAside()

        let tasks = try repository.tasks()
        XCTAssertEqual(tasks.map(\.status), [.todo, .todo])
        XCTAssertEqual(tasks[0].skipCount, 1, "미루기는 미룬 횟수 + 1")
        XCTAssertEqual(tasks[0].firstAction, "가짜 다음 일", "다음 할 일 줄이 이어서 할 일이 된다(R-109)")
        let checkpoint = try XCTUnwrap(repository.checkpoints().first)
        XCTAssertEqual(checkpoint.trigger, .skip)
        XCTAssertEqual(checkpoint.elapsedMin, 18)
        XCTAssertEqual(checkpoint.notes, CheckpointNotes(doneNote: "가짜 한 일", nextNote: "가짜 다음 일"))
        XCTAssertEqual(try repository.decisions().map(\.userAction), [.skip], "로그 한 줄(R-112)")
        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 2", chipMin: 25)), "다음 할 일을 고른다")
        XCTAssertNil(state.pendingAction)
        XCTAssertEqual(state.notesDraft, NotesDraft(), "두 줄 칸을 비운다")
    }

    func test_FR07_R106_switchWithoutNotesKeepsFirstActionAndCount() throws {
        let repository = try Self.seeded(2)
        let clock = TestClock(Self.noon)
        let state = runningFor18Minutes(repository, clock: clock)

        state.beginSetAside(.switch)
        state.editNotes(NotesDraft(done: "적다가 만 줄", next: ""))
        state.setAsideWithoutNotes()

        let tasks = try repository.tasks()
        XCTAssertEqual(tasks[0].status, .todo)
        XCTAssertEqual(tasks[0].skipCount, 0, "바꾸기는 미룬 횟수를 올리지 않는다")
        XCTAssertNil(tasks[0].firstAction)
        let checkpoint = try XCTUnwrap(repository.checkpoints().first)
        XCTAssertEqual(checkpoint.trigger, .switch)
        XCTAssertEqual(checkpoint.notes, .empty, "안 적기는 적던 글자를 버리고 빈 두 줄")
        XCTAssertEqual(try repository.decisions().map(\.userAction), [.switch])
        XCTAssertEqual(state.session.taskID, 2)
    }

    func test_FR07_R106_emptyNotesKeepPreviousFirstAction() throws {
        let clock = TestClock(Self.noon)
        let state = runningFor18Minutes(try Self.seededWithFirstAction("가짜 이전 줄"), clock: clock)

        state.beginSetAside(.switch)
        state.setAsideWithoutNotes()

        XCTAssertEqual(state.tasks.first?.firstAction, "가짜 이전 줄", "다음 할 일 줄이 비면 이전 값을 둔다(R-109)")
        XCTAssertEqual(state.firstAction, "가짜 이전 줄")
    }

    func test_FR11_R119_setAsideWithoutStorageOnlyEndsTimer() {
        let state = makeState(nil)
        state.enterTitle("가짜 할 일")
        state.start()

        state.beginSetAside(.skip)
        state.editNotes(NotesDraft(done: "가짜 한 일", next: ""))
        state.submitSetAside()

        XCTAssertEqual(state.timer, .empty(draft: nil), "저장할 수 없으면 spec 001 완료처럼 타이머만 끝난다")
        XCTAssertNil(state.pendingAction)
        XCTAssertEqual(state.notesDraft, NotesDraft())
    }

    func test_FR07_R106_cancelWritesNothingAndKeepsTimer() throws {
        let repository = try Self.seeded(2)
        let clock = TestClock(Self.noon)
        let state = runningFor18Minutes(repository, clock: clock)
        let running = state.timer

        state.beginSetAside(.switch)
        state.editNotes(NotesDraft(done: "가짜 한 일", next: "가짜 다음 일"))
        clock.advance(minutes: 1)
        state.tick()
        XCTAssertEqual(state.elapsedMinutes, 19, "두 줄 입력 중에도 타이머는 돈다")
        state.cancelSetAside()

        XCTAssertNil(state.pendingAction)
        XCTAssertEqual(state.notesDraft, NotesDraft())
        XCTAssertEqual(state.timer, running)
        XCTAssertEqual(try repository.tasks().map(\.status), [.active, .todo])
        XCTAssertEqual(try repository.checkpoints(), [])
        XCTAssertEqual(try repository.decisions(), [], "돌아가기는 로그를 남기지 않는다(R-112)")
    }

    func test_FR07_R106_onlyWhileRunning() throws {
        let state = makeState(try Self.seeded(1))
        state.launch()

        state.beginSetAside(.skip)
        XCTAssertNil(state.pendingAction, "초안에는 미루기가 없다")
        XCTAssertFalse(state.takeNotesFocusRequest())
    }

    func test_FR07_R106_firstFieldFocusIsRequestedOnce() throws {
        let state = runningFor18Minutes(try Self.seeded(1), clock: TestClock(Self.noon))

        state.beginSetAside(.skip)
        XCTAssertTrue(state.takeNotesFocusRequest(), "버튼을 누른 직후 첫 칸")
        XCTAssertFalse(state.takeNotesFocusRequest(), "다시 펼쳐 칸이 다시 만들어질 때는 주지 않는다")
    }

    func test_FR07_R106_expiryWhilePendingClearsActionKeepsNotes() throws {
        let clock = TestClock(Self.noon)
        let state = runningFor18Minutes(try Self.seeded(1), clock: clock)
        state.beginSetAside(.skip)
        state.editNotes(NotesDraft(done: "가짜 한 일", next: ""))

        clock.advance(minutes: 7)
        state.tick()

        XCTAssertEqual(state.timer, .expired(title: "가짜 할 일 1", chipMin: 25))
        XCTAssertNil(state.pendingAction, "시간 끝 화면으로 바뀐다(§8)")
        XCTAssertEqual(state.notesDraft, NotesDraft(done: "가짜 한 일", next: ""), "적던 글자는 이어진다")
    }

    func test_FR11_R119_failedSetAsideKeepsRunningAndNotes() throws {
        let repository = FailingAfterStartRepository()
        _ = try repository.inner.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: Self.noon)
        let clock = TestClock(Self.noon)
        let state = runningFor18Minutes(repository, clock: clock)
        let before = state.session
        repository.failsApply = true

        state.beginSetAside(.skip)
        state.editNotes(NotesDraft(done: "가짜 한 일", next: ""))
        state.submitSetAside()

        XCTAssertEqual(state.session, before, "쓰기가 실패하면 세션을 바꾸지 않는다")
        XCTAssertEqual(state.pendingAction, .skip, "두 줄 화면에 남아 다시 누를 수 있다")
        XCTAssertEqual(state.notesDraft, NotesDraft(done: "가짜 한 일", next: ""))
    }

    func test_FR07_R109_skipOnlyTaskPicksItAgainWithFirstAction() throws {
        let clock = TestClock(Self.noon)
        let state = runningFor18Minutes(try Self.seeded(1), clock: clock)

        state.beginSetAside(.skip)
        state.editNotes(NotesDraft(done: "", next: "가짜 다음 일"))
        state.submitSetAside()

        XCTAssertEqual(state.timer, .empty(draft: Draft(title: "가짜 할 일 1", chipMin: 25)), "하나뿐이면 다시 뽑힌다")
        XCTAssertEqual(state.firstAction, "가짜 다음 일")
        XCTAssertTrue(state.showsFirstActionCollapsed, "접힌 화면에 3초")
    }

    // MARK: - R-107 시간 끝

    func test_FR07_R107_restartFromExpiredRunsSameTaskAgain() throws {
        let repository = try Self.seeded(2)
        let clock = TestClock(Self.noon)
        let state = runningFor18Minutes(repository, clock: clock)
        clock.advance(minutes: 7)
        state.tick()
        XCTAssertEqual(state.timer, .expired(title: "가짜 할 일 1", chipMin: 25))

        state.chooseQuantum(15)
        state.start()

        let restartedAt = Self.noon.addingTimeInterval(25 * 60)
        XCTAssertEqual(
            state.timer,
            .running(
                title: "가짜 할 일 1", quantumMin: 15, startedAt: restartedAt,
                endsAt: restartedAt.addingTimeInterval(15 * 60)),
            "N분 더는 같은 할 일을 고른 시간으로 다시 돌린다")
        let checkpoint = try XCTUnwrap(repository.checkpoints().first)
        XCTAssertEqual(checkpoint.trigger, .quantum)
        XCTAssertEqual(checkpoint.elapsedMin, 25)
        XCTAssertEqual(try repository.decisions(), [], "다시 시작은 로그를 남기지 않는다")
        XCTAssertEqual(try repository.tasks().map(\.status), [.active, .todo])
    }

    /// 할 일 둘, 첫 할 일의 25분이 끝난 상태.
    private func expired(_ repository: any TaskRepository, clock: TestClock) -> AppState {
        let state = runningFor18Minutes(repository, clock: clock)
        clock.advance(minutes: 7)
        state.tick()
        return state
    }

    func test_FR07_R107_restartSavesNotesAndClearsFields() throws {
        let repository = try Self.seeded(2)
        let state = expired(repository, clock: TestClock(Self.noon))

        state.editNotes(NotesDraft(done: "가짜 한 일", next: "가짜 다음 일"))
        state.start()

        let checkpoint = try XCTUnwrap(repository.checkpoints().first)
        XCTAssertEqual(checkpoint.notes, CheckpointNotes(doneNote: "가짜 한 일", nextNote: "가짜 다음 일"))
        XCTAssertEqual(try repository.tasks().first?.firstAction, "가짜 다음 일")
        XCTAssertEqual(state.notesDraft, NotesDraft(), "새 회차는 빈 칸으로 시작한다")
    }

    func test_FR07_R107_completeFromExpiredSavesNotes() throws {
        let repository = try Self.seeded(2)
        let state = expired(repository, clock: TestClock(Self.noon))

        state.editNotes(NotesDraft(done: "가짜 한 일", next: ""))
        state.complete()

        let checkpoint = try XCTUnwrap(repository.checkpoints().first)
        XCTAssertEqual(checkpoint.trigger, .quantum)
        XCTAssertEqual(checkpoint.notes, CheckpointNotes(doneNote: "가짜 한 일", nextNote: ""))
        XCTAssertEqual(try repository.tasks().map(\.status), [.done, .todo])
        XCTAssertEqual(try repository.decisions().map(\.userAction), [.done])
        XCTAssertEqual(state.session.taskID, 2)
    }

    func test_FR07_R107_skipFromExpiredDoesNotAskAgain() throws {
        let repository = try Self.seeded(2)
        let state = expired(repository, clock: TestClock(Self.noon))

        state.editNotes(NotesDraft(done: "", next: "가짜 다음 일"))
        state.beginSetAside(.skip)

        XCTAssertNil(state.pendingAction, "시간 끝에서는 두 줄을 다시 묻지 않는다")
        let task = try XCTUnwrap(repository.tasks().first)
        XCTAssertEqual(task.status, .todo)
        XCTAssertEqual(task.skipCount, 1)
        XCTAssertEqual(task.firstAction, "가짜 다음 일")
        let checkpoint = try XCTUnwrap(repository.checkpoints().first)
        XCTAssertEqual(checkpoint.trigger, .quantum, "시간 끝 버튼은 계기 시간 끝")
        XCTAssertEqual(checkpoint.elapsedMin, 25)
        XCTAssertEqual(try repository.decisions().map(\.userAction), [.skip])
        XCTAssertEqual(state.session.taskID, 2)
    }

    func test_FR07_R107_switchFromExpiredWithEmptyNotes() throws {
        let repository = try Self.seeded(2)
        let state = expired(repository, clock: TestClock(Self.noon))

        state.beginSetAside(.switch)

        XCTAssertEqual(try repository.checkpoints().first?.notes, .empty)
        XCTAssertEqual(try repository.decisions().map(\.userAction), [.switch])
        XCTAssertEqual(try repository.tasks().first?.skipCount, 0)
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
        advance(seconds: TimeInterval(minutes * 60))
    }

    func advance(seconds: TimeInterval) {
        current.withLock { $0 += seconds }
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

private final class FailingAfterStartRepository: TaskRepository {
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

private final class InsertFailingRepository: TaskRepository {
    struct Failure: Error {}

    func tasks() throws -> [MokaTask] { [] }
    func insertTask(_ task: NewTask, cycleDay: LocalDay?, at: Date) throws -> MokaTask { throw Failure() }
    func checkpoints() throws -> [Checkpoint] { [] }
    func decisions() throws -> [DecisionLogEntry] { [] }
    func apply(_ batch: StoreBatch) throws {}
}
