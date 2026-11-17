import Foundation
import Testing

/// #72: 앱은 켤 때 복구·하루 판정·버튼 뒤 커밋을 `SessionAssembly`로만 부른다. 앱 시험은 macOS에서만 돌므로 필수
/// `core-test`에서 `AppState.swift` 소스를 읽어 확인한다. 이월 판정은 spec 005 단위 3 전까지 앱에 걸지 않는다. 주석 줄은 보지 않는다.
struct AssemblyBoundaryTests {
    private static let appStateURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MokaCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // 저장소 루트
        .appending(path: "App/Sources/AppState.swift", directoryHint: .notDirectory)

    @Test("#72: AppState는 LaunchRecovery·RecurrenceReset·SessionCommit·CarryJudgment를 직접 부르지 않는다")
    func appStateUsesSessionAssemblyOnly() throws {
        let lines = try String(contentsOf: Self.appStateURL, encoding: .utf8).components(separatedBy: "\n")
        let banned = ["LaunchRecovery.revert", "RecurrenceReset.reset", "SessionCommit.commit", "CarryJudgment"]

        var offending: [String] = []
        var usesAssembly = false
        for (index, line) in lines.enumerated() {
            let code = line.trimmingCharacters(in: .whitespaces)
            if code.hasPrefix("//") || code.hasPrefix("*") || code.hasPrefix("/*") { continue }
            let beforeComment = code.components(separatedBy: "//").first ?? code
            if beforeComment.contains("SessionAssembly.") { usesAssembly = true }
            for name in banned where beforeComment.contains(name) {
                offending.append("AppState.swift:\(index + 1) \(name)")
            }
        }
        #expect(usesAssembly, "AppState가 SessionAssembly를 부르지 않는다: \(Self.appStateURL.path)")
        #expect(offending.isEmpty, "AppState가 조립 순서를 직접 적는다: \(offending)")
    }
}
