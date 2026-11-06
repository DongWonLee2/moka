import MokaCore
import Testing

@Suite struct ContextTextTests {
    @Test("FR-02 R-115: 일정 목록 날짜는 월·일")
    func rowDate() {
        #expect(ContextText.rowDate(LocalDay(text: "2026-11-12")!) == "11월 12일")
        #expect(ContextText.rowDate(LocalDay(text: "2027-01-03")!) == "1월 3일")
    }

    @Test("FR-02 R-115: 새 일정 시트 날짜는 연·월·일")
    func formDate() {
        #expect(ContextText.formDate(LocalDay(text: "2026-12-03")!) == "2026년 12월 3일")
    }

    @Test(
        "FR-02 R-115: 중요도 저장 값 normal·high·critical은 화면에서 조금·꽤·아주",
        arguments: [(ContextImpact.normal, "조금"), (.high, "꽤"), (.critical, "아주")])
    func impact(impact: ContextImpact, expected: String) {
        #expect(ContextText.impact(impact) == expected)
    }
}
