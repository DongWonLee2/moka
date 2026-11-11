import Foundation
import MokaCore
import Testing

// ADR-0011 승인 항목 2a(B안): 지난 버전 질문 파일 사본은 저장소 루트 `questions-history/<version>.json`이다.

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let bundledURL = repositoryRoot.appendingPathComponent("Sources/MokaCore/Resources/questions.json")
private let historyURL = repositoryRoot.appendingPathComponent("questions-history")

/// v1 사본의 FNV-1a 64. 리눅스 CI에 CryptoKit이 없어 SHA-256 고정은 pytest가 맡는다.
private let v1Fingerprint = "2cafc8ae6880c139"

@Suite struct QuestionsHistoryTests {
    @Test("ADR-0011 R-612: 지금 질문 파일은 questions-history의 같은 버전 사본과 바이트까지 같다")
    func currentMatchesCopy() throws {
        let current = try Data(contentsOf: bundledURL)
        let version = try QuestionSet(json: current).version
        let copy = try Data(contentsOf: historyURL.appendingPathComponent("\(version).json"))
        #expect(copy == current)
    }

    @Test("ADR-0011 R-612: 지난 사본 v1은 고정한 지문 그대로이고 v1으로 읽힌다")
    func v1CopyIsFixed() throws {
        let data = try Data(contentsOf: historyURL.appendingPathComponent("v1.json"))
        #expect(JudgmentState.fnv1a64(Array(data)) == v1Fingerprint)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["version"] as? String == "v1")
        #expect(root["model"] as? String == "jev-1.13.0")
    }
}
