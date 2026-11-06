import MokaCore
import Testing

@Suite struct RowSelectionTests {
    @Test("FR-01 R-122: 보이는 줄 기준으로 없음·일부·전체를 판정한다(숨은 체크는 보지 않음)")
    func state() {
        #expect(RowSelection.state(checked: [], visible: [1, 2, 3]) == .none)
        #expect(RowSelection.state(checked: [2], visible: [1, 2, 3]) == .some)
        #expect(RowSelection.state(checked: [1, 2, 3], visible: [1, 2, 3]) == .all)
        #expect(RowSelection.state(checked: [9], visible: [1, 2]) == .none, "숨은 줄만 체크돼 있으면 없음")
        #expect(RowSelection.state(checked: [1, 2, 9], visible: [1, 2]) == .all)
        #expect(RowSelection.state(checked: [], visible: [Int]()) == .none, "빈 목록은 없음")
    }

    @Test("FR-01 R-122: 전체 토글은 보이는 줄을 모두 고르고, 다 골랐으면 보이는 것만 푼다")
    func toggleAll() {
        #expect(RowSelection.toggledAll(checked: [2], visible: [1, 2, 3]) == [1, 2, 3])
        #expect(RowSelection.toggledAll(checked: [9], visible: [1, 2]) == [1, 2, 9], "숨은 체크는 그대로")
        #expect(RowSelection.toggledAll(checked: [1, 2, 9], visible: [1, 2]) == [9], "다 골랐으면 보이는 것만 푼다")
    }

    @Test("FR-01 R-122: 완료만 고르기는 보이는 줄 가운데 완료한 할 일만 고른다")
    func doneOnly() {
        #expect(RowSelection.doneOnly([(1, false), (2, true), (3, true)]) == [2, 3])
        #expect(RowSelection.doneOnly([(1, false)]) == [])
    }
}
