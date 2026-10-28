import MokaCore
import Testing

@Test("FR-05 R-004: 프리셋은 15, 25, 45, 60분")
func presets() {
    #expect(QuantumChip.presets == [15, 25, 45, 60])
}

@Test("FR-05 R-004: 직접 입력은 1~180 정수를 받는다", arguments: [("1", 1), ("180", 180), ("90", 90), ("+45", 45)])
func parseCustomAccepts(text: String, expected: Int) {
    #expect(QuantumChip.parseCustom(text) == expected)
}

@Test(
    "FR-05 R-004: 직접 입력은 0, 181, 빈 값, 숫자 아님, 소수, 공백 섞인 값을 거부한다",
    arguments: ["0", "181", "", "abc", "4.5", " 45", "45 ", "-1"])
func parseCustomRejects(text: String) {
    #expect(QuantumChip.parseCustom(text) == nil)
}

@Test(
    "FR-06 R-006: 남은 시간은 M:SS, 분은 0을 채우지 않는다",
    arguments: [(1500, "25:00"), (599, "9:59"), (5400, "90:00"), (0, "0:00"), (61, "1:01"), (10800, "180:00")])
func remainingFormat(seconds: Int, expected: String) {
    #expect(RemainingFormat.string(seconds) == expected)
}

@Test("FR-06 R-006: 음수 초는 0으로 잘라 0:00을 보인다", arguments: [-1, -61])
func remainingFormatClampsNegative(seconds: Int) {
    #expect(RemainingFormat.string(seconds) == "0:00")
}

@Test(
    "FR-06 R-009: 고정·포커스·마우스 중 하나라도 참이면 펼친 채로 남는다",
    arguments: [true, false], [true, false])
func shouldStayExpandedTable(focused: Bool, hovering: Bool) {
    #expect(shouldStayExpanded(pinned: true, focused: focused, hovering: hovering))
    #expect(shouldStayExpanded(pinned: false, focused: focused, hovering: hovering) == (focused || hovering))
}
