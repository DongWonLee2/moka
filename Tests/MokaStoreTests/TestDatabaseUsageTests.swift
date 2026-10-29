import Foundation
import Testing

/// 금지 호출 문자열을 이 파일에 그대로 두면 검사가 자기 자신을 잡으므로 이어 붙여 만든다.
private let forbiddenCalls = [
    "MokaDatabase" + ".open(",
    "DatabaseQueue" + "(path:",
    "DatabasePool" + "(path:",
]

private let allowedFile = "Support/TestDatabase.swift"

@Test("ADR-0004: MokaStore 시험은 TestDatabase 도우미 밖에서 DB를 직접 열지 않는다")
func storeTestsOpenDatabaseOnlyThroughTestDatabase() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().standardizedFileURL
    let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"

    var scanned: [String] = []
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let path = url.standardizedFileURL.path
        let relative = path.hasPrefix(rootPrefix) ? String(path.dropFirst(rootPrefix.count)) : path
        scanned.append(relative)
        if relative == allowedFile { continue }

        let text = try String(contentsOf: url, encoding: .utf8)
        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            for call in forbiddenCalls where line.contains(call) {
                Issue.record("\(relative):\(index + 1): \(call) 직접 호출. TestDatabase 도우미로 연다(ADR-0004)")
            }
        }
    }

    // 경로가 어긋나 아무 파일도 읽지 않고 통과하는 거짓 PASS를 막는다.
    #expect(scanned.contains(allowedFile))
    #expect(scanned.contains("TestDatabaseUsageTests.swift"))
}
