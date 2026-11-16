import Foundation
import MokaCore
import XCTest

/// spec 005 단위 1: 앱 노치 순서(T043). 단위 1은 앱 코드를 바꾸지 않고 `NotchSession`의 고르기만 바꾼다.
/// 키 없음(판단 설정 없음), 메모리 저장소, 주입한 시계만 쓴다. 가짜 할 일만 쓴다.
@MainActor
final class AppSchedulerTests: XCTestCase {
    /// 마감 순 A(1)·B(2)·C(3)·D(4).
    private static func seeded() throws -> InMemoryTaskRepository {
        let repository = InMemoryTaskRepository()
        for (index, day) in ["2027-01-20", "2027-01-21", "2027-01-22", "2027-01-23"].enumerated() {
            _ = try repository.insertTask(
                NewTask(
                    title: "가짜 할 일 \(index + 1)", deadline: LocalDay(text: day), estMin: nil, recurrence: .none,
                    weekday: nil),
                cycleDay: nil, at: AppTestFixture.noon)
        }
        return repository
    }

    func test_FR05_R403_R408_switchAndSkipRotateTopThreeByRankShares() throws {
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(try Self.seeded(), clock: clock)
        state.launch()
        var shown: [TaskID] = []
        for index in 0..<20 {
            let current = try XCTUnwrap(state.session.taskID)
            shown.append(current)
            state.start()
            clock.advance(minutes: 1)
            state.beginSetAside(index.isMultiple(of: 2) ? .skip : .switch)
            state.setAsideWithoutNotes()
            XCTAssertNotEqual(state.session.taskID, current, "바꾸기·미루기 바로 뒤에 방금 할 일이 다시 뜨지 않는다")
        }
        let tally = shown.reduce(into: [TaskID: Int]()) { $0[$1, default: 0] += 1 }
        XCTAssertNil(tally[4], "넷째 D는 한 번도 뜨지 않는다")
        XCTAssertEqual(tally[1], 10)
        XCTAssertEqual(tally[2], 6)
        XCTAssertEqual(tally[3], 4)
    }

    func test_FR05_R408_completeHasNothingToExclude() throws {
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(try Self.seeded(), clock: clock)
        state.launch()
        XCTAssertEqual(state.session.taskID, 1)
        state.start()
        clock.advance(minutes: 1)
        state.complete()
        XCTAssertNil(state.session.previousTaskID, "완료 뒤에는 뺄 할 일이 없다")
        XCTAssertEqual(state.session.taskID, 2)
    }
}
