import AppKit
import MokaCore
import MokaStore
import SwiftUI

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
            SettingsView(store: AppSettings.store, onSaved: { delegate.defaultQuantumChanged() })
                // 설정 창 열기도 활성화다(research R11).
                .onAppear { delegate.activate() }
        }
    }
}

/// "설정…" 메뉴 항목. 메뉴 막대와 펼친 판 우클릭 메뉴가 같이 쓴다(R-012).
/// `LSUIElement` 앱은 활성이 아니어서 설정 창이 다른 앱 뒤에 열리므로 앱을 활성화한다.
/// macOS 14의 `activate()`는 요청이라 바로 활성이 되지 않을 수 있다. 그래서 설정 창을 연 뒤 다음 틱에
/// 그 창을 직접 앞으로 올린다(#45). 처음 만들어지는 창은 `SettingsWindowRaiser.Anchor`가 붙을 때 올린다.
struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("설정…") {
            SettingsWindowRaiser.request()
            NSApp.activate()
            openSettings()
            DispatchQueue.main.async { SettingsWindowRaiser.raise() }
        }
    }
}

/// 설정 창을 앞으로 올린다. 노치 패널은 건드리지 않는다(SC-003).
@MainActor
enum SettingsWindowRaiser {
    private static weak var window: NSWindow?
    /// 설정…을 눌렀을 때만 건다. 앵커는 이 요청이 있을 때만 창을 올려, 요청 없이 창이 저절로 앞으로 오지 않게 한다.
    private static var pending = OneShotRequest()

    static func request() {
        pending.request()
    }

    static func raise() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// 설정 화면 바탕에 깔아 설정 창을 알아낸다. 창에 붙을 때 설정… 요청이 걸려 있으면 다음 틱에 올린다.
    struct Anchor: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { AnchorView() }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    private final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            SettingsWindowRaiser.window = window
            guard SettingsWindowRaiser.pending.take() else { return }
            DispatchQueue.main.async { SettingsWindowRaiser.raise() }
        }
    }
}

/// 앱 저장소. 앱 DB(ADR-0004)는 앱 코드만 이 경로로 연다. 테스트·`moka-sim`은 열지 않는다.
@MainActor
enum AppSettings {
    /// DB를 한 번 열어 설정·할 일·일정 저장소에 나눠 준다. 못 열면 설정만 메모리로 동작한다(R-119).
    static let storage = AppStorage.open(openDatabase)
    static var store: any SettingsStore { storage.settings }

    /// `~/Library/Application Support/dev.dongwon.moka/moka.sqlite`. 마이그레이션까지 끝나야 저장소를 만든다.
    nonisolated private static func openDatabase() throws -> AppStorage {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let url = support.appending(path: "dev.dongwon.moka", directoryHint: .isDirectory)
            .appending(path: "moka.sqlite", directoryHint: .notDirectory)
        let db = try MokaDatabase.open(at: url)
        return AppStorage(
            settings: GRDBSettingsStore(db), repository: GRDBTaskRepository(db), contexts: GRDBContextStore(db))
    }
}

/// `LSUIElement` 앱에서는 SwiftUI `Window`가 저절로 열리지 않으므로(spike) 노치 패널은 AppKit으로 띄운다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 달력은 한 번 만들어 둔다. 시스템 시간대가 바뀌면 따라간다(ADR-0010 결정 검증 결과 (a)).
    private let appState = AppState(
        clock: MokaClock { Date() }, calendar: GregorianCalendar.make(timeZone: .autoupdatingCurrent),
        storage: AppSettings.storage)
    private var panelHost: NotchPanelHost?
    private var screenWatcher: ScreenWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 재시작 복구 → 하루 판정 → 고르기(R-111, R-113, R-104). 패널을 띄우기 전에 끝낸다.
        appState.launch()
        let host = NotchPanelHost(appState: appState)
        host.move(to: ScreenWatcher.currentPlacement())
        // 화면 연결이 바뀌면 같은 패널을 새 위치로 옮긴다(R-011). 타이머는 AppState에 있어 끊기지 않는다.
        screenWatcher = ScreenWatcher { [weak host] placement in
            host?.move(to: placement)
        }
        panelHost = host
    }

    /// 메뉴 "종료"·⌘Q(정상 종료). 도는 중이면 종료 체크포인트를 동기로 남긴다(R-110). 종료를 미루지 않는다.
    func applicationWillTerminate(_ notification: Notification) {
        appState.lifecycleCheckpoint(.quit)
    }

    func defaultQuantumChanged() {
        appState.defaultQuantumChanged()
    }

    func activate() {
        appState.activate()
    }
}
