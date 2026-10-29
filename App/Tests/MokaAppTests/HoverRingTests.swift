import XCTest

/// 시안 v3.5 `.ex.hover`: 마우스가 올라가 펼친 노치 판에만 모카 테두리를 그린다.
/// 시간 끝 자동 펼침(마우스 없음)과 떠 있는 창(시안 7번)에는 없다.
final class HoverRingTests: XCTestCase {
    func test_R009_hoverRingOnlyWhenHoveringExpandedNotch() {
        XCTAssertTrue(NotchLayout.showsHoverRing(isHovering: true, isExpanded: true, style: .notch))
        XCTAssertFalse(NotchLayout.showsHoverRing(isHovering: false, isExpanded: true, style: .notch))
        XCTAssertFalse(NotchLayout.showsHoverRing(isHovering: true, isExpanded: false, style: .notch))
        XCTAssertFalse(NotchLayout.showsHoverRing(isHovering: false, isExpanded: false, style: .notch))
        XCTAssertFalse(NotchLayout.showsHoverRing(isHovering: true, isExpanded: true, style: .floating))
    }
}
