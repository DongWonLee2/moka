import Foundation

/// 스케줄러 메모리(spec 005 data-model §8). `NotchSession`의 칸이고 저장하지 않는다. 앱 재시작에 비워진다.
public struct SchedulerMemory: Equatable, Sendable {
    /// 매끄러운 가중 순환의 몫 상태. 창에 든 할 일만 둔다.
    public var credits: [TaskID: Int]
    /// 최근 고른 할 일(최대 `Defaults.consecutiveCap`개).
    public var recentPicks: [TaskID]
    /// `credits`·`recentPicks`를 채운 하루.
    public var memoryDay: LocalDay?
    /// 지금 노치 할 일을 띄운 규칙. 버튼 로그 줄의 `scheduler_choice`다(§16).
    public var pickedBy: SchedulerChoice?
    /// 커서(`NotchSession.previousTaskID`)를 남긴 하루. 하루가 바뀐 뒤 첫 고르기는 어제 커서를 빼지 않는다.
    public var cursorDay: LocalDay?

    public init(
        credits: [TaskID: Int] = [:], recentPicks: [TaskID] = [], memoryDay: LocalDay? = nil,
        pickedBy: SchedulerChoice? = nil, cursorDay: LocalDay? = nil
    ) {
        self.credits = credits
        self.recentPicks = recentPicks
        self.memoryDay = memoryDay
        self.pickedBy = pickedBy
        self.cursorDay = cursorDay
    }

    public static let empty = SchedulerMemory()

    /// `today`에 고르기 전 상태. 하루가 바뀌었으면 몫 상태와 최근 고르기를 비운다. `today`가 nil이면 그대로다.
    public func on(_ today: LocalDay?) -> SchedulerMemory {
        guard let today, memoryDay != today else { return self }
        return SchedulerMemory(memoryDay: today, pickedBy: pickedBy, cursorDay: cursorDay)
    }
}
