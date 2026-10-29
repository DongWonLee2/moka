import AppKit
import MokaCore
import SwiftUI

@main
struct MokaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            // 설정 화면은 4c(#28). 지금은 자리만 둔다.
            Button("설정…") {}
                .keyboardShortcut(",")
                .disabled(true)
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image("MenuBarIcon")
                .accessibilityLabel("Moka")
        }
    }
}

/// `LSUIElement` 앱에서는 SwiftUI `Window`가 저절로 열리지 않으므로(spike) 노치 패널은 AppKit으로 띄운다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // 기본 작업 시간 저장소는 지금 메모리(DB 연결은 #28).
    private let appState = AppState(clock: MokaClock { Date() }, settings: InMemorySettingsStore())
    private var panelHost: NotchPanelHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NotchPanelHost(appState: appState)
        if let placement = ScreenWatcher.currentPlacement() {
            host.show(on: placement)
        }
        panelHost = host
    }
}
