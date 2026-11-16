import AppKit
import MokaCore
import SwiftUI

// 설정·온보딩 창의 앱 연결부. 앱 시험 번들이 함께 컴파일해 창 열기·닫기 연결을 시험한다(#153).

/// 설정 창을 앞으로 올린다. 노치 패널은 건드리지 않는다(SC-003).
@MainActor
enum SettingsWindowRaiser {
    private static weak var window: NSWindow?
    /// 설정…을 눌렀을 때만 건다. 앵커는 이 요청이 있을 때만 창을 올려, 요청 없이 창이 저절로 앞으로 오지 않게 한다.
    private static var pending = OneShotRequest()

    static func request() {
        pending.request()
    }

    /// "설정…"과 노치 키 확인 한 줄이 같은 순서로 설정 창을 연다(spec 004 plan "앱 연결").
    /// Dock에 보이는 앱(`.regular`)으로 바꾼 뒤 활성화를 요청한다. 메뉴 막대 앱의 활성화 요청은 받아들여지지 않을 때가 있다(#105).
    static func open(with openSettings: OpenSettingsAction) {
        request()
        AppWindowActivation.opened(.settings)
        raiseOnActivation()
        NSApp.activate()
        openSettings()
        DispatchQueue.main.async { raise() }
    }

    static func raise() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static var activationObserver: (any NSObjectProtocol)?

    /// 활성화가 다음 틱보다 늦게 오면 그사이 SwiftUI가 창을 다른 앱 뒤에 둔다. 활성이 된 순간 한 번 더 올린다.
    private static func raiseOnActivation() {
        guard !NSApp.isActive, activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if let observer = activationObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                activationObserver = nil
                // 활성이 오기 전에 창을 닫았으면 닫힌 창을 다시 띄우지 않는다.
                if window?.isVisible == true { raise() }
            }
        }
    }

    /// 설정 화면 바탕에 깔아 설정 창을 알아낸다. 창에 붙을 때 설정… 요청이 걸려 있으면 다음 틱에 올린다.
    struct Anchor: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { AnchorView() }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    private static var closeObserver: (any NSObjectProtocol)?

    private final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            if SettingsWindowRaiser.window !== window {
                closeObserver = AppWindowActivation.observeClose(of: window, as: .settings)
            }
            SettingsWindowRaiser.window = window
            // 제목줄까지 시안 바탕색이 보이게 한다(macOS 14에는 SwiftUI 창 바탕 지정이 없다).
            window.titlebarAppearsTransparent = true
            window.backgroundColor = MokaColors.settingsWindowNS
            // 노치는 모든 Space에 있어서, 다른 Space에서 설정을 열면 창이 그 Space로 따라온다(#105).
            window.collectionBehavior.insert(.moveToActiveSpace)
            guard SettingsWindowRaiser.pending.take() else { return }
            DispatchQueue.main.async { SettingsWindowRaiser.raise() }
        }
    }
}

/// 설정·온보딩 창이 열린 동안만 Dock·Command+Tab에 보이게 한다(ADR-0012, #105). 노치 패널은 세지 않는다.
/// 앱은 `shared`를 쓰고, 시험은 정책을 읽고 바꾸는 함수를 넣은 것으로 바꿔 끼운다.
@MainActor
final class AppWindowActivation {
    static var shared = AppWindowActivation(
        currentPolicy: { NSApp.activationPolicy() }, setPolicy: { NSApp.setActivationPolicy($0) })

    private var presence = AppWindowPresence()
    private let currentPolicy: () -> NSApplication.ActivationPolicy
    private let setPolicy: (NSApplication.ActivationPolicy) -> Void

    init(
        currentPolicy: @escaping () -> NSApplication.ActivationPolicy,
        setPolicy: @escaping (NSApplication.ActivationPolicy) -> Void
    ) {
        self.currentPolicy = currentPolicy
        self.setPolicy = setPolicy
    }

    static func opened(_ window: AppWindowPresence.Window) {
        shared.opened(window)
    }

    static func observeClose(of nsWindow: NSWindow, as window: AppWindowPresence.Window) -> any NSObjectProtocol {
        shared.observeClose(of: nsWindow, as: window)
    }

    func opened(_ window: AppWindowPresence.Window) {
        presence.opened(window)
        apply()
    }

    /// 빨간 버튼, ⌘W, 코드의 `close()`가 모두 `willClose`를 거친다. 블록 관찰자는 토큰을 놓아도 풀리지 않고
    /// `removeObserver` 전까지 남는다. 풀지 않으므로 닫힌 창의 관찰자도 남지만, 닫힌 창을 다시 닫는 알림은 규칙이 무시한다.
    func observeClose(of nsWindow: NSWindow, as window: AppWindowPresence.Window) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nsWindow, queue: .main)
        { _ in
            MainActor.assumeIsolated {
                self.presence.closed(window)
                self.apply()
            }
        }
    }

    private func apply() {
        let policy: NSApplication.ActivationPolicy =
            switch presence.policy {
            case .regular: .regular
            case .accessory: .accessory
            }
        guard currentPolicy() != policy else { return }
        setPolicy(policy)
    }
}
