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
    "FR-06 R-006: 남은 시간은 60분 미만 M:SS, 이상 H:MM:SS",
    arguments: [
        (1500, "25:00"), (599, "9:59"), (3599, "59:59"), (3600, "1:00:00"), (5400, "1:30:00"),
        (5099, "1:24:59"), (10800, "3:00:00"), (0, "0:00"), (61, "1:01"), (3661, "1:01:01"),
        (3609, "1:00:09"),
    ])
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

@Test(
    "FR-05 R-004: 직접 입력이 받는 값이거나 빈칸이면 이유 없음",
    arguments: ["1", "45", "180", "+45", ""])
func customIssueNone(text: String) {
    #expect(QuantumChip.customIssue(text) == nil)
}

@Test(
    "FR-05 R-004: 직접 입력이 180분을 넘으면 aboveMax",
    arguments: ["181", "999", "99999999999999999999999"])
func customIssueAboveMax(text: String) {
    #expect(QuantumChip.customIssue(text) == .aboveMax)
}

@Test("FR-05 R-004: 직접 입력이 1분보다 작으면 belowMin", arguments: ["0", "-1", "00"])
func customIssueBelowMin(text: String) {
    #expect(QuantumChip.customIssue(text) == .belowMin)
}

@Test(
    "FR-05 R-004: 직접 입력이 정수가 아니면(숫자 아님·소수·공백) notInteger",
    arguments: ["abc", "4.5", " 45", "45 ", "4분", "-"])
func customIssueNotInteger(text: String) {
    #expect(QuantumChip.customIssue(text) == .notInteger)
}

@Test(
    "FR-05 R-004: 이유가 없는 비지 않은 값만 parseCustom이 받는다",
    arguments: ["1", "180", "+45", "181", "0", "abc", "4.5", " 45"])
func customIssueAgreesWithParseCustom(text: String) {
    #expect((QuantumChip.customIssue(text) == nil) == (QuantumChip.parseCustom(text) != nil))
}

@Test("FR-05 R-003: 기본값이 프리셋이면 그 칸만 선택되고 직접 입력 칸은 직접…이다", arguments: [15, 25, 45, 60])
func segmentsPresetDefault(chipMin: Int) {
    let segments = QuantumChip.segments(chipMin: chipMin, customText: nil)
    #expect(segments.map(\.label) == ["15분", "25분", "45분", "60분", "직접…"])
    #expect(segments.filter(\.selected).map(\.kind) == [.preset(chipMin)])
}

@Test(
    "FR-05 R-003: 기본값이 프리셋 밖이면 직접 입력 칸 자리에 그 값이 보이며 선택되고 바로 시작할 수 있다",
    arguments: [(30, "30분"), (1, "1분"), (180, "180분")])
func segmentsOffPresetDefault(chipMin: Int, label: String) {
    let segments = QuantumChip.segments(chipMin: chipMin, customText: nil)
    #expect(segments.map(\.label) == ["15분", "25분", "45분", "60분", label])
    #expect(segments.filter(\.selected).map(\.kind) == [.custom])
    #expect(QuantumChip.startAllowed(customText: nil))
}

@Test(
    "FR-05 R-004: 직접 입력 중이면 직접 입력 칸은 직접…으로 선택된다",
    arguments: [(30, "30"), (25, "25"), (25, "")])
func segmentsEditingCustom(chipMin: Int, text: String) {
    let segments = QuantumChip.segments(chipMin: chipMin, customText: text)
    #expect(segments.map(\.label) == ["15분", "25분", "45분", "60분", "직접…"])
    #expect(segments.filter(\.selected).map(\.kind) == [.custom])
}
