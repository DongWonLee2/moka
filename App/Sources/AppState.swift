import AppKit
import MokaCore
import Observation
import SwiftUI
import os

/// 화면 상태와 타이머 값(data-model §6). 타이머 규칙은 MokaCore `NotchTimer`가 정하고 여기서는 이벤트를 전달만 한다.
/// 할 일과 타이머는 메모리에만 둔다(R-014).
@Observable @MainActor
final class AppState {
    private(set) var timer: NotchTimer = .empty(draft: nil)
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

    /// "직접…"을 누른 뒤 칸이 처음 나타날 때 한 번만 포커스를 준다. 마우스로 다시 펼쳐 칸이 다시 만들어질 때는
    /// 주지 않는다(R-002, SC-003).
    @ObservationIgnored private var customFocus = OneShotRequest()
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
        timer.applyDefaultQuantumChange(
            QuantumSettings.readDefault(from: settings), isEditingCustom: customText != nil)
    }

    func start() {
        guard canStart else { return }
        send(.start)
    }

    func complete() {
        send(.complete)
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
    private func updateExpansion() {
        let expanded = shouldStayExpanded(pinned: isPinnedOpen, focused: isInputFocused, hovering: isHovering)
        guard expanded != isExpanded else { return }
        let animation = NotchLayout.expansionAnimation(
            expanding: expanded, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        withAnimation(animation) {
            isExpanded = expanded
        }
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
        let previous = timer
        let result = timer.apply(event, at: now, defaultQuantumMin: QuantumSettings.readDefault(from: settings))
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
