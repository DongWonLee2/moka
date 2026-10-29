import AppKit
import MokaCore

/// 패널을 띄울 표시 위치와 그 화면의 치수.
struct ScreenPlacement {
    let target: DisplayTarget
    let geometry: ScreenGeometry
    let backingScale: Double
}

/// 화면 목록에서 표시 위치를 고르고(data-model §5), 화면 연결이 바뀔 때마다 다시 골라 알린다(R-011).
/// 알림을 받은 쪽은 창을 다시 만들지 않고 옮기기만 한다(ADR-0008).
@MainActor
final class ScreenWatcher {
    private var observer: (any NSObjectProtocol)?

    /// `onChange`는 `didChangeScreenParametersNotification`마다 새 표시 위치로 불린다. 화면이 없으면 nil.
    init(onChange: @escaping @MainActor (ScreenPlacement?) -> Void) {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onChange(Self.currentPlacement()) }
        }
    }

    static func currentPlacement() -> ScreenPlacement? {
        let screens = NSScreen.screens
        let candidates = screens.compactMap { screen in
            displayID(of: screen).map { (id: $0, screen: screen) }
        }
        let infos = candidates.map { candidate in
            ScreenInfo(
                id: candidate.id,
                // 노치는 내장 화면에만 있다.
                hasNotch: candidate.screen.safeAreaInsets.top > 0,
                // 메뉴 막대가 있는 화면. `NSScreen.main`은 key window가 있는 화면이라 쓰지 않는다.
                isMain: candidate.screen == screens.first)
        }
        guard let target = chooseDisplayTarget(infos) else { return nil }
        let chosenID: UInt32
        switch target {
        case .notch(let id), .floating(let id):
            chosenID = id
        }
        guard let screen = candidates.first(where: { $0.id == chosenID })?.screen else { return nil }
        return ScreenPlacement(
            target: target, geometry: geometry(of: screen), backingScale: Double(screen.backingScaleFactor))
    }

    private static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func geometry(of screen: NSScreen) -> ScreenGeometry {
        ScreenGeometry(
            frame: PanelRect(screen.frame),
            visibleFrame: PanelRect(screen.visibleFrame),
            safeAreaTop: Double(screen.safeAreaInsets.top),
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea.map { Double($0.width) },
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea.map { Double($0.width) })
    }
}

extension PanelRect {
    init(_ rect: NSRect) {
        self.init(
            x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }
}

extension NSRect {
    init(_ rect: PanelRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
