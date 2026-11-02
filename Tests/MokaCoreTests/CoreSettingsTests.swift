import Foundation
import MokaCore
import Testing

private struct ThrowingSettingsStore: SettingsStore {
    struct Failure: Error {}

    func value(for key: String) throws -> String? { throw Failure() }
    func setValue(_ value: String, for key: String) throws { throw Failure() }
}

@Test("FR-16: 설정 키 이름은 data-model §6 그대로")
func coreSettingsKeys() {
    #expect(CoreSettings.extendMinKey == "default_extend_min")
    #expect(CoreSettings.dayStartKey == "day_start")
    #expect(CoreSettings.onboardingDoneKey == "onboarding_done")
}

@Test("FR-16: 초기값은 추가 시간 10분, 범위 1~180, 하루 시작 06:00")
func coreSettingsDefaults() {
    #expect(Defaults.extendMin == 10)
    #expect(Defaults.extendMinRange == 1...180)
    #expect(Defaults.dayStart.text == "06:00")
}

// MARK: - default_extend_min

@Test("FR-16: 추가 시간 행이 없으면 10")
func extendMinWithoutRowIs10() {
    #expect(CoreSettings.readExtendMin(from: InMemorySettingsStore()) == 10)
}

@Test("FR-16: 저장된 1~180 정수는 추가 시간으로 그대로 읽는다", arguments: [("1", 1), ("15", 15), ("180", 180)])
func extendMinReadsStoredInteger(stored: String, expected: Int) throws {
    let store = InMemorySettingsStore()
    try store.setValue(stored, for: CoreSettings.extendMinKey)
    #expect(CoreSettings.readExtendMin(from: store) == expected)
}

@Test("FR-16: 추가 시간이 정수가 아니거나 범위 밖이면 10", arguments: ["0", "181", "-5", "4.5", "", "abc", " 15", "15 "])
func extendMinFallsBackTo10(stored: String) throws {
    let store = InMemorySettingsStore()
    try store.setValue(stored, for: CoreSettings.extendMinKey)
    #expect(CoreSettings.readExtendMin(from: store) == 10)
}

@Test("FR-16: 추가 시간 쓰기는 1~180만 받고 틀리면 이전 값을 둔다")
func extendMinWriteKeepsPreviousOnInvalid() throws {
    let store = InMemorySettingsStore()
    try CoreSettings.writeExtendMin(20, to: store)
    #expect(try store.value(for: CoreSettings.extendMinKey) == "20")
    for invalid in [0, 181, -1] {
        #expect(throws: CoreSettingsError.outOfRange) { try CoreSettings.writeExtendMin(invalid, to: store) }
    }
    #expect(try store.value(for: CoreSettings.extendMinKey) == "20")
    #expect(CoreSettings.readExtendMin(from: store) == 20)
}

// MARK: - day_start

@Test("FR-16: 하루 시작 행이 없으면 06:00")
func dayStartWithoutRowIs0600() {
    #expect(CoreSettings.readDayStart(from: InMemorySettingsStore()) == Defaults.dayStart)
}

@Test("FR-16: 저장된 HH:MM은 하루 시작으로 그대로 읽는다", arguments: ["00:00", "05:30", "23:59"])
func dayStartReadsStoredText(stored: String) throws {
    let store = InMemorySettingsStore()
    try store.setValue(stored, for: CoreSettings.dayStartKey)
    #expect(CoreSettings.readDayStart(from: store).text == stored)
}

@Test("FR-16: 하루 시작 형식이 틀리면 06:00", arguments: ["", "6:00", "24:00", "07:60", "07:00:00", " 07:00", "abc"])
func dayStartFallsBackTo0600(stored: String) throws {
    let store = InMemorySettingsStore()
    try store.setValue(stored, for: CoreSettings.dayStartKey)
    #expect(CoreSettings.readDayStart(from: store).text == "06:00")
}

@Test("FR-16: 하루 시작 쓰기는 HH:MM 텍스트로 남는다")
func dayStartWriteStoresText() throws {
    let store = InMemorySettingsStore()
    try CoreSettings.writeDayStart(try #require(DayStart(text: "05:30")), to: store)
    #expect(try store.value(for: CoreSettings.dayStartKey) == "05:30")
    #expect(CoreSettings.readDayStart(from: store).text == "05:30")
}

// MARK: - onboarding_done

@Test("FR-21 R-116: onboarding_done 행이 없으면 온보딩을 보인다")
func onboardingShownWithoutRow() {
    #expect(!CoreSettings.isOnboardingDone(in: InMemorySettingsStore()))
}

@Test("FR-21 R-116: 값이 정확히 true일 때만 온보딩을 끝낸 것으로 읽는다", arguments: [("true", true), ("TRUE", false), ("True", false), ("1", false), ("yes", false), ("", false), (" true", false), ("false", false)])
func onboardingDoneOnlyForExactTrue(stored: String, done: Bool) throws {
    let store = InMemorySettingsStore()
    try store.setValue(stored, for: CoreSettings.onboardingDoneKey)
    #expect(CoreSettings.isOnboardingDone(in: store) == done)
}

@Test("FR-21 R-116: 온보딩 끝내기 표시는 true를 쓴다")
func markOnboardingDoneWritesTrue() throws {
    let store = InMemorySettingsStore()
    try CoreSettings.markOnboardingDone(in: store)
    #expect(try store.value(for: CoreSettings.onboardingDoneKey) == "true")
    #expect(CoreSettings.isOnboardingDone(in: store))
}

// MARK: - 저장소 실패

@Test("FR-16: 저장소가 읽기에 실패하면 세 키 모두 읽기 기본값")
func readsFallBackWhenStoreThrows() {
    let store = ThrowingSettingsStore()
    #expect(CoreSettings.readExtendMin(from: store) == 10)
    #expect(CoreSettings.readDayStart(from: store).text == "06:00")
    #expect(!CoreSettings.isOnboardingDone(in: store))
}

@Test("FR-16: 저장소 쓰기 실패는 그대로 던진다")
func writesRethrowStoreFailure() throws {
    let store = ThrowingSettingsStore()
    let seven = try #require(DayStart(text: "07:00"))
    #expect(throws: ThrowingSettingsStore.Failure.self) { try CoreSettings.writeExtendMin(15, to: store) }
    #expect(throws: ThrowingSettingsStore.Failure.self) { try CoreSettings.writeDayStart(seven, to: store) }
    #expect(throws: ThrowingSettingsStore.Failure.self) { try CoreSettings.markOnboardingDone(in: store) }
}
