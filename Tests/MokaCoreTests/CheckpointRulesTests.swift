import Foundation
import MokaCore
import Testing

// data-model §5.5.

private let start = Fake.noon

@Suite struct ElapsedMinutesTests {
    @Test(
        "FR-07 R-108: 경과 분은 지난 초를 60으로 나눠 버리고 0...작업 시간으로 자른다",
        arguments: [
            (0.0, 25, 0), (59.999, 25, 0), (60.0, 25, 1), (12 * 60 + 59.9, 25, 12), (25 * 60.0, 25, 25),
            (40 * 60.0, 25, 25), (3 * 3600.0, 180, 180),
        ])
    func floorsAndClamps(seconds: Double, quantumMin: Int, expected: Int) {
        let now = start.addingTimeInterval(seconds)
        #expect(Checkpoint.elapsedMinutes(startedAt: start, now: now, quantumMin: quantumMin) == expected)
    }

    @Test("FR-07 R-108: 시계를 되돌려 now가 시작보다 앞이면 0", arguments: [-0.5, -60.0, -3600.0])
    func clockBackwardsIsZero(seconds: Double) {
        let now = start.addingTimeInterval(seconds)
        #expect(Checkpoint.elapsedMinutes(startedAt: start, now: now, quantumMin: 25) == 0)
    }
}

@Suite struct FirstActionDisplayTests {
    @Test(
        "FR-07 R-109: 접힌 화면의 이어서 할 일은 고른 뒤 0초 이상 2초 미만만 보인다",
        arguments: [(0.0, true), (1.999, true), (2.0, false), (5.0, false), (-0.001, false), (-3.0, false)])
    func showsForTwoSeconds(seconds: Double, shows: Bool) {
        let now = start.addingTimeInterval(seconds)
        #expect(FirstActionDisplay.showsInCollapsed(pickedAt: start, now: now) == shows)
    }
}
