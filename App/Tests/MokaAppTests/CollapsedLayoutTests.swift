import MokaCore
import XCTest

/// 도는 중·시간 끝 접힌 노치 판은 카메라 구멍 양옆을 같은 폭 64pt로 둔다(사용자 결정 2026-11-02). 64pt는 "1:04:59"가 들어가는 가장 작은 폭이다.
/// 떠 있는 창은 맞출 노치가 없어 제목 칸과 시간 칸을 내용대로 둔다(시안 v3.5 7번).
final class CollapsedLayoutTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func test_R006_runningNotchIsSymmetric() {
        let timer = NotchTimer.running(title: "가짜 할 일", quantumMin: 25, startedAt: t0, endsAt: t0 + 1500)
        for seconds in [1122, 3899] {
            let sides = NotchLayout.collapsedSideWidths(timer: timer, remainingSeconds: seconds, style: .notch)
            XCTAssertEqual(sides.leading, 64)
            XCTAssertEqual(sides.trailing, 64)
            XCTAssertEqual(
                NotchLayout.horizontalOffset(timer: timer, remainingSeconds: seconds, isExpanded: false, style: .notch), 0)
        }
    }

    func test_R008_expiredNotchIsSymmetric() {
        let sides = NotchLayout.collapsedSideWidths(
            timer: .expired(title: "가짜 할 일", chipMin: 25), remainingSeconds: 0, style: .notch)
        XCTAssertEqual(sides.leading, 64)
        XCTAssertEqual(sides.trailing, 64)
    }

    func test_R011_floatingKeepsContentWidths() {
        let timer = NotchTimer.running(title: "가짜 할 일", quantumMin: 25, startedAt: t0, endsAt: t0 + 1500)
        XCTAssertEqual(
            NotchLayout.collapsedSideWidths(timer: timer, remainingSeconds: 1122, style: .floating).leading, 104)
        XCTAssertEqual(
            NotchLayout.collapsedSideWidths(timer: timer, remainingSeconds: 1122, style: .floating).trailing, 52)
        XCTAssertEqual(
            NotchLayout.collapsedSideWidths(timer: timer, remainingSeconds: 3899, style: .floating).trailing, 64)
    }

    func test_R001_emptyStaysDotWidth() {
        let sides = NotchLayout.collapsedSideWidths(timer: .empty(draft: nil), remainingSeconds: nil, style: .notch)
        XCTAssertEqual(sides.leading, 28)
        XCTAssertEqual(sides.trailing, 28)
    }
}
