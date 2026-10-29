import AppKit
import MokaCore

/// 패널을 띄울 화면과 위치 종류.
struct ScreenPlacement {
    let target: DisplayTarget
    let screen: NSScreen
}

/// 현재 화면 목록에서 표시 위치를 고른다(data-model §5). 화면 변경 구독(T035)은 아직 없다.
@MainActor
enum ScreenWatcher {
    static func currentPlacement() -> ScreenPlacement? {
        let screens = NSScreen.screens
        let candidates = screens.compactMap { screen in
            displayID(of: screen).map { (id: $0, screen: screen) }
        }
        let infos = candidates.map { candidate in
            ScreenInfo(
                id: candidate.id,
                hasNotch: candidate.screen.safeAreaInsets.top > 0,
                isMain: candidate.screen == screens.first)
        }
        guard let target = chooseDisplayTarget(infos) else { return nil }
        let chosenID: UInt32
        switch target {
        case .notch(let id), .floating(let id):
            chosenID = id
        }
        guard let screen = candidates.first(where: { $0.id == chosenID })?.screen else { return nil }
        return ScreenPlacement(target: target, screen: screen)
    }

    private static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
