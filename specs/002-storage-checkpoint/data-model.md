# Data Model: 저장과 체크포인트 (spec 002)

이 문서가 규칙의 원본이다. spec은 범위·요구, research는 결정 근거·대안, tasks는 이 문서의 절 번호를 가리킨다. 이름은 `GLOSSARY.md`를 따른다. 저장 이름(표·열·값)은 GLOSSARY의 굵은 영어 이름이고, 화면 말은 한국어다. Swift 타입 이름은 아래 §1 예외만 빼고 같은 영어를 쓴다. 이 문서에 없는 작은 이름(내부 오류 경우 등)은 구현 PR에서 정하고 PR "가정"에 적는다.

## 1. 이름 예외

| 개념 | Swift 이름 | 이유 |
|---|---|---|
| task | `MokaTask` | Swift 동시성의 `Task`와 겹친다 |
| context | `MokaContext` | SwiftUI `NSViewRepresentable.Context`와 앱 코드에서 겹친다 |
| `switch` 값 | `` case `switch` `` | Swift 예약어라 백틱으로 쓴다. `rawValue`는 `"switch"` |
| 설정 키 읽기 규칙 | `CoreSettings` | 앱 타깃에 이미 `enum AppSettings`(`App/Sources/MokaApp.swift:81`, DB 열기)가 있어 겹치지 않게 한다 |

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
    public var title: String             // 앞뒤 공백을 뺀 값, 비어 있지 않음(R-101)
    public var deadline: LocalDay?
    public var estMin: Int?              // 1 이상
    public var recurrence: Recurrence
    public var weekday: Weekday?         // recurrence == .weekly일 때만 값
    public var cycleDay: LocalDay?       // recurrence != .none일 때만 값(§5.3)
    public var firstAction: String?      // 비어 있지 않거나 nil(R-109)
    public var status: TaskStatus
    public var skipCount: Int            // 0 이상
    public var streak: Int               // 0 이상, 반복 할 일만 움직임
    public var createdAt: Date           // 초 단위로 내린 값(§3)
}

/// 새 할 일 입력. 저장 전에 §5.8 `TaskWriteRules.prepareNew`를 거친다.
public struct NewTask: Equatable, Sendable {
    public var title: String
    public var deadline: LocalDay?
    public var estMin: Int?
    public var recurrence: Recurrence
    public var weekday: Weekday?         // .weekly인데 nil이면 prepareNew가 채운다(§5.8)
}

/// 설정 창 고침 입력. nil인 칸은 그대로 둔다. 마감·예상 소요를 비우려면 `.clear`.
public struct TaskEdit: Equatable, Sendable {
    public enum Field<Value: Equatable & Sendable>: Equatable, Sendable { case keep, set(Value), clear }
    public var title: String?
    public var deadline: Field<LocalDay>
    public var estMin: Field<Int>
    public var recurrence: Recurrence?
    public var weekday: Weekday?
}

public enum ContextImpact: String, CaseIterable, Sendable { case normal, high, critical }   // 화면 이름 "중요도": 조금/꽤/아주

public struct MokaContext: Equatable, Sendable {
    public var id: ContextID
    public var name: String              // 앞뒤 공백을 뺀 값, 비어 있지 않음
    public var date: LocalDay
    public var impact: ContextImpact
}

public enum CheckpointTrigger: String, CaseIterable, Sendable {
    case quantum, `switch`, skip, urgent, pause, quit, sleep
    case dayEnd = "day_end"
}

/// 두 줄 입력. 앞뒤 공백을 뺀 값이고 안 적기·빈 칸이면 빈 문자열.
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
public enum SchedulerChoice: String, CaseIterable, Sendable { case rotateByIDV0 = "rotate_by_id_v0" }

/// 두 줄 입력 중인 동작. `NotchStatus.label(for:pending:)`(기존 함수에 기본값 nil인 매개변수를 더함)의 입력이고 §8 `pendingAction`의 타입이다. 저장하지 않는다.
public enum PendingAction: Sendable { case skip, `switch` }

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

### 2.1 시각·날짜 문자열 `UTCTimestamp` (MokaCore, 공개)

```swift
public enum UTCTimestamp {
    public static func format(_ date: Date) -> String          // "YYYY-MM-DDTHH:MM:SSZ", 초 아래는 버림
    public static func parse(_ text: String) -> Date?          // 위 형식만, 틀리면 nil
    public static func floorToSecond(_ date: Date) -> Date
}
```

- 기존 `Sources/MokaCore/Sim/SimScenario.swift`의 `SimTimestamp.formatUTC`와 그레고리력 계산(`daysInMonth`, `daysFromCivil`, `civilFromDays`, 지금 `private`)을 MokaCore 안의 내부 `enum GregorianCivil`로 옮겨 `SimTimestamp`, `UTCTimestamp`, `LocalDay(text:)`가 함께 쓴다. `SimTimestamp.parse`(오프셋 있는 입력)는 그대로 둔다. 기존 golden 출력은 바뀌지 않아야 한다.
- MokaStore는 `UTCTimestamp`와 `LocalDay.text`·`LocalDay(text:)`만 부른다. `ISO8601DateFormatter`와 GRDB `Date` 기본 형식은 쓰지 않는다(research R13).

### 2.2 달력 만들기 `GregorianCalendar` (MokaCore, ADR-0010)

```swift
public enum GregorianCalendar {
    public static func make(timeZone: TimeZone) -> Calendar   // Calendar(identifier: .gregorian) + 받은 시간대
}
```

- 앱은 시간대만 넘긴다. `.autoupdatingCurrent`를 한 번 넘겨 둘지, 판정마다 `TimeZone.current`로 새로 만들지는 ADR-0010 결정 검증 시험으로 정하고 ADR-0010에 덧붙인다(tasks). MokaCore는 `TimeZone.current`를 읽지 않는다.
- 시험은 `make(timeZone: Asia/Seoul)`·`America/New_York`. `moka-sim`은 시나리오 `timezone`.

## 3. 저장 프로토콜과 구현

```swift
public enum StoreError: Error, Equatable, Sendable {
    case unknownValue(column: String, value: String)   // 열거형에 없는 값을 읽음(P3)
    case invalidValue(column: String)                   // 형식이 틀린 날짜·시각 등
    case taskNotFound(TaskID)
    case contextNotFound(ContextID)
}

/// 버튼 한 번(또는 설정 창 고침·지움 한 번)의 쓰기 묶음. 저장소가 한 트랜잭션으로 적용한다. 하나라도 실패하면 아무것도 남지 않는다.
public struct StoreBatch: Equatable, Sendable {
    public var updatedTasks: [MokaTask]               // id 기준으로 통째로 덮어씀(id, created_at은 바꾸지 않음)
    public var newCheckpoints: [NewCheckpoint]
    public var newDecisions: [NewDecisionLogEntry]
    public static let empty: StoreBatch
}

public protocol TaskRepository: AnyObject {
    func tasks() throws -> [MokaTask]                 // 버림 포함, id 오름차순
    func insertTask(_ task: NewTask, cycleDay: LocalDay?, at: Date) throws -> MokaTask
    func checkpoints() throws -> [Checkpoint]         // id 오름차순
    func decisions() throws -> [DecisionLogEntry]     // id 오름차순
    func apply(_ batch: StoreBatch) throws
}

public protocol ContextStore: AnyObject {
    func contexts() throws -> [MokaContext]           // date 오름차순, 같으면 id
    func insertContext(_ context: NewContext) throws -> MokaContext
    func deleteContext(id: ContextID) throws          // 실제 DELETE(research R4)
}
```

| 프로토콜 | MokaCore(메모리, 시험·`moka-sim`) | MokaStore(GRDB) |
|---|---|---|
| `SettingsStore`(기존) | `InMemorySettingsStore` | `GRDBSettingsStore` |
| `TaskRepository` | `InMemoryTaskRepository` | `GRDBTaskRepository` |
| `ContextStore` | `InMemoryContextStore` | `GRDBContextStore` |

- API 키 보관(`KeyStore`, Keychain)은 마일스톤 3으로 미뤘다(research R8, 사용자 결정 2026-10-30). 이번 단계에는 키 코드가 없다.
- 메모리 구현은 GRDB 구현과 같은 규칙을 지킨다: id는 1부터 차례로, 없는 할 일을 가리키는 체크포인트·로그는 `taskNotFound`, `apply` 도중 실패하면 되돌림.
- 시각: 두 구현 모두 `insertTask`의 `at`과 새 체크포인트·로그의 `createdAt`을 `UTCTimestamp.floorToSecond`로 내린 값으로 저장하고 돌려준다. 그래서 메모리와 GRDB가 같은 값을 돌려준다.
- `decisions_log`·`checkpoints`에는 덧붙이기만 있다. 수정·삭제 메서드를 만들지 않는다.
- 저장소는 로그를 남기지 않는다(spec 001 research R7).
- 공용 계약 시험(`MokaStoreTests`):
  - 인자는 Sendable한 구현 선택 `enum StoreKind: CaseIterable, Sendable { case memory, grdb }`이고, 시험 안에서 새 저장소를 만든다(`@Test(arguments: StoreKind.allCases)`). 가변 클래스 저장소를 인자로 넘기지 않는다(`@unchecked Sendable` 금지).
  - GRDB 쪽은 기존 `TestDatabase.migratedInMemory()`(`Tests/MokaStoreTests/Support/TestDatabase.swift`)로 연다. `DatabaseQueue(`·`MokaDatabase.inMemory(`를 시험에서 직접 부르지 않는다(기존 `TestDatabaseUsageTests` 가드).
  - 항목: 왕복(모든 열), id 순서, 버림 포함 목록, `apply` 원자성, 외래 키·RESTRICT(GRDB만, 메모리는 같은 오류 종류), 모르는 `user_action`·`scheduler_choice` 읽기 실패(GRDB는 원시 SQL로 넣음), 공급자 없이 다른 판단 칸이나 `model_snapshot`이 있는 줄 거부, 공급자만 있는 폴백 줄(`provider = 'fallback'`, 나머지 NULL) 허용, 반복인데 `cycle_day` NULL인 할 일 거부(GRDB는 원시 SQL).
  - 초 아래 값이 든 `Date`로 `insertTask`와 체크포인트·로그를 넣고 읽으면 두 구현이 같은 값(초 단위로 내린 값)을 돌려준다.
  - `StoreBatch` 셋 이상을 차례로 `apply`한 뒤 `tasks()`·`checkpoints()`·`decisions()`의 id 순서와 값이 두 구현에서 같다.

## 4. 상태 전이

### 4.1 할 일 상태

| 사건 | 조건 | `status` | 그 밖의 변화 | 체크포인트(계기) | 로그(`user_action`) |
|---|---|---|---|---|---|
| 만듦(노치 빠른 입력, 설정 창) | 제목 검증 통과 | → `todo` | §5.8 `prepareNew` | — | — |
| 시작 | 노치 초안 | `todo` → `active` | — | — | — |
| 다시 시작 | 시간 끝 | `active` 유지 | — | `quantum`(두 줄) | — |
| 완료 | 도는 중 | `active` → `done` | 반복이면 `streak` + 1 | — | `done` |
| 완료 | 시간 끝 | `active` → `done` | 같음 | `quantum`(두 줄) | `done` |
| 미루기(등록·안 적기) | 도는 중 | `active` → `todo` | `skip_count` + 1 | `skip`(두 줄) | `skip` |
| 미루기 | 시간 끝 | `active` → `todo` | `skip_count` + 1 | `quantum`(두 줄) | `skip` |
| 바꾸기(등록·안 적기) | 도는 중 | `active` → `todo` | — | `switch`(두 줄) | `switch` |
| 바꾸기 | 시간 끝 | `active` → `todo` | — | `quantum`(두 줄) | `switch` |
| 시간 끝 | `running` → `expired` | `active` 유지 | — | — | — |
| 잠자기 | 도는 중 | 유지 | 타이머 그대로 | `sleep`(빈 두 줄) | — |
| 종료 | 도는 중 | 유지(`active`) | — | `quit`(빈 두 줄) | — |
| 재시작(앱 시작) | `active`가 남음 | `active` → `todo` | — | — | — |
| 지움(설정 창) | 버림 아님 | → `dropped` | 노치의 할 일이면 §4.2 지움 | — | — |
| 고침(설정 창) | 버림 아님 | 유지 | §5.8 `applyEdit` | — | — |
| 하루 판정 | §5.3 | `todo`·`done` → `todo` | §5.3 | — | — |

- 시간 끝(`running` → `expired`)은 아무것도 기록하지 않는다. 계기 `quantum` 체크포인트는 시간 끝 화면에서 버튼(완료, 미루기, 바꾸기, 다시 시작)을 누를 때만 생기고, 그때 두 줄을 저장한다. 비어도 저장한다(R-107). 이 문장이 원본이다.
- 체크포인트의 다음 할 일 줄이 비어 있지 않으면 같은 쓰기에서 `first_action`을 그 줄로 바꾼다. 비어 있으면 이전 값을 둔다(R-109).
- 완료·미루기·바꾸기의 쓰기(할 일 갱신, 체크포인트, 로그 한 줄)는 `StoreBatch` 하나다. 로그 한 줄은 완료 한 번, 또는 미루기·바꾸기의 등록·안 적기 한 번에 생긴다(SC-102). 돌아가기는 앱 화면 상태(§8)만 되돌리고 세션 함수를 부르지 않는다.
- `done`·`dropped`는 끝 상태다. 반복 할 일의 `done`만 하루 판정이 `todo`로 되돌린다.
- 진행 중(`active`)인 반복 할 일은 하루 판정이 건드리지 않는다(§5.3). 하루 시작 시각을 넘겨 끝내도 따로 판정하지 않고 위 표의 버튼 규칙만 적용한다. 그래서 그 주기(예: 어제) 몫 완료로 세고, 다음 활성화의 하루 판정이 오늘 몫을 대기로 되돌린다(research R10, 사용자 결정 2026-10-30). 예: 매일 반복, 05:50 D−1에 시작(`cycle_day` = D−1) → 06:10 D에 완료(`done`, `streak` + 1) → 다음 활성화에 `c` = D, `cycleDay == p`라 `todo`, `streak` 유지.
- 설정 창 지움·고침의 쓰기도 `StoreBatch`(할 일 갱신만)로 적용한다. 로그·체크포인트는 남기지 않는다(research R4).

### 4.2 노치 세션 `NotchSession` (MokaCore, 메모리)

```swift
public struct NotchSession: Equatable, Sendable {
    public var timer: NotchTimer          // spec 001 값 타입. 타입과 기존 golden은 바꾸지 않는다
    public var taskID: TaskID?            // 초안·도는 중·시간 끝이 가리키는 할 일
    public var previousTaskID: TaskID?    // 고르기 커서(§5.1). 저장하지 않음
    public var run: RunInfo?              // running·expired 동안만 값. 저장하지 않음
}

/// 시작한 순간의 값. 시간 끝(`expired`)이 되면 spec 001 타이머는 작업 시간을 버리므로 세션이 따로 든다.
public struct RunInfo: Equatable, Sendable {
    public var startedAt: Date
    public var quantumMin: Int
}

/// 동작마다 넣는 입력. 호출자(앱 `AppState`, `moka-sim`)가 채운다.
public struct SessionInput: Sendable {
    public var tasks: [MokaTask]          // 저장소의 지금 목록(`tasks()`)
    public var now: Date
    public var defaultQuantumMin: Int
    public var calendar: Calendar         // GregorianCalendar.make(timeZone:)
}

/// 쓰기가 있는 동작의 결과. 호출자가 `batch`를 `apply`하고 성공한 뒤에만 `session`으로 바꾼다.
public struct SessionStep: Equatable, Sendable {
    public var session: NotchSession
    public var batch: StoreBatch
}

extension NotchSession {
    public static let initial: NotchSession                                     // empty(nil), 나머지 nil
    public func picked(_ input: SessionInput) -> NotchSession                    // 고르기. empty(nil)일 때만 바뀜
    public func addedTask(_ task: MokaTask, _ input: SessionInput) -> NotchSession   // 빠른 입력 둘째 단계
    public func nextDraft(_ input: SessionInput) -> NotchSession                 // "다른 할 일"(초안만)
    public func edited(_ task: MokaTask) -> NotchSession                         // 노치의 할 일을 고쳤을 때 제목 사본만 교체
    public func start(_ input: SessionInput) throws(SessionError) -> SessionStep
    public func complete(_ notes: CheckpointNotes?, _ input: SessionInput) throws(SessionError) -> SessionStep
    public func skip(_ notes: CheckpointNotes, _ input: SessionInput) throws(SessionError) -> SessionStep
    public func switchTask(_ notes: CheckpointNotes, _ input: SessionInput) throws(SessionError) -> SessionStep
    public func restart(_ notes: CheckpointNotes, quantumMin: Int, _ input: SessionInput) throws(SessionError) -> SessionStep
    public func lifecycleCheckpoint(_ trigger: CheckpointTrigger, _ input: SessionInput) -> StoreBatch?   // .sleep / .quit. running일 때만
    public func taskDropped(_ id: TaskID) -> NotchSession                       // 노치의 할 일이면 empty(nil), run nil
    public func nextMark(_ input: SessionInput) -> TaskID?                       // 할 일 탭 "다음" 표시(아래)
}

/// 쓰기가 있는 동작을 저장소에 적용한다. 앱과 `moka-sim`이 같이 쓴다.
public enum SessionCommit {
    /// `apply`가 성공하면 `step.session`을 돌려주고, throw하면 같은 오류를 다시 던진다. 호출자는 그때 세션을 그대로 둔다(R-119).
    public static func commit(_ step: SessionStep, to repository: any TaskRepository) throws -> NotchSession
}

public enum SessionError: Error, Equatable, Sendable { case notAllowed }    // 아래 표의 "거부"
```

빠른 입력과 설정 창 추가는 두 단계다: (1) `TaskWriteRules.prepareNew`(§5.8)로 검증·채움 → 호출자가 `insertTask` → (2) 돌려받은 `MokaTask`로 `addedTask`. 새 id는 저장소만 정한다.

| 세션 상태 \ 동작 | 고르기 | 빠른 입력 | 다른 할 일 | 시작 | 완료 | 미루기·바꾸기 | 다시 시작 | 잠자기·종료 | 지움(노치의 할 일) | 고침(노치의 할 일) |
|---|---|---|---|---|---|---|---|---|---|---|
| `empty(nil)` | 후보 있으면 `empty(draft)` + `taskID` | 할 일 만듦 → 그 할 일로 초안 | 거부 | 거부 | 거부 | 거부 | 거부 | 기록 없음 | — | — |
| `empty(draft)` | 그대로 | 할 일 만듦 → 그 할 일로 초안(칩 유지) | 커서 = 지금 초안 → 다음 후보로 초안(칩 유지) | `running`, 할 일 `active`, `run` 채움 | 거부 | 거부 | 거부 | 기록 없음 | `empty(nil)` → 고르기 | 초안 제목 교체 |
| `running` | 그대로 | 거부 | 거부 | 거부 | `empty(nil)`, `run` nil → 고르기 | `empty(nil)`, `run` nil, 커서 = 그 할 일 → 고르기 | 거부 | 체크포인트(`sleep`/`quit`) | `empty(nil)`, `run` nil → 고르기 | 제목 교체, 시간 값 그대로 |
| `expired` | 그대로 | 거부 | 거부 | 거부 | 같음 | 같음 | `running`, `run` = (지금, 고른 칩) | 기록 없음 | 같음 | 같음 |

- 초안의 칩은 그 순간의 `default_quantum_min`이다. 할 일별 마지막 칩(PRD `quantum_min`)은 범위 밖이다.
- 타이머 전이는 spec 001 `NotchTimer.apply`를 그대로 쓴다. 초안을 만들거나 제목을 바꿀 때는 `.enterTitle(title)`(빈 상태·초안에서 받음, `Sources/MokaCore/NotchTimer.swift:52`), 시작·다시 시작은 `.start`, 완료·미루기·바꾸기는 `.complete`. 도는 중·시간 끝의 제목 교체는 같은 경우 값을 제목만 바꿔 다시 만든다(`.running(title:quantumMin:startedAt:endsAt:)`, `.expired(title:chipMin:chipPicked:)`). `NotchTimer`에 새 경우나 이벤트를 더하지 않는다.
- 화면에 보이는 제목의 원본은 `MokaTask.title`이다. 타이머 안 제목은 표시용 사본이고, 설정 창에서 노치의 할 일을 고치면 `edited`가 사본을 맞춘다.
- 경과 분: 도는 중 버튼·잠자기·종료는 `run.startedAt`부터 `input.now`까지(§5.5), 시간 끝 버튼은 `run.quantumMin`이다. `expired`의 `chipMin`은 다시 시작용 칩이라 경과 분에 쓰지 않는다. 시험: 칩 45분으로 시작해 기본값 25분인 채 시간 끝 → `elapsed_min` 45.
- 버튼 뒤 고르기: 호출자는 `batch`를 적용한 뒤 저장소 `tasks()`를 다시 읽어 `picked`를 부른다. 고르기는 빈 상태(초안 없음)일 때만 돈다: 버튼 뒤, 재시작 뒤, 노치의 할 일을 지운 뒤, 빈 상태에서 할 일을 만들었을 때, 빈 상태에서 하루 판정이 돈 뒤.
- 로그 줄의 `schedulerChoice`는 `RotateByIDRule.choice`, `judgment`·`modelSnapshot`은 nil(R-112).

커서(`previousTaskID`) 수명:

| 사건 | 커서 |
|---|---|
| 처음(`initial`), 재시작(`relaunch`, 앱 시작) | nil |
| 완료 | nil |
| 미루기·바꾸기(등록·안 적기) | 그 할 일 |
| 다른 할 일(초안) | 그때의 초안 할 일 |
| 시작, 다시 시작, 돌아가기, 빠른 입력, 고침, 잠자기 | 그대로 |
| 노치의 할 일을 지움 | 그대로(지운 할 일 id여도 §5.1 비교는 그대로 됨) |
| 활성화(하루 판정) | 그대로 |

할 일 탭 "다음" 표시(R-102, `nextMark`): 타이머가 초안이면 `session.taskID`, 도는 중·시간 끝이면 지금 할 일을 끝냈을 때 뜰 할 일 = `RotateByIDRule.pick(from: tasks, after: nil)`(진행 중인 할 일은 후보가 아니다), 빈 상태면 없음. 보기·정렬(§5.7)과 무관하다.

## 5. 규칙 (MokaCore 순수 함수)

### 5.1 노치 고르기 `RotateByIDRule` (R-104)

```swift
public enum RotateByIDRule {
    public static let choice = SchedulerChoice.rotateByIDV0
    public static func pick(from tasks: [MokaTask], after previous: TaskID?) -> MokaTask?
}
```

1. 후보 = `status == .todo`인 할 일. `active`·`done`·`dropped`는 뺀다.
2. `previous`가 nil이면 후보 가운데 `id`가 가장 작은 것.
3. `previous`가 있으면 `id > previous`인 후보 가운데 `id`가 가장 작은 것. 그런 후보가 없으면 후보 가운데 `id`가 가장 작은 것(처음으로 돌아감).
4. 후보가 없으면 nil(빈 상태).

`id` 오름차순이 만든 순서다(research R13). 후보가 하나뿐이면 `previous`가 그 할 일이어도 다시 그것이 뽑힌다. 시험: 버림 제외, 후보 하나일 때 같은 할 일, 대기 할 일 넷에서 바꾸기를 이어 누르면 1 → 2 → 3 → 4 → 1, `previous`가 버린 할 일 id여도 그다음 큰 id, `previous`가 nil이면 가장 작은 id.

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
- 대상: `recurrence != .none`이고 `status`가 `todo` 또는 `done`이며 `cycleDay < c`인 할 일. `active`·`dropped`는 건드리지 않는다.
- 바꾸는 값:

| 지금 값 | `status` | `skip_count` | `streak` | `cycle_day` |
|---|---|---|---|---|
| `status == done` 그리고 `cycleDay == p` | `todo` | 0 | 그대로(완료 때 이미 + 1) | `c` |
| 그 밖(`todo`, 또는 더 오래전 `done`) | `todo` | 0 | 0 | `c` |

- 멱등: 결과의 `cycle_day`가 `c`이므로 같은 `today`로 다시 돌리면 대상이 없다. 시험은 두 번 돌린 결과 == 한 번 돌린 결과, 할 일 수가 그대로(SC-104), 두 시간대.
- 하루 시작 시각을 바꿔 `today`가 앞 하루로 돌아가도 `cycleDay < c`가 아니므로 되돌리지 않는다.
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
- 달력은 §2.2([ADR-0010](../../adr/ADR-0010-day-boundary-calendar.md)).
- 시험 경계값: 05:59:59 → 어제, 06:00:00 → 오늘. `America/New_York` 3월·11월 전환일. 하루 시작 02:30 같은 전환 구간 값.
- 단조성 시험: 같은 `dayStart`·`calendar`에서 `t1 ≤ t2`이면 `day(containing: t1) ≤ day(containing: t2)`(전환일 앞뒤 시각 묶음으로 확인).

### 5.5 경과 분과 첫 행동 표시

- `Checkpoint.elapsedMinutes(startedAt:now:quantumMin:) -> Int` = `floor((now − startedAt) / 60)`를 `0...quantumMin`으로 자름. `now`는 체크포인트를 저장하는 순간이다(버튼을 누른 순간이 아니라 두 줄을 등록·안 적기 한 순간, 종료·잠자기는 알림을 받은 순간, F6). 시간 끝 버튼은 `run.quantumMin`(§4.2).
- 끝 시각 기준 타이머라 잠자기에서 깨어난 뒤 남기는 체크포인트의 경과 분에는 잠든 시간이 들어간다(spec 001 R-008 그대로, 튜닝 때 해석에 참고).
- `FirstActionDisplay.showsInCollapsed(pickedAt:now:) -> Bool` = `0 ≤ now − pickedAt < 2초`. 접힌 화면은 고른 뒤 2초만, 펼친 화면은 첫 행동이 있으면 늘 보인다(R-109).

### 5.6 값 검증

| 값 | 규칙 | 틀리면 |
|---|---|---|
| 제목, 컨텍스트 이름 | 앞뒤 공백을 뺀 값을 저장. 비면 안 됨 | 저장 안 함 |
| `est_min` | nil 또는 1 이상 정수 | 저장 안 함 |
| `weekday` | `.weekly`면 1~7, 아니면 nil | 저장 안 함 |
| 두 줄 | 앞뒤 공백 제거. 비면 `""` | — |
| 마감, 컨텍스트 날짜 | `LocalDay`(날짜 고르기로만 받음) | 저장 안 함 |

### 5.7 할 일 목록 보기 `TaskListView` (R-118)

```swift
public enum TaskListScope: Sendable { case all, today, thisWeek }
public enum TaskListOrder: Sendable { case created, deadline }
public enum TaskListView {
    /// 버린(`dropped`) 할 일은 늘 뺀다. `today`는 호출자가 `DayBoundary`(§5.4)로 구해 넘긴다.
    public static func rows(_ tasks: [MokaTask], scope: TaskListScope, order: TaskListOrder, today: LocalDay, calendar: Calendar) -> [MokaTask]
}
```

- `all`: 버리지 않은 모든 할 일.
- `today`: 다음 가운데 하나에 해당하는 할 일 — 마감이 `today` 이하, 또는 `.daily`, 또는 `weekday`가 `today`의 요일과 같은 `.weekly`.
- `thisWeek`: 다음 가운데 하나에 해당하는 할 일 — 마감이 이번 주 토요일 이하(주는 일요일 시작, `weekday` 1=일과 같다), 또는 반복이 있음.
- 마감 없는 일반 할 일은 `all`에만 나온다. 상태(대기·진행 중·완료)로는 거르지 않는다.
- `created`: `id` 오름차순(§5.1과 같은 순서, research R13). `deadline`: 마감 오름차순, 마감 없음은 맨 뒤, 같은 마감이면 `id` 오름차순.
- 시험 경계값(`today: LocalDay` 기준): `today`가 토요일·일요일인 경우, 마감이 이번 주 토요일·다음 주 일요일, 매주 반복의 요일이 `today`와 같음·다름, 지난 마감. 시각 05:59:59/06:00:00 경계는 §5.4 시험이 맡는다.
- 고른 보기·정렬은 앱 `AppState`에만 두고 저장하지 않는다(§8).

### 5.8 할 일 쓰기 규칙 `TaskWriteRules` (R-101, R-113)

```swift
public enum TaskWriteRules {
    /// 검증하고, .weekly인데 weekday가 nil이면 등록 순간이 속한 하루의 요일로 채우고, 반복이면 cycleDay = 지금 주기 첫 하루.
    public static func prepareNew(_ task: NewTask, now: Date, dayStart: DayStart, calendar: Calendar) -> (task: NewTask, cycleDay: LocalDay?)?
    /// 고침 결과. 검증에 실패하면 nil(저장 안 함). dropped는 고칠 수 없다(nil).
    public static func applyEdit(_ task: MokaTask, _ edit: TaskEdit, now: Date, dayStart: DayStart, calendar: Calendar) -> MokaTask?
}
```

- "등록 순간이 속한 하루"는 `DayBoundary.day(containing: now, …)`다. 그래서 하루 시작 06:00이면 새벽 5시에 등록한 매주 할 일의 기본 요일은 전날의 요일이다.
- 고침의 반복·요일 규칙:
  - 반복을 `.weekly`로 바꾸면서 `weekday`가 없으면 그 순간이 속한 하루의 요일로 채운다.
  - 반복을 `.daily`·`.none`으로 바꾸면 `weekday`를 지운다.
  - 반복을 `.none`으로 바꾸면 `cycle_day`를 지운다.
  - 반복 값이나 요일이 실제로 바뀌었을 때만 `cycle_day = c`(그 순간 기준)와 `streak = 0`으로 둔다. 같은 값을 다시 주면 아무것도 바꾸지 않는다. `skip_count`는 그대로다. 그 순간에는 리셋하지 않는다.
  - 상태는 바꾸지 않는다. `done`인 할 일도 제목·마감·예상 소요·반복을 고칠 수 있다.
- 결과는 `StoreBatch(updatedTasks: [결과])`로 적용한다(§4.1).

## 6. 설정 키

`settings(key, value)` 표는 그대로다. 행은 처음 쓸 때 생긴다(seed 없음). 읽기 규칙은 MokaCore `CoreSettings`(§1), 초기값은 `Defaults.swift`.

| key | value 형식 | 읽기 규칙 | 쓰는 곳 |
|---|---|---|---|
| `default_quantum_min` | 10진 정수 | 기존(없거나 1~180 밖이면 25) | 설정 기본 탭, 온보딩 2단계 |
| `default_extend_min` | 10진 정수 | 없거나 1~180 밖이면 10. 저장만 하고 동작은 마일스톤 3 | 설정 기본 탭, 온보딩 2단계 |
| `day_start` | `HH:MM`(24시간, 두 자리) | 없거나 형식이 틀리면 `06:00` | 설정 기본 탭, 온보딩 2단계 |
| `onboarding_done` | `true` | 값이 `true`가 아니면 온보딩을 보임 | 온보딩 끝내기에서만 |

- 쓰기는 형식을 지킨 값만 받고, 틀리면 이전 값을 둔다(spec 001 R-012와 같다).
- `day_start`를 바꾸면 다음 판정부터 새 시각을 쓴다.
- 온보딩 끝내기 `Onboarding.finish(context: NewContext?, quantumMin: Int, extendMin: Int, dayStart: DayStart, settings: SettingsStore, contexts: ContextStore) throws`: 컨텍스트가 있으면 저장 → 세 설정 쓰기 → 마지막에 `onboarding_done = true`. 중간에 실패하면 `onboarding_done`을 쓰지 않아 다음 실행에 다시 보인다. 다시 실행해 컨텍스트가 두 번 저장되는 것은 받아들인다(사람이 일정 탭에서 지운다, 가정).

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
| | `created_at` | UTC `YYYY-MM-DDTHH:MM:SSZ`(`UTCTimestamp.format`) |
| | `first_action` | NULL 또는 비어 있지 않은 문자열 |
| `contexts` | `date` | `YYYY-MM-DD` |
| `checkpoints` | `done_note`, `next_note` | 안 적기·빈 칸이면 `''` |
| | `elapsed_min` | 0 이상 정수(§5.5) |
| `decisions_log` | 판단 칸 넷, `model_snapshot` | 이번 단계는 모두 NULL. 공급자가 없으면 나머지도 NULL, 공급자만 있는 줄은 허용(F5). 원문 텍스트 금지 |
| | `scheduler_choice` | `rotate_by_id_v0`(MokaCore 열거형 `rawValue`만) |
| | `user_action` | `done` / `skip` / `switch`(MokaCore 열거형 `rawValue`만) |

- CHECK가 있는 칸: `tasks.recurrence`, `tasks.status`, `tasks.weekday`(범위와 매주 짝), `tasks.cycle_day`(반복 짝, F2), `contexts.impact`, `checkpoints.trigger`, `decisions_log`의 공급자 기준 판단 칸(F5)과 `model_snapshot`. 그 밖의 형식은 MokaCore가 지킨다(P3 (c)). `trigger`에 이번에 안 쓰는 값까지 넣는 이유는 research R3.
- 기본값(`DEFAULT`)을 두지 않는다. 저장소가 모든 열을 쓴다.
- 외래 키는 GRDB가 연결마다 켠다(GRDB `Configuration.foreignKeysEnabled` 기본값 true, 미확인 → 공용 계약 시험의 RESTRICT 시험으로 확인).
- 색인은 두지 않는다(할 일 수십 건).
- `trigger` 열 이름을 따옴표 없이 쓰는 것은 macOS SQLite 3.54에서만 확인했다. 첫 시험을 리눅스 CI(`swift:6.3.3-noble`의 libsqlite3)에서도 돌린다.
- 이름 시험 리터럴: `["v1_settings", "v2_tasks_contexts_checkpoints_log"]`(ADR-0007).

스키마 스냅샷 `schema/moka-schema.sql`(spec 001 data-model §4의 질의·형식, 이름순):

```
CREATE TABLE checkpoints(…위 문장 그대로…);
CREATE TABLE contexts(…);
CREATE TABLE decisions_log(…);
CREATE TABLE settings(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
CREATE TABLE tasks(…);
```

파일은 시험이 출력한 텍스트를 사람이 옮긴다(ADR-0004). Red 단계에서는 스냅샷 파일을 위 다섯 문장으로 먼저 고쳐 시험이 실패하는지 보고, 마이그레이션을 넣은 뒤 시험 출력과 바이트가 같은지 확인한다. 스냅샷 변경은 PR "사람이 볼 결정"에 올린다.

## 8. 화면 상태 추가 (앱 `AppState`, 저장 안 함)

| 값 | 의미 |
|---|---|
| `session` | `NotchSession`(spec 001의 `timer`를 대신함) |
| `tasks` | 저장소 `tasks()`의 지금 목록. 노치·설정 창 할 일 탭의 단일 출처. 쓰기 뒤 다시 읽음 |
| `pickedAt` | 노치가 지금 할 일을 고른 시각. 첫 행동 접힘 표시 2초에 씀 |
| `pendingAction` | `PendingAction?`(§2). 미루기·바꾸기를 눌러 두 줄 입력 중이면 그 동작 |
| `taskListScope`, `taskListOrder` | 할 일 탭의 보기·정렬(§5.7). 처음 값은 `all`·`created`, 앱을 끄면 사라짐 |
| `notesDraft` | 두 줄 입력 칸의 글자(시간 끝 화면 포함) |
| `showsOnboarding` | `onboarding_done`이 `true`가 아니면 참 |
| `storageUnavailable` | 앱 DB를 열지 못했거나 마이그레이션이 실패하면 참(R-119) |

- 미루기·바꾸기를 누르면 `pendingAction`을 켜고 두 줄 칸을 보인다. 등록 또는 안 적기에서 세션 함수를 부른다(안 적기는 두 줄을 `""`로). 돌아가기(Esc)는 `pendingAction`을 nil로 되돌리고 `notesDraft`를 비우며 아무것도 쓰지 않는다. 그동안 타이머는 그대로 돈다. 화면의 "N분 했어요"는 지금까지의 경과로 계속 바뀌고, 체크포인트에는 등록·안 적기를 누른 순간 값이 남는다(§5.5).
- 두 줄 입력 중 시간이 끝나면 `pendingAction`을 nil로 지우고 시간 끝 화면으로 바뀐다. 적던 `notesDraft`는 이어지고, 그때 누르는 버튼은 시간 끝 규칙(계기 `quantum`)을 따른다.
- 쓰기가 throw하면 세션·`tasks`를 바꾸지 않고 `os.Logger`에 오류 종류만 남긴다(제목·본문 없음).
- 두 줄 칸은 각 한 줄이다. 노치에 보일 때는 끝을 "…"로 줄인다.
- 키 입력 규칙: 포커스 규칙은 spec 001 data-model §6 그대로다. 두 줄 칸은 펼친 판을 클릭한 뒤에만 키 입력을 받는다. 두 줄 화면(바꾸기·미루기)은 첫 칸 Enter·Tab = 둘째 칸, 둘째 칸 Enter = 등록. 시간 끝 화면은 첫 칸 Enter·Tab = 둘째 칸, 둘째 칸 Enter = 아무 동작 없음, 칸 밖 Enter = 완료(spec 001 R-003), 직접 입력 칸이 열려 있는 동안 Enter = 다시 시작(spec 001 R-003 예외) — R-107.
