import AppKit
import SwiftUI

/// 직접 만든 nonactivating 패널 하나로 노치 판을 띄운다(ADR-0008, research R6).
/// 패널 창은 펼친 판까지 들어가는 고정 크기 투명 창이고 노치 가운데·위에 붙인다. 판 모양은 SwiftUI 마스크가
/// 애니메이션으로 키우고 줄이며, 창 크기는 바꾸지 않는다(창 크기와 SwiftUI 스프링이 따로 움직여 튀었다, PR #30 사람 확인).
/// 투명한 부분의 클릭은 아래 앱으로 넘어간다. hover는 보이는 판 자리에서만 받는다.
@MainActor
final class NotchPanelHost: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let panel: NotchPanel
    private let hostingView: NSHostingView<NotchPanelRoot>
    private let hoverView: HoverTrackingView
    private var contentLayout: PanelContentLayout?

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
        container.addSubview(hoverView)
        panel.contentView = container
    }

    func show(on placement: ScreenPlacement) {
        let screen = placement.screen
        let metrics: NotchMetrics
        let centerX: CGFloat
        let top: CGFloat
        switch placement.target {
        case .notch:
            let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
            let holeWidth = max(screen.frame.width - leftWidth - rightWidth, 0)
            metrics = NotchMetrics(holeWidth: holeWidth, height: screen.safeAreaInsets.top)
            centerX = screen.frame.minX + leftWidth + holeWidth / 2
            top = screen.frame.maxY
            panel.level = .screenSaver
        case .floating:
            // 떠 있는 창은 단위 5(T036). 지금은 같은 판을 메뉴 막대 아래 가운데에 구멍 없이 둔다.
            metrics = NotchMetrics(holeWidth: 0, height: 28)
            centerX = screen.frame.midX
            top = screen.visibleFrame.maxY
            panel.level = .statusBar
        }

        hostingView.rootView = NotchPanelRoot(
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
            onLayoutChange: { [weak self] layout in
                self?.contentLayout = layout
                self?.updateHoverFrame()
            })
        let size = NotchLayout.panelSize(metrics: metrics)
        // 정수가 아니라 화면 픽셀 단위로 맞춘다. 노치 가운데가 반 포인트여도 어긋나지 않는다.
        let scale = screen.backingScaleFactor
        let originX = ((centerX - size.width / 2) * scale).rounded() / scale
        panel.setFrame(
            NSRect(x: originX, y: top - size.height, width: size.width, height: size.height),
            display: true)
        updateHoverFrame()
        panel.orderFrontRegardless()
    }

    /// 판은 패널 위쪽 가운데에서 가로로 `offsetX`만큼 밀려 놓인다. 그 자리에 hover 영역을 둔다(목표 크기 기준).
    private func updateHoverFrame() {
        guard let contentLayout else { return }
        let bounds = panel.contentView?.bounds ?? .zero
        let size = contentLayout.size
        hoverView.frame = NSRect(
            x: (bounds.width - size.width) / 2 + contentLayout.offsetX, y: bounds.height - size.height,
            width: size.width, height: size.height)
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

/// 보이는 판 자리에서 마우스 들어옴·나감을 받는다. 앱이 활성이 아니어도 받는다(`.activeAlways`).
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

/// AppState를 읽어 뷰에 값과 콜백만 넘기는 연결부. 판은 고정 패널 위쪽 가운데에 놓인다.
struct NotchPanelRoot: View {
    let appState: AppState
    var metrics = NotchMetrics(holeWidth: 0, height: 0)
    var onStart: () -> Void = {}
    var onComplete: () -> Void = {}
    var onLayoutChange: (PanelContentLayout) -> Void = { _ in }

    var body: some View {
        let offsetX = NotchLayout.horizontalOffset(
            timer: appState.timer, remainingSeconds: appState.remainingSeconds, isExpanded: appState.isExpanded)
        NotchContentView(
            timer: appState.timer,
            remainingSeconds: appState.remainingSeconds,
            isExpanded: appState.isExpanded,
            metrics: metrics,
            titleFocusRequest: appState.titleFocusRequest,
            chip: QuantumChipInput(
                customText: appState.customText,
                canStart: appState.canStart,
                onChoose: { appState.chooseQuantum($0) },
                onBeginCustom: { appState.beginCustom() },
                onEditCustom: { appState.editCustom($0) },
                takeFocusRequest: { appState.takeCustomFocusRequest() }),
            onEnterTitle: { appState.enterTitle($0) },
            onStart: onStart,
            onComplete: onComplete
        )
        .fixedSize()
        .onGeometryChange(for: PanelContentLayout.self) {
            PanelContentLayout(size: $0.size, offsetX: offsetX)
        } action: {
            onLayoutChange($0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 판 크기와 가로 이동 거리(목표값). hover 영역을 정하는 데만 쓴다.
struct PanelContentLayout: Equatable {
    var size: CGSize
    var offsetX: CGFloat
}
