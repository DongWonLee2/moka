import AppKit
import SwiftUI

/// 직접 만든 nonactivating 패널 하나로 노치 판을 띄운다(ADR-0008, research R6).
/// 패널 프레임은 늘 내용 크기와 같고, 노치 위 가운데에 위쪽을 맞춘다.
@MainActor
final class NotchPanelHost: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let panel: NotchPanel
    private let hostingView: NSHostingView<NotchPanelRoot>
    private var anchor: Anchor?

    /// 패널 위쪽 가운데 점(화면 좌표).
    private struct Anchor {
        var centerX: CGFloat
        var top: CGFloat
    }

    init(appState: AppState) {
        self.appState = appState
        panel = NotchPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        hostingView = NSHostingView(rootView: NotchPanelRoot(appState: appState))
        super.init()

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.delegate = self
        panel.onLeftMouseDown = { [weak self] in self?.panelClicked() }

        hostingView.sizingOptions = []
        let trackingView = HoverTrackingView { [weak appState] hovering in
            appState?.setHovering(hovering)
        }
        hostingView.autoresizingMask = [.width, .height]
        trackingView.addSubview(hostingView)
        panel.contentView = trackingView
    }

    func show(on placement: ScreenPlacement) {
        let screen = placement.screen
        let metrics: NotchMetrics
        switch placement.target {
        case .notch:
            let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
            let holeWidth = max(screen.frame.width - leftWidth - rightWidth, 0)
            metrics = NotchMetrics(holeWidth: holeWidth, height: screen.safeAreaInsets.top)
            anchor = Anchor(centerX: screen.frame.minX + leftWidth + holeWidth / 2, top: screen.frame.maxY)
            panel.level = .screenSaver
        case .floating:
            // 떠 있는 창은 단위 5(T036). 지금은 같은 판을 메뉴 막대 아래 가운데에 구멍 없이 둔다.
            metrics = NotchMetrics(holeWidth: 0, height: 28)
            anchor = Anchor(centerX: screen.frame.midX, top: screen.visibleFrame.maxY)
            panel.level = .statusBar
        }

        let root = NotchPanelRoot(
            appState: appState,
            metrics: metrics,
            onStart: { [weak self] in
                self?.appState.start()
                self?.giveUpKey()
            },
            onComplete: { [weak self] in
                self?.appState.complete()
                self?.giveUpKey()
            },
            onSizeChange: { [weak self] size in self?.resize(to: size) })
        hostingView.rootView = root
        // 패널 안의 호스팅 뷰는 크기 제약을 내지 않으므로(sizingOptions = []) 첫 크기는 따로 잰다.
        resize(to: NSHostingView(rootView: root).fittingSize)
        panel.orderFrontRegardless()
    }

    private func resize(to size: CGSize) {
        guard let anchor, size.width > 0, size.height > 0 else { return }
        let frame = NSRect(
            x: (anchor.centerX - size.width / 2).rounded(), y: anchor.top - size.height,
            width: size.width, height: size.height)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true, animate: false)
    }

    private func panelClicked() {
        panel.makeKey()
        appState.panelClicked()
    }

    /// 시작·완료 뒤 key를 내려놓아 키 입력이 이전 앱으로 돌아가게 한다(T015 사람 확인).
    private func giveUpKey() {
        panel.resignKey()
        appState.setInputFocused(false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        appState.setInputFocused(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        appState.setInputFocused(false)
    }
}

/// key가 될 수 있는 nonactivating 패널. 왼쪽 클릭을 먼저 알린다(펼친 판 클릭 → makeKey).
final class NotchPanel: NSPanel {
    var onLeftMouseDown: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            onLeftMouseDown?()
        }
        super.sendEvent(event)
    }
}

/// 패널 전체에서 마우스 들어옴·나감을 받는다. 앱이 활성이 아니어도 받는다(`.activeAlways`).
final class HoverTrackingView: NSView {
    private let onHoverChange: (Bool) -> Void

    init(onHoverChange: @escaping (Bool) -> Void) {
        self.onHoverChange = onHoverChange
        super.init(frame: .zero)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange(false)
    }
}

/// AppState를 읽어 뷰에 값과 콜백만 넘기는 연결부.
struct NotchPanelRoot: View {
    let appState: AppState
    var metrics = NotchMetrics(holeWidth: 0, height: 0)
    var onStart: () -> Void = {}
    var onComplete: () -> Void = {}
    var onSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        NotchContentView(
            timer: appState.timer,
            remainingSeconds: appState.remainingSeconds,
            isExpanded: appState.isExpanded,
            metrics: metrics,
            titleFocusRequest: appState.titleFocusRequest,
            onEnterTitle: { appState.enterTitle($0) },
            onStart: onStart,
            onComplete: onComplete
        )
        .fixedSize()
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            onSizeChange($0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
