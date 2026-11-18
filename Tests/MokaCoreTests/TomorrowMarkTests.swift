import Foundation
import MokaCore
import Testing

// spec 005 data-model §18(R-423). 가짜 할 일만 쓴다.

@Suite struct TomorrowMarkTests {
    /// 확정 시안 11번: 가용 시간 2시간, 노치 순서 C 40 → D 60 → E 30 → F(없음, 기본 25).
    private let order = [
        Fake.task(2, estMin: 40), Fake.task(3, estMin: 60), Fake.task(4, estMin: 30), Fake.task(5),
    ]

    @Test("FR-10 R-423 US3-7: 노치 순서로 쌓아 남은 분을 넘는 할 일부터 \"내일\"")
    func mockupExample() {
        #expect(TomorrowMark.ids(order: order, remainingMinutes: 120, defaultQuantumMin: 25) == [4, 5])
    }

    @Test("FR-10 R-423: 합이 남은 분과 같으면 표시하지 않는다")
    func equalIsNotOver() {
        #expect(TomorrowMark.ids(order: order, remainingMinutes: 130, defaultQuantumMin: 25) == [5])
        #expect(TomorrowMark.ids(order: order, remainingMinutes: 155, defaultQuantumMin: 25) == [])
    }

    @Test("FR-10 R-423: 다 하는 데 걸릴 시간이 없으면 기본 작업 시간으로 쌓는다")
    func missingEstimateUsesDefaultQuantum() {
        let unknown = [Fake.task(1), Fake.task(2)]
        #expect(TomorrowMark.ids(order: unknown, remainingMinutes: 50, defaultQuantumMin: 25) == [])
        #expect(TomorrowMark.ids(order: unknown, remainingMinutes: 50, defaultQuantumMin: 30) == [2])
    }

    @Test("FR-10 R-423: 앞 할 일이 넘으면 그 뒤는 짧아도 모두 \"내일\"")
    func everythingAfterFirstOverflow() {
        let tasks = [Fake.task(1, estMin: 90), Fake.task(2, estMin: 5)]
        #expect(TomorrowMark.ids(order: tasks, remainingMinutes: 60, defaultQuantumMin: 25) == [1, 2])
    }

    @Test("FR-10 R-423: 상한이 없으면(기록 없음·\"더 할래요\") 빈 집합")
    func noCap() {
        #expect(TomorrowMark.ids(order: order, remainingMinutes: nil, defaultQuantumMin: 25).isEmpty)
    }

    @Test("FR-10 R-423: 진행 중 할 일은 쌓지 않고 표시하지 않는다(data-model §18 가정)")
    func activeIsSkipped() {
        let tasks = [Fake.task(1, status: .active, estMin: 100), Fake.task(2, estMin: 40)]
        #expect(TomorrowMark.ids(order: tasks, remainingMinutes: 60, defaultQuantumMin: 25).isEmpty)
    }
}
