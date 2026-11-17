import Foundation

/// 설정 창 할 일 탭 "내일" 표시(spec 005 R-423, data-model §18). 표시만 하고 고르기는 바꾸지 않는다.
public enum TomorrowMark {
    /// `order`(노치 후보 순서)대로 다 하는 데 걸릴 시간(없으면 기본 작업 시간)을 쌓아, 합이 `remainingMinutes`를 넘는
    /// 할 일부터 끝까지. 진행 중 할 일은 쌓지 않는다. 상한이 없으면(`remainingMinutes == nil`) 빈 집합.
    public static func ids(order: [MokaTask], remainingMinutes: Int?, defaultQuantumMin: Int) -> Set<TaskID> {
        guard let remainingMinutes else { return [] }
        var total = 0
        var marked: Set<TaskID> = []
        for task in order where task.status != .active {
            total += task.estMin ?? defaultQuantumMin
            if total > remainingMinutes { marked.insert(task.id) }
        }
        return marked
    }
}
