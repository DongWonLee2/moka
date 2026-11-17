import Foundation
import MokaCore
import Testing

/// spec 005 data-model §9(Q1-B): 이월 판정 시각 키는 `TaskRepository` 구현(GRDB·메모리)만 읽고 쓴다.
/// 설정 저장소는 이 키를 거부하고, 소스에서 키 글자는 할 일 저장소 구현 밖에 없다. 주석 줄은 보지 않는다.
struct CarryJudgmentBoundaryTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MokaCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // 저장소 루트

    /// 금지 글자를 이 파일에 그대로 두면 소스 검색이 자기 자신을 잡지 않도록 이어 붙여 만든다.
    private static let keyLiteral = "\"carry_" + "judged_at\""
    private static let keyConstant = "CarryJudgmentStorage" + ".settingsKey"

    /// `Sources/`와 `App/Sources/` 아래 Swift 파일의 주석이 아닌 줄에서 `needle`이 든 파일(저장소 루트 기준 경로).
    private static func files(containing needle: String) throws -> Set<String> {
        var found: Set<String> = []
        var scanned = 0
        for folder in ["Sources", "App/Sources"] {
            let url = root.appending(path: folder, directoryHint: .isDirectory)
            let enumerator = try #require(FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil))
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                scanned += 1
                let relative = String(file.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
                for line in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n") {
                    let code = line.trimmingCharacters(in: .whitespaces)
                    if code.hasPrefix("//") || code.hasPrefix("*") || code.hasPrefix("/*") { continue }
                    if code.contains(needle) { found.insert(relative) }
                }
            }
        }
        #expect(scanned > 50, "소스 폴더를 찾지 못했다: \(root.path)")
        return found
    }

    @Test("FR-08 R-412: 메모리 설정 저장소는 이월 판정 시각 키를 읽지도 쓰지도 않고 거부한다")
    func inMemorySettingsRejectCarryJudgedAt() throws {
        let settings = InMemorySettingsStore()
        #expect(throws: StoreError.invalidValue(column: "key")) {
            try settings.setValue("2027-01-13T03:00:00Z", for: CarryJudgmentStorage.settingsKey)
        }
        #expect(throws: StoreError.invalidValue(column: "key")) {
            try settings.value(for: CarryJudgmentStorage.settingsKey)
        }
        try settings.setValue("07:00", for: CoreSettings.dayStartKey)
        #expect(try settings.value(for: CoreSettings.dayStartKey) == "07:00", "다른 키는 그대로 쓰고 읽는다")
    }

    @Test("FR-08 R-412: 이월 판정 시각 키 이름은 carry_judged_at이다")
    func carryJudgedAtKeyName() {
        #expect(CarryJudgmentStorage.settingsKey == "carry_judged_at")
    }

    @Test("FR-08 R-412: 키 글자는 할 일 저장소 구현 파일에만 있고 CoreSettings에는 없다")
    func keyLiteralLivesOnlyInRepositoryImplementation() throws {
        #expect(try Self.files(containing: Self.keyLiteral) == ["Sources/MokaCore/Storage.swift"])
    }

    @Test("FR-08 R-412: 키 상수는 할 일 저장소 두 구현과 키를 거부하는 설정 저장소 두 구현만 쓴다")
    func keyConstantUsedOnlyAtBoundary() throws {
        #expect(
            try Self.files(containing: Self.keyConstant) == [
                "Sources/MokaCore/Storage.swift", "Sources/MokaStore/GRDBTaskRepository.swift",
                "Sources/MokaCore/QuantumSettings.swift", "Sources/MokaStore/GRDBSettingsStore.swift",
            ])
    }
}
