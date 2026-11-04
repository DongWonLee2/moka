import MokaCore
import SwiftUI
import XCTest

/// 설정 창 탭 내용을 라이트·다크 PNG로 만든다(ADR-0009, 시안 6번). sanity만 보고 정합은 사람이 비교 페이지에서 본다.
@MainActor
final class SettingsSnapshotTests: XCTestCase {
    /// 설정 창 폭 460pt. 높이는 기본 탭 내용이 들어가는 만큼.
    private static let size = CGSize(width: 460, height: 200)

    func test_R012_basicTabDefaults() throws {
        try snapshot("s06-basic", quantumText: "25", extendText: "10")
    }

    /// 받지 않는 값을 적는 동안은 안내 대신 이유가 보인다(#59, #35에서 옮겨 온 항목).
    func test_R012_basicTabIssue() throws {
        try snapshot("s06-basic-issue", quantumText: "181", extendText: "4.5")
    }

    private func snapshot(_ name: String, quantumText: String, extendText: String) throws {
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let content = BasicTabView(
            quantum: Self.input(quantumText, range: Defaults.quantumMinRange),
            extend: Self.input(extendText, range: Defaults.extendMinRange),
            dayStart: .constant(Defaults.dayStart.date(calendar: calendar)))
            .environment(\.timeZone, calendar.timeZone)

        let light = try renderPNG(view: content, size: Self.size, appearance: .aqua)
        let dark = try renderPNG(view: content, size: Self.size, appearance: .darkAqua)
        for (png, suffix) in [(light, "light"), (dark, "dark")] {
            let url = try SnapshotOutput.write(png, name: "\(name)-\(suffix)")
            let issue = SnapshotSanity.issue(in: png)
            XCTAssertNil(issue, "\(url.lastPathComponent): \(issue ?? "")")
            let sizeIssue = SnapshotSanity.sizeIssue(in: png, size: Self.size)
            XCTAssertNil(sizeIssue, "\(url.lastPathComponent): \(sizeIssue ?? "")")
        }
        XCTAssertNotEqual(light, dark, "\(name): 라이트와 다크 PNG가 같다")
    }

    private static func input(_ text: String, range: ClosedRange<Int>) -> MinutesFieldInput {
        MinutesFieldInput(
            text: .constant(text), stepperValue: QuantumChip.parseCustom(text) ?? range.lowerBound, range: range,
            onCommit: {}, onStep: { _ in })
    }
}
