# Data Model: 스케줄러 (spec 005)

규칙, 값, 모양의 원본이다. tasks.md는 절 번호를 가리킨다. 이름은 [GLOSSARY.md](../../GLOSSARY.md)를 따르고, 새 코드 이름은 이 문서가 처음 정한다. plan "확정할 것" Q1~Q6은 2026-11-16에 정했고(기록 `.audit/debate/20261116-spec005-plan.md`, 저장소 밖) 이 문서에 반영했다. 기준 `origin/main` `67b526e`.

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

칸 모양은 Q6-A로 정했다(debate 3:0, 2026-11-16, research Q6).

```sql
ALTER TABLE tasks ADD COLUMN carry_count INTEGER NOT NULL DEFAULT 0 CHECK(carry_count >= 0)
ALTER TABLE tasks ADD COLUMN due_decision INTEGER NOT NULL DEFAULT 0 CHECK(due_decision IN (0, 1))
```

함께 바꾸는 것:
- `Tests/MokaStoreTests/MigrationTests.swift:9`의 이름 목록 끝에 `"v4_tasks_carry"`를 더한다(ADR-0007).
- `schema/moka-schema.sql`은 메모리 DB에 마이그레이션한 뒤의 `sqlite_master` 글자로 다시 만든다. `ADD COLUMN`은 SQLite가 `CREATE TABLE` 글자 끝에 열 정의를 붙이므로 글자 모양은 구현 PR의 시험 출력 그대로 쓴다. 손으로 고치지 않는다.
- `GRDBTaskRepository`의 읽기·쓰기(`insertTask`, `apply`, 행 읽기)가 두 열을 다룬다. 기존 행은 기본값으로 읽힌다(업그레이드 시험, quickstart 3).
- `tuning/tests/test_schema_contract.py`: tasks 열 집합에 두 열이 있는지, 기본값이 0인지, `due_decision = 2`가 CHECK로 막히는지, `carry_count = -1`이 CHECK로 막히는지, `decisions_log`에 `user_action = 'carry_today'`·`scheduler_choice = 'carry_card_v1'` 줄이 들어가는지(값 CHECK가 없으므로 지금도 들어감을 계약으로 고정) 본다.
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
- "다음" 표시(`nextMark`): 초안이면 그 할 일, 도는 중·시간 끝이면 **지금 상태에서 다음 고르기를 돌렸을 때 고를 할 일**(§5의 `SchedulerPick.pick`을 상태를 바꾸지 않고 부름, 현재 할 일은 `excluded`). 이월 카드·가용 시간 질문·오늘 끝 중에는 없음(nil). 빈 상태는 다음 고르기 결과(R-434). 알려진 한계: 미루기·바꾸기 직후, 그리고 판단 결과가 바뀐 경우에는 실제 다음 고르기와 다를 수 있다. 완료 뒤에는 같다(도는 중 할 일은 후보가 아니므로, `PriorityOrder.isCandidate`)(#174).

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
   - 몫 셈은 매끄러운 가중 순환이다(Q5-A, 사람 결정 2026-11-16, debate 2:1 다수안. 창 정의 수정은 debate에서 두 자리가 지적해 함께 채택, research Q5).
   - **창** = `order`의 앞 `Defaults.rotationWidth`(3)개. 창을 먼저 정하고, 그 뒤에 건너뛸 후보를 고른다. `excluded`를 빼고 넷째 후보를 끌어올리지 않는다(US1-1 "4위는 0번").
   - **몫 상태 정리**: `memory.credits`에서 창에 없는 할 일의 몫을 버린다(창에서 실제로 빠진 후보만). 창에 새로 든 할 일은 0에서 시작한다.
   - **정수 몫**: 창이 모두 점수 있는 할 일이면 몫 = `max(Int((priority × 1000).rounded()), Int((Defaults.rotationMinWeight × 1000).rounded()))`, 하나라도 점수 없는 할 일이면 순위 몫 `Defaults.rotationRankShares`(5, 3, 2, 창이 둘이면 5, 3). 몫과 `credits`는 `Int`라 플랫폼과 부동소수 오차에 따라 고른 결과가 달라지지 않는다. 1000은 `SchedulerPick` 안 상수(조정 값이 아님).
   - **셈**: 창의 모든 할 일(건너뛸 후보 포함)의 `credits`에 몫을 더한다. 고를 수 있는 후보 = 창에서 `excluded`(R-408)와 연속 상한(R-404: `recentPicks`의 마지막 `Defaults.consecutiveCap`(2)개가 같은 할 일 X이면 X)을 뺀 것. 그 가운데 `credits`가 가장 큰 할 일을 고르고, 동점이면 `order` 앞쪽. 고른 할 일의 `credits`에서 창 몫 합을 뺀다. 건너뛴 후보의 몫은 버리지 않고 그대로 둔다(다음 고르기에서 앞선다).
   - 고를 수 있는 후보가 비면: 창에 `excluded`만 남은 경우(후보가 하나) 그 할 일, 연속 상한 때문에 빈 경우 상한을 무시하고 고른다(R-404 "후보가 하나면 예외").
   - 지킬 성질: (a) 무작위 없음, 같은 입력과 같은 `memory`면 같은 결과, (b) 창이 바뀌지 않고 건너뛰기가 없는 동안 10번마다 몫 비 그대로(5:3:2면 5·3·2), 100번이면 50·30·20(SC-401), (c) 창 밖 후보는 0번, (d) 동점은 `order`의 앞쪽.
   - 근거 시뮬레이션(메인 세션, 기록 `.audit/debate/20261116-spec005-plan.md`)은 특정 사례 하나다: 몫 5:3:2 창에서 0부터 10번 고른 뒤(그때 몫 상태가 모두 0으로 돌아옴) 급한 새 할 일이 1위(몫 5)로 들고 나머지가 3·2가 되는 경우, 새 할 일이 바로 다음 차례에 뽑히고 이어지는 10번 중 5번 뽑혔다. "새 1위가 바로 다음 차례에 뽑힌다"는 일반 성질이 아니다. 반례: 몫 상태가 A 0, B 1200, C −1200인 때 priority 2.0(몫 2000)인 N이 1위로 들고 A가 창에서 밀려나면, 몫을 더한 뒤 N은 2000, B는 1200 + B의 몫이라 B의 몫이 800보다 크면(예: priority 0.9 → 900) B가 먼저 뽑힌다. 시험은 이 특정 사례만 고정한다.
   - 이름 `weighted_rotate_v1`.
5. `memory`를 갱신해 돌려준다: 고른 할 일을 `recentPicks` 끝에 붙이고 최근 `consecutiveCap`개만 남김, 갱신한 `credits`.

남은 예상 시간(`remainingMin`) = `estMin - (그 할 일 체크포인트 elapsed_min 합)`. `estMin`이 없으면 nil. 0 이하도 그대로 넘긴다(마무리 규칙 대상, spec Edge Cases). 계산 함수는 `RemainingEstimate.minutes(task:checkpoints:)`.

앱에서 `current`는 늘 nil이고(R-405·R-407), `recentPicks`의 연속 상한도 `excluded` 때문에 걸리지 않는다(R-404). 두 규칙은 `SchedulerPickTests`로만 재현하고 앱 시험·시뮬레이터로 보고하지 않는다(SC-402, 위험 8).

## §6 아침 워밍업 (R-406)

- `isWarmup` = 그 하루(§15 `today`)에 시작한 작업 시간이 없음. 설정 키 `last_start_day`(§13)가 `today`가 아니면 참.
- `last_start_day`는 `NotchSession.start`가 성공해 커밋될 때 그 하루로 쓴다. 시간 끝의 "N분 더"(`restart`)는 시작이 아니라 쓰지 않는다. 하루 경계 뒤 "N분 더"(spec 6c)도 그 하루의 첫 작업 시간으로 치지 않아, 새 하루 첫 고르기는 여전히 워밍업이다. 쓰기 실패는 워밍업이 한 번 더 걸릴 뿐이라 시작을 막지 않는다(로그 한 줄).
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
| `credits: [TaskID: Int]` | 매끄러운 가중 순환의 몫 상태(§5-4, 창에 든 할 일만) | 하루가 바뀐 뒤 첫 고르기, 앱 재시작 |
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
    var revertedIDs: Set<TaskID>       // 이번 앱 시작에서 R-111이 되돌린 할 일(저장하지 않음, Q2-A)
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
  - 손댄 할 일: `createdAt >= since`인 그 할 일의 체크포인트가 하나라도 있음(계기 상관없음), 또는 `createdAt >= since`이고 `userAction ∉ {carryToday, carryDrop, carryMove}`인 로그 줄이 있음, 또는 `status == .active`, 또는 `revertedIDs`에 있음.
  - 같은 초 처리: 저장 시각(`UTCTimestamp`)은 초 아래를 버리므로 `since`와 `createdAt`을 모두 초로 내림한 값으로 비교하고 경계를 포함한다(`>=`). 지난 판정과 같은 초에 남은 줄은 다음 판정에서도 손댄 것으로 센다. 두 번 세어 카드에 한 번 더 오를 수는 있어도 빠지지는 않는 쪽이다(FR-08 "자동 이월 0건").
  - 마감 지남: `deadline != nil && deadline < today`.
- 이미 `dueDecision`인 할 일은 대상이든 아니든 그대로 둔다(표시를 지우지 않는다). 그래서 여러 번 돌려도 결과가 같다.
- 결과를 쓰는 것은 §10의 판정 쓰기다. 순수 함수는 쓰지 않는다.

**판정 쓰기**(`CarryJudgmentWrite`): 대상마다 `dueDecision = true`인 할 일 갱신과 `carry_judged_at = now`를 **한 트랜잭션**으로 쓴다. 대상이 없어도 판정 시각은 쓴다. 쓰기가 실패하면 둘 다 남지 않고, 다음 활성화에 같은 `since`로 다시 돈다. 저장 경계는 Q1-B로 정했다(debate 3:0, 2026-11-16, research Q1).

- `TaskRepository`에 둘을 더한다: `lastCarryJudgment() throws -> Date?`, `applyCarryJudgment(_ batch: StoreBatch, judgedAt: Date) throws`.
- `GRDBTaskRepository.applyCarryJudgment`는 `batch`의 할 일 갱신과 `settings` 표의 `carry_judged_at` upsert를 한 `db.write`로 쓴다. `lastCarryJudgment`는 같은 키를 읽는다. `InMemoryTaskRepository`는 자기 사본 안에 판정 시각 하나를 들고 `apply`와 같은 방식(사본에 쓰고 다 되면 바꿔 넣음)으로 쓴다.
- 키 `carry_judged_at`은 `TaskRepository`만 읽고 쓴다. `SettingsStore`(`GRDBSettingsStore`, `InMemorySettingsStore`)와 `CoreSettings`는 이 키를 다루지 않는다. 경계 밖에서 쓰지 못하게 막는 시험을 둔다: `CoreSettings`에 이 키 이름 상수가 없음, `GRDBSettingsStore`와 `InMemorySettingsStore`의 `setValue(_:for: "carry_judged_at")`·`value(for: "carry_judged_at")`는 `StoreError.invalidValue(column: "key")`로 거부하고 아무것도 쓰지 않음, 앱·시뮬레이터 코드에서 이 키 글자가 `GRDBTaskRepository`·`InMemoryTaskRepository` 밖에 없음(소스 검색 시험).
- `StoreBatch`와 `apply`는 그대로다. 쓴 시간·`last_start_day`·`day_budget`은 `SettingsStore`로 따로 쓴다(버튼 커밋과 같은 트랜잭션이 아니다). 버튼 커밋은 됐는데 설정 쓰기가 실패하면 로그 한 줄을 남기고 다음 커밋에서 다시 쓰지 않는다. 시작 때 더하기를 못 쓰면 그만큼 적게 세고, 돌려주기를 못 쓰면 많이 센다.

R-119(앱 DB를 열 수 없음): `AppStorage.repository == nil`이면 판정을 돌리지 않는다. 설정은 메모리(`InMemorySettingsStore`)로 대체되지만 카드·질문을 띄우지 않으므로 판정 시각도 쓰지 않는다. 그래서 메모리 설정과 DB 사이의 트랜잭션은 생기지 않는다.

**R-111이 되돌린 할 일**(`revertedIDs`): 앱 시작 때 `LaunchRecovery.revert`가 돌려준 할 일 ID. 이번 실행 동안 메모리(`AppState.pendingRevertedIDs`, 시뮬레이터는 러너 상태)에 들고 있다가, 판정 쓰기가 **성공할 때** 비운다. 그래서 (1) 하루가 바뀐 뒤의 시작이면 같은 시작의 판정에 들어가고, (2) 그 판정 쓰기가 실패하면 다음 활성화의 재판정에도 들어가며, (3) 같은 하루 안의 재시작이라 판정이 돌지 않아도 앱을 끄지 않고 하루를 넘기면 그 하루 경계의 판정에 들어간다. 저장하지는 않는다(Q2-A, debate 3:0, 2026-11-16). 그래서 같은 하루 안에 재시작하고 그날 다시 앱을 끈 뒤 다음 날 켜면 그 할 일은 체크포인트나 로그 줄이 없으면 손댄 할 일이 아니고, 마감이 지났을 때만 카드에 오른다(plan 위험 14). 시간 끝 화면에서 정상 종료할 때도 체크포인트를 남기는 변경(Q2-D)은 별도 Issue로 넘겼다.

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
    var minutes: Int          // 가용 시간(분). 처음 답 + 늘린 분
    var extendedMinutes: Int  // 시작 전 화면에서 늘린 분의 합(처음 0)
    var usedSeconds: Int      // 쓴 시간
    var more: Bool            // "더 할래요"를 누름
}
```

- JSON 글자: `{"day":"2026-11-16","extended_min":15,"minutes":135,"more":false,"used_s":3600}`(`JSONEncoder.outputFormatting = .sortedKeys`로 키 순서 고정).
- 처음 답(R-419): 선택지 다섯은 `Defaults.availableHoursChoices`(1·2·4·6·8) × 60분. 직접 적기는 아래 "직접 적은 가용 시간". 답할 때 `minutes = 답`, `extendedMinutes = 0`, `usedSeconds = 0`, `more = false`.
- 오늘 기록: `day == today`인 값. 아니면 없음(어제 기록은 무시하고 지우지 않는다. 다음 답이 덮어쓴다).
- `remainingSeconds = minutes × 60 − usedSeconds`. `remainingMinutes = max(0, remainingSeconds) / 60`(내림).
- **작업 시간의 하루**(`budgetDay`): 작업 시간을 시작(`start`)한 하루. 그 작업 시간에서 이어 누른 "N분 더"(`restart`)는 처음 시작의 `budgetDay`를 물려받는다. `RunInfo.budgetDay`로 메모리에 둔다(진행 중 세션은 재시작에 남지 않으므로, spec 002 R-111).
- 상한이 걸림(`capActive(day)`) = 그 하루의 기록이 있고 `!more`. 시작 전 칩과 오늘 끝은 `today`로, 시간 끝 칩과 "N분 더"는 그 작업 시간의 `budgetDay`로 본다. 보통은 둘이 같고, 하루 경계를 넘긴 작업 시간에서만 다르다.

쓴 시간은 시작할 때 고른 분으로 센다(Q4-B, 사람 결정 2026-11-16, debate 2:1 다수안, research Q4).
- 시작(`NotchSession.start`)과 "N분 더"(`restart`)가 커밋될 때 고른 분 × 60을 `usedSeconds`에 더한다.
- 작업 시간이 일찍 끝나면 남은 초(`endsAt − 끝난 시각`, 0 이상)를 돌려준다(뺀다): 도는 중 완료·미루기·바꾸기, 도는 중 종료(`lifecycleCheckpoint(.quit)`). 잠자기는 타이머가 계속 도는 것으로 보므로(spec 001 R-005) 돌려주지 않는다. 시간 끝까지 간 작업 시간은 돌려줄 것이 없다.
- 비정상 종료하면 돌려받지 못해 고른 시간이 다 쓴 시간으로 남는다. 많이 세는 쪽으로 틀리고, 그날 "오늘 끝"이 일찍 올 수 있다(plan 위험 15). 소수 의견(가이드 자리)은 끝날 때 실제 초를 더하는 안이었다.
- 지키는 성질(SC-405, spec R-421 정정): 어느 하루의 기록이든 `capActive`인 동안 `usedSeconds ≤ minutes × 60`(늘린 분 포함)이고, 시작·"N분 더" 때 고르는 칩은 그 작업 시간의 `budgetDay` 기록의 `remainingMinutes` 이하다. "그날 시작한 작업 시간 분 합 ≤ minutes"는 성립하지 않는다. 일찍 끝내고 돌려받은 시간으로 다시 시작할 수 있기 때문이다(예: 2시간에서 60분 시작 → 10분에 완료(50분 돌려받음) → 110분 시작이면 시작한 분 합은 170, 쓴 시간은 120).

하루 경계를 넘는 작업 시간은 시작한 하루(`budgetDay`)의 기록에만 더하고 돌려준다. 그 작업 시간이 하루 경계 뒤 시간 끝이 되어 누르는 "N분 더"(spec 6c)도 같은 기록에 더하고 돌려준다(새 하루에는 아직 가용 시간 기록이 없다). 이때 상한도 그 기록으로 건다: 하루 경계 뒤 시간 끝 화면의 "N분 더" 칩은 시작한 하루의 남은 분 이하로 채우고, 남은 분이 1 미만이면 "N분 더"를 끄고 이유 한 줄을 보인다(R-422의 끈 화면과 같은 모양, 문구는 시안에서 확정). 시작한 하루에 가용 시간 기록이 없거나 "더 할래요"를 눌렀으면 상한이 없다. 이 규칙은 메인 세션 가정이다(PR "가정"). 함께 본 다른 안: (1) R-421을 "같은 하루 안"으로 좁혀 하루 경계 뒤 "N분 더"는 상한 없이 둠, (3) 하루 경계 뒤 "N분 더"는 어느 하루의 쓴 시간에도 넣지 않음. 새 하루의 쓴 시간은 가용 시간 답을 쓸 때 0에서 시작한다(가정, research R10). 새 하루의 질문은 그 작업 시간이 끝나 노치가 빈 뒤에야 뜨므로(R-417) 경계 뒤 몫을 담을 기록이 아직 없기 때문이다.

칩 상한(R-409, R-421):
- `QuantumChip.cap(chipMin:remainingMinutes:)`: `capActive`이면 `min(chipMin, remainingMinutes)`. 1 미만이면 시작할 수 없음(§12 오늘 끝).
- 시작 전 칩 처음 값 순서: `lastChip[id]` → 설정 기본 작업 시간 → 남은 예상 시간이 더 짧으면 그 값(1분 이상) → 남은 분이 더 짧으면 그 값.
- 시간 끝 칩 처음 값: 추가 시간(#151) → 남은 분이 더 짧으면 그 값.
- **시작 전 화면**(사용자 결정 2026-11-16): 남은 분보다 긴 프리셋도 누를 수 있다. 남은 분보다 긴 칩(프리셋 또는 직접 입력)이 고른 값이면 `extendNeeded = chipMin − remainingMinutes`(분, 1 이상)이고, 시작 버튼 자리에 늘리기 확인 한 줄을 보인다(아래 "늘리기").
- **시간 끝 화면**: 늘리기가 없다. 남은 분보다 긴 프리셋은 고를 수 없고(`QuantumChipSegment.enabled = false`), 직접 입력이 남은 분보다 크면 `QuantumChip.CustomIssue.aboveRemaining(minutes)`이고 "N분 더"가 꺼진다. 문구는 확정 시안 7번 글자(§19).

**늘리기**(R-421, 사용자 결정 2026-11-16. 방식은 메인 세션 가정, plan "사람이 볼 결정"):
- 조건: 시작 전 화면(초안), `capActive(today)`, `remainingMinutes ≥ 1`, 고른 칩 > `remainingMinutes`. 남은 분이 0이면 모드가 오늘 끝(§12-5)이라 초안이 없고 늘리기도 없다. 그때는 "더 할래요"다.
- 확인 줄: 제목 "오늘 시간을 {extendNeeded}분 늘려서 {chipMin}분 할까요?", 설명 "오늘 남은 시간은 {remainingMinutes}분이에요. 늘리면 오늘 정한 시간이 {새 가용 시간}이 돼요.", 버튼 "{remainingMinutes}분만 할래요"와 "늘리고 시작 ↵"(확정 대기 시안 6번 글자, `BudgetText`).
- "늘리고 시작": 오늘 기록에 `minutes += extendNeeded`, `extendedMinutes += extendNeeded`를 쓰고, 그 쓰기가 성공하면 그 칩으로 시작한다(시작 커밋이 `usedSeconds`에 칩 × 60을 더함). 늘린 뒤 `remainingMinutes ≥ chipMin`이라 `usedSeconds ≤ minutes × 60`이 지켜진다. 늘리기 쓰기가 실패하면 시작하지 않고 확인 줄에 다시 해 달라는 한 줄을 보인다.
- 늘리기 쓰기는 성공했는데 시작 커밋이 실패하면(메인 세션 가정): 늘린 가용 시간은 그대로 둔다(되돌리지 않음). 확인 줄 자리에 "시작하지 못했어요. 다시 해 주세요." 한 줄을 보인다. 이제 남은 분이 칩 이상이라 `extendNeeded == nil`이고, 다시 누르면(시작 버튼이나 Enter) 확인 줄 없이 바로 시작한다. 두 번 늘리지 않는다.
- "{N}분만 할래요": 칩을 `remainingMinutes`로 되돌리고 확인 줄을 닫는다. 시작하지 않는다.
- Enter: 확인 줄이 열린 동안 Enter는 "늘리고 시작"이다. 확인 줄이 닫혀 있고 칩이 남은 분 이하이면 지금처럼 시작이다. 3초 뒤 자동 시작(R-410)은 확인 줄이 열린 동안 돌지 않는다(늘리기는 사용자가 눌러야 한다).
- "더 할래요"와 다른 점: 늘린 분만큼만 커지고 상한(`capActive`)은 그대로라, 늘린 시간을 다 쓰면 다시 오늘 끝이 온다.
- 시간 끝 화면(시안 7·8번)과 하루 경계 뒤 "N분 더"(`budgetDay`)에는 늘리기를 두지 않는다. 7·8번은 사람이 그대로 확정했고, 오늘 끝과 겹친 화면은 R-422 결정(debate 3:0, "N분 더"만 끔)을 지키며 그 뒤 "오늘 끝"의 "더 할래요"가 이어 가는 길이다.
- 행동 로그: 늘리기는 `decisions_log`에 줄을 남기지 않는다. 가용 시간 답·"더 할래요"와 같은 규칙이다(R-416: 줄은 할 일 하나에 대한 버튼·카드 입력이고, 늘리기는 오늘 가용 시간을 바꾸는 입력이다). 늘린 양은 `day_budget.extended_min`에 남는다.

**직접 적은 가용 시간**(R-419, 사용자 결정 2026-11-16. 단위·범위·문구는 에이전트 가정):
- 선택지 다섯 뒤 "직접…" 칸. 누르면 숫자 칸이 열리고 포커스가 간다. 단위는 시간이고 소수 한 자리 0.5 단위만 받는다(예: 1.5 = 90분).
- 범위: `Defaults.customBudgetMinutesRange` = 30…960분(0.5~16시간), 단위 `Defaults.customBudgetStepMinutes` = 30분.
- 판정 `BudgetInput.parse(_ text: String) -> Result<Int, BudgetInputIssue>`: 앞뒤 공백 제거, 쉼표 소수점 받지 않음. 오류 넷과 문구(확정 대기 시안 4-3): `.notNumber` "시간은 숫자로 적어 주세요. 예: 1.5", `.notHalfHour` "30분 단위로 적어 주세요. 예: 2 또는 2.5", `.belowMin` "30분(0.5)부터 정할 수 있어요", `.aboveMax` "16시간까지 정할 수 있어요". 오류거나 비면 "정하기"가 꺼지고 Enter도 답하지 않는다.
- 답은 "정하기" 또는 Enter. 선택지를 누르면 칸은 닫히고 그 선택지로 바로 답한다.

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

- 3·4·5가 되면 초안을 비운다(R-413 Edge Case). 잃는 것은 칩 값과 그 고르기의 몫 빼기(§5-4)다. 몫 빼기는 되돌리지 않는다. 앱에서는 초안이 하루 경계 뒤에만 비워지고, 다음 고르기 전에 몫 상태가 비워지므로(§8 `memory.on(today)`) 영향이 없다(debate 3:0, 2026-11-16, #179). 같은 하루 안에 초안을 비우는 길(#171 긴급·일시 중지)이 생기면, 비울 때 고르기 전 스케줄러 메모리 전체로 되돌려야 한다. 빠른 입력으로 넣은 할 일은 저장만 하고 초안으로 띄우지 않는다(spec Edge Cases).
- 2에서 시간 끝이고 그 작업 시간의 `budgetDay`가 `capActive`이고 그 기록의 `remainingMinutes < 1`이면 "N분 더"를 끄고 이유 한 줄을 보인다(`ExpiredDayEnd`). 직접 입력 칸은 열 수 없다. 이때 완료·미루기·바꾸기의 체크포인트 계기는 `day_end`다(research R11). 버튼 처리 뒤 모드는 `budgetDay == today`면 5, 하루 경계를 넘긴 작업 시간이면 새 하루의 표(보통 3이나 4)다.
- 오늘 끝 판정은 고르기보다 먼저다. 버튼 처리 순서를 못박는다: (1) 버튼의 `StoreBatch` 커밋 → (2) 남은 초 돌려주기(§11, `day_budget` 쓰기) → (3) 모드 판정(§12 표) → (4) 모드가 6일 때만 `pickIfEmpty`의 고르기. (2)를 (3) 뒤에 하면 일찍 끝내 돌려받을 시간이 있는데도 오늘 끝이 뜰 수 있다(SC-405).
- "더 할래요": `more = true`를 쓰고 모드 6으로 고른다. 쓰기가 실패하면 모드 5에 머물고 다시 해 달라는 한 줄을 보인다.
- 가용 시간 답: `DayBudget(day: today, minutes: m, extendedMinutes: 0, usedSeconds: 0, more: false)`를 쓴다(선택지면 시간 × 60, 직접 적기면 §11의 분). 실패하면 질문에 머문다.
- 하루 경계를 지난 활성화에서 2이면(도는 중) 판정은 돌고(§9, 진행 중 할 일에 표시) 화면은 그대로다. 버튼으로 빈 상태가 되면 3부터 본다(R-417).

## §13 설정 키 (승인 항목 5)

기존 `settings(key, value)` 표에 더한다. 읽기 실패와 형식 오류는 기본값으로 본다(`CoreSettings` 무늬). 예외: `carry_judged_at` 읽기 오류(DB 읽기 실패)는 기본값으로 보지 않고 판정을 미룬다(R-412). 형식 오류만 없음(처음 판정)으로 본다.

| 키 | 값 | 기본 | 쓰는 곳 |
|---|---|---|---|
| `auto_start` | `"true"` / `"false"` / 없음(정확히 `"true"`일 때만 켜짐, 끄면 `"false"`를 씀) | 꺼짐 | 기본 탭(R-410) |
| `carry_judged_at` | `UTCTimestamp` 글자 | 없음(처음 판정) | 판정 쓰기(§9). `TaskRepository`만 다룸, `SettingsStore`는 거부 |
| `day_budget` | §11 JSON(가용 시간은 분, 늘린 분 따로) | 없음 | 가용 시간 답(직접 적기 포함), 늘리기, 쓴 시간, "더 할래요" |
| `last_start_day` | `LocalDay` 글자 | 없음 | 시작 커밋(§6) |

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
| `customBudgetMinutesRange` | `30...960` | spec R-419 직접 적기(사용자 결정 2026-11-16), 범위는 에이전트 가정 |
| `customBudgetStepMinutes` | 30 | 같음 |
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
- 가용 시간 답(직접 적기 포함), "더 할래요", 늘리기: 줄 없음(R-416, §11 늘리기).

`ValueTypeTests`의 `allCases` 단언은 새 값을 끝에 더하는 것으로 고친다(값을 빼지 않는다, 계약 덧붙이기).

## §17 3초 뒤 자동 시작 (R-410)

`AutoStart.shouldStart(enabled:mode:draftShownAt:lastInputAt:gateBusy:extendNeeded:startFailed:now:) -> Bool`: 켜짐 && 모드가 §12-6의 초안 && 게이트가 묻거나 확인하는 중이 아님(그 할 일의 지금 판단 입력에 대한 판단 결과를 기다리는 동안은 시작하지 않는다(R-306). 기다림은 `ConcreteGate.awaitsJudgment`: 초안이고 통과 전이고 물을 수 있고 임계값이 있는데 지금 해시의 판단 결과가 없고 그 해시가 실패로 적히지 않음, `gateBusy`에 함께 넣는다) && 늘리기 확인 줄이 닫혀 있음(`extendNeeded == nil`, 곧 칩 ≤ 남은 분이거나 상한이 없음, §11 "늘리기") && 시작 실패 문구("시작하지 못했어요. 다시 해 주세요.", §11)가 떠 있지 않음(`startFailed == false`, 메인 세션 가정: 실패를 사람이 보고 직접 누르게 하려고 자동 시작은 다시 시도하지 않는다. 사용자가 칩·버튼을 누르면 문구가 사라지고 다시 3초를 센다) && `now - max(draftShownAt, lastInputAt) ≥ Defaults.autoStartDelay`. 남은 10분에서 25분 칩을 고르면 확인 줄이 열려 자동 시작하지 않는다. 늘리기는 사용자가 눌러야 한다. 앱은 초안이 뜰 때 한 번 일정을 걸고, 입력이 있으면 다시 건다. 시간은 주입한 시계로 시험한다.

## §18 "내일" 표시 (R-423)

`TomorrowMark.ids(order:remainingMinutes:defaultQuantumMin:) -> Set<TaskID>`: `capActive`일 때만. 후보 순서대로 `estMin ?? defaultQuantumMin`을 쌓아 합이 `remainingMinutes`를 넘는 할 일부터 표시한다. 진행 중 할 일은 쌓지 않는다(가정). 상한이 없으면 빈 집합.

## §19 화면 값과 스냅샷 이름

화면 글자는 확정 시안 `~/Dev/ai-platform/projects/moka/design/005-mockup.html`(저장소 밖)의 글자를 그대로 쓴다. 값을 끼워 넣는 글자(남은 개수, 남은 분, 시간, D+N)는 MokaCore(`NotchStatus.swift` 무늬, #42)에, 고정 글자는 뷰 상수에 둔다.

- MokaCore 글자 함수: `CarryText.reason(_:)`, `CarryText.left(_:)`, `BudgetText.capNote(minutes:expired:)`, `BudgetText.customAbove(minutes:)`(시간 끝만), `BudgetText.extendTitle(extra:chip:)`, `BudgetText.extendDetail(remaining:newTotal:)`, `BudgetText.keepRemaining(minutes:)`, `BudgetInputIssue` 문구 넷, `BudgetText.dayEndOff(minutes:)`, `BudgetText.dayEndTitle(minutes:)`, `NotchStatus.label`의 새 경우("오늘 정하기", "날짜 바꾸기", "오늘 끝").
- 뷰 상수: `CarryText` 버튼 셋, 질문 문구, 오늘 끝 문구, "더 할래요", 접힌 노치 글자, 할 일 탭 "오늘 정할 일"과 "내일", 기본 탭 자동 시작 칸.

스냅샷 이름(라이트·다크): `test_R414_carryCardTouched`, `test_R414_carryCardOverdueLast`, `test_R415_datePicker`, `test_R419_askBudget`, `test_R419_askBudgetCustom`, `test_R419_askBudgetCustomInvalid`, `test_R421_draftCapped`, `test_R421_extendConfirm`, `test_R409_expiredCapped`, `test_R422_expiredDayEnd`, `test_R422_dayEnd`, `test_R414_collapsedCarry`, `test_R419_collapsedAskBudget`, `test_R422_collapsedDayEnd`, `test_R413_taskTabDue`, `test_R423_taskTabTomorrow`, `test_R410_basicTabAutoStart`. 확정 시안 번호와 같은 순서다.
