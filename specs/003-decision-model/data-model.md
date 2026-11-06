# Data Model: 판단 모델 연동 MVP (spec 003)

규칙의 원본이다. 결정 이유는 [research.md](research.md), 외부 계약은 [contracts/](contracts/). 이름은 GLOSSARY를 따른다. 타입 이름은 구현 PR에서 다듬을 수 있으나 바꾸면 PR "가정"에 적는다.

## 1. MokaCore 값 타입 (새로 둠)

| 타입 | 모양 | 비고 |
|---|---|---|
| `QuestionSet` | `version: String`, `language: String`, `model: String`, `questions: [String: Question]`, `thresholds: [String: [String: Double]]` | `questions.json`을 읽은 값(contracts/questions-json.md). `QuestionSet.bundled()`는 `Bundle.module`에서 읽는다. 임계값은 `thresholds[model]` |
| `Question` | `noul(instructions)`, `score(instructions, criteria: [String])` | noul은 "이 문장이 참일 확률" 하나를 받는 질문, score는 낮음→높음 옵션 중 어디인지를 받는 질문(contracts/decision-provider.md "질문 타입") |
| `JudgmentState` | `today: LocalDay`, `weekday: Weekday`, `task: StateTask`, `contexts: [StateContext]`, `checkpoint: StateCheckpoint?` | 판단 입력. 저장하지 않는다 |
| `StateTask` | `title`, `deadline: LocalDay?`, `estMin: Int?`, `firstAction: String?` | 금지 필드 없음(§4) |
| `StateContext` | `name`, `date: LocalDay`, `impact: ContextImpact` | 보낼 때 "조금/꽤/아주" |
| `StateCheckpoint` | `done: String`, `next: String` | §4 |
| `DecisionRequest` | `model: String`, `state: [UInt8]`(정준 바이트), `questions: QuestionSet` | |
| `DecisionResponse` | `model: String?`, `answers: [String: Answer]` | |
| `Answer` | `noul(p)`, `score(score, confidence, probabilities: [Int: Double])` | |
| `DecisionError` | `missingKey`, `unauthorized`(401·403), `rateLimited`(429), `overloaded`(529), `timeout`, `network`, `server(status)`, `malformed` | 동작은 셋으로 나뉜다: `unauthorized`는 질의를 멈추고 문구를 켬(§6), 나머지는 그 할 일 실패로 기록(§6). 종류는 로그용이다 |
| `protocol DecisionProvider: Sendable` | `var name: String { get }`, `func decide(_: DecisionRequest) async throws(DecisionError) -> DecisionResponse` | 앱 `TypeSafeProvider`의 `name`은 `"typesafe"`. 가짜는 `FakeDecisionProvider`(정한 답 또는 정한 오류를 돌려주고, 동시에 진행 중인 최대 개수를 센다) |
| `TaskScore` | `taskID`, `questionVersion`, `provider`, `modelSnapshot: String?`, `urgency`(0~1), `impact`(0~1), `concrete`(0~1), `avoiding`(0~1), `probsJSON: String`, `stateHash: String`, `scoredAt: Date` | `scores` 한 줄. priority는 없다 |
| `protocol ScoreStore: AnyObject` | `func scores() throws -> [TaskID: TaskScore]`, `func upsertScore(_: TaskScore) throws` | 메모리 `InMemoryScoreStore`(MokaCore), GRDB `GRDBScoreStore`(MokaStore). 지우기 메서드 없음 |
| `protocol KeyStore: AnyObject` | `func hasKey() throws -> Bool`, `func read() throws -> String?`, `func save(_: String) throws`, `func delete() throws` | 가짜 `InMemoryKeyStore`(MokaCore, 정한 오류를 던질 수 있음). 앱 `KeychainKeyStore` |

`Defaults`에 더하는 값(이전 값 없음, 새 값): `weightUrgency 1.0`, `weightImpact 0.7`, `weightAging 0.8`, `avoidingAgingFactor 1.5`, `decisionTimeout 3초`, `maxConcurrentDecisions 4`. 질문 임계값은 `questions.json`(AGENTS.md).

`SchedulerChoice`에 `priorityRotateV0 = "priority_rotate_v0"`를 더한다. `rotateByIDV0`는 남긴다(이전 로그를 읽어야 한다). 앱과 시뮬레이터의 새 로그 줄은 늘 `priorityRotateV0`이다.

## 2. 스키마: 마이그레이션 `v3_scores`

```sql
CREATE TABLE scores(
  task_id INTEGER PRIMARY KEY NOT NULL REFERENCES tasks(id) ON DELETE RESTRICT,
  question_version TEXT NOT NULL,
  provider TEXT NOT NULL,
  model_snapshot TEXT,
  urgency REAL NOT NULL,
  impact REAL NOT NULL,
  concrete REAL NOT NULL,
  avoiding REAL NOT NULL,
  probs_json TEXT NOT NULL,
  state_hash TEXT NOT NULL,
  scored_at TEXT NOT NULL
);
```

- CHECK 없음(사용자 승인 조건). `provider`에 `fallback`은 들어가지 않는다(폴백은 판단 결과를 저장하지 않는다).
- `upsertScore`는 `INSERT … ON CONFLICT(task_id) DO UPDATE`로 덮어쓴다. 이전 값은 남기지 않는다(버튼을 누른 순간의 판단 결과는 행동 로그에 남는다).
- 마이그레이션 이름 시험 리터럴을 `["v1_settings", "v2_tasks_contexts_checkpoints_log", "v3_scores"]`로 덧붙인다(ADR-0007). `schema/moka-schema.sql` 스냅샷을 갱신한다.
- 시각은 spec 002처럼 UTC 초 문자열(`UTCTimestamp`).
- `probs_json`은 응답 답을 정준 JSON으로 적은 것이다: 질문 이름 오름차순 객체, noul은 `{"noul":p}`, score는 `{"score":s,"confidence":c,"probabilities":{"0":p0,…}}`. 행동 로그 `probs_json`에 그대로 옮긴다. 할 일 제목·체크포인트 본문은 없다.
- pytest: `scores` 열 이름 집합 시험(`tuning/tests/test_schema_contract.py`에 덧붙임), `questions.json`을 같은 경로로 읽는 시험.

## 3. 판단 결과 규칙

- **해석**(`ScoreRules.score(taskID:response:questions:provider:stateHash:now:)`): 질문 넷이 모두 있고 타입이 질문 파일과 맞고 noul 확률이 0~1, score 값이 0~(옵션 수 − 1), 확률이 0~1이어야 한다. 하나라도 어긋나면 `malformed`로 보고 판단 결과를 만들지 않는다.
- **정규화**: `urgency = score / (urgency 옵션 수 − 1)`(지금 3), `impact = score / (impact 옵션 수 − 1)`(지금 2). noul은 그대로. 저장하는 값은 하한을 적용하기 전의 정규화 값이다.
- **urgency 하한**: 고르는 날의 오늘(spec 002 R-114 하루 경계) 기준으로 마감이 내일까지(지난 마감 포함)이면 urgency를 1로 본다. 날이 바뀌면 달라지므로 priority 계산 때 적용한다.
- **aging** = `skipCount × (avoiding ≥ thresholds[model].avoiding ? 1.5 : 1)`. 이월 횟수는 마일스톤 4.
- **priority** = `1.0 × urgency' + 0.7 × impact + 0.8 × aging`(urgency'는 하한 적용 뒤). 고를 때마다 계산한다.
- **쓰는 판단 결과**(`ScoreRules.usable(scores:hasKey:questionVersion:) -> [TaskID: TaskScore]`): 키가 있고 `questionVersion`이 지금 질문 파일 버전과 같은 판단 결과만 남긴다. 판단 입력이 바뀐 판단 결과(해시가 다름)도 다시 묻기 전까지는 쓴다. 순서·고르기·로그 함수는 이 사전만 받는다.

## 4. 판단 입력 조립과 금지 필드

`StateBuilder.state(task:contexts:checkpoints:today:calendar:)`는 다음만 넣는다(spec R-201).

| 칸 | 값 |
|---|---|
| `today` | `"YYYY-MM-DD (요일)"`, 요일은 일·월·화·수·목·금·토. 오늘은 spec 002 R-114 하루 경계(`MokaClock` + `DayStart`) |
| `context` | 모든 일정(날짜 오름차순, 같으면 id 순). `{"name","date","impact"}`, date는 `YYYY-MM-DD`, impact는 "조금/꽤/아주" |
| `task` | `{"title", "deadline"?, "est_min"?, "first_action"?}`. deadline은 `YYYY-MM-DD`. 값이 없으면 키를 뺀다 |
| `checkpoint` | 그 할 일의 체크포인트 가운데 두 줄 중 하나라도 적힌 것의 id가 가장 큰 것 `{"done","next"}`. 없으면 키를 뺀다. 종료·잠자기처럼 두 줄이 빈 체크포인트는 고르지 않는다 |

- 넣지 않는 것(헌법 VIII, MUST 시험): 다른 할 일, `skip_count`, `carry_count`, `streak`, 상태, 반복, 이전 확률, 행동 로그, 할 일 id, 만든 시각. 시험은 조립한 JSON의 키 집합이 위 표와 정확히 같은지 본다.
- 바이트는 손으로 조립한다: 키 순서는 위 표 순서(`today`, `context`, `task`, `checkpoint`, 안쪽도 표 순서), 공백 없음, 문자열은 RFC 8259 이스케이프(`"`, `\`, U+0000~U+001F), 그 밖의 문자는 UTF-8 그대로. 실수는 넣지 않는다(est_min은 정수).
- 체크포인트는 `TaskRepository.checkpoints()` 전체를 읽어 할 일별로 고른다. 할 일 수십 건, 체크포인트 수백 건 규모라 받아들인다(색인·새 메서드 없음).

## 5. 판단 입력 해시

- `stateHash = FNV-1a 64(state 바이트)`, 소문자 16진수 16자. offset basis `0xcbf29ce484222325`, prime `0x100000001b3`.
- 같은 바이트는 리눅스·macOS에서 같은 해시를 낸다: golden 시험(정한 state 셋 → 정한 해시 셋)을 `swift test`(리눅스 CI)와 macOS 로컬에서 돌린다.
- 보안용이 아니다(research R12).

## 6. 다시 물을 할 일과 보내기 (spec R-206·R-207)

**다시 물을 할 일**(`ScoringPlan.needsQuery(tasks:scores:states:questionVersion:)` → id 오름차순): 대기·진행 중 할 일 가운데 다음 하나에 해당하는 것.
- 판단 결과가 없다
- `questionVersion`이 지금 버전과 다르다
- 지금 판단 입력의 해시가 저장된 `stateHash`와 다르다

**묻지 않는 경우**(AppState가 먼저 본다): 키 없음, `keyNeedsCheck`(401 뒤 키를 다시 저장하기 전), 판단 결과 저장소 없음(앱 DB를 열 수 없음).

**보내기 장부**(AppState 메모리, 저장하지 않음): `attempted: [TaskID: (hash: String, failed: Bool)]`.
- 보낼 때 `attempted[id] = (지금 해시, false)`. 이미 같은 해시로 적혀 있으면(실패 여부와 상관없이) 보내지 않는다.
- 실패(`unauthorized` 아님)하면 `failed = true`로 바꾼다.
- 활성화 때, 보내기 전에 `failed == true`인 항목을 지운다(실패한 할 일은 다음 활성화 때 한 번 다시).
- 키 저장, "다시 물어보기", 앱 재시작(메모리라 저절로)에는 장부를 비운다.
- `unauthorized`면 `keyNeedsCheck = true`로 두고 남은 질의를 보내지 않는다. 키를 저장하거나 지우면 `false`로 돌린다.

**묻는 때**(같은 함수 `requestScores()` 하나를 부름): 할 일 다시 읽기(`reloadTasks`, 노치 빠른 입력·버튼·설정 창 쓰기 모두 거침) 뒤, 일정 다시 읽기(`reloadContexts`) 뒤, 활성화(`activate`) 끝, 키 저장 뒤, "다시 물어보기".

**보내기**: 대상마다 판단 입력을 조립·해시하고, `Task` 하나 안에서 `withTaskGroup`으로 동시에 최대 `maxConcurrentDecisions`(4)개씩 `provider.decide`를 부른다. 취소·우선순위·백오프 없음.

**답 받기**(`ScoringPlan.accepts(requestHash:currentHash:taskStatus:)`, MainActor): 답이 왔을 때 그 할 일의 지금 판단 입력을 다시 조립해 해시가 요청 때와 같고, 할 일이 대기·진행 중일 때만 `ScoreRules.score` → `upsertScore` 한다. 다르면 버린다(질의 중 고침·일정 변경·버림·완료). 같은 할 일에 질의가 겹치면 각 답이 이 판정을 따로 거치므로 지금 입력과 맞는 답만 남는다.

## 7. 노치 순서와 고르기 (spec R-208·R-209)

`PriorityOrder.order(tasks:usable:questions:today:calendar:)` → 대기 할 일 순서.

1. 점수 있는 대기 할 일(`usable`에 있음): priority 내림차순, 같으면 아래 2의 비교.
2. 점수 없는 대기 할 일: 마감 오름차순(마감 없음 맨 뒤), 같으면 id 순. 이 비교는 기존 `TaskListView.rows(order: .deadline)`의 비교(`Sources/MokaCore/TaskListView.swift`)를 꺼내 함께 쓴다(`OtherTaskList`도 쓰는 것).

`PriorityRotateRule.pick(order:after:)`: `after`가 없거나 순서에 없으면 1위, 있으면 그다음(끝이면 1위). 후보가 하나면 그 할 일. `NotchSession.picked`와 `nextMark`가 `RotateByIDRule` 대신 이것을 쓴다. `NotchSession`에는 `SessionInput`으로 `usable` 사전·질문 세트·오늘을 넘긴다.

- 순서는 버튼 처리(미룬 횟수 반영)를 저장한 뒤의 할 일로 계산한다. 기존 패턴(커밋 뒤 `pickIfEmpty`)과 같다.
- 실행 중·시간 끝·초안 상태는 바꾸지 않는다(고르기는 빈 상태에서만, spec 002와 같음).
- "다른 할 일" 목록(`OtherTaskList`)은 그대로 급한 순이다.
- 키가 없으면 `usable`이 비어 모든 할 일이 2의 순서다. spec 002의 만든 순서 순환을 대신한다(spec R-209). 그래서 spec 002 storage 시뮬레이터 golden의 기대 출력이 바뀐다(§11).

## 8. 행동 로그 판단 칸 (spec R-212)

`NotchSession.logLine`이 줄을 만들 때:

| 그 할 일 | `judgment` | `model_snapshot` | `scheduler_choice` |
|---|---|---|---|
| `usable`에 있음 | `provider`, `questionVersion`, `probsJSON`, `stateHash`는 저장된 `TaskScore` 값 | `TaskScore.modelSnapshot` | `priority_rotate_v0` |
| 없음 | `provider = "fallback"`, 나머지 비움 | 비움 | `priority_rotate_v0` |

spec 002 F5 CHECK(공급자가 없으면 나머지도 비어야 함)에 걸리지 않는다. 제목·두 줄 본문은 판단 칸에 없다.

## 9. 앱 상태 (AppState에 더함)

- 저장소: `AppStorage`에 `scores: (any ScoreStore)?`(DB를 열지 못하면 `nil`, spec 002 R-119처럼 메모리로 대체하지 않는다)와 `keyStore: any KeyStore`. 공급자는 `any DecisionProvider`로 주입한다. `AppState`는 `TypeSafeProvider`·`KeychainKeyStore`를 직접 가리키지 않는다(앱 시험 번들이 그 파일을 컴파일하지 않는다).
- 메모리 값: `hasKey`(앱 시작·키 저장·키 지움 때 `KeyStore.hasKey()`로 갱신, 던지면 `false`), `keyNeedsCheck`, `keyActionFailed`(저장·지우기가 던지면 `true`, 다음 성공에 `false`), `attempted`(§6), `scores` 사전(저장소에서 다시 읽음).
- 질의 흐름은 §6. `TypeSafeProvider`는 질의 때마다 `KeyStore.read()`로 키를 읽는다. 던지거나 `nil`이면 `missingKey`.
- 답을 저장한 뒤 `scores`를 다시 읽고 "다음" 표시와 설정 창 priority 칸을 다시 계산한다. 질의 중에도 노치·타이머·버튼은 막히지 않는다.

## 10. 설정 창 화면 상태 (시안으로 확정)

| 상태 | 기본 탭 키 칸 |
|---|---|
| 키 없음 | 안내 한 줄 + 붙여 넣기 칸(가림 입력) + "저장"(칸이 비면 꺼짐) |
| 키 있음, 할 일 있음 | "저장돼 있어요" + "지우기" + "다시 물어보기"(다시 물을 할 일이 없으면 꺼짐) |
| 키 있음, 할 일 없음 | 위 + "할 일을 저장하면 키가 맞는지 확인돼요" |
| 키 확인 필요(401) | 위 + 키를 다시 확인해 달라는 문구(경고색) |
| 저장·지우기 실패 | 그 상태 + 다시 해 달라는 문구 |
| 저장 불가(spec 002 R-119) | 키 칸은 보이되 "다시 물어보기" 꺼짐 |

할 일 탭: 줄마다 priority 칸(소수 둘째 자리 반올림, 점수 없으면 빈칸). 문구는 시안에서 정하고 해요체다.

## 11. 기존 기대 출력 갱신 (사용자 결정 2026-11-07)

- 바뀌는 것: spec 002 storage 시뮬레이터 golden(`Tests/MokaCoreTests/Fixtures/sim/storage-*.expected.jsonl`)의 `notch_task` 순서와 `decision.scheduler_choice`(`rotate_by_id_v0` → `priority_rotate_v0`). 키가 없으므로 마감일 순이 된다. 시나리오 입력은 지우거나 바꾸지 않는다.
- 바뀌지 않는 것: spec 001 타이머 golden(storage 아님), 이미 쌓인 앱 DB의 `rotate_by_id_v0` 로그 줄.
- 갱신은 R-209 구현 PR(단위 2) 안에서 하고, PR 본문에 "spec 002 R-104 → spec 003 R-209 규칙 교체, 테스트 약화 아님"과 바뀐 시나리오·줄 목록을 적는다.
