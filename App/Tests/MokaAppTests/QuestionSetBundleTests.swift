import MokaCore
import XCTest

/// 호스트 없는 앱 시험 번들에서도 MokaCore 리소스 번들을 찾는지 본다(spec 003 plan 위험 8).
final class QuestionSetBundleTests: XCTestCase {
    func testBundledQuestionsLoadInAppTestBundle() throws {
        XCTAssertEqual(try QuestionSet.bundled().version, "v1")
    }
}
