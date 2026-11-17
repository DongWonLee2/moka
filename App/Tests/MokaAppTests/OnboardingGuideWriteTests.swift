import AppKit
import MokaCore
import SwiftUI
import XCTest

/// spec 007 SC-705 뷰 수준(#163): 온보딩 창의 쓰기 길은 키 단계의 `onSave`와 "시작하기"의 `onFinish` 둘뿐이다.
/// 안내 장 1/6~3/6을 Enter로 넘기는 동안 둘 다 0번 불리는지 센다. 저장할 수 있는 가짜 키를 미리 넣어 둔다.
@MainActor
final class OnboardingGuideWriteTests: XCTestCase {
    func test_SC705_enteringThroughGuidePagesWritesNothing() throws {
        var saves = 0
        var finishes = 0
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let view = OnboardingView(
            today: try XCTUnwrap(LocalDay(text: "2026-11-06")), calendar: calendar, initialQuantum: 25,
            initialExtend: 10, initialDayStart: Defaults.dayStart,
            keyStep: OnboardingKeyInput(
                hasKey: false,
                onSave: { _ in
                    saves += 1
                    return true
                }, issueURL: nil, host: "example-resource.invalid"),
            initialKeyDraft: OnboardingKeyDraft(text: "fake-key-0123456789"),
            onFinish: { _ in finishes += 1 })
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 520), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        settle()

        XCTAssertNil(Self.keyField(in: hosting), "1/6에는 키 칸이 없다")
        for page in 1...3 {
            XCTAssertNil(Self.keyField(in: hosting), "\(page)/6은 안내 장이다")
            XCTAssertTrue(pressReturn(in: window), "\(page)/6에서 Enter를 받는 버튼이 있다")
            settle()
            XCTAssertEqual(saves, 0, "\(page)/6에서 넘길 때 키를 저장하지 않는다")
            XCTAssertEqual(finishes, 0, "\(page)/6에서 넘길 때 끝내지 않는다")
        }
        XCTAssertNotNil(Self.keyField(in: hosting), "Enter 세 번이면 4/6 키 단계에 닿는다(빈 통과가 아님)")
    }

    private func pressReturn(in window: NSWindow) -> Bool {
        guard
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)
        else { return false }
        return window.performKeyEquivalent(with: event)
    }

    /// SwiftUI가 다음 틱에 갱신하므로 런루프를 몇 틱 돌린다. 시각 규칙을 기다리는 것이 아니다.
    private func settle() {
        for _ in 0..<10 {
            RunLoop.main.run(mode: .default, before: Date())
        }
    }

    private static func keyField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.placeholderString == OnboardingKeyText.placeholder { return field }
        return view.subviews.lazy.compactMap(keyField(in:)).first
    }
}
