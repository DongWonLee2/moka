import MokaCore
import Testing

@Test("R-012 ADR-0012: 앱 창이 하나도 없으면 메뉴 막대 앱(accessory)이다")
func presenceStartsAsMenuBarApp() {
    #expect(AppWindowPresence().policy == .accessory)
}

@Test("R-012 ADR-0012: 설정 창이 열리면 Dock·Command+Tab에 보이고(regular), 닫히면 메뉴 막대 앱으로 돌아간다")
func presenceFollowsSettingsWindow() {
    var presence = AppWindowPresence()
    presence.opened(.settings)
    #expect(presence.policy == .regular)
    presence.closed(.settings)
    #expect(presence.policy == .accessory)
}

@Test("R-116 ADR-0012: 온보딩 창도 열려 있는 동안 Dock·Command+Tab에 보인다")
func presenceFollowsOnboardingWindow() {
    var presence = AppWindowPresence()
    presence.opened(.onboarding)
    #expect(presence.policy == .regular)
    presence.closed(.onboarding)
    #expect(presence.policy == .accessory)
}

@Test("ADR-0012: 두 창이 열려 있으면 하나를 닫아도 남은 창이 있어 regular를 유지한다")
func presenceKeepsRegularWhileAnyWindowIsOpen() {
    var presence = AppWindowPresence()
    presence.opened(.onboarding)
    presence.opened(.settings)
    presence.closed(.onboarding)
    #expect(presence.policy == .regular)
    presence.closed(.settings)
    #expect(presence.policy == .accessory)
}

@Test("ADR-0012: 같은 창을 여러 번 열었다는 알림은 한 창으로 센다. 한 번 닫으면 accessory다")
func presenceCountsEachWindowOnce() {
    var presence = AppWindowPresence()
    presence.opened(.settings)
    presence.opened(.settings)
    presence.closed(.settings)
    #expect(presence.policy == .accessory)
}

@Test("ADR-0012: 열린 적 없는 창을 닫았다는 알림은 아무것도 바꾸지 않는다")
func presenceIgnoresCloseWithoutOpen() {
    var presence = AppWindowPresence()
    presence.closed(.settings)
    #expect(presence.policy == .accessory)
    presence.opened(.onboarding)
    presence.closed(.settings)
    #expect(presence.policy == .regular)
}
