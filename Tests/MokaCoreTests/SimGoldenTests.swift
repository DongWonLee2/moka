import Foundation
import MokaCore
import Testing

let simFixturesURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/sim", isDirectory: true)

func goldenScenarioNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: simFixturesURL.path)
        .filter { $0.hasSuffix(".json") }
        .map { String($0.dropLast(".json".count)) }
        .sorted()
}

@Test("ADR-0003 R-015: errors/ 밖 시나리오마다 기대 출력 파일이 있다")
func everyGoldenScenarioHasExpectedOutput() throws {
    let names = try goldenScenarioNames()
    #expect(
        Set([
            "contract-example", "default-after-expiry", "us1-basic", "us2-choose-45", "us3-sleep", "us4-default-change",
            "us4-picked-chip",
        ])
        .isSubset(of: Set(names)))
    for name in names {
        let expected = simFixturesURL.appendingPathComponent("\(name).expected.jsonl")
        #expect(FileManager.default.fileExists(atPath: expected.path), "\(name).expected.jsonl 없음")
    }
}

@Test("ADR-0003 R-015: 시나리오 출력이 기대 출력과 바이트 단위로 같다", arguments: try goldenScenarioNames())
func goldenOutputMatchesBytes(name: String) throws {
    let input = try Data(contentsOf: simFixturesURL.appendingPathComponent("\(name).json"))
    let expectedURL = simFixturesURL.appendingPathComponent("\(name).expected.jsonl")
    let expected = try #require(FileManager.default.contents(atPath: expectedURL.path))
    let result = SimRunner.run(input)
    guard case .success(let output) = result else {
        Issue.record("\(name): 오류 \(result)")
        return
    }
    #expect(Data(output.utf8) == expected)
    #expect(SimExitCode.code(for: result) == 0)
}
