/// 설정 창이나 온보딩 창이 하나라도 열려 있는 동안만 Dock·Command+Tab에 보이고,
/// 모두 닫히면 메뉴 막대 앱으로 돌아간다(ADR-0012, #105). 앱은 `policy`를 `NSApp.setActivationPolicy`에 옮긴다.
public struct AppWindowPresence: Equatable, Sendable {
    public enum Window: Hashable, Sendable {
        case settings
        case onboarding
    }

    /// `NSApplication.ActivationPolicy`의 `.regular`·`.accessory`와 같다. MokaCore는 AppKit을 모른다.
    public enum Policy: Equatable, Sendable {
        case regular
        case accessory
    }

    private var openWindows: Set<Window> = []

    public init() {}

    public var policy: Policy {
        openWindows.isEmpty ? .accessory : .regular
    }

    public mutating func opened(_ window: Window) {
        openWindows.insert(window)
    }

    public mutating func closed(_ window: Window) {
        openWindows.remove(window)
    }
}
