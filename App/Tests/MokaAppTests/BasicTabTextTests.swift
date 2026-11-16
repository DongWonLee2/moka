import XCTest

/// spec 005 R-434: 기본 탭 하루 시작 시각 안내(확정 시안 005 13번 마지막 줄, 사람 확인 2026-11-16).
final class BasicTabTextTests: XCTestCase {
    func test_R434_dayStartHint() {
        XCTAssertEqual(BasicTabView.dayStartHint, "이 시각이 지나면 반복 할 일이 다시 대기로 돌아오고, 남은 할 일을 오늘 할지 물어요.")
    }
}
