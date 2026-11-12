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

@Test(
    "FR-21 R-116: 값이 정확히 true일 때만 온보딩을 끝낸 것으로 읽는다",
    arguments: [
        ("true", true), ("TRUE", false), ("True", false), ("1", false), ("yes", false), ("", false), (" true", false),
        ("false", false),
    ])
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

@Test("FR-16 R-012 #59: 추가 시간 칸에 받는 값을 제출하면 저장하고 칸은 저장된 값", arguments: [("15", "15"), ("+15", "15"), ("180", "180")])
func commitExtendFieldSavesAcceptedText(text: String, shown: String) throws {
    let store = InMemorySettingsStore()
    let result = CoreSettings.commitExtendField(text, to: store)
    #expect(result.shown == shown)
    #expect(result.attempted)
    #expect(result.error == nil)
    #expect(try store.value(for: CoreSettings.extendMinKey) == shown)
}

@Test("FR-16 R-012 #59: 추가 시간 칸에 받지 않는 값을 제출하면 저장하지 않고 칸은 저장된 값으로 되돌린다", arguments: ["", "0", "181", "4.5", "abc"])
func commitExtendFieldRevertsRejectedText(text: String) throws {
    let store = InMemorySettingsStore()
    try CoreSettings.writeExtendMin(15, to: store)
    let result = CoreSettings.commitExtendField(text, to: store)
    #expect(result.shown == "15")
    #expect(!result.attempted)
    #expect(try store.value(for: CoreSettings.extendMinKey) == "15")
}

@Test("FR-16 R-012 #59: 추가 시간 저장에 실패하면 오류를 돌려주고 칸은 읽기 기본값 10")
func commitExtendFieldRevertsWhenSaveFails() {
    let result = CoreSettings.commitExtendField("30", to: ThrowingSettingsStore())
    #expect(result.shown == "10")
    #expect(result.attempted)
    #expect(result.error is ThrowingSettingsStore.Failure)
}

@Test("FR-16 R-012 #59: 추가 시간 스테퍼 값은 해석 없이 저장한다")
func saveExtendFieldStoresStepperValue() {
    let store = InMemorySettingsStore()
    let result = CoreSettings.saveExtendField(11, to: store)
    #expect(result.shown == "11")
    #expect(CoreSettings.readExtendMin(from: store) == 11)
}

@Test("FR-16 #59: 하루 시작 시각은 시각 고르기의 Date로 바꿨다 되돌려도 같다", arguments: ["00:00", "06:00", "05:30", "23:59"])
func dayStartRoundTripsThroughDate(text: String) throws {
    let calendar = GregorianCalendar.make(timeZone: try #require(TimeZone(identifier: "Asia/Seoul")))
    let dayStart = try #require(DayStart(text: text))
    let date = dayStart.date(calendar: calendar)
    #expect(calendar.component(.hour, from: date) == dayStart.hour)
    #expect(calendar.component(.minute, from: date) == dayStart.minute)
    #expect(DayStart(date: date, calendar: calendar) == dayStart)
}

@Test("FR-16 #59: 시각 고르기가 낸 Date의 초는 버리고 시·분만 쓴다")
func dayStartFromDateDropsSeconds() throws {
    let calendar = GregorianCalendar.make(timeZone: try #require(TimeZone(identifier: "America/New_York")))
    let parts = DateComponents(year: 2026, month: 3, day: 8, hour: 7, minute: 15, second: 42)
    let date = try #require(calendar.date(from: parts))
    #expect(DayStart(date: date, calendar: calendar).text == "07:15")
}

// MARK: - 판단 공급자 (spec 006 research R8)

@Test("ADR-0011 R-614: 판단 공급자 설정 키 이름은 research R8 그대로")
func decisionProviderKeys() {
    #expect(CoreSettings.decisionProviderKey == "decision_provider")
    #expect(CoreSettings.microsoftEndpointKey == "microsoft_endpoint")
    #expect(CoreSettings.microsoftDeploymentKey == "microsoft_deployment")
}

@Test("ADR-0011 R-614: 판단 공급자 행이 없으면 nil(Jev로 본다)")
func decisionProviderMissingIsNil() throws {
    #expect(try CoreSettings.readDecisionProvider(from: InMemorySettingsStore()) == nil)
    #expect(try CoreSettings.readMicrosoftEndpoint(from: InMemorySettingsStore()) == nil)
    #expect(CoreSettings.readMicrosoftDeployment(from: ThrowingSettingsStore()) == nil)
}

@Test("ADR-0011 R-614 #128: 판단 공급자·Microsoft 주소 읽기가 실패하면 없음과 구분해 던진다")
func decisionProviderReadFailureThrows() {
    #expect(throws: (any Error).self) { try CoreSettings.readDecisionProvider(from: ThrowingSettingsStore()) }
    #expect(throws: (any Error).self) { try CoreSettings.readMicrosoftEndpoint(from: ThrowingSettingsStore()) }
}

@Test("ADR-0011 R-614: 판단 공급자는 공급자 ID 원시값으로 쓰고 읽은 글자는 그대로 돌려준다")
func decisionProviderRoundTrip() throws {
    let store = InMemorySettingsStore()
    try CoreSettings.writeDecisionProvider(.liquid, to: store)
    #expect(try store.value(for: CoreSettings.decisionProviderKey) == "liquid")
    #expect(try CoreSettings.readDecisionProvider(from: store) == "liquid")
    try store.setValue("fake-unknown", for: CoreSettings.decisionProviderKey)
    #expect(try CoreSettings.readDecisionProvider(from: store) == "fake-unknown")
}

@Test("ADR-0011 R-614: Microsoft 주소는 검사를 통과한 주소 글자로, 배포 이름은 앞뒤 공백을 지워 쓴다")
func microsoftFieldsRoundTrip() throws {
    let store = InMemorySettingsStore()
    let endpoint = try EndpointRule.check(" https://example-resource.invalid/ ", allowsPath: false).get()
    try CoreSettings.writeMicrosoftEndpoint(endpoint, to: store)
    try CoreSettings.writeMicrosoftDeployment("  fake-deploy \n", to: store)
    #expect(try store.value(for: CoreSettings.microsoftEndpointKey) == "https://example-resource.invalid")
    #expect(try CoreSettings.readMicrosoftEndpoint(from: store) == "https://example-resource.invalid")
    #expect(CoreSettings.readMicrosoftDeployment(from: store) == "fake-deploy")
}

@Test("ADR-0011 R-614: 판단 공급자 설정 쓰기가 실패하면 던진다")
func decisionProviderWriteFailureThrows() throws {
    let endpoint = try EndpointRule.check("https://example-resource.invalid", allowsPath: false).get()
    let failing = ThrowingSettingsStore()
    #expect(throws: (any Error).self) { try CoreSettings.writeDecisionProvider(.typesafe, to: failing) }
    #expect(throws: (any Error).self) { try CoreSettings.writeMicrosoftEndpoint(endpoint, to: failing) }
    #expect(throws: (any Error).self) { try CoreSettings.writeMicrosoftDeployment("fake-deploy", to: failing) }
}
