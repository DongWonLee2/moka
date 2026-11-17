import AppKit
import MokaCore
import SwiftUI
import XCTest

@MainActor
final class AppWindowsTests: XCTestCase {
    private final class PolicyRecorder {
        var current: NSApplication.ActivationPolicy = .accessory
        var applied: [NSApplication.ActivationPolicy] = []
    }

    private var recorder = PolicyRecorder()
    private var savedShared: AppWindowActivation?
    private var observers: [any NSObjectProtocol] = []

    override func setUp() async throws {
        recorder = PolicyRecorder()
        savedShared = AppWindowActivation.shared
        AppWindowActivation.shared = makeActivation()
    }

    override func tearDown() async throws {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let savedShared { AppWindowActivation.shared = savedShared }
    }

    private func makeActivation() -> AppWindowActivation {
        let recorder = recorder
        return AppWindowActivation(
            currentPolicy: { recorder.current },
            setPolicy: {
                recorder.current = $0
                recorder.applied.append($0)
            })
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    func test_ADR0012_closingObservedWindowReturnsToAccessory() {
        let activation = makeActivation()
        let window = makeWindow()
        observers.append(activation.observeClose(of: window, as: .settings))

        activation.opened(.settings)
        XCTAssertEqual(recorder.applied, [.regular])

        window.close()
        XCTAssertEqual(recorder.applied, [.regular, .accessory], "willClose 관찰자가 창을 닫힘으로 센다")
    }

    func test_ADR0012_closingOneOfTwoWindowsStaysRegular() {
        let activation = makeActivation()
        let settings = makeWindow()
        let onboarding = makeWindow()
        observers.append(activation.observeClose(of: settings, as: .settings))
        observers.append(activation.observeClose(of: onboarding, as: .onboarding))
        activation.opened(.settings)
        activation.opened(.onboarding)

        settings.close()
        XCTAssertEqual(recorder.applied, [.regular], "온보딩 창이 남아 있으면 Dock에 남는다")

        onboarding.close()
        XCTAssertEqual(recorder.applied, [.regular, .accessory])
    }

    func test_ADR0012_settingsAnchorObservesItsWindowClose() {
        let window = makeWindow()
        window.contentView = NSHostingView(rootView: SettingsWindowRaiser.Anchor())
        window.contentView?.layoutSubtreeIfNeeded()
        AppWindowActivation.opened(.settings)
        XCTAssertEqual(recorder.applied, [.regular])

        window.close()
        XCTAssertEqual(recorder.applied, [.regular, .accessory], "설정 화면 앵커가 붙은 창을 닫으면 .accessory로 돌아온다")
    }

    func test_FR14_R627_settingsViewTakesTabRequestOnAppearAndOnChange() {
        let state = makeState(InMemoryTaskRepository())
        state.requestKeySettings()
        let window = makeWindow()
        window.contentView = NSHostingView(
            rootView: SettingsView(store: InMemorySettingsStore(), appState: state, onSaved: {}))
        window.orderFront(nil)
        defer { window.close() }
        spinUntil { state.settingsTabRequest == nil }
        XCTAssertNil(state.settingsTabRequest, "설정 화면이 나타날 때 탭 요청을 가져간다(onAppear)")

        state.requestKeySettings()
        spinUntil { state.settingsTabRequest == nil }
        XCTAssertNil(state.settingsTabRequest, "열린 설정 화면이 새 탭 요청을 가져간다(onChange)")
    }

    /// SwiftUI가 다음 틱에 갱신하므로 런루프를 조건이 맞을 때까지(최대 100틱) 돌린다. 시각 규칙을 기다리는 것이 아니다.
    private func spinUntil(_ condition: () -> Bool) {
        var ticks = 0
        while !condition(), ticks < 100 {
            RunLoop.main.run(mode: .default, before: Date())
            ticks += 1
        }
    }
}
