import Foundation
import MokaCore
import Testing

// spec 005 data-model §11. 가짜 값만 쓴다.

private let today = Fake.day("2027-01-13")
private let yesterday = Fake.day("2027-01-12")

private func budget(_ minutes: Int, used: Int = 0, extended: Int = 0, more: Bool = false, day: LocalDay = today)
    -> DayBudget
{
    DayBudget(day: day, minutes: minutes, extendedMinutes: extended, usedSeconds: used, more: more)
}

@Suite struct DayBudgetRecordTests {
    @Test("FR-10 R-419: 답하면 쓴 시간 0, 늘린 분 0, 더 할래요 거짓")
    func answered() {
        #expect(DayBudget.answered(day: today, minutes: 90) == budget(90))
    }

    @Test("FR-10 R-419: 선택지는 1·2·4·6·8시간 × 60분")
    func choices() {
        #expect(DayBudget.choiceMinutes == [60, 120, 240, 360, 480])
        #expect(Defaults.availableHoursChoices == [1, 2, 4, 6, 8])
    }

    @Test("FR-10 R-419 R-420: 오늘 기록만 읽고 어제 기록은 없는 것으로 본다")
    func readsTodayOnly() {
        #expect(DayBudget.record(budget(120, day: yesterday), for: today) == nil)
        #expect(DayBudget.record(budget(120), for: today) == budget(120))
        #expect(DayBudget.record(nil, for: today) == nil)
    }

    @Test("FR-10 R-420: JSON은 키 순서가 고정이고 왕복한다")
    func json() throws {
        let value = budget(135, used: 3600, extended: 15)
        #expect(value.json == #"{"day":"2027-01-13","extended_min":15,"minutes":135,"more":false,"used_s":3600}"#)
        #expect(DayBudget(json: value.json) == value)
        #expect(DayBudget(json: #"{"day":"2027-13-01","extended_min":0,"minutes":60,"more":false,"used_s":0}"#) == nil)
        #expect(DayBudget(json: "not json") == nil)
    }

    @Test("FR-10 R-421: 남은 분은 남은 초를 분으로 내림, 음수면 0", arguments: [(0, 120), (59, 119), (60, 119), (7199, 0), (7300, 0)])
    func remainingMinutes(used: Int, minutes: Int) {
        #expect(budget(120, used: used).remainingMinutes == minutes)
        #expect(budget(120, used: used).remainingSeconds == 7200 - used)
    }

    @Test("FR-10 R-422: 상한은 기록이 있고 더 할래요가 아닐 때만, 그때 남은 분")
    func cap() {
        #expect(DayBudget.capMinutes(budget(120, used: 6600)) == 10)
        #expect(DayBudget.capMinutes(budget(120, used: 6600, more: true)) == nil)
        #expect(DayBudget.capMinutes(nil) == nil)
    }

    @Test("FR-10 R-420: 시작·N분 더 때 고른 분 × 60을 더하고, 일찍 끝나면 남은 초를 돌려준다")
    func chargeAndRefund() {
        let charged = budget(120).applying(BudgetUse(day: today, seconds: 25 * 60))
        #expect(charged.usedSeconds == 1500)
        let refunded = charged.applying(BudgetUse(day: today, seconds: -1220))
        #expect(refunded.usedSeconds == 280)
        #expect(refunded.applying(BudgetUse(day: yesterday, seconds: 600)) == refunded)
    }

    @Test("FR-10 R-420: 돌려줄 초는 끝 시각까지 남은 초(0 이상, 초 아래 버림)")
    func refundSeconds() {
        let endsAt = Fake.noon.addingTimeInterval(25 * 60)
        #expect(DayBudget.refundSeconds(endsAt: endsAt, now: Fake.noon.addingTimeInterval(280.6)) == 1219)
        #expect(DayBudget.refundSeconds(endsAt: endsAt, now: endsAt) == 0)
        #expect(DayBudget.refundSeconds(endsAt: endsAt, now: endsAt.addingTimeInterval(30)) == 0)
    }

    @Test("FR-10 R-421: 늘리기는 가용 시간과 늘린 분을 같이 늘리고, 늘린 뒤 남은 분은 칩 이상")
    func extend() throws {
        let record = budget(120, used: 110 * 60)
        let needed = try #require(QuantumChip.extendNeeded(chipMin: 25, remainingMinutes: record.remainingMinutes))
        #expect(needed == 15)
        let extended = record.extended(by: needed)
        #expect(extended.minutes == 135)
        #expect(extended.extendedMinutes == 15)
        #expect(extended.remainingMinutes >= 25)
        #expect(extended.applying(BudgetUse(day: today, seconds: 25 * 60)).usedSeconds <= extended.minutes * 60)
    }

    @Test("FR-10 R-421: 남은 분 이하 칩, 상한 없음, 남은 분 0이면 늘리기 없음")
    func extendNotNeeded() {
        #expect(QuantumChip.extendNeeded(chipMin: 10, remainingMinutes: 10) == nil)
        #expect(QuantumChip.extendNeeded(chipMin: 60, remainingMinutes: nil) == nil)
        #expect(QuantumChip.extendNeeded(chipMin: 25, remainingMinutes: 0) == nil)
    }

    @Test("FR-10 R-422: 더 할래요는 그날 상한을 푼다")
    func more() {
        #expect(budget(120, used: 7200).withMore() == budget(120, used: 7200, more: true))
    }

    @Test(
        "FR-10 R-421 SC-405: 상한이 걸린 동안 쓴 시간 ≤ 가용 시간, 돌려받은 시간으로 다시 시작하면 시작한 분 합은 더 클 수 있다")
    func usedStaysWithinMinutes() {
        var record = budget(120)
        var started = 0
        // 60분 시작 → 10분에 완료(50분 돌려받음) → 남은 110분으로 시작해 끝까지.
        record = record.applying(BudgetUse(day: today, seconds: 60 * 60))
        started += 60
        record = record.applying(BudgetUse(day: today, seconds: -50 * 60))
        #expect(record.usedSeconds <= record.minutes * 60)
        let chip = QuantumChip.draftChip(
            lastChip: nil, defaultMin: 180, remainingEstimateMin: nil, remainingMinutes: record.remainingMinutes)
        #expect(chip == 110)
        record = record.applying(BudgetUse(day: today, seconds: chip * 60))
        started += chip
        #expect(record.usedSeconds == record.minutes * 60)
        #expect(started == 170)
        #expect(record.remainingMinutes == 0)
    }
}

@Suite struct DayBudgetChipTests {
    @Test("FR-05 R-409: 시작 전 칩은 마지막 칩 → 기본 작업 시간 → 남은 예상 시간 → 남은 분 순으로 짧은 값")
    func draftChipOrder() {
        #expect(QuantumChip.draftChip(lastChip: 45, defaultMin: 25, remainingEstimateMin: nil, remainingMinutes: nil) == 45)
        #expect(QuantumChip.draftChip(lastChip: nil, defaultMin: 25, remainingEstimateMin: nil, remainingMinutes: nil) == 25)
        #expect(QuantumChip.draftChip(lastChip: 45, defaultMin: 25, remainingEstimateMin: 20, remainingMinutes: nil) == 20)
        #expect(QuantumChip.draftChip(lastChip: 45, defaultMin: 25, remainingEstimateMin: 20, remainingMinutes: 10) == 10)
        #expect(QuantumChip.draftChip(lastChip: nil, defaultMin: 25, remainingEstimateMin: 30, remainingMinutes: 40) == 25)
    }

    @Test("FR-05 R-409: 남은 예상 시간이 0 이하면 1분")
    func draftChipEstimateFloor() {
        #expect(QuantumChip.draftChip(lastChip: nil, defaultMin: 25, remainingEstimateMin: -5, remainingMinutes: nil) == 1)
    }

    @Test("FR-05 R-409 US3-3: 시간 끝 칩은 추가 시간, 남은 분이 더 짧으면 그 값")
    func expiredChip() {
        #expect(QuantumChip.expiredChip(extendMin: 10, remainingMinutes: 5) == 5)
        #expect(QuantumChip.expiredChip(extendMin: 10, remainingMinutes: 30) == 10)
        #expect(QuantumChip.expiredChip(extendMin: 10, remainingMinutes: nil) == 10)
    }

    @Test("FR-10 R-421: 시작 전 화면은 남은 분보다 긴 프리셋도 켜 두고, 시간 끝 화면만 끈다")
    func presetsEnabled() {
        let draft = QuantumChip.segments(chipMin: 10, customText: nil)
        #expect(draft.allSatisfy(\.enabled))
        let expired = QuantumChip.segments(chipMin: 10, customText: nil, maxMinutes: 25)
        #expect(expired.map(\.enabled) == [true, true, false, false, true])
    }

    @Test("FR-10 R-421: 시간 끝 화면의 직접 입력이 남은 분보다 크면 aboveRemaining과 해요체 한 줄")
    func aboveRemaining() {
        #expect(QuantumChip.customIssue("6", remainingMinutes: 5) == .aboveRemaining(5))
        #expect(QuantumChip.customIssue("5", remainingMinutes: 5) == nil)
        #expect(QuantumChip.customIssue("200", remainingMinutes: 5) == .aboveMax)
        #expect(
            QuantumChip.customIssueMessage(customText: "6", remainingMinutes: 5)
                == "오늘 남은 시간이 5분이라 5분까지 이어 갈 수 있어요.")
        #expect(!QuantumChip.startAllowed(customText: "6", remainingMinutes: 5))
        #expect(QuantumChip.startAllowed(customText: "5", remainingMinutes: 5))
    }

    @Test("FR-10 R-421 R-420: 하루 경계를 넘긴 작업 시간의 N분 더는 시작한 하루 기록으로 상한을 건다")
    func boundaryUsesBudgetDay() {
        let started = budget(120, used: 115 * 60, day: yesterday)
        let record = DayBudget.record(started, for: yesterday)
        #expect(QuantumChip.expiredChip(extendMin: 10, remainingMinutes: DayBudget.capMinutes(record)) == 5)
        #expect(started.applying(BudgetUse(day: yesterday, seconds: 300)).usedSeconds == 7200)
        #expect(DayBudget.capMinutes(DayBudget.record(started, for: today)) == nil)
        #expect(DayBudget.capMinutes(DayBudget.record(budget(120, used: 0, more: true, day: yesterday), for: yesterday)) == nil)
    }
}

@Suite struct BudgetInputTests {
    @Test("FR-10 R-419: 직접 적은 가용 시간은 0.5 단위 시간을 분으로", arguments: [("1.5", 90), ("0.5", 30), ("16", 960), (" 2 ", 120), ("2.50", 150)])
    func accepts(text: String, minutes: Int) {
        #expect(BudgetInput.parse(text) == .success(minutes))
    }

    @Test(
        "FR-10 R-419: 오류 넷과 빈 칸",
        arguments: [
            ("abc", BudgetInputIssue.notNumber), ("1,5", .notNumber), ("-1", .notNumber), ("2.3", .notHalfHour),
            ("0", .belowMin), ("16.5", .aboveMax), ("", .empty), ("  ", .empty),
        ])
    func rejects(text: String, issue: BudgetInputIssue) {
        #expect(BudgetInput.parse(text) == .failure(issue))
    }

    @Test("FR-10 R-419: 오류 문구 넷, 빈 칸은 문구 없음")
    func messages() {
        #expect(BudgetInputIssue.notNumber.message == "시간은 숫자로 적어 주세요. 예: 1.5")
        #expect(BudgetInputIssue.notHalfHour.message == "30분 단위로 적어 주세요. 예: 2 또는 2.5")
        #expect(BudgetInputIssue.belowMin.message == "30분(0.5)부터 정할 수 있어요")
        #expect(BudgetInputIssue.aboveMax.message == "16시간까지 정할 수 있어요")
        #expect(BudgetInputIssue.empty.message == nil)
    }

    @Test("FR-10 R-419: 범위와 단위는 Defaults 한 곳에 있다")
    func defaults() {
        #expect(Defaults.customBudgetMinutesRange == 30...960)
        #expect(Defaults.customBudgetStepMinutes == 30)
    }
}
