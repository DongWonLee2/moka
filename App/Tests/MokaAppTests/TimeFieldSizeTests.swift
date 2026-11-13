import AppKit
import MokaCore
import SwiftUI
import XCTest

/// 온보딩 기본값 단계의 하루 시작 시각 칸은 설정 창 기본 탭의 같은 칸과 크기가 같다.
@MainActor
final class TimeFieldSizeTests: XCTestCase {
    func test_R116_onboardingDayStartFieldMatchesBasicTab() throws {
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let onboarding = OnboardingView(
            today: try XCTUnwrap(LocalDay(text: "2026-11-06")), calendar: calendar, initialQuantum: 25,
            initialExtend: 10, initialDayStart: Defaults.dayStart, initialStep: 2, onFinish: { _ in })
        let basic = BasicTabView(
            quantum: Self.input("25", range: Defaults.quantumMinRange),
            extend: Self.input("10", range: Defaults.extendMinRange),
            dayStart: .constant(Defaults.dayStart.date(calendar: calendar)))

        let onboardingField = try XCTUnwrap(Self.datePickerSize(in: onboarding, size: CGSize(width: 400, height: 250)))
        let basicField = try XCTUnwrap(Self.datePickerSize(in: basic, size: CGSize(width: 460, height: 440)))

        XCTAssertEqual(onboardingField, basicField)
    }

    private static func input(_ text: String, range: ClosedRange<Int>) -> MinutesFieldInput {
        MinutesFieldInput(
            text: .constant(text), stepperValue: Int(text) ?? range.lowerBound, range: range, onCommit: {},
            onStep: { _ in })
    }

    private static func datePickerSize(in view: some View, size: CGSize) -> CGSize? {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return firstDatePicker(in: hosting)?.frame.size
    }

    private static func firstDatePicker(in view: NSView) -> NSDatePicker? {
        if let picker = view as? NSDatePicker { return picker }
        return view.subviews.lazy.compactMap(firstDatePicker(in:)).first
    }
}
