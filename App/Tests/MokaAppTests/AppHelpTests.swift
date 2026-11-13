import MokaCore
import XCTest

/// 도움말 펼침 상태(spec 007 R-706·R-707, data-model §2). 메모리에만 두고 저장하지 않는다.
@MainActor
final class AppHelpTests: XCTestCase {
    func test_R707_helpExpandedInMemory() {
        let settings = WriteCountingSettingsStore()
        let state = makeState(InMemoryTaskRepository(), settings: settings)
        let writesBefore = settings.writes
        XCTAssertEqual(state.helpExpanded, [])

        state.helpExpanded.insert(.reasonLine)
        state.helpExpanded.insert(.firstAction)
        XCTAssertEqual(state.helpExpanded, [.reasonLine, .firstAction])

        state.helpExpanded.remove(.reasonLine)
        XCTAssertEqual(state.helpExpanded, [.firstAction])
        XCTAssertEqual(settings.writes, writesBefore, "설정 저장소에 쓰면 안 된다")
    }
}

/// 쓰기 횟수를 센다.
private final class WriteCountingSettingsStore: SettingsStore {
    private let inner = InMemorySettingsStore()
    private(set) var writes = 0

    func value(for key: String) throws -> String? { try inner.value(for: key) }

    func setValue(_ value: String, for key: String) throws {
        writes += 1
        try inner.setValue(value, for: key)
    }
}
