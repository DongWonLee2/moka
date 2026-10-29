import AppKit
import MokaCore
import SwiftUI

/// 직접 만든 nonactivating 패널 하나로 노치 판을 띄운다(ADR-0008, research R6).
/// 노치 없는 화면에서는 같은 패널을 노치 모양 없이 메뉴 막대 아래 가운데에 고정한다(R-011, 드래그 없음).
/// 패널 창은 펼친 판까지 들어가는 고정 크기 투명 창이고 노치 가운데·위(또는 메뉴 막대 아래 가운데)에 붙인다.
/// 판 모양은 SwiftUI 마스크가 애니메이션으로 키우고 줄이며, 창 크기는 바꾸지 않는다(창 크기와 SwiftUI 스프링이 따로 움직여 튀었다, PR #30 사람 확인).
/// 투명한 부분의 클릭은 아래 앱으로 넘어간다. hover는 보이는 판 자리에서만 받는다.
@MainActor
final class NotchPanelHost: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let panel: NotchPanel
    private let hostingView: NSHostingView<NotchPanelRoot>
    private let hoverView: HoverTrackingView
    private var contentLayout: PanelContentLayout?
    private var currentMetrics: NotchMetrics?
    private var currentStyle: PanelStyle?

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

    /// 표시 위치로 패널을 옮긴다(R-011). 처음 띄울 때와 화면 연결이 바뀔 때 모두 부른다.
    /// 창은 다시 만들지 않고 `setFrame`으로만 옮기므로 key 상태와 입력 중인 글자가 남는다(ADR-0008).
    /// 타이머와 `isPinnedOpen`은 `AppState`에 있고 여기서 건드리지 않는다. 화면이 없으면(nil) 감춘다.
    func move(to placement: ScreenPlacement?) {
        guard let placement else {
            panel.orderOut(nil)
            return
        }
        let anchor = panelAnchor(for: placement.target, on: placement.geometry)
        let metrics = NotchMetrics(holeWidth: anchor.holeWidth, height: anchor.barHeight)
        let style: PanelStyle
        switch placement.target {
        case .notch:
            style = .notch
            panel.level = .screenSaver
        case .floating:
            style = .floating
            panel.level = .statusBar
        }

        // 판 모양이 바뀔 때만 뷰를 바꾼다. 같은 화면 안 변경(해상도 등)에서는 위치만 옮긴다.
        if metrics != currentMetrics || style != currentStyle {
            currentMetrics = metrics
            currentStyle = style
            hostingView.rootView = NotchPanelRoot(
                appState: appState,
                metrics: metrics,
                style: style,
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
        }
        let size = NotchLayout.panelSize(metrics: metrics)
        let frame = panelFrame(
            anchor: anchor, width: Double(size.width), height: Double(size.height), scale: placement.backingScale)
        panel.setFrame(NSRect(frame), display: true)
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
    var style: PanelStyle = .notch
    var onStart: () -> Void = {}
    var onComplete: () -> Void = {}
    var onLayoutChange: (PanelContentLayout) -> Void = { _ in }

    var body: some View {
        let offsetX = NotchLayout.horizontalOffset(
            timer: appState.timer, remainingSeconds: appState.remainingSeconds, isExpanded: appState.isExpanded,
            style: style)
        NotchContentView(
            timer: appState.timer,
            remainingSeconds: appState.remainingSeconds,
            isExpanded: appState.isExpanded,
            isHovering: appState.isHovering,
            metrics: metrics,
            style: style,
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
        // 우클릭 메뉴는 보이는 요소가 아니라서(R-006) 뷰가 아니라 여기서 붙인다. 빈 상태·도는 중·시간 끝 모두(R-012).
        .contextMenu {
            OpenSettingsButton()
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
        }
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
