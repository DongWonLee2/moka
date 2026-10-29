import SwiftUI
import XCTest

/// 스냅샷 sanity 단언이 망가진 그림을 실제로 잡는지 본다(#39). 판 대신 빈 뷰나 내용 없는 판이 그려지면 걸려야 한다.
@MainActor
final class SnapshotSanityTests: XCTestCase {
    private static let size = CGSize(width: 200, height: 80)
    private static let board = CGPoint(x: 100, y: 16)

    func test_intentionalFailureForCIRollout() {
        XCTFail("의도한 실패: #39 app-snapshots 도입 검증. 다음 커밋에서 되돌린다")
    }

    func test_sizeIssue_rejectsWrongPixelSize() throws {
        let png = try renderPNG(view: Color.red, size: Self.size, appearance: .aqua)
        XCTAssertNil(SnapshotSanity.sizeIssue(in: png, size: Self.size))
        XCTAssertNotNil(SnapshotSanity.sizeIssue(in: png, size: CGSize(width: 100, height: 40)))
    }

    func test_boardIssue_rejectsEmptyView() throws {
        let (light, dark) = try render(Color.clear)
        XCTAssertNotNil(SnapshotSanity.notchBoardIssue(light: light, dark: dark, board: Self.board))
        XCTAssertNotNil(SnapshotSanity.floatingBoardIssue(light: light, dark: dark, board: Self.board))
    }

    /// 검은 판만 있고 안에 그린 것이 없으면 노치 판 단언이 걸린다.
    func test_notchBoardIssue_rejectsBoardWithoutContent() throws {
        let (light, dark) = try render(Color.black.frame(width: 120, height: 32))
        XCTAssertNotNil(SnapshotSanity.notchBoardIssue(light: light, dark: dark, board: Self.board))
    }

    /// 검은 판 안에 점이 있으면 노치 판 단언을 통과한다. 점 색은 테마와 무관한 고정 색이다(`Color.orange`는 테마마다 다르다).
    func test_notchBoardIssue_acceptsBoardWithContent() throws {
        let (light, dark) = try render(
            Color.black.frame(width: 120, height: 32).overlay(alignment: .leading) {
                Circle().fill(Color(red: 1, green: 0.5, blue: 0)).frame(width: 8, height: 8).padding(.leading, 10)
            })
        XCTAssertNil(SnapshotSanity.notchBoardIssue(light: light, dark: dark, board: Self.board))
    }

    /// 판 색이 테마와 무관하면(떠 있는 창인데 늘 검정) 떠 있는 창 단언이 걸린다.
    func test_floatingBoardIssue_rejectsThemeIndependentBoard() throws {
        let (light, dark) = try render(Color.black.frame(width: 120, height: 32))
        XCTAssertNotNil(SnapshotSanity.floatingBoardIssue(light: light, dark: dark, board: Self.board))
    }

    /// 반투명 판은 판 밖 바탕이 비쳐 라이트·다크 픽셀이 조금 달라진다. 판 색 자체가 테마를 따르지 않으면 걸려야 한다.
    func test_floatingBoardIssue_rejectsTranslucentThemeIndependentBoard() throws {
        let (light, dark) = try render(
            Color(red: 0.15, green: 0.12, blue: 0.11).opacity(0.9).frame(width: 120, height: 32))
        XCTAssertNotNil(SnapshotSanity.floatingBoardIssue(light: light, dark: dark, board: Self.board))
    }

    func test_floatingBoardIssue_acceptsThemedBoard() throws {
        let (light, dark) = try render(ThemedBoard().frame(width: 120, height: 32))
        XCTAssertNil(SnapshotSanity.floatingBoardIssue(light: light, dark: dark, board: Self.board))
    }

    private func render(_ view: some View) throws -> (Data, Data) {
        (
            try renderPNG(view: view, size: Self.size, appearance: .aqua),
            try renderPNG(view: view, size: Self.size, appearance: .darkAqua)
        )
    }
}

private struct ThemedBoard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        colorScheme == .light ? Color(red: 1, green: 0.98, blue: 0.95) : Color(red: 0.15, green: 0.12, blue: 0.11)
    }
}
