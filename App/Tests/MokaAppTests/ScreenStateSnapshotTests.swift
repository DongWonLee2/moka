import AppKit
import MokaCore
import SwiftUI
import XCTest

/// 화면 상태를 라이트·다크 PNG로 만든다(T037, ADR-0009). 기준 이미지와 비교하지 않고 sanity만 본다
/// (크기 0 아님, 단색 아님, 라이트≠다크). 생성 PASS는 화면이 시안과 맞다는 증거가 아니다. 정합은 사람이 비교 페이지에서 본다.
/// 할 일 제목은 가짜 예시만 쓴다.
@MainActor
final class ScreenStateSnapshotTests: XCTestCase {
    /// 맥북 프로 14" 노치(시안 v3.5: 약 185×32pt).
    private static let notchMetrics = NotchMetrics(holeWidth: 185, height: 32)
    /// 떠 있는 창은 구멍이 없고 귀 줄 높이는 `PanelPlacementMetrics.floatingBarHeight`.
    private static let floatingMetrics = NotchMetrics(
        holeWidth: 0, height: CGFloat(PanelPlacementMetrics.floatingBarHeight))

    private static let title = "보고서 1절 쓰기"
    private static let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private static let running = NotchTimer.running(
        title: title, quantumMin: 25, startedAt: startedAt, endsAt: startedAt.addingTimeInterval(1500))
    /// 접힌 판 오른쪽 "18:42".
    private static let runningRemaining = 1122

    func test_R001_emptyCollapsed() throws {
        try snapshot("01-empty", timer: .empty(draft: nil), remaining: nil, expanded: false)
    }

    func test_R001_R002_titleEntry() throws {
        try snapshot("02-input", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true)
    }

    func test_R003_R004_chipExpanded() throws {
        try snapshot(
            "03-chip", timer: .empty(draft: Draft(title: Self.title, chipMin: 25)), remaining: nil, expanded: true)
    }

    func test_R006_runningCollapsed() throws {
        try snapshot("04-running-collapsed", timer: Self.running, remaining: Self.runningRemaining, expanded: false)
    }

    func test_R006_runningExpanded() throws {
        try snapshot(
            "05-running-expanded", timer: Self.running, remaining: Self.runningRemaining, expanded: true,
            hovering: true)
    }

    func test_R008_R009_R010_expired() throws {
        try snapshot("06-expired", timer: .expired(title: Self.title, chipMin: 25), remaining: 0, expanded: true)
    }

    func test_R011_floatingCollapsed() throws {
        try snapshot(
            "07-floating-collapsed", timer: Self.running, remaining: Self.runningRemaining, expanded: false,
            style: .floating)
    }

    func test_R011_floatingExpanded() throws {
        try snapshot(
            "08-floating-expanded", timer: Self.running, remaining: Self.runningRemaining, expanded: true,
            style: .floating)
    }

    func test_R011_floatingExpired() throws {
        try snapshot(
            "09-floating-expired", timer: .expired(title: Self.title, chipMin: 25), remaining: 0, expanded: true,
            style: .floating)
    }

    /// 같은 상태를 라이트·다크로 그려 저장하고 sanity를 단언한다.
    /// 시안 2번(입력)·5번(도는 중 펼침)은 마우스를 올린 상태라 `hovering: true`로 모카 테두리를 그린다.
    private func snapshot(
        _ name: String, timer: NotchTimer, remaining: Int?, expanded: Bool, hovering: Bool = false,
        style: PanelStyle = .notch
    ) throws {
        let metrics = style == .notch ? Self.notchMetrics : Self.floatingMetrics
        let size = NotchLayout.panelSize(metrics: metrics)
        let content = NotchContentView(
            timer: timer, remainingSeconds: remaining, isExpanded: expanded, isHovering: hovering, metrics: metrics,
            style: style,
            titleFocusRequest: 0,
            chip: QuantumChipInput(
                customText: nil, canStart: true, onChoose: { _ in }, onBeginCustom: {}, onEditCustom: { _ in },
                takeFocusRequest: { false }),
            onEnterTitle: { _ in }, onStart: {}, onComplete: {})

        let light = try renderPNG(view: content, size: size, appearance: .aqua)
        let dark = try renderPNG(view: content, size: size, appearance: .darkAqua)
        for (png, suffix) in [(light, "light"), (dark, "dark")] {
            let url = try SnapshotOutput.write(png, name: "\(name)-\(suffix)")
            let issue = SnapshotSanity.issue(in: png)
            XCTAssertNil(issue, "\(url.lastPathComponent): \(issue ?? "")")
        }
        XCTAssertNotEqual(light, dark, "\(name): 라이트와 다크 PNG가 같다")
    }
}
