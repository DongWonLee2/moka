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

@Suite struct ContextDeleteTextTests {
    @Test("FR-02 R-120: 일정 지우기 확인은 이름이나 개수를 묻고, 되돌릴 수 없다고 알린다")
    func deleteTexts() {
        #expect(ContextText.deleteTitle("가짜 시험") == "\"가짜 시험\"을 지울까요?")
        #expect(ContextText.deleteTitle("가짜 중간고사") == "\"가짜 중간고사\"를 지울까요?")
        #expect(ContextText.deleteManyTitle(count: 2) == "일정 2개를 지울까요?")
        #expect(ContextText.deleteMessage == "지운 일정은 되돌릴 수 없어요.")
    }
}
