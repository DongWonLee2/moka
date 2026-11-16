import AppKit
import MokaCore
import SwiftUI
import XCTest

/// 시간 끝 화면 스냅샷 보강(#59의 #42·PR #60 리뷰 몫). 노치 판(맥북 프로 14")만 그리고 sanity만 본다.
/// 정합은 사람이 비교 페이지에서 본다. 할 일 제목은 가짜 예시만 쓴다.
@MainActor
final class ExpiredSnapshotTests: XCTestCase {
    private static let metrics = NotchMetrics(holeWidth: 185, height: 32)
    private static let title = "가짜 할 일 A"

    /// 프리셋 밖 기본값(30분)이 "직접…" 자리에 선택된 채 "30분 더"로 보인다.
    func test_R008_R004_expiredChipOffPresetDefault() throws {
        try snapshot("16-expired-chip-default-30", chipMin: 30)
    }

    /// 가장 긴 기본값(180분)에서 칩 줄과 "180분 더"가 넘치지 않는다.
    func test_R008_R004_expiredChip180() throws {
        try snapshot("16-expired-chip-180", chipMin: 180)
    }

    /// 직접 입력 값이 맞으면 "45분 더"가 켜지고 Enter 표시가 붙는다(틀린 값은 `test_R107_expiredCustomInvalid`).
    func test_R107_expiredCustomValid() throws {
        try snapshot("16-expired-custom-valid", chipMin: 25, customText: "45")
    }

    /// "N분 더"의 숫자는 고정 폭이라 같은 자릿수면 버튼 폭이 흔들리지 않는다(PR #60 리뷰).
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
