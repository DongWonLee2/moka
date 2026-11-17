import AppKit
import MokaCore
import SwiftUI
import XCTest

@MainActor
final class ExpiredSnapshotTests: XCTestCase {
    private static let metrics = NotchMetrics(holeWidth: 185, height: 32)
    private static let title = "가짜 할 일 A"

    func test_R008_R004_expiredChipOffPresetDefault() throws {
        try snapshot("16-expired-chip-default-30", chipMin: 30)
    }

    func test_R008_R004_expiredChip180() throws {
        try snapshot("16-expired-chip-180", chipMin: 180)
    }

    func test_R107_expiredCustomValid() throws {
        try snapshot("16-expired-custom-valid", chipMin: 25, customText: "45")
    }

    func test_R008_againLabelWidthDoesNotDependOnDigits() {
        func width(_ minutes: String) -> CGFloat {
            NSHostingView(rootView: ButtonLabel(text: "\(minutes)분 더", shortcut: "↵")).fittingSize.width
        }
        XCTAssertEqual(width("11"), width("88"))
        XCTAssertEqual(width("111"), width("180"))
    }

    private func snapshot(_ name: String, chipMin: Int, customText: String? = nil) throws {
        let size = NotchLayout.panelSize(metrics: Self.metrics)
        let content = NotchContentView(
            timer: .expired(title: Self.title, chipMin: chipMin), remainingSeconds: 0, isExpanded: true,
            metrics: Self.metrics, titleFocusRequest: 0,
            chip: QuantumChipInput(
                customText: customText, canStart: QuantumChip.startAllowed(customText: customText), onChoose: { _ in },
                onBeginCustom: {}, onEditCustom: { _ in }, takeFocusRequest: { false }),
            onEnterTitle: { _ in }, onStart: {}, onComplete: {})
        let light = try renderPNG(view: content, size: size, appearance: .aqua)
        let dark = try renderPNG(view: content, size: size, appearance: .darkAqua)
        for (png, suffix) in [(light, "light"), (dark, "dark")] {
            let url = try SnapshotOutput.write(png, name: "\(name)-\(suffix)")
            XCTAssertNil(SnapshotSanity.issue(in: png), url.lastPathComponent)
            XCTAssertNil(SnapshotSanity.sizeIssue(in: png, size: size), url.lastPathComponent)
        }
        XCTAssertNotEqual(light, dark, "\(name): 라이트와 다크 PNG가 같다")
        let board = CGPoint(x: size.width / 2, y: Self.metrics.height / 2)
        let boardIssue = SnapshotSanity.notchBoardIssue(light: light, dark: dark, board: board)
        XCTAssertNil(boardIssue, "\(name): \(boardIssue ?? "")")
    }
}
