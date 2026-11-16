import AppKit
import MokaCore
import SwiftUI
import XCTest

@MainActor
final class TimeFieldSizeTests: XCTestCase {
    func test_R116_onboardingDayStartFieldMatchesBasicTab() throws {
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let onboarding = OnboardingView(
            today: try XCTUnwrap(LocalDay(text: "2026-11-06")), calendar: calendar, initialQuantum: 25,
            initialExtend: 10, initialDayStart: Defaults.dayStart, showsGuide: false, initialStep: 2,
            onFinish: { _ in })
        let basic = BasicTabView(
            quantum: Self.input("25", range: Defaults.quantumMinRange),
            extend: Self.input("10", range: Defaults.extendMinRange),
            dayStart: .constant(Defaults.dayStart.date(calendar: calendar)))

        let onboardingField = try XCTUnwrap(Self.datePickerSize(in: onboarding, size: CGSize(width: 400, height: 250)))
        let basicField = try XCTUnwrap(Self.datePickerSize(in: basic, size: CGSize(width: 460, height: 440)))

        XCTAssertEqual(onboardingField, basicField)
    }

    /// 칸 폭은 프레임으로 고정하므로 칸 안 글자의 고유 폭이 그 안에 드는지 따로 본다(#167).
    func test_R116_timeFieldContentFitsWidthAcrossLocales() throws {
        let seoul = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let calendar = GregorianCalendar.make(timeZone: seoul)
        for identifier in ["ko_KR", "en_US", "en_GB", "ja_JP", "de_DE", "fr_FR", "ar_EG", "hi_IN", "th_TH"] {
            var components = Locale.Components(locale: Locale(identifier: identifier))
            components.hourCycle = .zeroToTwentyThree
            let locale = Locale(components: components)
            for (hour, minute) in [(23, 59), (20, 8), (0, 0)] {
                let date = try XCTUnwrap(
                    calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: hour, minute: minute)))
                let view = TimeField(date: .constant(date), locale: locale)
                    .frame(width: TimeField.width)
                    .environment(\.calendar, calendar)
                    .environment(\.timeZone, seoul)
                let hosting = NSHostingView(rootView: view)
                hosting.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
                hosting.layoutSubtreeIfNeeded()
                let picker = try XCTUnwrap(Self.firstDatePicker(in: hosting))
                XCTAssertLessThanOrEqual(
                    picker.intrinsicContentSize.width, TimeField.width, "\(identifier) \(hour):\(minute)")
            }
        }
    }

    func test_R116_minutesFieldsShareOneWidth() throws {
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let onboarding = OnboardingView(
            today: try XCTUnwrap(LocalDay(text: "2026-11-06")), calendar: calendar, initialQuantum: 25,
            initialExtend: 10, initialDayStart: Defaults.dayStart, showsGuide: false, initialStep: 2,
            onFinish: { _ in })
        let basic = BasicTabView(
            quantum: Self.input("25", range: Defaults.quantumMinRange),
            extend: Self.input("10", range: Defaults.extendMinRange),
            dayStart: .constant(Defaults.dayStart.date(calendar: calendar)))

        let onboardingWidths = Self.textFieldWidths(in: onboarding, size: CGSize(width: 400, height: 250))
        let basicWidths = Self.textFieldWidths(in: basic, size: CGSize(width: 460, height: 440))
        XCTAssertEqual(onboardingWidths.count, 2, "온보딩 분 칸 두 개")
        XCTAssertEqual(basicWidths.count, 2, "기본 탭 분 칸 두 개")
        for width in onboardingWidths + basicWidths {
            XCTAssertEqual(width, BasicTabView.minutesFieldWidth)
        }
    }

    private static func textFieldWidths(in view: some View, size: CGSize) -> [CGFloat] {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return editableTextFields(in: hosting).map(\.frame.width)
    }

    private static func editableTextFields(in view: NSView) -> [NSTextField] {
        let own = (view as? NSTextField).flatMap { $0.isEditable ? [$0] : nil } ?? []
        return own + view.subviews.flatMap(editableTextFields(in:))
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
