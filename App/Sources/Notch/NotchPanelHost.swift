import AppKit
import SwiftUI

/// 직접 만든 nonactivating 패널 하나로 노치 판을 띄운다(ADR-0008, research R6).
/// 패널 프레임은 내용 크기이고, 노치 위 가운데에 위쪽을 맞춘다. 내용은 구멍이 가운데에 오도록 여백을 더한 크기다.
/// 판이 커질 때는 패널을 먼저 키우고(내용이 그 안에서 자람), 작아질 때는 접는 애니메이션이 끝난 뒤 줄인다
/// (먼저 줄이면 줄어드는 판이 잘린다).
@MainActor
final class NotchPanelHost: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let panel: NotchPanel
    private let hostingView: NSHostingView<NotchPanelRoot>
    private let hoverView: HoverTrackingView
    private var anchor: Anchor?
    private var layout: PanelContentLayout?
    private var pendingShrink: Task<Void, Never>?

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
        hoverView = HoverTrackingView { [weak appState] hovering in
            appState?.setHovering(hovering)
        }
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
        hostingView.autoresizingMask = [.width, .height]
        let container = NSView()
        container.addSubview(hostingView)
        // hover는 검은 판 위에서만 받는다(구멍을 가운데에 두려고 더한 투명 여백은 뺀다).
        container.addSubview(hoverView)
        panel.contentView = container
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
            onLayoutChange: { [weak self] layout in self?.resize(to: layout) })
        hostingView.rootView = root
        // 패널 안의 호스팅 뷰는 크기 제약을 내지 않으므로(sizingOptions = []) 첫 크기는 따로 잰다.
        resize(
            to: PanelContentLayout(
                size: NSHostingView(rootView: root).fittingSize,
                holeCenterOffset: NotchLayout.holeCenterOffset(
                    timer: appState.timer, remainingSeconds: appState.remainingSeconds,
                    isExpanded: appState.isExpanded)))
        panel.orderFrontRegardless()
    }

    private func resize(to layout: PanelContentLayout) {
        guard layout.size.width > 0, layout.size.height > 0, let target = panelFrame(size: layout.size) else { return }
        self.layout = layout
        pendingShrink?.cancel()
        pendingShrink = nil

        let current = panel.frame
        let grown =
            current.isEmpty
            ? target
            : panelFrame(
                size: CGSize(width: max(current.width, target.width), height: max(current.height, target.height)))
        apply(grown ?? target)
        guard let grown, grown != target else { return }
        pendingShrink = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NotchLayout.collapseDuration + 0.03))
            guard !Task.isCancelled else { return }
            self?.apply(target)
        }
    }

    /// 노치 가운데 위에 위쪽을 맞춘 프레임. 내용이 구멍을 가운데에 두므로 그대로 가운데 맞춤이다.
    private func panelFrame(size: CGSize) -> NSRect? {
        guard let anchor else { return nil }
        return NSRect(
            x: (anchor.centerX - size.width / 2).rounded(), y: anchor.top - size.height,
            width: size.width, height: size.height)
    }

    private func apply(_ frame: NSRect) {
        if frame != panel.frame {
            panel.setFrame(frame, display: true, animate: false)
        }
        updateHoverFrame()
    }

    /// 내용은 패널 위쪽 가운데에 놓인다. 그중 여백을 뺀 검은 판 자리에 hover 영역을 둔다.
    private func updateHoverFrame() {
        guard let layout else { return }
        let bounds = panel.contentView?.bounds ?? .zero
        let insets = NotchLayout.balancingInsets(holeCenterOffset: layout.holeCenterOffset)
        let outerMinX = (bounds.width - layout.size.width) / 2
        hoverView.frame = NSRect(
            x: outerMinX + insets.leading, y: bounds.height - layout.size.height,
            width: layout.size.width - insets.leading - insets.trailing, height: layout.size.height)
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

/// 검은 판 자리에서 마우스 들어옴·나감을 받는다. 앱이 활성이 아니어도 받는다(`.activeAlways`).
/// 클릭은 받지 않고 아래 호스팅 뷰로 넘긴다.
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
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
    var onLayoutChange: (PanelContentLayout) -> Void = { _ in }

    var body: some View {
        let holeCenterOffset = NotchLayout.holeCenterOffset(
            timer: appState.timer, remainingSeconds: appState.remainingSeconds, isExpanded: appState.isExpanded)
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
        .onGeometryChange(for: PanelContentLayout.self) {
            PanelContentLayout(size: $0.size, holeCenterOffset: holeCenterOffset)
        } action: {
            onLayoutChange($0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 판 내용 크기(구멍을 가운데에 두는 여백 포함)와 구멍 가운데 위치. hover 영역은 여백을 뺀 자리다.
struct PanelContentLayout: Equatable {
    var size: CGSize
    var holeCenterOffset: CGFloat
}
