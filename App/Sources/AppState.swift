import AppKit
import MokaCore
import Observation
import SwiftUI
import os

/// 앱이 쓰는 저장소 묶음. DB 하나를 열어 나눠 준다(spec 002 plan "앱 연결").
/// 할 일·일정 저장소가 nil이면 저장할 수 없는 상태다(R-119).
struct AppStorage {
    let settings: any SettingsStore
    let repository: (any TaskRepository)?
    let contexts: (any ContextStore)?

    var isUnavailable: Bool { repository == nil }

    private static let logger = Logger(subsystem: "dev.dongwon.moka", category: "storage")

    /// `openStores`를 한 번만 부른다. 실패하면 설정만 메모리 저장소로 대체하고 할 일·일정 저장소는 만들지 않는다.
    /// DB 파일을 지우거나, 새로 만들거나, 옮기지 않는다(R-119, research R20). 로그에는 오류 종류만 남긴다.
    static func open(_ openStores: () throws -> AppStorage) -> AppStorage {
        do {
            return try openStores()
        } catch {
            logger.error(
                "DB를 열지 못해 저장 없이 동작: \(String(reflecting: type(of: error)), privacy: .public)")
            return AppStorage(settings: InMemorySettingsStore(), repository: nil, contexts: nil)
        }
    }
}

/// 알림 처리기 하나. 없어질 때 등록을 해제한다(#37). 처리기는 주 스레드에서 돈다.
final class NotificationObservation {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(center: NotificationCenter, name: Notification.Name, handler: @escaping @MainActor () -> Void) {
        self.center = center
        token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    deinit {
        center.removeObserver(token)
    }
}

/// 화면 상태와 노치 세션(spec 001 data-model §6, spec 002 data-model §8). 규칙은 MokaCore `NotchSession`·`NotchTimer`가
/// 정하고 여기서는 이벤트를 전달하고 쓰기를 저장소에 적용한다. 저장할 수 없으면(R-119) spec 001처럼 타이머만 돈다.
@Observable @MainActor
final class AppState {
    private(set) var session: NotchSession = .initial
    /// 화면에 보이는 타이머. 세션 안의 spec 001 값이다.
    var timer: NotchTimer { session.timer }
    /// 저장소 `tasks()`의 지금 목록. 쓰기 뒤 다시 읽는다.
    private(set) var tasks: [MokaTask] = []
    /// 노치가 지금 할 일을 고른 시각(이어서 할 일 접힘 표시 2초, data-model §5.5).
    private(set) var pickedAt: Date?
    /// 앱 DB를 열지 못했거나 마이그레이션이 실패했다(R-119).
    let storageUnavailable: Bool
    /// 화면에 쓰는 남은 초. 늘 `apply(.tick, …)` 뒤에 다시 계산한다(#13).
    private(set) var remainingSeconds: Int?
    /// 시간 끝 자동 펼침 고정(R-009). `running → expired`에서 켜고 시작·완료로 끈다(`pinnedOpenAfter`).
    /// 판 내용만 펼치고 패널을 key window로 만들거나 앱을 활성화하지 않는다(data-model §6 포커스 표).
    private(set) var isPinnedOpen = false
    private(set) var isHovering = false
    private(set) var isInputFocused = false
    private(set) var titleFocusRequest = 0
    /// 직접 입력 칸에 쓴 글자. nil이면 직접 입력을 쓰지 않는 중이다(data-model §6 `isEditingCustom`).
    private(set) var customText: String?
    /// 직접 입력 값이 1~180 정수가 아니면 시작을 막는다(R-004).
    var canStart: Bool { QuantumChip.startAllowed(customText: customText) }

    /// 펼침 여부. 바뀔 때는 `updateExpansion()` 한 곳에서 `withAnimation`으로 바꾼다.
    private(set) var isExpanded = false

    /// 설정 창 할 일 탭의 보기·정렬(R-118). 앱이 켜져 있는 동안만 둔다(data-model §8).
    var taskListScope: TaskListScope = .all
    var taskListOrder: TaskListOrder = .created

    /// 지금이 속한 하루. 하루 시작 시각 기준이다(R-114).
    var logicalToday: LocalDay {
        DayBoundary.day(
            containing: clock.now(), dayStart: CoreSettings.readDayStart(from: settings), calendar: calendar)
    }

    var taskListRows: [MokaTask] {
        TaskListView.rows(tasks, scope: taskListScope, order: taskListOrder, today: logicalToday, calendar: calendar)
    }

    /// 할 일 탭 "다음" 표시(R-102). 보기·정렬과 무관하다.
    var nextMarkID: TaskID? { session.nextMark(input(at: clock.now())) }

    /// "직접…"을 누른 뒤 칸이 처음 나타날 때 한 번만 포커스를 준다. 마우스로 다시 펼쳐 칸이 다시 만들어질 때는
    /// 주지 않는다(R-002, SC-003).
    @ObservationIgnored private var customFocus = OneShotRequest()
    @ObservationIgnored private let clock: MokaClock
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let settings: any SettingsStore
    @ObservationIgnored private let repository: (any TaskRepository)?
    /// 기본 작업 시간. 처음에 한 번 읽고 설정에서 바꿨을 때만 다시 읽는다(#35).
    @ObservationIgnored private var defaultQuantumMin: Int
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var observations: [NotificationObservation] = []

    private static let logger = Logger(subsystem: "dev.dongwon.moka", category: "timer")
    private static let storageLogger = Logger(subsystem: "dev.dongwon.moka", category: "storage")

    /// `calendar`는 `GregorianCalendar.make(timeZone: .autoupdatingCurrent)`로 한 번 만든 것을 받는다(ADR-0010).
    /// `workspaceCenter`는 깨어남·잠자기 알림을 받는 곳이다. 시험은 전용 센터를 넘긴다.
    init(
        clock: MokaClock, calendar: Calendar, storage: AppStorage,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.clock = clock
        self.calendar = calendar
        settings = storage.settings
        repository = storage.repository
        storageUnavailable = storage.isUnavailable
        defaultQuantumMin = QuantumSettings.readDefault(from: storage.settings)
        observations = [
            NotificationObservation(center: workspaceCenter, name: NSWorkspace.didWakeNotification) { [weak self] in
                self?.tick()
                self?.activate()
            },
            NotificationObservation(center: workspaceCenter, name: NSWorkspace.willSleepNotification) {
                [weak self] in
                self?.lifecycleCheckpoint(.sleep)
            },
        ]
    }

    // MARK: - 앱 수명

    /// 앱 시작: 재시작 복구(R-111) → 하루 판정 → 고르기. 저장할 수 없으면 아무것도 하지 않는다.
    func launch() {
        guard let repository else { return }
        reloadTasks()
        let reverted = LaunchRecovery.revert(tasks)
        if !reverted.isEmpty {
            guard write(StoreBatch(updatedTasks: reverted), to: repository) else { return }
            reloadTasks()
        }
        activate()
    }

    /// 설정 창 할 일 추가(R-101, #70): 검증·채움 → 넣기 → `tasks()` 다시 읽기 → 빈 상태일 때만 고르기.
    /// 초안·도는 중·시간 끝이면 세션을 그대로 둔다. 검증이나 쓰기에 실패하면 false.
    @discardableResult
    func addTask(_ new: NewTask) -> Bool {
        guard let repository else { return false }
        let now = clock.now()
        guard
            let prepared = TaskWriteRules.prepareNew(
                new, now: now, dayStart: CoreSettings.readDayStart(from: settings), calendar: calendar)
        else { return false }
        do {
            _ = try repository.insertTask(prepared.task, cycleDay: prepared.cycleDay, at: now)
        } catch {
            Self.logStorageFailure(error)
            return false
        }
        reloadTasks()
        pickIfEmpty(at: now)
        return true
    }

    /// 설정 창 고침(R-102, §4.2): 검증 → 저장 → `tasks()` 다시 읽기 → 노치의 할 일이면 제목 사본만 맞춘다(타이머 그대로).
    @discardableResult
    func editTask(_ id: TaskID, _ edit: TaskEdit) -> Bool {
        guard let repository, let task = tasks.first(where: { $0.id == id }) else { return false }
        guard
            let edited = TaskWriteRules.applyEdit(
                task, edit, now: clock.now(), dayStart: CoreSettings.readDayStart(from: settings), calendar: calendar),
            write(StoreBatch(updatedTasks: [edited]), to: repository)
        else { return false }
        reloadTasks()
        session = session.edited(edited)
        return true
    }

    /// 설정 창 지움(R-102, §4.2): 행을 지우지 않고 버림으로 바꾼다(research R4). 노치의 할 일이면 타이머를 멈추고
    /// 빈 상태에서 다시 고른다.
    @discardableResult
    func dropTask(_ id: TaskID) -> Bool {
        guard let repository, var task = tasks.first(where: { $0.id == id }), task.status != .dropped else {
            return false
        }
        task.status = .dropped
        guard write(StoreBatch(updatedTasks: [task]), to: repository) else { return false }
        reloadTasks()
        let now = clock.now()
        let next = session.taskDropped(id)
        if next != session {
            session = next
            remainingSeconds = timer.remainingSeconds(at: now)
            customText = nil
            customFocus.cancel()
            isPinnedOpen = false
            updateExpansion()
            updateRefreshTimer()
        }
        pickIfEmpty(at: now)
        return true
    }

    /// 활성화 판정(research R11): 앱 시작, 잠자기에서 깨어남, 노치 펼침, 설정 창 열기가 부른다.
    /// 반복 리셋(R-113)을 적용하고 빈 상태면 고른다(R-104). 같은 하루에 여러 번 돌아도 결과가 같다.
    func activate() {
        guard let repository else { return }
        let now = clock.now()
        let changed = RecurrenceReset.reset(
            tasks, now: now, dayStart: CoreSettings.readDayStart(from: settings), calendar: calendar)
        if !changed.isEmpty {
            guard write(StoreBatch(updatedTasks: changed), to: repository) else { return }
            reloadTasks()
        }
        pickIfEmpty(at: now)
    }

    /// 종료(`.quit`)·잠자기(`.sleep`) 체크포인트(R-110, research R12). 도는 중일 때만 빈 두 줄로 남기고 동기로 저장한다.
    /// 할 일 상태와 타이머는 바꾸지 않는다. 종료를 미루지 않는다.
    func lifecycleCheckpoint(_ trigger: CheckpointTrigger) {
        guard let repository, let batch = session.lifecycleCheckpoint(trigger, input(at: clock.now())) else { return }
        _ = write(batch, to: repository)
    }

    // MARK: - 노치 동작

    /// 빠른 입력(R-103). 저장할 수 있으면 할 일을 만들어 그 할 일로 초안을 바꾼다. 아니면 spec 001 타이머만.
    /// "다른 할 일"(R-104): 초안을 만든 순서의 다음 대기 할 일로 바꾼다. 칩은 그대로, 기록은 없다.
    func nextDraft() {
        let now = clock.now()
        let next = session.nextDraft(input(at: now))
        guard next != session else { return }
        session = next
        pickedAt = now
    }

    func enterTitle(_ text: String) {
        guard let repository else {
            send(.enterTitle(text))
            return
        }
        transition(.enterTitle(text)) { session, now in
            guard case .empty = session.timer else { return .rejected(.notAllowedInPhase) }
            guard
                let prepared = TaskWriteRules.prepareNew(
                    NewTask(title: text, deadline: nil, estMin: nil, recurrence: .none, weekday: nil), now: now,
                    dayStart: CoreSettings.readDayStart(from: settings), calendar: calendar)
            else { return .rejected(.emptyTitle) }
            let task: MokaTask
            do {
                task = try repository.insertTask(prepared.task, cycleDay: prepared.cycleDay, at: now)
            } catch {
                Self.logStorageFailure(error)
                return .rejected(.notAllowedInPhase)
            }
            reloadTasks()
            session = session.addedTask(task, input(at: now))
            return .applied
        }
    }

    /// 프리셋 칩을 골랐다. 직접 입력을 그만둔다.
    func chooseQuantum(_ minutes: Int) {
        customText = nil
        customFocus.cancel()
        send(.chooseQuantum(minutes))
    }

    /// "직접…"을 골랐다. 칸은 지금 칩 값으로 시작한다.
    func beginCustom() {
        switch timer {
        case .empty(.some(let draft)): customText = String(draft.chipMin)
        case .expired(_, let chipMin, _): customText = String(chipMin)
        case .empty(nil), .running: return
        }
        customFocus.request()
    }

    /// 직접 입력 칸이 나타날 때 부른다. "직접…"을 누른 직후에만 true.
    func takeCustomFocusRequest() -> Bool {
        customFocus.take()
    }

    /// 직접 입력 칸이 바뀌었다. 1~180 정수면 칩 값으로 쓴다(R-004).
    func editCustom(_ text: String) {
        customText = text
        if let minutes = QuantumChip.parseCustom(text) {
            send(.chooseQuantum(minutes))
        }
    }

    /// 설정에서 기본 작업 시간을 저장했다. 칩을 직접 고르지 않았고 직접 입력 중이 아니면 칩이 새 값이 된다(R-013).
    func defaultQuantumChanged() {
        defaultQuantumMin = QuantumSettings.readDefault(from: settings)
        session.timer.applyDefaultQuantumChange(defaultQuantumMin, isEditingCustom: customText != nil)
    }

    func start() {
        guard canStart else { return }
        commit(.start) { session, input throws(SessionError) in try session.start(input) }
    }

    func complete() {
        commit(.complete) { session, input throws(SessionError) in try session.complete(nil, input) }
    }

    func tick() {
        send(.tick)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        updateExpansion()
    }

    func setInputFocused(_ focused: Bool) {
        isInputFocused = focused
        updateExpansion()
    }

    /// 접힘 판정(`shouldStayExpanded`)이 바뀌면 방향에 맞는 애니메이션으로 펼치거나 접는다.
    /// 노치가 펼쳐지면 활성화 판정을 돈다(research R11).
    private func updateExpansion() {
        let expanded = shouldStayExpanded(pinned: isPinnedOpen, focused: isInputFocused, hovering: isHovering)
        guard expanded != isExpanded else { return }
        let animation = NotchLayout.expansionAnimation(
            expanding: expanded, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        withAnimation(animation) {
            isExpanded = expanded
        }
        if expanded {
            activate()
        }
    }

    /// 펼친 판을 클릭했다. 빈 상태면 제목 칸에 포커스를 준다(data-model §6).
    func panelClicked() {
        if case .empty(nil) = timer {
            titleFocusRequest += 1
        }
    }

    // MARK: - 내부

    private func input(at now: Date) -> SessionInput {
        SessionInput(tasks: tasks, now: now, defaultQuantumMin: defaultQuantumMin, calendar: calendar)
    }

    /// 타이머만 바뀌는 이벤트(칩, tick). 저장할 수 없을 때는 빠른 입력·시작·완료도 여기로 온다.
    @discardableResult
    private func send(_ event: TimerEvent) -> TransitionResult {
        transition(event) { session, now in
            session.timer.apply(event, at: now, defaultQuantumMin: defaultQuantumMin)
        }
    }

    /// 쓰기가 있는 세션 동작: 세션 함수 → `apply` → 성공하면 `tasks()` 다시 읽기 → 세션 교체 → 빈 상태면 고르기.
    /// 거부되거나 쓰기가 실패하면 세션을 그대로 둔다(R-119).
    private func commit(
        _ event: TimerEvent, _ step: (NotchSession, SessionInput) throws(SessionError) -> SessionStep
    ) {
        guard let repository else {
            send(event)
            return
        }
        var picked = false
        transition(event) { session, now in
            let next: SessionStep
            do {
                next = try step(session, input(at: now))
            } catch {
                return .rejected(.notAllowedInPhase)
            }
            do {
                session = try SessionCommit.commit(next, to: repository)
            } catch {
                Self.logStorageFailure(error)
                return .rejected(.notAllowedInPhase)
            }
            reloadTasks()
            picked = true
            return .applied
        }
        if picked {
            pickIfEmpty(at: clock.now())
        }
    }

    /// 타이머 전이와 그 뒤 화면 상태(고정, 펼침, 직접 입력, 1초 tick)를 한 곳에서 맞춘다.
    @discardableResult
    private func transition(
        _ event: TimerEvent, _ change: (inout NotchSession, Date) -> TransitionResult
    ) -> TransitionResult {
        let now = clock.now()
        let before = Self.phaseName(timer)
        let previous = timer
        var next = session
        let result = change(&next, now)
        session = next
        remainingSeconds = timer.remainingSeconds(at: now)
        let after = Self.phaseName(timer)
        if result == .applied, event == .start || event == .complete {
            customText = nil
            customFocus.cancel()
        }
        isPinnedOpen = pinnedOpenAfter(event, result: result, from: previous, to: timer, wasPinned: isPinnedOpen)
        updateExpansion()

        if case .rejected(let reason) = result {
            Self.logger.notice(
                "거부 \(Self.eventName(event), privacy: .public) in \(after, privacy: .public): \(String(describing: reason), privacy: .public)"
            )
        } else if before != after {
            Self.logger.info(
                "전이 \(Self.eventName(event), privacy: .public): \(before, privacy: .public) → \(after, privacy: .public)"
            )
        }
        updateRefreshTimer()
        return result
    }

    /// 빈 상태(초안 없음)면 고른다(R-104). 새로 고르면 `pickedAt`을 그 시각으로 둔다.
    private func pickIfEmpty(at now: Date) {
        let next = session.picked(input(at: now))
        guard next != session else { return }
        session = next
        pickedAt = now
        remainingSeconds = timer.remainingSeconds(at: now)
    }

    private func reloadTasks() {
        guard let repository else { return }
        do {
            tasks = try repository.tasks()
        } catch {
            Self.logStorageFailure(error)
        }
    }

    /// 동기로 적용한다. 실패하면 오류 종류만 로그에 남기고 false.
    private func write(_ batch: StoreBatch, to repository: any TaskRepository) -> Bool {
        do {
            try repository.apply(batch)
            return true
        } catch {
            Self.logStorageFailure(error)
            return false
        }
    }

    /// 제목·두 줄 본문을 남기지 않는다. 오류 종류만.
    private static func logStorageFailure(_ error: any Error) {
        storageLogger.error("저장 실패: \(String(reflecting: type(of: error)), privacy: .public)")
    }

    /// `running` 동안만 1초마다 tick을 보낸다(research R1).
    private func updateRefreshTimer() {
        guard case .running = timer else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            return
        }
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// 로그용 단계 이름. 제목은 넣지 않는다(R7).
    private static func phaseName(_ timer: NotchTimer) -> String {
        switch timer {
        case .empty(nil): "empty"
        case .empty(.some): "empty(draft)"
        case .running: "running"
        case .expired: "expired"
        }
    }

    private static func eventName(_ event: TimerEvent) -> String {
        switch event {
        case .enterTitle: "enterTitle"
        case .chooseQuantum: "chooseQuantum"
        case .start: "start"
        case .tick: "tick"
        case .complete: "complete"
        }
    }
}
