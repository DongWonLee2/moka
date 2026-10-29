import AppKit
import MokaCore
import MokaStore
import SwiftUI
import os

@main
struct MokaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            OpenSettingsButton()
                .keyboardShortcut(",")
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image("MenuBarIcon")
                .accessibilityLabel("Moka")
        }
        Settings {
            SettingsView(store: AppSettings.store)
        }
    }
}

/// "설정…" 메뉴 항목. 메뉴 막대와 펼친 판 우클릭 메뉴가 같이 쓴다(R-012).
/// `LSUIElement` 앱은 활성이 아니어서 설정 창이 다른 앱 뒤에 열리므로 앱을 활성화한다.
struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("설정…") {
            NSApp.activate()
            openSettings()
        }
    }
}

/// 기본 작업 시간 저장소. 앱 DB(ADR-0004)는 앱 코드만 이 경로로 연다. 테스트·`moka-sim`은 열지 않는다.
@MainActor
enum AppSettings {
    static let store: any SettingsStore = openStore()

    private static let logger = Logger(subsystem: "dev.dongwon.moka", category: "settings")

    /// `~/Library/Application Support/dev.dongwon.moka/moka.sqlite`. 못 열면 메모리 저장소(기본값 25, 저장 안 남음)로 동작한다(research R2).
    private static func openStore() -> any SettingsStore {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let url = support.appending(path: "dev.dongwon.moka", directoryHint: .isDirectory)
                .appending(path: "moka.sqlite", directoryHint: .notDirectory)
            return GRDBSettingsStore(try MokaDatabase.open(at: url))
        } catch {
            logger.error(
                "설정 DB를 열지 못해 메모리 저장소로 동작: \(String(reflecting: type(of: error)), privacy: .public)")
            return InMemorySettingsStore()
        }
    }
}

/// `LSUIElement` 앱에서는 SwiftUI `Window`가 저절로 열리지 않으므로(spike) 노치 패널은 AppKit으로 띄운다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState(clock: MokaClock { Date() }, settings: AppSettings.store)
    private var panelHost: NotchPanelHost?
    private var screenWatcher: ScreenWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NotchPanelHost(appState: appState)
        host.move(to: ScreenWatcher.currentPlacement())
        // 화면 연결이 바뀌면 같은 패널을 새 위치로 옮긴다(R-011). 타이머는 AppState에 있어 끊기지 않는다.
        screenWatcher = ScreenWatcher { [weak host] placement in
            host?.move(to: placement)
        }
        panelHost = host
    }
}
