# Data Model: 스케줄러 (spec 005)

규칙, 값, 모양의 원본이다. tasks.md는 절 번호를 가리킨다. 이름은 [GLOSSARY.md](../../GLOSSARY.md)를 따르고, 새 코드 이름은 이 문서가 처음 정한다. "확정할 것 Qn"이 붙은 곳은 plan "확정할 것"의 답에 따라 모양이 달라지고, 답이 나오면 이 문서를 고친다. 기준 `origin/main` `67b526e`.

## §1 할 일(`MokaTask`)에 더하는 값

| 코드 이름 | 열 | 타입 | 처음 값 | 바뀌는 때 |
|---|---|---|---|---|
| `carryCount` | `carry_count` | `Int` (0 이상) | 0 | "오늘 할래요"에 +1(R-415). 반복 할 일은 이월 대상이 아니라 늘 0이다(R-412, R-418 지움) |
| `dueDecision` | `due_decision` | `Bool` | 거짓 | 이월 판정이 참으로(§9), 이월 답 셋과 진행 중 완료가 거짓으로(§10, R-417) |

- `NewTask`와 할 일 폼은 두 값을 받지 않는다. 새 할 일은 늘 0과 거짓이다.
- `TaskWriteRules.applyEdit`(할 일 탭 고치기)는 두 값을 바꾸지 않는다. 할 일 탭에서 마감을 고쳐도 이월 답 대기는 풀리지 않는다(카드에서만 푼다).
- "버릴래요"는 `status = .dropped`(spec 002 R-102 지우기와 같음)이고 `dueDecision = false`다.
- `RecurrenceReset.reset`은 `carryCount`를 건드리지 않는다(반복 할 일은 늘 0이므로 따로 지울 것이 없다).

## §2 스키마 마이그레이션 (승인 항목 1, ADR-0004·ADR-0007)

마이그레이션 이름 `v4_tasks_carry`를 `v3_scores` 뒤에 덧붙인다. 배포한 마이그레이션은 고치지 않는다. `eraseDatabaseOnSchemaChange`는 켜지 않는다.

확정할 것 Q6에 따라 둘 가운데 하나다.

- Q6-A(참·거짓):
  ```sql
  ALTER TABLE tasks ADD COLUMN carry_count INTEGER NOT NULL DEFAULT 0 CHECK(carry_count >= 0)
  ALTER TABLE tasks ADD COLUMN due_decision INTEGER NOT NULL DEFAULT 0 CHECK(due_decision IN (0, 1))
  ```
- Q6-B(표시 시각): `due_decision TEXT`(NULL = 대기 아님, 값 = 표시를 붙인 판정 시각, `UTCTimestamp` 형식). `carry_count`는 A와 같다. `MokaTask.dueDecision`은 `Date?`가 되고 이 문서의 "참"은 "NULL 아님"으로 읽는다.

함께 바꾸는 것:
- `Tests/MokaStoreTests/MigrationTests.swift:9`의 이름 목록 끝에 `"v4_tasks_carry"`를 더한다(ADR-0007).
- `schema/moka-schema.sql`은 메모리 DB에 마이그레이션한 뒤의 `sqlite_master` 글자로 다시 만든다. `ADD COLUMN`은 SQLite가 `CREATE TABLE` 글자 끝에 열 정의를 붙이므로 글자 모양은 구현 PR의 시험 출력 그대로 쓴다. 손으로 고치지 않는다.
- `GRDBTaskRepository`의 읽기·쓰기(`insertTask`, `apply`, 행 읽기)가 두 열을 다룬다. 기존 행은 기본값으로 읽힌다(업그레이드 시험, quickstart 3).
- `tuning/tests/test_schema_contract.py`: tasks 열 집합에 두 열이 있는지, 기본값이 0(Q6-B면 NULL)인지, `carry_count = -1`이 CHECK로 막히는지, `decisions_log`에 `user_action = 'carry_today'`·`scheduler_choice = 'carry_card_v1'` 줄이 들어가는지(값 CHECK가 없으므로 지금도 들어감을 계약으로 고정) 본다.
- `decisions_log`·`checkpoints`·`settings` 표는 바꾸지 않는다. `checkpoints.trigger`는 이미 `day_end`를 받는다.

## §3 priority와 aging (R-402)

`ScoreRules.priority`의 aging 한 줄만 바꾼다.

```
aging = (skipCount + Defaults.carryAgingWeight × carryCount) × (avoiding ≥ 임계값 ? Defaults.avoidingAgingFactor : 1)
```

- `Defaults.carryAgingWeight = 0.5`(새 값). 나머지 가중치(`weightUrgency` 1.0, `weightImpact` 0.7, `weightAging` 0.8)와 urgency 하한(마감이 내일까지면 1)은 그대로다.
- 판단 입력에는 `carryCount`를 넣지 않는다(spec 003 R-201, PRD 6장 금지 필드). 판단 입력 해시도 그대로다. 그래서 `carryCount`가 바뀌어도 다시 묻지 않는다.

## §4 후보와 순서 (R-401, R-413)

- **후보** = `status == .todo` && `!dueDecision`. 오늘 끝(§12)인 동안은 후보 목록을 쓰지 않는다(고르기 자체를 하지 않는다).
- `PriorityOrder.order(...)`가 후보만 늘어놓는다. 순서 규칙(점수 있는 할 일 priority 순, 동점은 `TaskListView.deadlineFirst`, 그 뒤 점수 없는 할 일 마감일 순)은 그대로다.
- 이 순서를 쓰는 곳 셋이 모두 이월 답 대기를 뺀다: 고르기(§5), 할 일 탭 순위(`AppState.ranks`, 앞 셋), "다른 할 일" 목록(`OtherTaskList.rows`에 `!dueDecision` 거르기).
- "다음" 표시(`nextMark`): 초안이면 그 할 일, 도는 중·시간 끝이면 **지금 상태에서 다음 고르기를 돌렸을 때 고를 할 일**(§5의 `SchedulerPick.pick`을 상태를 바꾸지 않고 부름, 현재 할 일은 `excluded`). 이월 카드·가용 시간 질문·오늘 끝 중에는 없음(nil). 빈 상태는 다음 고르기 결과(R-434).

## §5 고르기 (`SchedulerPick`, R-403~R-406, R-408)

MokaCore `Sources/MokaCore/Scheduler/SchedulerPick.swift`. 순수 함수이고 시계를 받지 않는다(시간 규칙은 호출자가 `today`·`dayStartedRun`으로 넘긴다).

```swift
struct PickInput {
    var order: [MokaTask]                 // §4 후보 순서
    var scores: [TaskID: TaskScore]       // usable 판단 결과
    var priorities: [TaskID: Double]      // 점수 있는 후보의 priority
    var excluded: TaskID?                 // 바꾸기·미루기 직후 방금 할 일(R-408)
    var isWarmup: Bool                    // §6
    var current: CurrentTask?             // R-405 순수 함수 시험 전용(앱은 늘 nil)
    var memory: SchedulerMemory           // §8
}
struct CurrentTask { var id: TaskID; var remainingMin: Int?; var quantumMin: Int }
struct PickResult { var taskID: TaskID?; var rule: SchedulerChoice?; var memory: SchedulerMemory }
```

판정 순서(앞에서 정해지면 끝):
1. 후보가 없으면 `taskID = nil`.
2. 마무리 규칙(R-405): `current`가 있고 `remainingMin`이 있고 `remainingMin ≤ quantumMin`이면 `current.id`. 이름은 `weighted_rotate_v1`(마무리 규칙만의 이름은 두지 않는다, R-411). 연속 상한보다 앞선다.
3. 아침 워밍업(R-406): `isWarmup`이면 §6 후보 가운데 priority 1위. 있으면 `warmup_v1`.
4. 가중 순환(R-403):
   - 창 = `order`에서 `excluded`를 뺀 앞 `Defaults.rotationWidth`(3)개. 빼고 나서 비면 `excluded` 하나(후보가 하나면 예외, R-408).
   - 연속 상한(R-404): `memory.recentPicks`의 마지막 `Defaults.consecutiveCap`(2)개가 같은 할 일 X이고 창에 X 말고도 후보가 있으면 X를 창에서 뺀다.
   - 몫: 창이 모두 점수 있는 할 일이면 `max(priority, Defaults.rotationMinWeight)`, 하나라도 점수 없는 할 일이면 순위 몫 `Defaults.rotationRankShares`(5, 3, 2, 창이 둘이면 5, 3).
   - 몫 셈 방식은 확정할 것 Q5다. 어느 안이든 지킬 성질: (a) 무작위 없음, 같은 입력과 같은 `memory`면 같은 결과, (b) 창이 바뀌지 않는 동안 100번 고르면 각 후보 횟수가 몫 비에서 2 이내(SC-401), (c) 창 밖 후보는 0번, (d) 동점은 `order`의 앞쪽.
   - 이름 `weighted_rotate_v1`.
5. `memory`를 갱신해 돌려준다: 고른 할 일을 `recentPicks` 끝에 붙이고 최근 `consecutiveCap`개만 남김, Q5 안에 따른 몫 상태.

남은 예상 시간(`remainingMin`) = `estMin - (그 할 일 체크포인트 elapsed_min 합)`. `estMin`이 없으면 nil. 0 이하도 그대로 넘긴다(마무리 규칙 대상, spec Edge Cases). 계산 함수는 `RemainingEstimate.minutes(task:checkpoints:)`.

앱에서 `current`는 늘 nil이고(R-405·R-407), `recentPicks`의 연속 상한도 `excluded` 때문에 걸리지 않는다(R-404). 두 규칙은 `SchedulerPickTests`로만 재현하고 앱 시험·시뮬레이터로 보고하지 않는다(SC-402, 위험 8).

## §6 아침 워밍업 (R-406)

- `isWarmup` = 그 하루(§15 `today`)에 시작한 작업 시간이 없음. 설정 키 `last_start_day`(§13)가 `today`가 아니면 참.
- `last_start_day`는 `NotchSession.start`가 성공해 커밋될 때 그 하루로 쓴다. 쓰기 실패는 워밍업이 한 번 더 걸릴 뿐이라 시작을 막지 않는다(로그 한 줄).
- 워밍업 후보 = 창이 아니라 후보 전체(`order`, `excluded` 뺌) 가운데 판단 결과가 있고 `concrete ≥ Defaults.warmupConcreteMin`(0.8)이고 `estMin != nil && estMin ≤ Defaults.warmupEstMaxMin`(30)인 할 일. 그 가운데 `order`의 첫째(= priority 1위).
- 없으면 §5-4로 간다. 워밍업으로 고른 할 일도 `recentPicks`에 들어가지만 몫 상태는 바꾸지 않는다.
- 하루 첫 작업 시간을 시작하기 전에 바꾸기·미루기를 누를 수 없으므로(초안에는 그 버튼이 없다) 워밍업 고르기는 "다른 할 일"로 초안을 바꿔도 다시 돌지 않는다. "다른 할 일"로 바꾼 할 일의 로그 이름은 `warmup_v1`이다(R-411).

## §7 연속 상한과 마무리 규칙의 자리 (R-404, R-405, R-407)

- 둘 다 §5 순수 함수 안에만 있다. `NotchSession`은 `current`를 넘기지 않는다.
- 시간 끝 화면 버튼은 그대로다. "N분 더"(`NotchSession.restart`)는 고르기가 아니라 `recentPicks`를 바꾸지 않는다.

## §8 스케줄러 메모리 (`SchedulerMemory`, R-403, R-409)

메모리에만 둔다. 저장하지 않는다.

| 값 | 뜻 | 비우는 때 |
|---|---|---|
| `credits` 또는 `pickCounts` | 몫 셈 상태(확정할 것 Q5의 안에 따라 하나) | 하루가 바뀐 뒤 첫 고르기, 앱 재시작 |
| `recentPicks: [TaskID]` | 최근 고른 할 일(최대 `consecutiveCap`개) | 같음 |
| `lastChip: [TaskID: Int]` | 그 할 일에서 이번 실행 중 마지막으로 고른 칩 값(R-409) | 앱 재시작 |
| `memoryDay: LocalDay?` | `credits`·`recentPicks`를 채운 하루 | — |
| `pickedBy: SchedulerChoice?` | 지금 노치 할 일을 띄운 규칙(로그 이름, §16) | 할 일이 노치에서 떠날 때 |

`SchedulerMemory`는 `NotchSession`의 칸이다(시뮬레이터와 앱이 같은 상태를 쓴다). `memoryDay != today`이면 고르기 전에 `credits`·`recentPicks`를 비운다.

## §9 이월 판정 (`CarryJudgment`, R-412, R-417)

MokaCore `Sources/MokaCore/Scheduler/CarryJudgment.swift`.

```swift
struct CarryJudgmentInput {
    var tasks: [MokaTask]; var checkpoints: [Checkpoint]; var decisions: [DecisionLogEntry]
    var lastJudgedAt: Date?            // 설정 키 carry_judged_at
    var revertedIDs: Set<TaskID>       // 이번 앱 시작에서 R-111이 되돌린 할 일(+ 확정할 것 Q2의 저장 표시)
    var now: Date; var dayStart: DayStart; var calendar: Calendar
}
enum CarryJudgment {
    static func needsRun(lastJudgedAt: Date?, now: Date, dayStart: DayStart, calendar: Calendar) -> Bool
    static func targets(_ input: CarryJudgmentInput) -> Set<TaskID>
}
```

- `today = DayBoundary.day(containing: now, ...)`.
- `needsRun`: `lastJudgedAt == nil`이면 참, 아니면 `DayBoundary.day(containing: lastJudgedAt) < today`.
- 구간 시작 `since` = `lastJudgedAt`, 없으면 `DayBoundary.start(of: today.adding(days: -1))`(바로 앞 하루 시작).
- 대상 = `recurrence == .none` && `status ∈ {.todo, .active}` && (손댄 할 일 || 마감 지남).
  - 손댄 할 일: `since` 이후(`createdAt > since`) 그 할 일의 체크포인트가 하나라도 있음(계기 상관없음), 또는 `since` 이후 `userAction ∉ {carryToday, carryDrop, carryMove}`인 로그 줄이 있음, 또는 `status == .active`, 또는 `revertedIDs`에 있음.
  - 마감 지남: `deadline != nil && deadline < today`.
- 이미 `dueDecision`인 할 일은 대상이든 아니든 그대로 둔다(표시를 지우지 않는다). 그래서 여러 번 돌려도 결과가 같다.
- 결과를 쓰는 것은 §10의 판정 쓰기다. 순수 함수는 쓰지 않는다.

**판정 쓰기**(`CarryJudgmentWrite`): 대상마다 `dueDecision = true`인 할 일 갱신과 `carry_judged_at = now`를 **한 트랜잭션**으로 쓴다. 대상이 없어도 판정 시각은 쓴다. 쓰기가 실패하면 둘 다 남지 않고, 다음 활성화에 같은 `since`로 다시 돈다. 어떻게 한 트랜잭션으로 쓰는지가 확정할 것 Q1이다.

- Q1-A: `StoreBatch`에 `settings: [String: String]`(덮어쓰기) 칸을 더한다. `GRDBTaskRepository.apply`가 같은 `db.write` 안에서 `settings` 표에 upsert하고, `InMemoryTaskRepository`는 자기 사본 안의 설정 사전에 쓴다. 설정 키를 읽는 쪽은 그대로 `SettingsStore`다(같은 DB 파일). 메모리 구현은 두 저장소가 사전 하나를 함께 보도록 `InMemoryStore` 하나에서 둘을 만든다.
- Q1-B: `TaskRepository`에 `lastCarryJudgment() throws -> Date?`와 `applyCarryJudgment(_ batch: StoreBatch, judgedAt: Date) throws`를 더한다. 키 `carry_judged_at`은 저장소가 혼자 읽고 쓴다(`SettingsStore`로는 다루지 않음).
- Q1-C: MokaCore에 `protocol StoreTransaction { func write(_ body: (TaskWrites, SettingsWrites) throws -> Void) throws }`를 두고, `MokaStore`가 같은 `DatabaseQueue`로 구현한다. 앱과 시뮬레이터가 판정 쓰기·쓴 시간·`last_start_day`를 이 경계로 쓴다.

R-119(앱 DB를 열 수 없음): `AppStorage.repository == nil`이면 판정을 돌리지 않는다. 설정은 메모리(`InMemorySettingsStore`)로 대체되지만 카드·질문을 띄우지 않으므로 판정 시각도 쓰지 않는다. 그래서 메모리 설정과 DB 사이의 트랜잭션은 생기지 않는다.

**R-111이 되돌린 할 일**(`revertedIDs`): 앱 시작 때 `LaunchRecovery.revert`가 돌려준 할 일 ID. 같은 시작에서 판정이 돌면(하루가 바뀐 뒤의 시작) 그 판정에 넘긴다. 같은 하루 안의 재시작이라 판정이 돌지 않으면, 확정할 것 Q2에 따라 다음 판정까지 남기는 방법이 갈린다.

- Q2-A: 남기지 않는다. 같은 하루 재시작의 빈틈을 위험으로 둔다.
- Q2-B: 설정 키 `carry_reverted`(쉼표로 이은 할 일 ID)에 더해 두고, 판정 쓰기가 같은 트랜잭션에서 지운다(Q1과 같은 경계).
- Q2-C: 되돌릴 때 그 할 일에 체크포인트 한 줄(계기 `quit`, 두 줄 빈칸, `elapsed_min` 0)을 남긴다. 판정은 체크포인트로 손댄 할 일을 찾는다.
- Q2-D: 시간 끝 화면에서 정상 종료할 때도 `lifecycleCheckpoint(.quit)`이 체크포인트를 남기게 넓힌다(spec 002 바뀜). 비정상 종료는 빈틈으로 남는다.

## §10 이월 답 (`CarryAnswer`, R-415, R-416, R-417)

`NotchSession`이 아니라 `CarryAnswer.apply(_ answer:, task:, input:) -> StoreBatch`(순수). 할 일 하나에 대해:

| 답 | 할 일 갱신 | 로그 줄 |
|---|---|---|
| `.today` | `carryCount += 1`, `dueDecision = false` | `carry_today` |
| `.drop` | `status = .dropped`, `dueDecision = false` | `carry_drop` |
| `.move(LocalDay)` | `deadline = 고른 날`, `dueDecision = false` | `carry_move` |

- 로그 줄의 `scheduler_choice`는 `carry_card_v1`, 판단 칸은 spec 003 R-212 규칙(`input.scoring?.usable[id]`이 있으면 그 결과, 없으면 `provider: "fallback"`).
- 체크포인트는 남기지 않는다.
- `.move`의 날은 `today`보다 뒤여야 한다(내일부터). 아니면 `CarryAnswerError.dateNotAfterToday`이고 아무것도 쓰지 않는다.
- 카드에 올라가는 할 일은 `dueDecision && status == .todo`다. 진행 중이면 답할 수 없다(`CarryAnswerError.notOnCard`).
- 진행 중 할 일의 완료(`NotchSession.complete`)는 그 갱신에 `dueDecision = false`를 함께 넣는다(R-417). 미루기·바꾸기는 표시를 그대로 둔다(대기가 되며 카드에 오름).
- 카드 순서: `TaskListView.deadlineFirst`(지난 마감 → 가까운 마감 → 마감 없음, 동점은 id). 남은 개수 = 카드에 오를 할 일 수(지금 보이는 것 포함).
- 카드 위 줄의 까닭(시안 1·2번): 마감 지남이면 `.overdue(days)`, 아니면 `.touched`. 둘 다면 `.overdue`. `CarryCardReason.of(task:today:)`.

## §11 가용 시간과 쓴 시간 (`DayBudget`, R-419~R-421)

```swift
struct DayBudget: Codable, Equatable {   // 설정 키 day_budget의 JSON
    var day: LocalDay
    var hours: Int        // Defaults.availableHoursChoices 가운데 하나
    var usedSeconds: Int  // 쓴 시간
    var more: Bool        // "더 할래요"를 누름
}
```

- JSON 글자: `{"day":"2026-11-16","hours":2,"used_s":3600,"more":false}`(키 순서 고정, `JSONEncoder.outputFormatting = .sortedKeys`로 쓰면 `day, hours, more, used_s` 순. 구현 PR에서 하나로 정해 시험에 적는다).
- 오늘 기록: `day == today`인 값. 아니면 없음(어제 기록은 무시하고 지우지 않는다. 다음 답이 덮어쓴다).
- `remainingSeconds = hours × 3600 − usedSeconds`. `remainingMinutes = max(0, remainingSeconds) / 60`(내림).
- 상한이 걸림(`capActive`) = 오늘 기록이 있고 `!more`.

쓴 시간을 셈하는 방법은 확정할 것 Q4다.
- Q4-A(끝날 때 실제 시간): 작업 시간이 끝날 때(시간 끝 `endsAt`, 도는 중 완료·미루기·바꾸기, 종료·잠자기 체크포인트) 그 작업 시간의 실제 초를 더한다. 잠든 시간은 spec 001 R-005 끝 시각 기준이라 들어간다. 비정상 종료한 작업 시간은 더해지지 않는다.
- Q4-B(시작할 때 고른 시간): 시작할 때 고른 분 × 60을 더하고, 일찍 끝나면(도는 중 완료·미루기·바꾸기) 남은 초를 돌려준다. "N분 더"는 그 분을 더한다. 비정상 종료하면 고른 시간이 그대로 쓴 시간이다.
- Q4-C(기록에서 셈): 체크포인트 `elapsed_min`과 새 저장(도는 중 완료의 경과 분)을 합한다. 도는 중 완료는 지금 체크포인트가 없어 새 저장이 하나 더 는다.

어느 안이든 하루 경계를 넘는 작업 시간은 시작한 하루의 기록에만 더한다. 새 하루의 쓴 시간은 가용 시간 답을 쓸 때 0에서 시작한다(가정, research R10). 새 하루의 질문은 그 작업 시간이 끝나 노치가 빈 뒤에야 뜨므로(R-417) 경계 뒤 몫을 담을 기록이 아직 없기 때문이다.

칩 상한(R-409, R-421):
- `QuantumChip.cap(chipMin:remainingMinutes:)`: `capActive`이면 `min(chipMin, remainingMinutes)`. 1 미만이면 시작할 수 없음(§12 오늘 끝).
- 시작 전 칩 처음 값 순서: `lastChip[id]` → 설정 기본 작업 시간 → 남은 예상 시간이 더 짧으면 그 값(1분 이상) → 남은 분이 더 짧으면 그 값.
- 시간 끝 칩 처음 값: 추가 시간(#151) → 남은 분이 더 짧으면 그 값.
- 남은 분보다 긴 프리셋은 고를 수 없다(`QuantumChipSegment.enabled = false`). 직접 입력이 남은 분보다 크면 `QuantumChip.CustomIssue.aboveRemaining(minutes)`이고 시작이 꺼진다. 문구는 확정 시안 글자(§19).

## §12 노치 모드와 오늘 끝 (R-413, R-414, R-419, R-422)

화면은 아래 순서의 첫 조건으로 정한다. `NotchMode.of(...)` 순수 함수.

| 순서 | 조건 | 모드 | 고르기 |
|---|---|---|---|
| 1 | 앱 DB를 열 수 없음(R-119) | `.storageUnavailable`(지금 그대로) | 없음 |
| 2 | 현재 할 일이 도는 중 또는 시간 끝 | `.session`(지금 화면, 시간 끝은 §11 칩 상한과 "N분 더" 끔) | 없음 |
| 3 | 카드에 오를 할 일이 있음(§10) | `.carryCard(task, left, reason)` | 없음 |
| 4 | 오늘 기록이 없음 | `.askBudget` | 없음 |
| 5 | `capActive && remainingMinutes < 1` | `.dayEnd` | 없음 |
| 6 | 그 밖 | `.session`(빈 상태면 고르기, 초안이면 그대로) | §5 |

- 3·4·5가 되면 초안을 비운다(R-413 Edge Case, 잃는 것은 칩 값뿐). 빠른 입력으로 넣은 할 일은 저장만 하고 초안으로 띄우지 않는다(spec Edge Cases).
- 2에서 시간 끝이고 `capActive && remainingMinutes < 1`이면 "N분 더"를 끄고 이유 한 줄을 보인다(`ExpiredDayEnd`). 직접 입력 칸은 열 수 없다. 이때 완료·미루기·바꾸기의 체크포인트 계기는 `day_end`다(research R11). 버튼 처리 뒤 모드는 5다.
- 오늘 끝 판정은 고르기보다 먼저다: 완료·미루기·바꾸기 커밋 뒤 `pickIfEmpty`가 모드를 먼저 보고 6일 때만 고른다(SC-405).
- "더 할래요": `more = true`를 쓰고 모드 6으로 고른다. 쓰기가 실패하면 모드 5에 머물고 다시 해 달라는 한 줄을 보인다.
- 가용 시간 답: `DayBudget(day: today, hours: h, usedSeconds: 0, more: false)`를 쓴다. 실패하면 질문에 머문다.
- 하루 경계를 지난 활성화에서 2이면(도는 중) 판정은 돌고(§9, 진행 중 할 일에 표시) 화면은 그대로다. 버튼으로 빈 상태가 되면 3부터 본다(R-417).

## §13 설정 키 (승인 항목 5)

기존 `settings(key, value)` 표에 더한다. 읽기 실패와 형식 오류는 기본값으로 본다(`CoreSettings` 무늬).

| 키 | 값 | 기본 | 쓰는 곳 |
|---|---|---|---|
| `auto_start` | `"true"` / 없음 | 꺼짐 | 기본 탭(R-410) |
| `carry_judged_at` | `UTCTimestamp` 글자 | 없음(처음 판정) | 판정 쓰기(§9). Q1-B면 저장소만 다룸 |
| `day_budget` | §11 JSON | 없음 | 가용 시간 답, 쓴 시간, "더 할래요" |
| `last_start_day` | `LocalDay` 글자 | 없음 | 시작 커밋(§6) |
| `carry_reverted` | 쉼표로 이은 할 일 ID | 없음 | Q2-B를 고를 때만 |

`off_days`와 `default_pause_min`은 Issue #171이다.

## §14 `Defaults.swift` 새 값 (승인 항목 6, PR "사람이 볼 결정")

| 이름 | 값 | 근거 |
|---|---|---|
| `carryAgingWeight` | 0.5 | PRD 7장 aging 식 |
| `warmupConcreteMin` | 0.8 | PRD 7장 정책 6, debate 3:0(스케줄러 값) |
| `warmupEstMaxMin` | 30 | PRD 7장 정책 6 |
| `rotationWidth` | 3 | PRD 정책 2 상위 3개 |
| `rotationRankShares` | `[5, 3, 2]` | PRD "대략 0.5/0.3/0.2" |
| `rotationMinWeight` | 0.05 | priority 0 후보도 굶지 않게(spec Edge Cases). priority 크기(대략 0~3)의 작은 값으로 잡은 에이전트 값 |
| `consecutiveCap` | 2 | PRD 정책 2 |
| `availableHoursChoices` | `[1, 2, 4, 6, 8]` | spec R-419 |
| `autoStartDelay` | 3(초) | spec R-410 |

이전 값은 모두 없음(새 값)이다. 질문 임계값은 `questions.json`에 그대로 두고 여기 두지 않는다.

## §15 활성화 순서 (R-412, R-113, R-111)

`AppState.launch()`와 `activate()`, 시뮬레이터 `relaunch`·`activate`가 같은 순서를 쓴다.

1. (앱 시작만) `LaunchRecovery.revert` 쓰기 → `revertedIDs`
2. `RecurrenceReset.reset` 쓰기(지금 그대로)
3. `CarryJudgment.needsRun`이면 대상 계산 → 판정 쓰기(§9)
4. 모드 판정(§12) → 6이면 고르기(`pickIfEmpty`)
5. `requestScores()`(지금 그대로, `defer`)

판단 질의는 카드·질문·오늘 끝 중에도 spec 003 규칙대로 돈다. "날짜 바꿀래요"로 바뀐 마감은 판단 입력 해시가 바뀌어 다시 묻는다.

## §16 행동 로그 값 (승인 항목 2·3)

`UserAction`에 더함: `carryToday = "carry_today"`, `carryDrop = "carry_drop"`, `carryMove = "carry_move"`.

`SchedulerChoice`에 더함: `weightedRotateV1 = "weighted_rotate_v1"`, `warmupV1 = "warmup_v1"`, `carryCardV1 = "carry_card_v1"`. 기존 `rotateByIDV0`·`priorityRotateV0`는 이전 줄을 읽으려고 남기고 새 줄에는 쓰지 않는다.

줄마다 `scheduler_choice`:
- 완료·미루기·바꾸기: `memory.pickedBy`(그 할 일을 노치에 띄운 규칙). "다른 할 일"로 초안을 바꾸면 바꾸기 전 `pickedBy`를 그대로 둔다(R-411). 빠른 입력으로 넣어 바로 초안이 된 할 일은 그 앞 `pickedBy`, 없으면 `weighted_rotate_v1`(가정, research R12).
- 이월 답: `carry_card_v1`.
- 가용 시간 답, "더 할래요": 줄 없음(R-416).

`ValueTypeTests`의 `allCases` 단언은 새 값을 끝에 더하는 것으로 고친다(값을 빼지 않는다, 계약 덧붙이기).

## §17 3초 뒤 자동 시작 (R-410)

`AutoStart.shouldStart(enabled:mode:draftShownAt:lastInputAt:gateBusy:now:) -> Bool`: 켜짐 && 모드가 §12-6의 초안 && 게이트가 묻거나 확인하는 중이 아님 && `now - max(draftShownAt, lastInputAt) ≥ Defaults.autoStartDelay`. 앱은 초안이 뜰 때 한 번 일정을 걸고, 입력이 있으면 다시 건다. 시간은 주입한 시계로 시험한다.

## §18 "내일" 표시 (R-423)

`TomorrowMark.ids(order:remainingMinutes:defaultQuantumMin:) -> Set<TaskID>`: `capActive`일 때만. 후보 순서대로 `estMin ?? defaultQuantumMin`을 쌓아 합이 `remainingMinutes`를 넘는 할 일부터 표시한다. 진행 중 할 일은 쌓지 않는다(가정). 상한이 없으면 빈 집합.

## §19 화면 값과 스냅샷 이름

화면 글자는 확정 시안 `~/Dev/ai-platform/projects/moka/design/005-mockup.html`(저장소 밖)의 글자를 그대로 쓴다. 값을 끼워 넣는 글자(남은 개수, 남은 분, 시간, D+N)는 MokaCore(`NotchStatus.swift` 무늬, #42)에, 고정 글자는 뷰 상수에 둔다.

- MokaCore 글자 함수: `CarryText.reason(_:)`, `CarryText.left(_:)`, `BudgetText.capNote(minutes:expired:)`, `BudgetText.customAbove(minutes:)`, `BudgetText.dayEndOff(hours:)`, `BudgetText.dayEndTitle(hours:)`, `NotchStatus.label`의 새 경우("오늘 정하기", "날짜 바꾸기", "오늘 끝").
- 뷰 상수: `CarryText` 버튼 셋, 질문 문구, 오늘 끝 문구, "더 할래요", 접힌 노치 글자, 할 일 탭 "오늘 정할 일"과 "내일", 기본 탭 자동 시작 칸.

스냅샷 이름(라이트·다크): `test_R414_carryCardTouched`, `test_R414_carryCardOverdueLast`, `test_R415_datePicker`, `test_R419_askBudget`, `test_R421_draftCapped`, `test_R421_customAboveRemaining`, `test_R409_expiredCapped`, `test_R422_expiredDayEnd`, `test_R422_dayEnd`, `test_R414_collapsedCarry`, `test_R419_collapsedAskBudget`, `test_R422_collapsedDayEnd`, `test_R413_taskTabDue`, `test_R423_taskTabTomorrow`, `test_R410_basicTabAutoStart`. 확정 시안 번호와 같은 순서다.
