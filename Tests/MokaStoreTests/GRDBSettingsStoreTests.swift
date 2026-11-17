import Foundation
import GRDB
import MokaCore
import MokaStore
import Testing

private func settingsRowCount(_ db: DatabaseQueue) throws -> Int {
    try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM settings") } ?? -1
}

@Test("FR-16 R-012: 없는 하위 폴더 경로로 열면 폴더가 생기고 seed 행이 없다")
func openCreatesFolderWithoutSeed() throws {
    let url = TestDatabase.freshFileURL()
    defer { TestDatabase.removeTestFolder(of: url) }
    #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))

    let db = try TestDatabase.open(at: url)
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(try settingsRowCount(db) == 0)
    #expect(QuantumSettings.readDefault(from: GRDBSettingsStore(db)) == 25)
}

@Test("FR-16 R-012: 45를 저장하고 닫았다 다시 열어도 45")
func savedDefaultSurvivesReopen() throws {
    let url = TestDatabase.freshFileURL()
    defer { TestDatabase.removeTestFolder(of: url) }

    let first = try TestDatabase.open(at: url)
    try QuantumSettings.writeDefault(45, to: GRDBSettingsStore(first))
    try first.close()

    let second = try TestDatabase.open(at: url)
    #expect(QuantumSettings.readDefault(from: GRDBSettingsStore(second)) == 45)
    let stored = try second.read {
        try String.fetchOne($0, sql: "SELECT value FROM settings WHERE key = ?", arguments: [QuantumSettings.key])
    }
    #expect(stored == "45")
}

@Test("FR-16 R-012: 같은 키를 두 번 저장하면 UPSERT로 행 하나, 나중 값")
func saveTwiceUpserts() throws {
    let db = try TestDatabase.migratedInMemory()
    let store = GRDBSettingsStore(db)
    try store.setValue("15", for: QuantumSettings.key)
    try store.setValue("60", for: QuantumSettings.key)
    #expect(try settingsRowCount(db) == 1)
    #expect(try store.value(for: QuantumSettings.key) == "60")
    #expect(try store.value(for: "missing") == nil)
}

@Test("FR-16 R-012: 범위 밖 저장은 거부되고 이전 값이 남는다")
func outOfRangeKeepsPreviousValue() throws {
    let db = try TestDatabase.migratedInMemory()
    let store = GRDBSettingsStore(db)
    try QuantumSettings.writeDefault(45, to: store)
    #expect(throws: QuantumSettingsError.outOfRange) { try QuantumSettings.writeDefault(181, to: store) }
    #expect(QuantumSettings.readDefault(from: store) == 45)
}

@Test("FR-08 R-412: 설정 저장소는 이월 판정 시각 키를 읽지도 쓰지도 않고 거부한다(Q1-B)")
func settingsStoreRejectsCarryJudgedAt() throws {
    let db = try TestDatabase.migratedInMemory()
    let settings = GRDBSettingsStore(db)
    #expect(throws: StoreError.invalidValue(column: "key")) {
        try settings.setValue("2026-10-26T07:33:20Z", for: "carry_judged_at")
    }
    #expect(try settingsRowCount(db) == 0, "거부한 쓰기는 아무것도 남기지 않는다")

    try GRDBTaskRepository(db).applyCarryJudgment(.empty, judgedAt: Date(timeIntervalSince1970: 1_793_000_000))
    #expect(try settingsRowCount(db) == 1, "판정 시각은 할 일 저장소가 같은 settings 표에 쓴다")
    #expect(throws: StoreError.invalidValue(column: "key")) { try settings.value(for: "carry_judged_at") }
    #expect(try settings.value(for: "day_start") == nil, "다른 키는 그대로 읽는다")
}
