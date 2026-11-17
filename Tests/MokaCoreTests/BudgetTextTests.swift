import Foundation
import MokaCore
import Testing

// spec 005 data-model §11·§13·§19, 확정 시안 005 4~9·10-2·10-3번. 가짜 값만 쓴다.

private struct ThrowingSettingsStore: SettingsStore {
    struct Failure: Error {}

    func value(for key: String) throws -> String? { throw Failure() }
    func setValue(_ value: String, for key: String) throws { throw Failure() }
}

@Suite struct BudgetTextTests {
    @Test(
        "FR-10 R-422: 시간 값은 시간과 분으로 쓰고 0인 쪽은 뺀다",
        arguments: [(120, "2시간"), (135, "2시간 15분"), (30, "30분"), (90, "1시간 30분"), (960, "16시간")])
    func duration(minutes: Int, expected: String) {
        #expect(BudgetText.duration(minutes: minutes) == expected)
    }

    @Test("FR-10 R-419: 선택지 글자는 시간 × 1·2·4·6·8")
    func choices() {
        #expect(BudgetText.choices == ["1시간", "2시간", "4시간", "6시간", "8시간"])
    }

    @Test("FR-10 R-409 R-421: 남은 시간 안내 줄(시안 5·7번)")
    func capNote() {
        #expect(BudgetText.capNote(minutes: 10, expired: false) == "오늘 남은 시간은 10분이에요. 더 길게 고르면 오늘 시간을 늘릴지 물어요.")
        #expect(BudgetText.capNote(minutes: 5, expired: true) == "오늘 남은 시간이 5분이라 5분까지 이어 갈 수 있어요.")
    }

    @Test("FR-10 R-421: 늘리기 확인 줄(시안 6번)")
    func extend() {
        #expect(BudgetText.extendTitle(extra: 15, chip: 25) == "오늘 시간을 15분 늘려서 25분 할까요?")
        #expect(BudgetText.extendDetail(remaining: 10, newTotal: 135) == "오늘 남은 시간은 10분이에요. 늘리면 오늘 정한 시간이 2시간 15분이 돼요.")
        #expect(BudgetText.keepRemaining(minutes: 10) == "10분만 할래요")
    }

    @Test("FR-10 R-422: 오늘 끝과 겹친 시간 끝, 하루 경계 뒤 시간 끝, 오늘 끝 제목(시안 8·9번, 사용자 결정 2026-11-17)")
    func dayEnd() {
        #expect(BudgetText.dayEndOff(minutes: 120) == "오늘 정한 2시간을 다 써서 더 이어 갈 수 없어요. 두 줄을 적고 버튼을 눌러 주세요.")
        #expect(BudgetText.crossDayOff(minutes: 120) == "어제 정한 2시간을 다 썼어요.")
        #expect(BudgetText.dayEndTitle(minutes: 135) == "오늘 정한 2시간 15분을 다 썼어요")
    }

    @Test("FR-10 R-422: 오늘 쓴 시간은 가까운 분으로 반올림하고 막대는 0~1")
    func usage() {
        #expect(BudgetText.used(seconds: 7170) == "2시간")
        #expect(BudgetText.used(seconds: 7140) == "1시간 59분")
        #expect(BudgetText.usedFraction(DayBudget(day: Fake.day("2027-01-13"), minutes: 120, extendedMinutes: 0, usedSeconds: 3600, more: false)) == 0.5)
        #expect(BudgetText.usedFraction(DayBudget(day: Fake.day("2027-01-13"), minutes: 120, extendedMinutes: 0, usedSeconds: 9000, more: false)) == 1)
    }

    @Test("FR-10 R-419 R-422: 노치 귀 글자")
    func earLabels() {
        #expect(NotchStatus.askBudgetLabel == "오늘 정하기")
        #expect(NotchStatus.dayEndLabel == "오늘 끝")
    }
}

@Suite struct DayBudgetSettingsTests {
    private let value = DayBudget(day: Fake.day("2027-01-13"), minutes: 135, extendedMinutes: 15, usedSeconds: 60, more: false)

    @Test("FR-10 R-419: 설정 키 이름은 day_budget(승인 5)")
    func key() {
        #expect(CoreSettings.dayBudgetKey == "day_budget")
    }

    @Test("FR-10 R-419 R-420: 쓰면 data-model §11 JSON으로 저장하고 다시 읽는다")
    func roundTrip() throws {
        let store = InMemorySettingsStore()
        try CoreSettings.writeDayBudget(value, to: store)
        #expect(try store.value(for: "day_budget") == value.json)
        #expect(CoreSettings.readDayBudget(from: store) == value)
    }

    @Test("FR-10 R-419: 없거나 읽기 실패·형식 오류면 없음")
    func missingOrBroken() throws {
        #expect(CoreSettings.readDayBudget(from: InMemorySettingsStore()) == nil)
        #expect(CoreSettings.readDayBudget(from: ThrowingSettingsStore()) == nil)
        let store = InMemorySettingsStore()
        try store.setValue("{}", for: "day_budget")
        #expect(CoreSettings.readDayBudget(from: store) == nil)
    }
}

@Suite struct SessionAssemblyBudgetModeTests {
    @Test("FR-10 R-419 R-422: 하루 값이 있으면 질문과 오늘 끝을 늘 쓴다(앱과 sim이 같은 표)")
    func modeAsksBudget() {
        let today = Fake.day("2027-01-13")
        let schedule = SessionAssembly.Schedule(today: today, budget: nil, revertedIDs: [])
        #expect(SessionAssembly.mode(.empty(draft: nil), tasks: [Fake.task(1)], schedule: schedule) == .askBudget)
        let spent = SessionAssembly.Schedule(
            today: today,
            budget: DayBudget(day: today, minutes: 60, extendedMinutes: 0, usedSeconds: 3600, more: false),
            revertedIDs: [])
        #expect(SessionAssembly.mode(.empty(draft: nil), tasks: [Fake.task(1)], schedule: spent) == .dayEnd)
    }
}
