import Foundation
import XCTest

/// ADR-0013: 앱 시험은 가짜 URLProtocol 세션(`FakeDecisionURLProtocol.makeSession()`)으로만 판단 공급자를 부른다.
/// 시험 소스에 실제 세션으로 가는 길이 없는지 글자로 읽어 본다. 이 파일도 검사 대상이라 찾을 글자는 이어 붙여 만든다.
final class AppTestSessionBoundaryTests: XCTestCase {
    func test_ADR0013_testSourcesUseOnlyFakeSession() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 1, "시험 소스를 찾지 못하면 검사가 빈 통과가 된다")
        let forbidden = [
            "live" + "Session", "URLSession" + ".shared", "URLSession" + "(configuration:", "URLSession" + ".init(",
        ]
        let providerSession = "HTTPDecisionProvider" + ".makeSession("
        var providerSessionSites: [(file: String, before: Substring)] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for word in forbidden where source.contains(word) {
                XCTFail("\(file.lastPathComponent)에 \(word)가 있다. 시험 세션은 FakeDecisionURLProtocol.makeSession()으로만 만든다")
            }
            for range in source.ranges(of: providerSession) {
                providerSessionSites.append((file.lastPathComponent, source[..<range.lowerBound].suffix(300)))
            }
        }
        // 공급자 세션 공장은 가짜 도우미 안 한 곳에서만 부른다.
        XCTAssertEqual(providerSessionSites.map(\.file), ["HTTPDecisionProviderTests.swift"])
        let fakeHelper =
            "static func makeSession() -> URLSession {\n"
            + "        let configuration = URLSessionConfiguration.ephemeral"
        XCTAssertTrue(providerSessionSites.first?.before.contains(fakeHelper) == true)
    }
}
