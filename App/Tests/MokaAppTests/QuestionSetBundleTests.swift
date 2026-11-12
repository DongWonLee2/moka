import MokaCore
import XCTest

final class QuestionSetBundleTests: XCTestCase {
    func test_FR03_R202_bundledQuestionsLoadInAppTestBundle() throws {
        XCTAssertEqual(try QuestionSet.bundled().version, "v3")
    }
}
