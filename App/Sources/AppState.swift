import AppKit
import MokaCore
import Observation
import os

/// 화면 상태와 타이머 값(data-model §6). 타이머 규칙은 MokaCore `NotchTimer`가 정하고 여기서는 이벤트를 전달만 한다.
/// 할 일과 타이머는 메모리에만 둔다(R-014).
@Observable @MainActor
final class AppState {
    private(set) var timer: NotchTimer = .empty(draft: nil)
    /// 화면에 쓰는 남은 초. 늘 `apply(.tick, …)` 뒤에 다시 계산한다(#13).
    private(set) var remainingSeconds: Int?
    /// 시간 끝 자동 펼침 고정(R-009). 자동 펼침은 4b에서 켠다.
    private(set) var isPinnedOpen = false
    private(set) var isHovering = false
    private(set) var isInputFocused = false
    private(set) var titleFocusRequest = 0

    var isExpanded: Bool {
        shouldStayExpanded(pinned: isPinnedOpen, focused: isInputFocused, hovering: isHovering)
    }

    @ObservationIgnored private let clock: MokaClock
    @ObservationIgnored private let settings: any SettingsStore
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

    private static let logger = Logger(subsystem: "dev.dongwon.moka", category: "timer")

    init(clock: MokaClock, settings: any SettingsStore) {
        self.clock = clock
        self.settings = settings
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func enterTitle(_ text: String) {
        send(.enterTitle(text))
    }

    func start() {
        if send(.start) == .applied {
            isPinnedOpen = false
        }
    }

    func complete() {
        if send(.complete) == .applied {
            isPinnedOpen = false
        }
    }

    func tick() {
        send(.tick)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    func setInputFocused(_ focused: Bool) {
        isInputFocused = focused
    }

    /// 펼친 판을 클릭했다. 빈 상태면 제목 칸에 포커스를 준다(data-model §6).
    func panelClicked() {
        if case .empty(nil) = timer {
            titleFocusRequest += 1
        }
    }

    @discardableResult
    private func send(_ event: TimerEvent) -> TransitionResult {
        let now = clock.now()
        let before = Self.phaseName(timer)
        let result = timer.apply(event, at: now, defaultQuantumMin: QuantumSettings.readDefault(from: settings))
        remainingSeconds = timer.remainingSeconds(at: now)
        let after = Self.phaseName(timer)

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
