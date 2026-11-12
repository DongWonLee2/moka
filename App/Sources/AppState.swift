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
    /// 판단 결과 저장소(spec 003 data-model §9). 멤버와이즈 생성자의 인자로 남도록 `var`로 둔다. DB를 열지 못하면 nil이다.
    var scores: (any ScoreStore)? = nil

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

/// 고른 공급자로 만든 판단 설정(spec 006 data-model §8). 키 보관함은 들지 않는다.
struct DecisionBinding {
    let provider: any DecisionProvider
    let baseModel: String
    let requestModel: String
}

/// 판단 기능 주입(spec 006 data-model §8, research R5). 앱은 HTTP 공급자와 공급자별 Keychain 항목을, 시험은 가짜를 넘긴다.
/// `questions`가 nil(질문 파일 해석 실패)이면 판단 기능을 끈다. `catalog`은 시험이 공급자를 연 가짜 표를 넣을 때만 바꾼다.
struct DecisionSetup {
    let bind: @MainActor (DecisionSelection.Ready) -> DecisionBinding
    let keyStore: @MainActor (ProviderID) -> any KeyStore
    let catalog: [ProviderConfig]
    let questions: QuestionSet?

    init(
        bind: @escaping @MainActor (DecisionSelection.Ready) -> DecisionBinding,
        keyStore: @escaping @MainActor (ProviderID) -> any KeyStore, catalog: [ProviderConfig] = ProviderCatalog.all,
        questions: QuestionSet?
    ) {
        self.bind = bind
        self.keyStore = keyStore
        self.catalog = catalog
        self.questions = questions
    }

    /// 공급자 하나와 보관함 하나로 고정한 설정. 공급자와 상관없이 같은 보관함과 공급자를 쓴다.
    @MainActor init(keyStore: any KeyStore, provider: any DecisionProvider, questions: QuestionSet?) {
        self.init(
            bind: { DecisionBinding(provider: provider, baseModel: $0.baseModel, requestModel: $0.requestModel) },
            keyStore: { _ in keyStore }, questions: questions)
    }
}

/// 공급자 설정 동작 가운데 실패한 것(spec 006 data-model §8). 다음 성공에 지운다.
enum ProviderAction: Equatable {
    case select
    case saveMicrosoft
}

/// 지금 판단 설정에서 판단 결과 규칙이 쓰는 값(spec 006 data-model §7). `provider`는 주입된 공급자 `name`이다.
private struct Judging {
    let questions: QuestionSet
    let binding: DecisionBinding
    var provider: String { binding.provider.name }
    var baseModel: String { binding.baseModel }
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
    private(set) var session: NotchSession = .initial {
        didSet {
            if session.taskID != oldValue.taskID || !Self.isDraft(session.timer) {
                isEnteringNewTitle = false
                isPickingOtherTask = false
            }
            if session.taskID != oldValue.taskID || session.run != oldValue.run || Self.isEmpty(session.timer) {
                notesDraft = NotesDraft()
            }
            if !Self.isRunning(session.timer) {
                pendingAction = nil
                notesFocus.cancel()
            }
            if session.taskID != oldValue.taskID {
                gateWaitingTaskID = nil
                gateDraftText = ""
                gateDraftTaskID = nil
            }
            if session.taskID != oldValue.taskID || Self.isDraft(session.timer) != Self.isDraft(oldValue.timer) {
                refreshGate()
            }
        }
    }
    /// 시작 전 화면에서 "+ 새 할 일"로 제목 칸을 연 상태(R-103). 노치의 할 일이 바뀌거나 초안이 아니게 되면 닫힌다.
    private(set) var isEnteringNewTitle = false
    /// 시작 전 화면에서 "다른 할 일" 목록을 연 상태(R-104). 닫히는 조건은 새 할 일 칸과 같다.
    private(set) var isPickingOtherTask = false
    /// 도는 중 미루기·바꾸기를 눌러 두 줄 입력 중인 동작(R-106). 도는 중이 아니게 되면 nil.
    private(set) var pendingAction: PendingAction?
    private(set) var notesDraft = NotesDraft()
    /// 화면에 보이는 타이머. 세션 안의 spec 001 값이다.
    var timer: NotchTimer { session.timer }
    /// 저장소 `tasks()`의 지금 목록. 쓰기 뒤 다시 읽는다.
    private(set) var tasks: [MokaTask] = []
    /// 일정(R-115), 날짜순. 쓰기 뒤 다시 읽는다.
    private(set) var contexts: [MokaContext] = []
    /// 노치가 지금 할 일을 고른 시각(이어서 할 일 접힘 표시 3초, data-model §5.5).
    private(set) var pickedAt: Date? {
        didSet { scheduleFirstActionRedraw() }
    }
    private var collapsedRedrawTick = 0
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

    /// 펼친 화면 제목 아래 이어서 할 일(R-109). 시작 전·도는 중 펼친 화면은 있으면 보인다.
    /// 게이트가 묻는 중이거나 확인하는 중이면 게이트 칸이 같은 줄을 보이므로 숨긴다(spec 004 R-311).
    var firstAction: String? {
        gatePhase == .closed ? collapsedFirstAction : nil
    }

    /// 접힌 3초 표시에 쓰는 노치 할 일의 첫 행동(R-109). 게이트와 관계없이 저장된 값이다(spec 004 R-311).
    var collapsedFirstAction: String? {
        guard let id = session.taskID else { return nil }
        return tasks.first { $0.id == id }?.firstAction
    }

    /// 접힌 초안에 "이어서 · <첫 행동>"을 보이는지(R-109). 고른 뒤 3초만이고, 도는 중·시간 끝은 spec 001 그대로다.
    /// 게이트를 통과해도 다시 켜지 않는다(spec 004 R-311).
    var showsFirstActionCollapsed: Bool {
        _ = collapsedRedrawTick
        guard Self.isDraft(timer), collapsedFirstAction != nil, let pickedAt else { return false }
        return FirstActionDisplay.showsInCollapsed(pickedAt: pickedAt, now: clock.now())
    }

    var elapsedMinutes: Int {
        guard let run = session.run else { return 0 }
        return Checkpoint.elapsedMinutes(startedAt: run.startedAt, now: clock.now(), quantumMin: run.quantumMin)
    }

    /// 할 일 탭 "다음" 표시(R-102). 보기·정렬과 무관하다.
    var nextMarkID: TaskID? { session.nextMark(input(at: clock.now())) }

    // MARK: 판단 모델(spec 003 data-model §6·§9)

    /// 키가 있는지. 켤 때·키 저장·키 지움 때 `KeyStore.hasKey()`로 읽고, 보내기 직전 키를 읽지 못하면 false로 고친다.
    private(set) var hasKey = false {
        didSet { if hasKey != oldValue { refreshGate() } }
    }
    /// 401·403을 받아 키를 다시 저장하기 전까지 묻지 않는 중이다.
    private(set) var keyNeedsCheck = false {
        didSet { if keyNeedsCheck != oldValue { refreshGate() } }
    }
    /// 키 저장·지우기 가운데 실패한 동작. 다음 성공에 지운다.
    private(set) var keyActionFailure: KeyAction?
    /// 키 저장·지우기가 실패했다. 다음 성공에 꺼진다.
    var keyActionFailed: Bool { keyActionFailure != nil }
    /// 저장소의 판단 결과. 켤 때와 답을 저장한 뒤 다시 읽는다.
    private(set) var scores: [TaskID: TaskScore] = [:]

    // MARK: 판단 공급자(spec 006 data-model §6·§8)

    /// 고른 공급자. 설정이 없으면 Jev, 모르는 ID면 nil이고 그때는 키 동작을 끈다.
    private(set) var selectedProvider: ProviderID?
    /// 판단 기능이 꺼진 이유. 켜져 있거나 질문 파일이 없으면 nil이다.
    private(set) var selectionOff: DecisionSelection.OffReason?
    /// 공급자 고르기·Microsoft 칸 저장 가운데 실패한 동작. 다음 성공에 지운다.
    private(set) var providerActionFailure: ProviderAction?
    private(set) var microsoftEndpoint: String?
    private(set) var microsoftDeployment: String?
    private(set) var microsoftKeyCleared = false

    /// 요청이 갈 곳의 호스트(spec 006 R-606). 판단 기능이 켜져 있으면 지금 바인딩의 주소에서 꺼내 실제 목적지와 늘 같다.
    /// 꺼져 있으면 고정 주소 공급자는 표의 주소, Microsoft는 저장된 주소가 규칙을 지킬 때 그 주소에서 꺼낸다(US3 시나리오 7, #127).
    var sendingHost: String? {
        if let boundURL { return EndpointRule.host(of: boundURL) }
        guard let selectedProvider,
            let config = ProviderCatalog.config(selectedProvider, in: decision?.catalog ?? ProviderCatalog.all)
        else { return nil }
        switch config.endpoint {
        case .fixed(let url):
            return EndpointRule.host(of: url)
        case .userResource:
            guard let microsoftEndpoint,
                case .success(let url) = EndpointRule.check(microsoftEndpoint, allowsPath: false)
            else { return nil }
            return EndpointRule.host(of: url)
        }
    }

    var decisionField: DecisionFieldInput {
        let catalog = decision?.catalog ?? ProviderCatalog.all
        let questions = decision?.questions
        let rows = catalog.map { row in
            let isOpen = questions.map { ProviderCatalog.isOpen(row.id, questions: $0, catalog: catalog) } ?? false
            return ProviderRow(
                id: row.id, displayName: row.displayName, isOpen: isOpen,
                closedNote: isOpen ? nil : DecisionFieldText.closedNote)
        }
        let config = selectedProvider.flatMap { ProviderCatalog.config($0, in: catalog) }
        let baseModel = selectedProvider.flatMap { questions?.models[$0.rawValue] }
        return DecisionFieldInput(
            providers: rows, selected: selectedProvider,
            issueURL: config.flatMap { $0.issueURLConfirmed ? $0.issueURL : nil }, host: sendingHost,
            provisional: baseModel.map { questions?.provisional.contains($0) ?? false } ?? false,
            offNote: selectionOff.map(DecisionFieldText.offNote),
            microsoft: selectedProvider == .microsoft
                ? MicrosoftFieldInput(
                    savedEndpoint: microsoftEndpoint, savedDeployment: microsoftDeployment,
                    showsKeyResetNotice: microsoftEndpoint != nil && !microsoftKeyCleared,
                    keyCleared: microsoftKeyCleared) : nil,
            keyState: keyFieldState, canRetry: canRetryScores, failure: providerActionFailure,
            onSelect: { [weak self] in self?.selectProvider($0) },
            onSaveMicrosoft: { [weak self] in self?.saveMicrosoft(endpoint: $0, deployment: $1) },
            onSaveKey: { [weak self] in self?.saveKey($0) }, onDeleteKey: { [weak self] in self?.deleteKey() },
            onRetry: { [weak self] in self?.retryScores() })
    }

    /// 노치 후보 순서의 앞 세 대기 할 일과 순위(1~3, data-model §10 할 일 탭).
    var ranks: [TaskID: Int] {
        let order = PriorityOrder.order(input(at: clock.now())).prefix(3)
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element.id, $0.offset + 1) })
    }

    /// 기본 탭 키 칸 상태(data-model §10). 할 일 없음은 저장된 할 일이 하나도 없을 때다.
    var keyFieldState: KeyFieldState {
        .make(
            hasKey: hasKey, hasTasks: !tasks.isEmpty, needsCheck: keyNeedsCheck, failedAction: keyActionFailure,
            storageUnavailable: storageUnavailable)
    }

    /// "다시 물어보기"를 누를 수 있는지: 물을 수 있고 다시 물을 할 일이 있다.
    var canRetryScores: Bool {
        guard let judging = queryable else { return false }
        return !pendingQueries(judging, skippingAttempted: false).isEmpty
    }

    /// 노치·할 일 탭의 키 확인 한 줄(spec 004 R-318). 기본 탭 키 칸이 키 확인 필요를 보일 때와 같다.
    var showsKeyNotice: Bool { keyFieldState == .needsCheck }

    /// 설정 창이 열 탭(spec 004 research R8). 설정 창이 나타날 때와 바뀔 때 그 탭으로 바꾸고 비운다.
    var settingsTabRequest: SettingsTab?

    /// 노치 할 일의 이유 줄(spec 004 data-model §2·§4). 시작 전과 도는 중에만 있다.
    var reasonLine: String? {
        guard Self.isDraft(timer) || Self.isRunning(timer), let id = session.taskID,
            let task = tasks.first(where: { $0.id == id }), let questions = decision?.questions
        else { return nil }
        let usable = judging.map(usableScores) ?? [:]
        return ReasonText.line(
            ReasonLine.make(task: task, usable: usable, questions: questions, today: logicalToday, calendar: calendar))
    }

    // MARK: 구체화 게이트(spec 004 data-model §3·§4). 메모리에만 두고 로그에 남기지 않는다.

    /// 할 일마다 제출 횟수와 통과 여부. 앱을 다시 켜면 사라진다(R-309).
    private(set) var gateRecords: [TaskID: GateRecord] = [:]
    /// 제출 뒤 판정을 기다리는 할 일.
    private(set) var gateWaitingTaskID: TaskID?
    /// 노치에 보일 게이트 단계. `refreshGate()`만 판정 시점에 바꾼다.
    private(set) var gatePhase: GatePhase = .closed
    /// 게이트 입력 칸의 글자. 제출하면 그 줄이 남아 다시 묻는 중으로 돌아올 때 보인다.
    var gateDraftText = ""
    /// `gateDraftText`가 어느 할 일의 칸인지. 다시 묻는 중으로 판정한 할 일과 다르면 그 할 일의 마지막 줄로 채운다.
    @ObservationIgnored private var gateDraftTaskID: TaskID?
    /// 첫 행동 저장에 실패했다. 다음 제출 성공이나 게이트가 묻는 중이 아니게 되면 꺼진다.
    private(set) var gateSaveFailed = false

    /// "직접…"을 누른 뒤 칸이 처음 나타날 때 한 번만 포커스를 준다. 마우스로 다시 펼쳐 칸이 다시 만들어질 때는
    /// 주지 않는다(R-002, SC-003).
    @ObservationIgnored private var customFocus = OneShotRequest()
    @ObservationIgnored private var notesFocus = OneShotRequest()
    @ObservationIgnored private let clock: MokaClock
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let settings: any SettingsStore
    @ObservationIgnored private let repository: (any TaskRepository)?
    @ObservationIgnored private let contextStore: (any ContextStore)?
    /// 기본 작업 시간. 처음에 한 번 읽고 설정에서 바꿨을 때만 다시 읽는다(#35).
    @ObservationIgnored private var defaultQuantumMin: Int
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var firstActionRedrawTask: Task<Void, Never>?
    @ObservationIgnored private var observations: [NotificationObservation] = []
    @ObservationIgnored private let decision: DecisionSetup?
    /// 지금 판단 설정. 꺼져 있으면 nil이다. 공급자를 바꾸거나 Microsoft 칸을 저장할 때 다시 만든다.
    @ObservationIgnored private var binding: DecisionBinding?
    /// 지금 바인딩이 보내는 주소. `binding`과 함께 바뀐다.
    @ObservationIgnored private var boundURL: URL?
    /// 바인딩을 다시 만들 때마다 오른다. 다른 세대의 답은 받지 않는다(spec 006 research R6).
    @ObservationIgnored private var providerGeneration = 0
    @ObservationIgnored private let scoreStore: (any ScoreStore)?
    /// 보내기 장부(data-model §6). 메모리에만 둔다.
    @ObservationIgnored private var attempted: [TaskID: Attempt] = [:]
    /// 질의 실행기. 최대 하나다.
    @ObservationIgnored private var queryRunner: Task<Void, Never>?

    private static let logger = Logger(subsystem: "dev.dongwon.moka", category: "timer")
    private static let storageLogger = Logger(subsystem: "dev.dongwon.moka", category: "storage")
    private static let decisionLogger = Logger(subsystem: "dev.dongwon.moka", category: "decision")

    /// `calendar`는 `GregorianCalendar.make(timeZone: .autoupdatingCurrent)`로 한 번 만든 것을 받는다(ADR-0010).
    /// `workspaceCenter`는 깨어남·잠자기 알림을 받는 곳이다. 시험은 전용 센터를 넘긴다.
    /// `decision`이 nil이면 판단 모델에 묻지 않는다.
    init(
        clock: MokaClock, calendar: Calendar, storage: AppStorage,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter, decision: DecisionSetup? = nil
    ) {
        self.clock = clock
        self.calendar = calendar
        settings = storage.settings
        repository = storage.repository
        contextStore = storage.contexts
        scoreStore = storage.scores
        self.decision = decision
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
        // 읽기 실패는 값 없음(Jev)과 달리 모르는 공급자 ID처럼 판단 기능을 끈다(#128).
        do {
            let stored = try CoreSettings.readDecisionProvider(from: storage.settings)
            selectedProvider = stored.map { ProviderID(rawValue: $0) } ?? .typesafe
        } catch {
            selectedProvider = nil
        }
        rebind()
    }

    // MARK: - 앱 수명

    /// 앱 시작: 키·판단 결과 읽기 → 재시작 복구(R-111) → 하루 판정 → 고르기. 저장할 수 없으면 할 일은 건드리지 않는다.
    func launch() {
        refreshHasKey()
        reloadScores()
        reloadContexts()
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
        dropTasks([id])
    }

    /// 여러 개 골라 지우기(R-120). 한 번의 쓰기로 모두 버림으로 바꾸고, 노치의 할 일이 들어 있으면 타이머를 멈추고 다시 고른다.
    /// 지울 할 일이 없거나 쓰기에 실패하면 false.
    @discardableResult
    func dropTasks(_ ids: Set<TaskID>) -> Bool {
        let dropped = tasks.filter { ids.contains($0.id) && $0.status != .dropped }.map { task in
            var task = task
            task.status = .dropped
            return task
        }
        guard let repository, !dropped.isEmpty, write(StoreBatch(updatedTasks: dropped), to: repository) else {
            return false
        }
        reloadTasks()
        let now = clock.now()
        let next = session.taskID.flatMap { ids.contains($0) ? session.taskDropped($0) : nil } ?? session
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

    /// 첫 실행 온보딩을 띄울지(R-116). 저장할 수 없으면(R-119) 끝냄 표시도 남길 수 없어 띄우지 않는다.
    var showsOnboarding: Bool {
        !storageUnavailable && !CoreSettings.isOnboardingDone(in: settings)
    }

    /// 온보딩 끝내기(R-116, data-model §6): 일정·세 설정·끝냄 표시를 저장하고, 일정 목록과 기본 작업 시간을 다시 읽는다.
    /// 실패하면 false이고 끝냄 표시가 남지 않아 다음 실행에 다시 보인다.
    @discardableResult
    func finishOnboarding(_ values: OnboardingValues) -> Bool {
        guard let contextStore else { return false }
        let context = values.context.flatMap { new in
            MokaContext.normalizedName(new.name).map { NewContext(name: $0, date: new.date, impact: new.impact) }
        }
        do {
            try Onboarding.finish(
                context: context, quantumMin: values.quantumMin, extendMin: values.extendMin,
                dayStart: values.dayStart, settings: settings, contexts: contextStore)
        } catch {
            Self.logStorageFailure(error)
            return false
        }
        reloadContexts()
        defaultQuantumChanged()
        return true
    }

    /// 저장할 수 없으면(R-119) 일정을 더하거나 지울 수 없다.
    var canEditContexts: Bool { contextStore != nil }

    /// 일정 더하기(R-115). 이름은 앞뒤 공백을 빼고, 비면 넣지 않는다. 넣기에 실패하면 false.
    @discardableResult
    func addContext(_ new: NewContext) -> Bool {
        guard let contextStore, let name = MokaContext.normalizedName(new.name) else { return false }
        do {
            _ = try contextStore.insertContext(NewContext(name: name, date: new.date, impact: new.impact))
        } catch {
            Self.logStorageFailure(error)
            return false
        }
        reloadContexts()
        return true
    }

    /// 일정 고치기(R-121). 이름은 앞뒤 공백을 빼고, 비면 거부한다. 쓰기에 실패하면 false.
    @discardableResult
    func editContext(_ id: ContextID, _ values: NewContext) -> Bool {
        guard let contextStore, let name = MokaContext.normalizedName(values.name) else { return false }
        do {
            try contextStore.updateContext(MokaContext(id: id, name: name, date: values.date, impact: values.impact))
        } catch {
            Self.logStorageFailure(error)
            return false
        }
        reloadContexts()
        return true
    }

    /// 일정 지우기(R-115). 행을 실제로 지운다(research R4).
    @discardableResult
    func deleteContext(_ id: ContextID) -> Bool {
        guard let contextStore else { return false }
        do {
            try contextStore.deleteContext(id: id)
        } catch {
            Self.logStorageFailure(error)
            return false
        }
        reloadContexts()
        return true
    }

    /// 일정 여러 개 지우기(R-120). 하나라도 실패하면 거기서 멈추고 false, 목록은 다시 읽는다.
    @discardableResult
    func deleteContexts(_ ids: Set<ContextID>) -> Bool {
        guard let contextStore, !ids.isEmpty else { return false }
        defer { reloadContexts() }
        do {
            for id in ids.sorted() {
                try contextStore.deleteContext(id: id)
            }
        } catch {
            Self.logStorageFailure(error)
            return false
        }
        return true
    }

    /// 활성화 판정(research R11): 앱 시작, 잠자기에서 깨어남, 노치 펼침, 설정 창 열기가 부른다.
    /// 반복 리셋(R-113)을 적용하고 빈 상태면 고른다(R-104). 같은 하루에 여러 번 돌아도 결과가 같다.
    func activate() {
        guard let repository else { return }
        attempted = attempted.filter { !$0.value.failed }
        defer { requestScores() }
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

    var otherTaskItems: [OtherTaskItem] {
        let today = logicalToday
        return OtherTaskList.rows(tasks, current: session.taskID, today: today, calendar: calendar).map { task in
            let note = OtherTaskText.note(task, today: today, calendar: calendar)
            return OtherTaskItem(id: task.id, title: task.title, note: note.text, tone: note.tone)
        }
    }

    func beginOtherTask() {
        guard Self.isDraft(timer) else { return }
        isEnteringNewTitle = false
        isPickingOtherTask = true
    }

    func cancelOtherTask() {
        isPickingOtherTask = false
    }

    /// 목록에서 고른 할 일로 초안을 바꾼다(R-104). 칩은 그대로, 기록은 없다.
    func chooseOtherTask(_ id: TaskID) {
        let now = clock.now()
        let next = session.chosenDraft(id, input(at: now))
        guard next != session else { return }
        session = next
        pickedAt = now
    }

    func beginNewTitle() {
        guard Self.isDraft(timer) else { return }
        isPickingOtherTask = false
        isEnteringNewTitle = true
    }

    func cancelNewTitle() {
        isEnteringNewTitle = false
    }

    /// 빠른 입력(R-103). 저장할 수 있으면 할 일을 만들어 그 할 일로 초안을 바꾼다. 아니면 spec 001 타이머만.
    func enterTitle(_ text: String) {
        guard let repository else {
            if send(.enterTitle(text)) == .applied { isEnteringNewTitle = false }
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

    /// 시작 전이면 시작, 시간 끝이면 같은 할 일을 고른 칩으로 다시 시작(N분 더, R-107).
    func start() {
        guard canStart else { return }
        if case .expired(_, let chipMin, _) = timer {
            let notes = currentNotes
            commit(.start) { session, input throws(SessionError) in
                try session.restart(notes, quantumMin: chipMin, input)
            }
        } else {
            commit(.start) { session, input throws(SessionError) in try session.start(input) }
        }
    }

    /// 시간 끝이면 적힌 두 줄(비어도 됨)을 체크포인트로 남긴다(R-107).
    func complete() {
        let notes = Self.isExpired(timer) ? currentNotes : nil
        commit(.complete) { session, input throws(SessionError) in try session.complete(notes, input) }
    }

    func tick() {
        send(.tick)
    }

    // MARK: - 미루기·바꾸기(R-105·R-106)

    /// 도는 중이면 두 줄 입력을 연다. 시간 끝이면 다시 묻지 않고 적힌 두 줄로 바로 남긴다(R-107).
    func beginSetAside(_ action: PendingAction) {
        if Self.isExpired(timer) {
            setAside(action, currentNotes)
            return
        }
        guard Self.isRunning(timer) else { return }
        pendingAction = action
        notesFocus.request()
    }

    func takeNotesFocusRequest() -> Bool {
        notesFocus.take()
    }

    func editNotes(_ draft: NotesDraft) {
        notesDraft = draft
    }

    func cancelSetAside() {
        pendingAction = nil
        notesDraft = NotesDraft()
        notesFocus.cancel()
    }

    func submitSetAside() {
        guard let pendingAction else { return }
        setAside(pendingAction, currentNotes)
    }

    func setAsideWithoutNotes() {
        guard let pendingAction else { return }
        setAside(pendingAction, .empty)
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

    // MARK: - 판단 모델 질의(spec 003 data-model §6)

    /// 다시 물을 할 일을 묻는다. 실행기가 돌고 있으면 그 `Task`를, 보낼 것이 없으면 nil을 돌려준다.
    /// 실행기는 자리가 빌 때마다 다시 물을 할 일을 새로 계산하므로 트리거가 겹쳐도 동시 질의는 4개를 넘지 않는다.
    @discardableResult
    func requestScores() -> Task<Void, Never>? {
        if let queryRunner { return queryRunner }
        guard let judging = queryable, !pendingQueries(judging, skippingAttempted: true).isEmpty else {
            return nil
        }
        let runner = Task { @MainActor in await self.runQueries() }
        queryRunner = runner
        return runner
    }

    /// 키 저장(data-model §9). 앞뒤 공백·줄바꿈을 지우고 비면 저장하지 않는다. 저장하면 장부를 비우고 다시 묻는다.
    @discardableResult
    func saveKey(_ text: String) -> Bool {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyStore = selectedKeyStore, !key.isEmpty else { return false }
        do {
            try keyStore.save(key)
        } catch {
            keyActionFailure = .save
            Self.logKeyFailure("저장", error)
            return false
        }
        keyActionFailure = nil
        keyNeedsCheck = false
        microsoftKeyCleared = false
        attempted = [:]
        refreshHasKey()
        requestScores()
        return true
    }

    /// 온보딩 키 단계 값(spec 006 data-model §8, R-624). 고른 공급자·바인딩과 상관없이 Jev 보관함과 Jev 호스트를 쓴다.
    var onboardingKey: OnboardingKeyInput? {
        guard let decision, let config = ProviderCatalog.config(.typesafe, in: decision.catalog),
            case .fixed(let url) = config.endpoint
        else { return nil }
        let hasKey: Bool
        do {
            hasKey = try decision.keyStore(.typesafe).hasKey()
        } catch {
            Self.logKeyFailure("확인", error)
            hasKey = false
        }
        return OnboardingKeyInput(
            hasKey: hasKey, onSave: { [weak self] in self?.saveOnboardingKey($0) ?? false },
            issueURL: config.issueURLConfirmed ? config.issueURL : nil, host: EndpointRule.host(of: url))
    }

    /// 온보딩 키 단계 저장(R-625). 설정 창 키 저장처럼 앞뒤 공백을 지우고 장부를 비운 뒤 다시 묻지만, Jev 보관함에만
    /// 저장하고 고른 공급자 설정은 쓰지 않는다. 실패는 온보딩 창이 보이므로 기본 탭 키 칸 실패 표시를 남기지 않는다.
    @discardableResult
    func saveOnboardingKey(_ text: String) -> Bool {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decision, !key.isEmpty else { return false }
        do {
            try decision.keyStore(.typesafe).save(key)
        } catch {
            Self.logKeyFailure("저장", error)
            return false
        }
        if selectedProvider == .typesafe {
            keyActionFailure = nil
            keyNeedsCheck = false
        }
        attempted = [:]
        refreshHasKey()
        requestScores()
        return true
    }

    /// 키 지우기. 판단 결과는 지우지 않고 키가 없는 순서(마감 순)로만 바뀐다.
    @discardableResult
    func deleteKey() -> Bool {
        guard let keyStore = selectedKeyStore else { return false }
        do {
            try keyStore.delete()
        } catch {
            keyActionFailure = .delete
            Self.logKeyFailure("지우기", error)
            return false
        }
        keyActionFailure = nil
        keyNeedsCheck = false
        refreshHasKey()
        return true
    }

    /// 공급자 바꾸기(spec 006 data-model §6 "바꾸기"). 같거나 열리지 않은 공급자면 아무것도 하지 않는다.
    func selectProvider(_ id: ProviderID) {
        guard id != selectedProvider, let decision, let questions = decision.questions,
            ProviderCatalog.isOpen(id, questions: questions, catalog: decision.catalog)
        else { return }
        do {
            try CoreSettings.writeDecisionProvider(id, to: settings)
        } catch {
            providerActionFailure = .select
            Self.decisionLogger.error(
                "공급자 고르기 실패: \(String(reflecting: type(of: error)), privacy: .public)")
            return
        }
        selectedProvider = id
        providerChanged()
    }

    /// Microsoft 칸 저장(spec 006 data-model §6). 주소가 거부되면 저장하지 않고 이유를 돌려준다. 빈 값이거나
    /// 주소 규칙으로 정규화한 값이 저장된 값과 같으면 아무것도 하지 않는다.
    /// 저장된 주소를 다른 주소로 바꿀 때만 Microsoft 키를 먼저 지운다(옛 키가 새 호스트로 가지 않게).
    @discardableResult
    func saveMicrosoft(endpoint: String, deployment: String) -> EndpointRejection? {
        let endpointText = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let deploymentText = deployment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decision, selectedProvider == .microsoft, !endpointText.isEmpty, !deploymentText.isEmpty else {
            return nil
        }
        let url: URL
        switch EndpointRule.check(endpointText, allowsPath: false) {
        case .success(let value): url = value
        case .failure(let rejection): return rejection
        }
        // 저장된 주소를 읽지 못하면 같은 주소인지 모르므로 바꾼 것으로 보고 키를 지운다(#128).
        let saved = Result(catching: { try CoreSettings.readMicrosoftEndpoint(from: settings) })
        if (try? saved.get()) == url.absoluteString,
            CoreSettings.readMicrosoftDeployment(from: settings) == deploymentText
        {
            return nil
        }
        let endpointChanged =
            switch saved {
            case .success(let text): text != nil && text != url.absoluteString
            case .failure: true
            }
        var deletedKey = false
        if endpointChanged {
            do {
                try decision.keyStore(.microsoft).delete()
            } catch {
                keyActionFailure = .delete
                Self.logKeyFailure("지우기", error)
                return nil
            }
            deletedKey = true
        }
        do {
            try CoreSettings.writeMicrosoftEndpoint(url, to: settings)
            try CoreSettings.writeMicrosoftDeployment(deploymentText, to: settings)
        } catch {
            // 주소만 저장됐을 수 있으므로 저장된 값으로 바꾸기와 같은 정리를 한다. 보이는 곳과 실제 목적지가 갈리지 않고,
            // 세대가 바뀌어 버려진 답의 할 일도 다시 묻는다.
            Self.decisionLogger.error(
                "Microsoft 칸 저장 실패: \(String(reflecting: type(of: error)), privacy: .public)")
            providerChanged()
            providerActionFailure = .saveMicrosoft
            microsoftKeyCleared = deletedKey
            return nil
        }
        providerChanged()
        microsoftKeyCleared = deletedKey
        return nil
    }

    /// 바꾸기 4~7단계: 세대를 올리고 바인딩을 다시 만든 뒤 장부와 키 확인 필요를 비우고 새 항목으로 다시 묻는다.
    private func providerChanged() {
        providerGeneration += 1
        rebind()
        providerActionFailure = nil
        attempted = [:]
        keyNeedsCheck = false
        keyActionFailure = nil
        microsoftKeyCleared = false
        refreshHasKey()
        refreshGate()
        requestScores()
    }

    /// 메모리의 `selectedProvider`와 설정의 Microsoft 칸 값으로 바인딩을 다시 만든다. 공급자 ID는 설정을 다시 읽지 않아
    /// 키 보관함과 바인딩이 늘 같은 공급자에서 나온다. 꺼지면 이유 종류만 로그에 남긴다.
    private func rebind() {
        guard let decision, let questions = decision.questions else {
            setBinding(nil, off: nil)
            return
        }
        guard let selectedProvider else {
            setBinding(nil, off: .unknownProvider)
            return
        }
        microsoftEndpoint = try? CoreSettings.readMicrosoftEndpoint(from: settings)
        microsoftDeployment = CoreSettings.readMicrosoftDeployment(from: settings)
        let resolution = DecisionSelection.resolve(
            providerID: selectedProvider.rawValue, microsoftEndpoint: microsoftEndpoint,
            microsoftDeployment: microsoftDeployment, questions: questions, catalog: decision.catalog)
        switch resolution {
        case .ready(let ready):
            setBinding((decision.bind(ready), ready.url), off: nil)
        case .off(let reason):
            setBinding(nil, off: reason)
        }
    }

    private func setBinding(_ value: (binding: DecisionBinding, url: URL)?, off reason: DecisionSelection.OffReason?) {
        binding = value?.binding
        boundURL = value?.url
        selectionOff = reason
        if let reason {
            Self.decisionLogger.error("판단 기능 꺼짐: \(Self.offKind(reason), privacy: .public)")
        }
    }

    private static func offKind(_ reason: DecisionSelection.OffReason) -> String {
        switch reason {
        case .unknownProvider: "unknownProvider"
        case .closedProvider: "closedProvider"
        case .needsEndpoint: "needsEndpoint"
        case .needsDeployment: "needsDeployment"
        }
    }

    /// 고른 공급자의 키 보관함. 모르는 공급자 ID면 nil이다.
    private var selectedKeyStore: (any KeyStore)? {
        guard let decision, let selectedProvider else { return nil }
        return decision.keyStore(selectedProvider)
    }

    /// "다시 물어보기". 장부를 비우고 다시 물을 할 일을 묻는다. 키 확인이 필요한 동안은 꺼져 있다.
    @discardableResult
    func retryScores() -> Task<Void, Never>? {
        guard canRetryScores else { return nil }
        attempted = [:]
        return requestScores()
    }

    /// 노치 설정 열기 앞에 기본 탭을 요청한다(spec 004 research R8).
    func requestKeySettings() {
        settingsTabRequest = .basic
    }

    func takeSettingsTabRequest() -> SettingsTab? {
        guard let request = settingsTabRequest else { return nil }
        settingsTabRequest = nil
        return request
    }

    /// 게이트 제출(spec 004 data-model §3). 앞뒤 공백·줄바꿈을 지운 줄을 첫 행동으로 쓰고 할 일을 다시 읽는다.
    /// 다시 읽기가 `requestScores()`를 불러 바뀐 해시로 다시 묻는다. 비었거나 묻는 중이 아니거나 저장에 실패하면 false.
    @discardableResult
    func submitFirstAction(_ text: String) -> Bool {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard gatePhase == .asking, !line.isEmpty, let repository, let id = session.taskID,
            var task = tasks.first(where: { $0.id == id })
        else { return false }
        task.firstAction = line
        guard write(StoreBatch(updatedTasks: [task]), to: repository) else {
            gateSaveFailed = true
            return false
        }
        gateSaveFailed = false
        gateDraftText = line
        gateDraftTaskID = id
        gateRecords[id, default: GateRecord()].submissions += 1
        gateWaitingTaskID = id
        reloadTasks()
        return true
    }

    /// "지금은 넘기기": 통과로 보고 닫는다. 첫 행동과 질의는 그대로다.
    func skipGate() {
        guard gatePhase != .closed, let id = session.taskID else { return }
        gateRecords[id, default: GateRecord()].passed = true
        gateWaitingTaskID = nil
        gateSaveFailed = false
        gatePhase = .closed
    }

    /// 게이트 판정(data-model §3 "판정 시점"). 노치 할 일의 지금 판단 입력 해시는 여기서만 계산한다.
    func refreshGate() {
        guard let judging, let id = session.taskID, Self.isDraft(timer),
            let currentHash = currentJudgmentHash(id)
        else {
            setGate(.closed)
            return
        }
        let record = gateRecords[id] ?? GateRecord()
        let facts = ConcreteGate.Facts(
            isDraft: true, canQuery: queryable != nil, score: usableScores(judging)[id],
            currentHash: currentHash, failedHash: attempted[id].flatMap { $0.failed ? $0.hash : nil },
            threshold: ConcreteGate.threshold(judging.questions, baseModel: judging.baseModel), record: record,
            waiting: gateWaitingTaskID == id)
        let updated = ConcreteGate.afterAnswer(facts)
        if updated != record {
            gateRecords[id] = updated
        }
        let phase = ConcreteGate.phase(facts)
        // 다시 묻는 중인데 칸이 이 할 일의 것이 아니면 마지막에 적은 줄(저장된 첫 행동)로 채운다(data-model §3 마지막 줄).
        // 칸이 이 할 일의 것인 동안 사람이 고치거나 비운 글자는 그대로 둔다.
        if phase == .asking, updated.submissions > 0, gateDraftTaskID != id,
            let line = tasks.first(where: { $0.id == id })?.firstAction
        {
            gateDraftText = line
            gateDraftTaskID = id
        }
        setGate(phase)
    }

    /// 기다림은 `checking`일 때만 이어진다.
    private func setGate(_ phase: GatePhase) {
        if phase != .checking, gateWaitingTaskID != nil {
            gateWaitingTaskID = nil
        }
        if phase != .asking, gateSaveFailed {
            gateSaveFailed = false
        }
        if gatePhase != phase {
            gatePhase = phase
        }
    }

    /// 체크포인트는 그때그때 읽는다(spec 003 data-model §4). 읽지 못하면 nil.
    private func currentJudgmentHash(_ id: TaskID) -> String? {
        guard let repository else { return nil }
        do {
            return judgmentStates(checkpoints: try repository.checkpoints())[id]?.hash
        } catch {
            Self.logStorageFailure(error)
            return nil
        }
    }

    private struct Attempt {
        var hash: String
        var failed: Bool
    }

    private struct Query: Sendable {
        let request: DecisionRequest
        let hash: String
        let key: String
        let provider: any DecisionProvider
        let generation: Int
    }

    private struct QueryOutcome: Sendable {
        let taskID: TaskID
        let hash: String
        let result: Result<DecisionResponse, DecisionError>
        let provider: String
        let generation: Int
    }

    /// 묻지 않는 경우(판단 기능 꺼짐, 키 없음, 키 확인 필요, 판단 결과 저장소 없음)가 아니면 지금 판단 설정.
    private var queryable: Judging? {
        guard let judging, hasKey, !keyNeedsCheck, scoreStore != nil else { return nil }
        return judging
    }

    /// 질문 파일이 없거나 고른 공급자로 판단 설정을 만들지 못하면(spec 006 data-model §6) 판단 기능을 끈다.
    private var judging: Judging? {
        guard let questions = decision?.questions, let binding else { return nil }
        return Judging(questions: questions, binding: binding)
    }

    private func usableScores(_ judging: Judging) -> [TaskID: TaskScore] {
        ScoreRules.usable(
            scores: scores, hasKey: hasKey, questionVersion: judging.questions.version, provider: judging.provider)
    }

    /// 다시 물을 할 일과 지금 판단 입력, 보낼 순서대로. 체크포인트는 그때그때 읽는다(data-model §4).
    private func pendingQueries(_ judging: Judging, skippingAttempted: Bool) -> [(TaskID, JudgmentState)] {
        guard let repository, !tasks.isEmpty else { return [] }
        let checkpoints: [Checkpoint]
        do {
            checkpoints = try repository.checkpoints()
        } catch {
            Self.logStorageFailure(error)
            return []
        }
        let states = judgmentStates(checkpoints: checkpoints)
        return ScoringPlan.needsQuery(
            tasks: tasks, scores: scores, states: states, questionVersion: judging.questions.version,
            provider: judging.provider
        )
        .compactMap { id in
            guard let state = states[id] else { return nil }
            if skippingAttempted, attempted[id]?.hash == state.hash { return nil }
            return (id, state)
        }
    }

    private func judgmentStates(checkpoints: [Checkpoint]) -> [TaskID: JudgmentState] {
        let today = logicalToday
        return Dictionary(
            uniqueKeysWithValues: tasks.map { task in
                (
                    task.id,
                    JudgmentState.build(
                        task: task, contexts: contexts, checkpoints: checkpoints, today: today, calendar: calendar)
                )
            })
    }

    /// 단일 실행기. 꺼내기·답 받기·끝내기 판정은 MainActor에서 하고, 끝내기 판정과 `queryRunner = nil`은
    /// 같은 동기 구간에서 한다(끝나는 순간 들어온 트리거를 잃지 않게).
    /// 공급자는 꺼낼 때마다 지금 바인딩에서 읽는다(spec 006 research R6).
    private func runQueries() async {
        await withTaskGroup(of: QueryOutcome.self) { group in
            var inFlight = 0
            while true {
                while inFlight < Defaults.maxConcurrentDecisions, let query = takeNextQuery() {
                    group.addTask {
                        let result: Result<DecisionResponse, DecisionError>
                        do throws(DecisionError) {
                            result = .success(try await query.provider.decide(query.request, key: query.key))
                        } catch {
                            result = .failure(error)
                        }
                        return QueryOutcome(
                            taskID: query.request.taskID, hash: query.hash, result: result,
                            provider: query.provider.name, generation: query.generation)
                    }
                    inFlight += 1
                }
                guard inFlight > 0, let outcome = await group.next() else {
                    queryRunner = nil
                    return
                }
                inFlight -= 1
                receive(outcome)
            }
        }
    }

    /// 다음에 보낼 질의 하나. 꺼낼 때마다 묻지 않는 경우를 다시 보고, 키를 읽은 뒤에만 장부에 적는다.
    private func takeNextQuery() -> Query? {
        guard let judging = queryable, let keyStore = selectedKeyStore,
            let next = pendingQueries(judging, skippingAttempted: true).first
        else { return nil }
        let (id, state) = next
        let key: String?
        do {
            key = try keyStore.read()
        } catch {
            Self.logKeyFailure("읽기", error)
            key = nil
        }
        guard let key else {
            hasKey = false
            return nil
        }
        let hash = state.hash
        attempted[id] = Attempt(hash: hash, failed: false)
        return Query(
            request: DecisionRequest(
                taskID: id, model: judging.binding.requestModel, state: state.bytes, questions: judging.questions),
            hash: hash, key: key, provider: judging.binding.provider, generation: providerGeneration)
    }

    /// 답 받기: 지금 판단 입력이 요청 때와 같고 할 일이 대기·진행 중일 때만 저장한다. 실패는 종류만 남긴다.
    /// 공급자를 바꾸기 전에 떠난 답은 성공이든 실패든 아무것도 바꾸지 않는다(spec 006 research R6).
    private func receive(_ outcome: QueryOutcome) {
        guard outcome.generation == providerGeneration else { return }
        let response: DecisionResponse
        switch outcome.result {
        case .success(let value):
            response = value
        case .failure(.unauthorized):
            keyNeedsCheck = true
            Self.decisionLogger.error("판단 실패: unauthorized")
            return
        case .failure(let error):
            markFailed(outcome, kind: String(describing: error))
            return
        }
        guard let questions = judging?.questions, let scoreStore, let repository,
            let task = tasks.first(where: { $0.id == outcome.taskID })
        else { return }
        let checkpoints: [Checkpoint]
        do {
            checkpoints = try repository.checkpoints()
        } catch {
            Self.logStorageFailure(error)
            markFailed(outcome, kind: "checkpoints")
            return
        }
        let current = JudgmentState.build(
            task: task, contexts: contexts, checkpoints: checkpoints, today: logicalToday, calendar: calendar)
        guard ScoringPlan.accepts(requestHash: outcome.hash, currentHash: current.hash, taskStatus: task.status)
        else { return }
        guard
            let score = ScoreRules.score(
                taskID: task.id, response: response, questions: questions, provider: outcome.provider,
                stateHash: outcome.hash, now: clock.now())
        else {
            markFailed(outcome, kind: "malformed")
            return
        }
        do {
            try scoreStore.upsertScore(score)
        } catch {
            Self.logStorageFailure(error)
            markFailed(outcome, kind: "store")
            return
        }
        reloadScores()
    }

    /// 실패한 할 일은 다음 활성화 때 한 번 다시 보낸다(장부의 `failed`).
    private func markFailed(_ outcome: QueryOutcome, kind: String) {
        if attempted[outcome.taskID]?.hash == outcome.hash {
            attempted[outcome.taskID]?.failed = true
        }
        Self.decisionLogger.error("판단 실패: \(kind, privacy: .public)")
        refreshGate()
    }

    private func refreshHasKey() {
        guard let keyStore = selectedKeyStore else {
            hasKey = false
            return
        }
        do {
            hasKey = try keyStore.hasKey()
        } catch {
            Self.logKeyFailure("확인", error)
            hasKey = false
        }
    }

    private func reloadScores() {
        guard let scoreStore else {
            scores = [:]
            return
        }
        do {
            scores = try scoreStore.scores()
        } catch {
            Self.logStorageFailure(error)
            scores = [:]
        }
        refreshGate()
    }

    /// 키 값은 남기지 않는다. 동작과 오류 종류만.
    private static func logKeyFailure(_ action: String, _ error: any Error) {
        decisionLogger.error(
            "키 \(action, privacy: .public) 실패: \(String(reflecting: type(of: error)), privacy: .public)")
    }

    // MARK: - 내부

    private func input(at now: Date) -> SessionInput {
        let scoring = judging.map { judging in
            SessionScoring(
                usable: usableScores(judging), questions: judging.questions,
                thresholds: judging.questions.thresholds(for: judging.baseModel),
                today: DayBoundary.day(
                    containing: now, dayStart: CoreSettings.readDayStart(from: settings), calendar: calendar))
        }
        return SessionInput(
            tasks: tasks, now: now, defaultQuantumMin: defaultQuantumMin, calendar: calendar, scoring: scoring)
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

    private var currentNotes: CheckpointNotes {
        CheckpointNotes(doneNote: notesDraft.done, nextNote: notesDraft.next)
    }

    private func setAside(_ action: PendingAction, _ notes: CheckpointNotes) {
        commit(.complete) { session, input throws(SessionError) in
            switch action {
            case .skip: try session.skip(notes, input)
            case .switch: try session.switchTask(notes, input)
            }
        }
    }

    private static func isEmpty(_ timer: NotchTimer) -> Bool {
        if case .empty = timer { return true }
        return false
    }

    private static func isExpired(_ timer: NotchTimer) -> Bool {
        if case .expired = timer { return true }
        return false
    }

    private static func isRunning(_ timer: NotchTimer) -> Bool {
        if case .running = timer { return true }
        return false
    }

    private static func isDraft(_ timer: NotchTimer) -> Bool {
        if case .empty(.some) = timer { return true }
        return false
    }

    /// 빈 상태(초안 없음)면 고른다(R-104). 새로 고르면 `pickedAt`을 그 시각으로 둔다.
    private func pickIfEmpty(at now: Date) {
        let next = session.picked(input(at: now))
        guard next != session else { return }
        session = next
        pickedAt = now
        remainingSeconds = timer.remainingSeconds(at: now)
    }

    private func reloadContexts() {
        guard let contextStore else { return }
        do {
            contexts = try contextStore.contexts()
        } catch {
            Self.logStorageFailure(error)
        }
        requestScores()
    }

    private func reloadTasks() {
        guard let repository else { return }
        do {
            tasks = try repository.tasks()
        } catch {
            Self.logStorageFailure(error)
        }
        requestScores()
        refreshGate()
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

    private func scheduleFirstActionRedraw() {
        firstActionRedrawTask?.cancel()
        firstActionRedrawTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(FirstActionDisplay.collapsedSeconds))
            guard !Task.isCancelled, let self else { return }
            let animation = NotchLayout.expansionAnimation(
                expanding: false, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            withAnimation(animation) {
                collapsedRedrawTick += 1
            }
        }
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
