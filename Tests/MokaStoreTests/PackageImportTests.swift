import Foundation
import Testing

/// 툴체인 설정(`--explicit-target-dependency-import-check`)이 전이 의존 import를 잡지 못해 소스로 확인한다(#17, #50).
/// 테스트 타깃 파일의 `import X`마다 `Package.swift`의 그 타깃 의존 선언에 X가 있어야 한다.

/// 의존 선언 없이 import할 수 있는 툴체인 모듈.
private let toolchainModules: Set<String> = ["Foundation", "Testing", "XCTest", "Dispatch", "os", "Observation"]

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

/// `Package.swift`의 `.testTarget(name:dependencies:)`마다 타깃 이름 → 의존 모듈 이름.
/// `.product(name: "GRDB", package: "GRDB.swift")`는 `GRDB`로 센다.
private func declaredTestTargets(in manifest: String) throws -> [String: Set<String>] {
    let target = try Regex(#"\.testTarget\(\s*name:\s*"([^"]+)"\s*,\s*dependencies:\s*\[([^\]]*)\]"#)
    let packageArgument = try Regex(#"package:\s*"[^"]*""#)
    let quoted = try Regex(#""([^"]+)""#)

    var result: [String: Set<String>] = [:]
    for match in manifest.matches(of: target) {
        guard let name = match.output[1].substring, let list = match.output[2].substring else { continue }
        let names = String(list).replacing(packageArgument, with: "").matches(of: quoted).compactMap {
            $0.output[1].substring.map(String.init)
        }
        result[String(name)] = Set(names)
    }
    return result
}

private func importedModules(in source: String) throws -> [(line: Int, module: String)] {
    let kinds = "struct|class|enum|protocol|func|var|let|typealias"
    let importLine = try Regex(#"^\s*(?:@\w+\s+)*import\s+(?:(?:"# + kinds + #")\s+)?(\w+)"#)
    return source.components(separatedBy: .newlines).enumerated().compactMap { index, line in
        guard let match = line.firstMatch(of: importLine), let module = match.output[1].substring else { return nil }
        return (index + 1, String(module))
    }
}

@Test("#50: 테스트 타깃 파일의 import는 Package.swift의 그 타깃 의존 선언에 있다")
func testImportsAreDeclaredDependencies() throws {
    let manifest = try String(contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
    let targets = try declaredTestTargets(in: manifest)
    let testsDir = packageRoot.appendingPathComponent("Tests", isDirectory: true)
    let folders = try FileManager.default.contentsOfDirectory(atPath: testsDir.path).filter { !$0.hasPrefix(".") }

    // 파싱이 어긋나 아무것도 보지 않고 통과하는 거짓 PASS를 막는다.
    #expect(Set(folders) == Set(targets.keys))
    #expect(targets.values.allSatisfy { !$0.isEmpty })

    for folder in folders {
        let declared = (targets[folder] ?? []).union(toolchainModules)
        let root = testsDir.appendingPathComponent(folder, isDirectory: true)
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            scanned += 1
            for (line, module) in try importedModules(in: String(contentsOf: url, encoding: .utf8))
            where !declared.contains(module) {
                Issue.record("\(folder)/\(url.lastPathComponent):\(line): import \(module)이 \(folder) 의존 선언에 없다")
            }
        }
        #expect(scanned > 0, "\(folder)에서 Swift 파일을 찾지 못했다")
    }
}

@Test("#66: 속성이 붙은 import(@preconcurrency, @_exported, @testable)와 종류 import도 모듈 이름을 꺼낸다")
func importedModulesSeeAttributedImports() throws {
    // 이 파일도 검사 대상이라 줄 머리에 import를 두지 않고 글자로 만든다.
    let keyword = "import"
    let source = [
        "@preconcurrency \(keyword) FakeA",
        "@_exported \(keyword) FakeB",
        "  @testable \(keyword) FakeC",
        "\(keyword) struct FakeD.Thing",
        "@preconcurrency @testable \(keyword) FakeE",
        "@_spi(Fake) \(keyword) FakeF",
        "// \(keyword) FakeIgnored",
    ].joined(separator: "\n")
    #expect(try importedModules(in: source).map(\.module) == ["FakeA", "FakeB", "FakeC", "FakeD", "FakeE", "FakeF"])
}

@Test("#66: 의존 선언 없이 import할 수 있는 SDK 모듈에 os·Observation이 있다")
func toolchainModulesIncludeSDKModules() {
    #expect(toolchainModules.isSuperset(of: ["os", "Observation"]))
}
