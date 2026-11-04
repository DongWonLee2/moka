import Foundation
import Testing

/// ADR-0009 보완(2026-11-04): 스냅샷 번들에 `AppState.swift`가 들어가 컴파일만으로는 "뷰는 `AppState`를 모른다"를
/// 지킬 수 없다. 필수 `core-test`에서 뷰 소스를 읽어 대신 확인한다. 주석 줄은 보지 않는다.
struct ViewBoundaryTests {
    private static let viewsURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MokaCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // 저장소 루트
        .appending(path: "App/Sources/Views", directoryHint: .isDirectory)

    @Test("ADR-0009: App/Sources/Views의 코드는 AppState를 참조하지 않는다")
    func viewsDoNotReferenceAppState() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.viewsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty, "뷰 폴더를 찾지 못했다: \(Self.viewsURL.path)")

        var offending: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") || code.hasPrefix("*") || code.hasPrefix("/*") { continue }
                let beforeComment = code.components(separatedBy: "//").first ?? code
                if beforeComment.contains("AppState") {
                    offending.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        #expect(offending.isEmpty, "뷰가 AppState를 참조한다: \(offending)")
    }
}
