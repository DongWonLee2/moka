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

@Test("FR-16 R-013: 기본값을 바꿔도 도는 타이머와 이미 채운 칩은 그대로, 다음 채움에 반영")
func defaultChangeAffectsOnlyNextFill() throws {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let store = InMemorySettingsStore()
    var timer = NotchTimer.empty(draft: nil)
    _ = timer.apply(.enterTitle("가짜 할 일 A"), at: t0, defaultQuantumMin: QuantumSettings.readDefault(from: store))
    _ = timer.apply(.start, at: t0, defaultQuantumMin: QuantumSettings.readDefault(from: store))
    let started = timer

    try QuantumSettings.writeDefault(45, to: store)
    let t1 = t0.addingTimeInterval(60)
    #expect(timer.apply(.tick, at: t1, defaultQuantumMin: QuantumSettings.readDefault(from: store)) == .applied)
    #expect(timer == started)
    #expect(timer == .running(title: "가짜 할 일 A", quantumMin: 25, startedAt: t0, endsAt: t0.addingTimeInterval(1500)))

    let t2 = t0.addingTimeInterval(1500)
    _ = timer.apply(.tick, at: t2, defaultQuantumMin: QuantumSettings.readDefault(from: store))
    #expect(timer == .expired(title: "가짜 할 일 A", chipMin: 45))

    try QuantumSettings.writeDefault(15, to: store)
    _ = timer.apply(.tick, at: t2.addingTimeInterval(60), defaultQuantumMin: QuantumSettings.readDefault(from: store))
    #expect(timer == .expired(title: "가짜 할 일 A", chipMin: 45))
}
