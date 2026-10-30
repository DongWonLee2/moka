# Data Model: 저장과 체크포인트 (spec 002)

이름은 `GLOSSARY.md`를 따른다. 저장 이름(표·열·값)은 GLOSSARY의 굵은 영어 이름이고, 화면 말은 한국어다. Swift 타입 이름은 아래 §1 예외만 빼고 같은 영어를 쓴다. 정확한 메서드 시그니처와 `RejectReason` 같은 내부 경우 이름은 구현 PR에서 정하고 PR "가정"에 적는다.

## 1. 이름 예외

| 개념 | Swift 이름 | 이유 |
|---|---|---|
| task | `MokaTask` | Swift 동시성의 `Task`와 겹친다 |
| context | `MokaContext` | SwiftUI `NSViewRepresentable.Context`와 앱 코드에서 겹친다 |
| `switch` 값 | `` case `switch` `` | Swift 예약어라 백틱으로 쓴다. `rawValue`는 `"switch"` |

## 2. 값 타입 (MokaCore)

```swift
public typealias TaskID = Int64
public typealias ContextID = Int64

public enum TaskStatus: String, CaseIterable, Sendable { case todo, active, done, dropped }
public enum Recurrence: String, CaseIterable, Sendable { case none, daily, weekly }

/// 1(일)~7(토). Foundation `Calendar.component(.weekday, from:)`와 같은 번호.
public struct Weekday: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init?(rawValue: Int)          // 1...7 밖이면 nil
}

/// 지역 날짜 `YYYY-MM-DD`(그레고리력, 시간대 없음). 마감, 컨텍스트 날짜, 주기 날짜에 쓴다.
public struct LocalDay: Comparable, Hashable, Sendable {
    public let year: Int, month: Int, day: Int
    public init?(text: String)           // 형식·달력 날짜가 틀리면 nil
    public var text: String
    public func adding(days: Int, calendar: Calendar) -> LocalDay
    public func weekday(calendar: Calendar) -> Weekday
}

/// 하루 시작 시각 `HH:MM`(24시간, 두 자리). 00:00~23:59.
public struct DayStart: Equatable, Sendable {
    public let hour: Int, minute: Int
    public init?(text: String)
    public var text: String
}

public struct MokaTask: Equatable, Sendable {
    public var id: TaskID
    public var title: String             // 앞뒤 공백 제거 뒤 비어 있지 않음(R-101)
    public var deadline: LocalDay?
    public var estMin: Int?              // 1 이상
    public var recurrence: Recurrence
    public var weekday: Weekday?         // recurrence == .weekly일 때만 값
    public var cycleDay: LocalDay?       // recurrence != .none일 때만 값(§5.3)
    public var firstAction: String?      // 비어 있지 않거나 nil(R-109)
    public var status: TaskStatus
    public var skipCount: Int            // 0 이상
    public var streak: Int               // 0 이상, 반복 할 일만 움직임
    public var createdAt: Date
}

/// 새 할 일 입력. 검증을 통과해야 만들어진다. `cycleDay`는 저장 직전에 §5.3 규칙으로 채운다.
public struct NewTask: Equatable, Sendable {
    public var title: String
    public var deadline: LocalDay?
    public var estMin: Int?
    public var recurrence: Recurrence
    public var weekday: Weekday?         // .weekly인데 nil이면 등록 순간이 속한 하루의 요일(R-101)
}

public enum ContextImpact: String, CaseIterable, Sendable { case normal, high, critical }   // 보통/큼/치명적

public struct MokaContext: Equatable, Sendable {
    public var id: ContextID
    public var name: String              // 앞뒤 공백 제거 뒤 비어 있지 않음
    public var date: LocalDay
    public var impact: ContextImpact
}

public enum CheckpointTrigger: String, CaseIterable, Sendable {
    case quantum, `switch`, skip, urgent, pause, quit, sleep
    case dayEnd = "day_end"
}

/// 두 줄 입력. 앞뒤 공백을 뺀 값이고 건너뛰면 빈 문자열.
public struct CheckpointNotes: Equatable, Sendable {
    public var doneNote: String
    public var nextNote: String
    public static let empty: CheckpointNotes
}

public struct Checkpoint: Equatable, Sendable {
    public var id: Int64
    public var taskID: TaskID
    public var notes: CheckpointNotes
    public var trigger: CheckpointTrigger
    public var elapsedMin: Int           // 0...작업 시간
    public var createdAt: Date
}

public enum UserAction: String, CaseIterable, Sendable { case done, skip, `switch` }
public enum SchedulerChoice: String, CaseIterable, Sendable { case oldestUnpickedV0 = "oldest_unpicked_v0" }

/// 판단 칸. 이번 단계에서는 늘 nil(R-112). 공급자가 있을 때만 존재하고, 나머지는 폴백 줄에서 비어도 된다(F5).
public struct Judgment: Equatable, Sendable {
    public var provider: String
    public var questionVersion: String?
    public var probsJSON: String?
    public var stateHash: String?
}

public struct DecisionLogEntry: Equatable, Sendable {
    public var id: Int64
    public var taskID: TaskID
    public var judgment: Judgment?
    public var modelSnapshot: String?    // judgment가 nil이면 nil
    public var schedulerChoice: SchedulerChoice
    public var userAction: UserAction
    public var createdAt: Date
}
```

`NewCheckpoint`, `NewDecisionLogEntry`, `NewContext`는 `id`가 없는 같은 모양이다.

## 3. 저장 프로토콜과 구현

```swift
public enum StoreError: Error, Equatable, Sendable {
    case unknownValue(column: String, value: String)   // 열거형에 없는 값을 읽음(P3)
    case invalidValue(column: String)                   // 형식이 틀린 날짜·시각 등
    case taskNotFound(TaskID)
    case contextNotFound(ContextID)
}

/// 버튼 한 번의 쓰기 묶음. 저장소가 한 트랜잭션으로 적용한다. 하나라도 실패하면 아무것도 남지 않는다.
public struct StoreBatch: Equatable, Sendable {
    public var updatedTasks: [MokaTask]               // id 기준으로 통째로 덮어씀(id, created_at은 바꾸지 않음)
    public var newCheckpoints: [NewCheckpoint]
    public var newDecisions: [NewDecisionLogEntry]
    public static let empty: StoreBatch
}

public protocol TaskRepository: AnyObject {
    func tasks() throws -> [MokaTask]                 // 버림 포함, id 오름차순
    func insertTask(_ task: NewTask, cycleDay: LocalDay?, at: Date) throws -> MokaTask
    func latestCheckpoint(taskID: TaskID) throws -> Checkpoint?
    func checkpoints() throws -> [Checkpoint]         // id 오름차순
    func decisions() throws -> [DecisionLogEntry]     // id 오름차순
    func apply(_ batch: StoreBatch) throws
}

public protocol ContextStore: AnyObject {
    func contexts() throws -> [MokaContext]           // date 오름차순, 같으면 id
    func insertContext(_ context: NewContext) throws -> MokaContext
    func deleteContext(id: ContextID) throws          // 실제 DELETE(R4)
}

/// API 키 보관(P8). 값 읽기는 없다(마일스톤 3에서 더함).
public protocol KeyStore: AnyObject {
    func save(_ key: String) throws                   // 앞뒤 공백을 뺀 값. 비면 저장하지 않음
    func hasKey() throws -> Bool
    func delete() throws
}
```

| 프로토콜 | MokaCore(메모리, 시험·`moka-sim`) | MokaStore(GRDB) | 앱 타깃 |
|---|---|---|---|
| `SettingsStore`(기존) | `InMemorySettingsStore` | `GRDBSettingsStore` | — |
| `TaskRepository` | `InMemoryTaskRepository` | `GRDBTaskRepository` | — |
| `ContextStore` | `InMemoryContextStore` | `GRDBContextStore` | — |
| `KeyStore` | `InMemoryKeyStore`(가짜) | 없음 | `KeychainKeyStore`(service `dev.dongwon.moka`, account `openrouter`) |

- 메모리 구현은 GRDB 구현과 같은 규칙을 지킨다: id는 1부터 차례로, 없는 할 일을 가리키는 체크포인트·로그는 `taskNotFound`, `apply` 도중 실패하면 되돌림.
- `decisions_log`·`checkpoints`에는 덧붙이기만 있다. 수정·삭제 메서드를 만들지 않는다.
- 저장소는 로그를 남기지 않는다(spec 001 research R7).
- 공용 계약 시험(`MokaStoreTests`, `@Test(arguments:)`로 두 구현): 왕복, id 순서, 버림 포함 목록, `apply` 원자성, 외래 키·RESTRICT(GRDB만, 메모리는 같은 오류 종류), 모르는 `user_action`·`scheduler_choice` 읽기 실패(GRDB는 원시 SQL로 넣음), 공급자 없이 다른 판단 칸이나 `model_snapshot`이 있는 줄 거부, 공급자만 있는 폴백 줄(`provider = 'fallback'`, 나머지 NULL) 허용, 반복인데 `cycle_day` NULL인 할 일 거부(GRDB는 원시 SQL).

## 4. 상태 전이

### 4.1 할 일 상태

| 사건 | 조건 | `status` | 그 밖의 변화 | 체크포인트(계기) | 로그(`user_action`) |
|---|---|---|---|---|---|
| 만듦(노치 빠른 입력, 설정 창) | 제목 검증 통과 | → `todo` | 반복이면 `cycle_day` = 지금 주기(§5.3) | — | — |
| 시작 | 노치 초안 | `todo` → `active` | — | — | — |
| 다시 시작 | 시간 끝 | `active` 유지 | — | `quantum`(두 줄) | — |
| 완료 | 도는 중 | `active` → `done` | 반복이면 `streak` + 1 | — | `done` |
| 완료 | 시간 끝 | `active` → `done` | 같음 | `quantum`(두 줄) | `done` |
| 미루기 | 도는 중 | `active` → `todo` | `skip_count` + 1 | `skip`(두 줄) | `skip` |
| 미루기 | 시간 끝 | `active` → `todo` | `skip_count` + 1 | `quantum`(두 줄) | `skip` |
| 바꿔줘 | 도는 중 | `active` → `todo` | — | `switch`(두 줄) | `switch` |
| 바꿔줘 | 시간 끝 | `active` → `todo` | — | `quantum`(두 줄) | `switch` |
| 시간 끝 | `running` → `expired` | `active` 유지 | — | — | — |
| 잠자기 | 도는 중 | 유지 | 타이머 그대로 | `sleep`(빈 두 줄) | — |
| 종료 | 도는 중 | 유지(`active`) | — | `quit`(빈 두 줄) | — |
| 재시작(앱 시작) | `active`가 남음 | `active` → `todo` | — | — | — |
| 지움(설정 창) | 버림 아님 | → `dropped` | 노치의 할 일이면 타이머를 멈추고 다시 고름 | — | — |
| 고침(설정 창) | 버림 아님 | 유지 | 반복·요일을 바꾸면 `cycle_day` = 지금 주기 | — | — |
| 하루 판정 | §5.3 | `todo`·`done` → `todo` | §5.3 | — | — |

- 체크포인트의 다음 할 일 줄이 비어 있지 않으면 같은 쓰기에서 `first_action`을 그 줄로 바꾼다. 비어 있으면 이전 값을 둔다(R-109, spec Edge Cases).
- 시간 끝 화면의 어떤 버튼이든(완료, 미루기, 바꿔줘, 다시 시작) 그때 두 줄을 계기 `quantum`으로 저장한다. 비어도 저장한다(R-107).
- 완료·미루기·바꿔줘의 쓰기(할 일 갱신, 체크포인트, 로그 한 줄)는 `StoreBatch` 하나다. 버튼 한 번 = 로그 한 줄(SC-102).
- `done`·`dropped`는 끝 상태다. 반복 할 일의 `done`만 하루 판정이 `todo`로 되돌린다.
- 진행 중인 반복 할 일은 하루 판정에서 건너뛴다. 그 할 일을 완료·미루기·바꿔줘로 끝낼 때 그 할 일만 먼저 판정하고(§5.3), 그 뒤에 버튼 규칙을 적용한다.

### 4.2 노치 세션 `NotchSession` (MokaCore, 메모리)

```swift
public struct NotchSession: Equatable, Sendable {
    public var timer: NotchTimer          // spec 001 값 타입 그대로
    public var taskID: TaskID?            // 초안·도는 중·시간 끝이 가리키는 할 일
    public var previousTaskID: TaskID?    // 바꿔줘·미루기 직후 고르기에서 뺄 할 일(R-104). 저장하지 않음
}
```

앱(`AppState`)과 `moka-sim`이 같은 함수를 부른다. 함수는 새 세션과 `StoreBatch`를 돌려주고, 호출자가 `apply`한 뒤 세션을 바꾼다.

| 세션 상태 \ 동작 | 고르기(§5.1) | 빠른 입력 | 시작 | 완료 | 미루기·바꿔줘 | 다시 시작 | 잠자기·종료 | 지움(노치의 할 일) |
|---|---|---|---|---|---|---|---|---|
| `empty(nil)` | 후보 있으면 `empty(draft)` + `taskID` | 할 일 만듦 → `empty(draft)` | 거부 | 거부 | 거부 | 거부 | 기록 없음 | — |
| `empty(draft)` | 그대로 | 거부 | `running`, 할 일 `active` | 거부 | 거부 | 거부 | 기록 없음 | `empty(nil)` → 고르기 |
| `running` | 그대로 | 거부 | 거부 | `empty(nil)` → 고르기 | `empty(nil)`, `previousTaskID` = 그 할 일 → 고르기 | 거부 | 체크포인트(`sleep`/`quit`) | `empty(nil)` → 고르기 |
| `expired` | 그대로 | 거부 | 거부 | `empty(nil)` → 고르기 | 같음 | `running` | 기록 없음 | `empty(nil)` → 고르기 |

- 초안의 칩은 그 순간의 `default_quantum_min`이다. 할 일별 마지막 칩(PRD `quantum_min`)은 범위 밖이다.
- 완료 뒤 `previousTaskID`는 nil이다. 고르기는 빈 상태(초안 없음)가 될 때만 돈다: 버튼 뒤, 재시작 뒤, 노치의 할 일을 지운 뒤, 빈 상태에서 할 일을 만들었을 때, 빈 상태에서 하루 판정이 돈 뒤.
- 타이머 전이는 spec 001 `NotchTimer.apply`를 그대로 쓴다. 완료·미루기·바꿔줘는 모두 타이머에 `.complete`를 보낸다. 다시 시작은 시간 끝의 `.start`다.

## 5. 규칙 (MokaCore 순수 함수)

### 5.1 노치 고르기 `OldestUnpickedRule` (R-104)

```swift
public enum OldestUnpickedRule {
    public static let choice = SchedulerChoice.oldestUnpickedV0
    public static func pick(from tasks: [MokaTask], excluding previous: TaskID?) -> MokaTask?
}
```

1. 후보 = `status == .todo`인 할 일. `active`·`done`·`dropped`는 뺀다.
2. 후보가 둘 이상이고 `previous`가 후보에 있으면 그것을 뺀다. 후보가 하나뿐이면 빼지 않는다.
3. 남은 후보 가운데 `id`가 가장 작은 것. 없으면 nil(빈 상태).

`id` 오름차순이 만든 순서다(research R13). 시험: 버림 제외, 후보 하나일 때 같은 할 일, `previous`가 후보에 없을 때 무시.

### 5.2 재시작 복구 `LaunchRecovery` (R-111)

`revert(_ tasks: [MokaTask]) -> [MokaTask]`: `active`인 할 일을 모두 `todo`로 바꾼 목록(바뀐 것만). 앱 시작마다 한 번, 하루 판정보다 먼저 돈다. 정상 종료와 비정상 종료를 구분하지 않는다.

### 5.3 반복 리셋 `RecurrenceReset` (R-113)

```swift
public enum RecurrenceReset {
    /// 지금 주기의 첫 하루. 반복 없음이면 nil.
    public static func cycleStart(for task: MokaTask, today: LocalDay, calendar: Calendar) -> LocalDay?
    /// 바뀐 할 일만 돌려준다.
    public static func reset(_ tasks: [MokaTask], now: Date, dayStart: DayStart, calendar: Calendar) -> [MokaTask]
}
```

- `today = DayBoundary.day(containing: now, dayStart:, calendar:)`.
- 지금 주기 첫 하루 `c`: 매일은 `today`. 매주는 `today − ((today의 요일 − weekday + 7) % 7)`일.
- 바로 앞 주기 첫 하루 `p`: 매일은 `c − 1일`, 매주는 `c − 7일`.
- 대상: `recurrence != .none`, `status ∈ {todo, done}`, `cycleDay < c`. `active`·`dropped`는 건드리지 않는다.
- 바꾸는 값:

| 지금 값 | `status` | `skip_count` | `streak` | `cycle_day` |
|---|---|---|---|---|
| `status == done` 그리고 `cycleDay == p` | `todo` | 0 | 그대로(완료 때 이미 + 1) | `c` |
| 그 밖(`todo`, 또는 더 오래전 `done`) | `todo` | 0 | 0 | `c` |

- 멱등: 결과의 `cycle_day`가 `c`이므로 같은 `today`로 다시 돌리면 대상이 없다. 시험은 두 번 돌린 결과 == 한 번 돌린 결과, 할 일 수가 그대로(SC-104), 두 시간대.
- 하루 시작 시각을 바꿔 `today`가 앞 날로 돌아가도 `cycleDay < c`가 아니므로 되돌리지 않는다.
- 새로 만들 때, 반복을 새로 걸 때, 요일을 바꿀 때 `cycle_day = c`(그 순간 기준). 반복을 없애면 nil.
- `weekday`가 없는 매주, `cycle_day`가 없는 반복은 값 검증에서 막고 DB CHECK도 막는다(F2).

### 5.4 하루 경계 `DayBoundary` (R-114)

```swift
public enum DayBoundary {
    public static func day(containing instant: Date, dayStart: DayStart, calendar: Calendar) -> LocalDay
    public static func start(of day: LocalDay, dayStart: DayStart, calendar: Calendar) -> Date
}
```

- `d` = `instant`의 지역 달력 날짜(`calendar.timeZone`). `b` = `start(of: d)` = `d`의 `dayStart` 시·분, `matchingPolicy: .nextTime`, `repeatedTimePolicy: .first`.
- `instant ≥ b`면 `d`, 아니면 `d − 1일`.
- 앱은 `Calendar(identifier: .gregorian)` + 시스템 시간대([ADR-0010](../../adr/ADR-0010-day-boundary-calendar.md)), 시험은 그레고리력 + `Asia/Seoul`·`America/New_York` 고정, `moka-sim`은 그레고리력 + 시나리오 `timezone`(research R9).
- 시험 경계값: 05:59:59 → 어제, 06:00:00 → 오늘. `America/New_York` 3월·11월 전환일. 하루 시작 02:30 같은 전환 구간 값.

### 5.5 경과 분과 첫 행동 표시

- `Checkpoint.elapsedMinutes(startedAt:now:quantumMin:) -> Int` = `floor((now − startedAt) / 60)`를 `0...quantumMin`으로 자름. `now`는 체크포인트를 저장하는 순간이다(버튼을 누른 순간이 아니라 두 줄을 저장·건너뛴 순간, 종료·잠자기는 알림을 받은 순간, F6). 시간 끝에서는 `quantumMin`이다.
- `FirstActionDisplay.showsInCollapsed(pickedAt:now:) -> Bool` = `0 ≤ now − pickedAt < 2초`. 접힌 화면은 고른 뒤 2초만, 펼친 화면은 첫 행동이 있으면 늘 보인다(R-109).

### 5.6 값 검증

| 값 | 규칙 | 틀리면 |
|---|---|---|
| 제목, 컨텍스트 이름 | 앞뒤 공백 제거 뒤 비어 있지 않음 | 저장 안 함 |
| `est_min` | nil 또는 1 이상 정수 | 저장 안 함 |
| `weekday` | `.weekly`면 1~7, 아니면 nil | 저장 안 함 |
| 두 줄 | 앞뒤 공백 제거. 비면 `""` | — |
| 마감, 컨텍스트 날짜 | `LocalDay`(날짜 고르기로만 받음) | 저장 안 함 |

## 6. 설정 키

`settings(key, value)` 표는 그대로다. 행은 처음 쓸 때 생긴다(seed 없음). 읽기 규칙은 MokaCore(`AppSettings`), 초기값은 `Defaults.swift`.

| key | value 형식 | 읽기 규칙 | 쓰는 곳 |
|---|---|---|---|
| `default_quantum_min` | 10진 정수 | 기존(없거나 1~180 밖이면 25) | 설정, 온보딩 3단계 |
| `default_extend_min` | 10진 정수 | 없거나 1~180 밖이면 10. 저장만 하고 동작은 마일스톤 3 | 설정, 온보딩 3단계 |
| `day_start` | `HH:MM`(24시간, 두 자리) | 없거나 형식이 틀리면 `06:00` | 설정, 온보딩 3단계 |
| `onboarding_done` | `true` | 값이 `true`가 아니면 온보딩을 보임 | 온보딩 끝내기에서만 |

- 쓰기는 형식을 지킨 값만 받고, 틀리면 이전 값을 둔다(spec 001 R-012와 같다).
- `day_start`를 바꾸면 다음 판정부터 새 시각을 쓴다.
- 온보딩 끝내기(`Onboarding.finish`): 컨텍스트가 있으면 저장 → 세 설정 쓰기 → 마지막에 `onboarding_done = true`. 중간에 실패하면 `onboarding_done`을 쓰지 않아 다음 실행에 다시 보인다. 키는 1단계 "다음"에서 `KeyStore.save`로만 저장하고 settings에는 아무것도 쓰지 않는다.

## 7. v2 마이그레이션 (MokaStore)

이름 `v2_tasks_contexts_checkpoints_log`. `v1_settings` 뒤에 등록한다. 문장 넷을 각각 `db.execute(sql:)`로 실행한다(한 줄 문자열, `sqlite_master`에 그대로 남는다).

```sql
CREATE TABLE tasks(id INTEGER PRIMARY KEY NOT NULL, title TEXT NOT NULL, deadline TEXT, est_min INTEGER, recurrence TEXT NOT NULL CHECK(recurrence IN ('none', 'daily', 'weekly')), weekday INTEGER CHECK(weekday BETWEEN 1 AND 7), cycle_day TEXT, first_action TEXT, status TEXT NOT NULL CHECK(status IN ('todo', 'active', 'done', 'dropped')), skip_count INTEGER NOT NULL, streak INTEGER NOT NULL, created_at TEXT NOT NULL, CHECK((recurrence = 'weekly') = (weekday IS NOT NULL)), CHECK((recurrence = 'none') = (cycle_day IS NULL)))
CREATE TABLE contexts(id INTEGER PRIMARY KEY NOT NULL, name TEXT NOT NULL, date TEXT NOT NULL, impact TEXT NOT NULL CHECK(impact IN ('normal', 'high', 'critical')))
CREATE TABLE checkpoints(id INTEGER PRIMARY KEY NOT NULL, task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE RESTRICT, done_note TEXT NOT NULL, next_note TEXT NOT NULL, trigger TEXT NOT NULL CHECK(trigger IN ('quantum', 'switch', 'skip', 'urgent', 'pause', 'quit', 'sleep', 'day_end')), elapsed_min INTEGER NOT NULL, created_at TEXT NOT NULL)
CREATE TABLE decisions_log(id INTEGER PRIMARY KEY NOT NULL, task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE RESTRICT, question_version TEXT, provider TEXT, probs_json TEXT, state_hash TEXT, model_snapshot TEXT, scheduler_choice TEXT NOT NULL, user_action TEXT NOT NULL, created_at TEXT NOT NULL, CHECK(provider IS NOT NULL OR (question_version IS NULL AND probs_json IS NULL AND state_hash IS NULL)), CHECK(model_snapshot IS NULL OR provider IS NOT NULL))
```

| 표 | 열 | 형식·규칙 |
|---|---|---|
| `tasks` | `deadline` | `YYYY-MM-DD` 또는 NULL |
| | `cycle_day` | `YYYY-MM-DD`. 반복 없음이면 NULL, 반복이면 값(CHECK, F2) |
| | `created_at` | UTC `YYYY-MM-DDTHH:MM:SSZ` |
| | `first_action` | NULL 또는 비어 있지 않은 문자열 |
| `contexts` | `date` | `YYYY-MM-DD` |
| `checkpoints` | `done_note`, `next_note` | 건너뛰면 `''` |
| | `elapsed_min` | 0 이상 정수(§5.5) |
| `decisions_log` | 판단 칸 넷, `model_snapshot` | 이번 단계는 모두 NULL. 공급자가 없으면 나머지도 NULL, 공급자만 있는 줄은 허용(F5). 원문 텍스트 금지 |
| | `scheduler_choice` | `oldest_unpicked_v0`(MokaCore 열거형 `rawValue`만) |
| | `user_action` | `done` / `skip` / `switch`(MokaCore 열거형 `rawValue`만) |

- CHECK가 있는 칸: `tasks.recurrence`, `tasks.status`, `tasks.weekday`(범위와 매주 짝), `tasks.cycle_day`(반복 짝, F2), `contexts.impact`, `checkpoints.trigger`, `decisions_log`의 공급자 기준 판단 칸(F5)과 `model_snapshot`. 그 밖의 형식은 MokaCore가 지킨다(P3 (c)).
- 기본값(`DEFAULT`)을 두지 않는다. 저장소가 모든 열을 쓴다.
- 외래 키는 GRDB가 연결마다 켠다(GRDB `Configuration.foreignKeysEnabled` 기본값 true, 미확인 → 공용 계약 시험의 RESTRICT 시험으로 확인).
- 색인은 두지 않는다(할 일 수십 건).
- 이름 시험 리터럴: `["v1_settings", "v2_tasks_contexts_checkpoints_log"]`(ADR-0007).

스키마 스냅샷 `schema/moka-schema.sql`(spec 001 data-model §4의 질의·형식, 이름순):

```
CREATE TABLE checkpoints(…위 문장 그대로…);
CREATE TABLE contexts(…);
CREATE TABLE decisions_log(…);
CREATE TABLE settings(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
CREATE TABLE tasks(…);
```

파일은 시험이 출력한 텍스트를 사람이 옮긴다(ADR-0004). 스냅샷 변경은 PR "사람이 볼 결정"에 올린다.

## 8. 화면 상태 추가 (앱 `AppState`, 저장 안 함)

| 값 | 의미 |
|---|---|
| `session` | `NotchSession`(spec 001의 `timer`를 감쌈) |
| `pickedAt` | 노치가 지금 할 일을 고른 시각. 첫 행동 접힘 표시 2초에 씀 |
| `pendingAction` | 미루기·바꿔줘를 눌러 두 줄 입력 중이면 그 동작, 아니면 nil |
| `notesDraft` | 두 줄 입력 칸의 글자(시간 끝 화면 포함) |
| `showsOnboarding` | `onboarding_done`이 `true`가 아니면 참 |

- 미루기·바꿔줘를 누르면 `pendingAction`을 켜고 두 줄 칸을 보인다. 저장 또는 건너뛰기에서 `StoreBatch`를 적용한다. 그동안 타이머는 그대로 돈다. 입력 중 시간이 끝나면 시간 끝 화면으로 바뀌고, 그때 누르는 버튼은 시간 끝 규칙(계기 `quantum`)을 따른다.
- 두 줄 칸은 각 한 줄이다. 노치에 보일 때는 끝을 "…"로 줄인다(spec Edge Cases).
- 포커스 규칙은 spec 001 data-model §6 그대로다. 두 줄 칸은 펼친 판을 클릭한 뒤에만 키 입력을 받는다.
