import Foundation
import MokaCore
import Testing

private struct ThrowingSettingsStore: SettingsStore {
    struct Failure: Error {}

    func value(for key: String) throws -> String? {
        throw Failure()
    }

    func setValue(_ value: String, for key: String) throws {
        throw Failure()
    }
}

@Test("FR-16 R-012: 설정 행이 없으면 기본 작업 시간은 25")
func readDefaultWithoutRowIs25() {
    #expect(QuantumSettings.readDefault(from: InMemorySettingsStore()) == 25)
}

@Test("FR-16 R-012: 저장된 1~180 정수는 그대로 읽는다", arguments: [("1", 1), ("45", 45), ("180", 180)])
func readDefaultReadsStoredInteger(stored: String, expected: Int) throws {
    let store = InMemorySettingsStore()
    try store.setValue(stored, for: QuantumSettings.key)
    #expect(QuantumSettings.readDefault(from: store) == expected)
}

@Test("FR-16 R-012: 정수가 아니거나 범위 밖이면 25", arguments: ["0", "181", "-5", "4.5", "", "abc", " 45"])
func readDefaultFallsBackTo25(stored: String) throws {
    let store = InMemorySettingsStore()
    try store.setValue(stored, for: QuantumSettings.key)
    #expect(QuantumSettings.readDefault(from: store) == 25)
}

@Test("FR-16 R-012: 저장소가 읽기에 실패하면 25")
func readDefaultFallsBackWhenStoreThrows() {
    #expect(QuantumSettings.readDefault(from: ThrowingSettingsStore()) == 25)
}

@Test("FR-16 R-012: 1~180 정수는 저장하고 다시 읽힌다", arguments: [1, 45, 180])
func writeDefaultStoresValue(minutes: Int) throws {
    let store = InMemorySettingsStore()
    try QuantumSettings.writeDefault(minutes, to: store)
    #expect(try store.value(for: QuantumSettings.key) == String(minutes))
    #expect(QuantumSettings.readDefault(from: store) == minutes)
}

@Test("FR-16 R-012: 범위 밖 값은 outOfRange로 거부하고 이전 값을 유지한다", arguments: [0, -1, 181])
func writeDefaultRejectsOutOfRange(minutes: Int) throws {
    let store = InMemorySettingsStore()
    try QuantumSettings.writeDefault(45, to: store)
    #expect(throws: QuantumSettingsError.outOfRange) {
        try QuantumSettings.writeDefault(minutes, to: store)
    }
    #expect(try store.value(for: QuantumSettings.key) == "45")
}

@Test("FR-16 R-012: 저장소 쓰기 실패는 그대로 던진다")
func writeDefaultPropagatesStoreError() {
    #expect(throws: ThrowingSettingsStore.Failure.self) {
        try QuantumSettings.writeDefault(45, to: ThrowingSettingsStore())
    }
}

@Test("FR-16 R-013 R-003: 설정 쓰기와 tick만으로는 도는 타이머가 그대로이고, 시간 끝 칩은 저장된 추가 시간이며 기본값 변경에 그대로")
func defaultChangeAppliesOnlyThroughApplyDefaultQuantumChange() throws {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let store = InMemorySettingsStore()
    func apply(_ event: TimerEvent, at now: Date, to timer: inout NotchTimer) -> TransitionResult {
        timer.apply(
            event, at: now, defaultQuantumMin: QuantumSettings.readDefault(from: store),
            extendMin: CoreSettings.readExtendMin(from: store))
    }
    var timer = NotchTimer.empty(draft: nil)
    _ = apply(.enterTitle("가짜 할 일 A"), at: t0, to: &timer)
    _ = apply(.start, at: t0, to: &timer)
    let started = timer

    try QuantumSettings.writeDefault(45, to: store)
    try CoreSettings.writeExtendMin(20, to: store)
    let t1 = t0.addingTimeInterval(60)
    #expect(apply(.tick, at: t1, to: &timer) == .applied)
    #expect(timer == started)
    #expect(timer == .running(title: "가짜 할 일 A", quantumMin: 25, startedAt: t0, endsAt: t0.addingTimeInterval(1500)))

    let t2 = t0.addingTimeInterval(1500)
    _ = apply(.tick, at: t2, to: &timer)
    #expect(timer == .expired(title: "가짜 할 일 A", chipMin: 20))

    try QuantumSettings.writeDefault(15, to: store)
    try CoreSettings.writeExtendMin(30, to: store)
    _ = apply(.tick, at: t2.addingTimeInterval(60), to: &timer)
    #expect(timer == .expired(title: "가짜 할 일 A", chipMin: 20))

    timer.applyDefaultQuantumChange(QuantumSettings.readDefault(from: store), isEditingCustom: false)
    #expect(timer == .expired(title: "가짜 할 일 A", chipMin: 20))
}

/// 읽기는 되고 쓰기만 실패하는 저장소. 저장 실패 뒤 칸이 이전 값으로 돌아가는지 본다.
private final class WriteFailingSettingsStore: SettingsStore {
    struct Failure: Error {}
    private let stored: InMemorySettingsStore

    init(stored: InMemorySettingsStore) { self.stored = stored }

    func value(for key: String) throws -> String? {
        try stored.value(for: key)
    }

    func setValue(_ value: String, for key: String) throws {
        throw Failure()
    }
}

@Test("FR-16 R-012 #35: 칸에 받는 값을 제출하면 저장하고 칸은 저장된 값", arguments: [("45", "45"), ("+45", "45"), ("180", "180")])
func commitFieldSavesAcceptedText(text: String, shown: String) throws {
    let store = InMemorySettingsStore()
    let result = QuantumSettings.commitField(text, to: store)
    #expect(result.shown == shown)
    #expect(result.attempted)
    #expect(result.error == nil)
    #expect(try store.value(for: QuantumSettings.key) == shown)
}

@Test("FR-16 R-012 #35: 칸에 받지 않는 값을 제출하면 저장하지 않고 칸은 저장된 값으로 되돌린다", arguments: ["", "0", "181", "4.5", "abc", " 45"])
func commitFieldRevertsRejectedText(text: String) throws {
    let store = InMemorySettingsStore()
    try QuantumSettings.writeDefault(45, to: store)
    let result = QuantumSettings.commitField(text, to: store)
    #expect(result.shown == "45")
    #expect(!result.attempted)
    #expect(result.error == nil)
    #expect(try store.value(for: QuantumSettings.key) == "45")
}

@Test("FR-16 R-012 #35: 저장에 실패하면 오류를 돌려주고 칸은 이전 값으로 되돌린다")
func commitFieldRevertsWhenSaveFails() throws {
    let stored = InMemorySettingsStore()
    try QuantumSettings.writeDefault(45, to: stored)
    let result = QuantumSettings.commitField("60", to: WriteFailingSettingsStore(stored: stored))
    #expect(result.shown == "45")
    #expect(result.attempted)
    #expect(result.error is WriteFailingSettingsStore.Failure)
}

@Test("FR-16 R-012 #35: 스테퍼 값은 해석 없이 저장하고 칸은 저장된 값")
func saveFieldStoresStepperValue() throws {
    let store = InMemorySettingsStore()
    let result = QuantumSettings.saveField(26, to: store)
    #expect(result.shown == "26")
    #expect(result.attempted)
    #expect(result.error == nil)
    #expect(QuantumSettings.readDefault(from: store) == 26)
}
