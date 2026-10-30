# Research: 저장과 체크포인트 (spec 002)

이 문서가 결정 근거와 대안의 원본이다. 규칙 자체는 [data-model.md](data-model.md), 범위·요구는 [spec.md](spec.md)에 있다.

승인 항목 P1~P8은 토론(`.audit/debate/20261030-plan002-approvals.md`, 커밋 안 함)으로 추천안을 만들었고 사용자가 2026-10-30 정했다. P1·P2·P4~P8은 3:0, P3는 2:1(A·B / C)이고 사용자가 (c)를 골랐다. `model_snapshot`은 사용자 위임이다. 후속 결정 F1~F6은 토론(`.audit/debate/20261030-plan002-followups.md`, 커밋 안 함)을 거쳐 같은 날 사용자가 정했다(plan "후속 결정"). EGM 금붕어 리뷰(`.audit/egm/002/`, 커밋 안 함) 뒤 승인 항목 Q1~Q5는 토론(`.audit/debate/20261030-1720-spec002-egm-approvals.md`, 커밋 안 함)을 거쳐 같은 날 사용자가 추천안 그대로 골랐다(R18~R21, R6~R8·R10·R16 갱신). 기술 설계서(`~/Dev/ai-platform/projects/moka/tech-design.md`, 이하 "설계서")와 PRD는 재료로 쓰고, 채택된 ADR과 어긋나면 ADR을 따른다. 토론 기록은 커밋하지 않으므로 결정 요지와 기각 이유는 이 문서에 적는다. 확인하지 못한 외부 사실은 "미확인"으로 적는다.

## R1. 첫 저장 마이그레이션의 범위 (P1 (b), 3:0)

- **Decision**: 새 마이그레이션 `v2_tasks_contexts_checkpoints_log` 하나. `v1_settings` 뒤에 등록하고 이름 시험 리터럴을 `["v1_settings", "v2_tasks_contexts_checkpoints_log"]`로 덧붙인다(ADR-0007). 표는 `tasks`, `contexts`, `checkpoints`, `decisions_log` 넷. `scores`·`labels`는 쓰는 단계(마일스톤 3·5)에서 새 마이그레이션으로 만든다. SQL 전문은 data-model §7.
- **Rationale**: `scores`·`labels`는 PRD 9장과 설계서의 열이 이미 다르다(설계서의 `state_json`, `model_snapshot`). 쓰는 코드가 없을 때 열을 고정하면 추측이 된다. spec 위험 2가 미리 두라고 한 것은 로그의 판단 칸이지 표가 아니다.
- **Alternatives**: (a) PRD 9장 표 여섯을 모두 지금(추측한 열이 전진 전용 마이그레이션에 묶임), 표마다 마이그레이션 하나(이름 목록만 길어짐).
- **`tasks` 열 범위 (F1, 3:0 승인)**: PRD 9장 `tasks` 열 가운데 이번 단계가 쓰는 열만 둔다. `quantum_min`(할 일별 마지막 칩, FR-05), `is_urgent`(FR-19), `carry_count`·`due_decision`(FR-08), 설계서의 `paused_until`(FR-20)은 빼고, 쓰는 단계에서 `ADD COLUMN … NOT NULL DEFAULT 0`(또는 NULL 허용)으로 더한다. SQLite `ADD COLUMN`은 상수 기본값이 있으면 `NOT NULL`도 받으므로 표를 다시 만들 일이 없다. 판단 칸과 달리 이 열들은 튜닝 스크립트 계약이 아니다.

## R2. 매주 반복 요일 (P2 (a), 3:0)

- **Decision**: `tasks.weekday INTEGER` NULL 허용. 1(일)~7(토)이고 Foundation `Calendar.component(.weekday, from:)`와 같은 번호다. `CHECK(weekday BETWEEN 1 AND 7)`, `CHECK((recurrence = 'weekly') = (weekday IS NOT NULL))`. 요일 비교는 MokaCore 순수 함수가 주입한 `Calendar`로 한다. SQL `strftime('%w')`(0=일)는 쓰지 않는다. 기본값은 할 일을 등록한 순간이 속한 하루(R9)의 요일이다(data-model §5.8).
- **Rationale**: 번호를 Foundation과 맞추면 변환 코드가 없다. SQL에서 요일을 계산하지 않으므로 SQLite의 0 기반 번호와 섞이지 않는다.
- **Alternatives**: `recurrence` 문자열에 넣기(`weekly:3`, CHECK와 파이썬 읽기가 어려움), 별도 표(요일 하나뿐인데 과함).

## R3. 열거 값의 강제 위치 (P3 (c), 2:1 A·B / C, 사용자 결정)

- **Decision**: 닫힌 칸에만 SQLite `CHECK`를 둔다: `tasks.status`(`todo`/`active`/`done`/`dropped`), `tasks.recurrence`(`none`/`daily`/`weekly`), `tasks.weekday`, `tasks.cycle_day`(반복 짝, F2로 더함), `contexts.impact`(`normal`/`high`/`critical`), `checkpoints.trigger`(여덟 값). `decisions_log.user_action`·`scheduler_choice`는 CHECK 없는 TEXT이고, MokaCore 열거형의 `rawValue`로만 쓴다. 저장소가 모르는 값을 읽으면 `StoreError.unknownValue`로 실패한다. 이 실패를 시험으로 고정한다(원시 SQL로 넣은 `'mystery'` 줄을 읽으면 throw).
- **Rationale**: 사용자 결정 이유(요지): 여러 사람이 쓰는 서비스가 아니라 각자 자기 컴퓨터에서 돌리는 앱이라 `user_action`을 DB에서 엄격히 막지 않아도 된다. 토론 사실 확인: PRD의 `user_action` 여덟 값에 긴급·일시 중지·연장이 없고, FR-11 "모든 버튼·카드 입력을 기록"과 맞지 않는 PRD 공백이 있다. 값 목록이 아직 움직이는 칸에 CHECK를 걸면 값을 더할 때마다 표를 다시 만들어야 한다.
- **`trigger`는 왜 안 쓰는 값까지 CHECK에 넣나**: 계기 여덟 값은 PRD FR-07이 이미 닫아 둔 목록이고(R-108), 쓰는 단계(긴급·일시 중지·하루 끝)마다 표를 다시 만들지 않으려고 지금 다 넣는다. `user_action`은 PRD 목록 자체가 비어 있어(위) 닫힌 목록이 아니다. 두 칸의 기준은 "목록이 닫혔는가" 하나다.
- **소수 의견(C)**: PRD 전체 값으로 CHECK를 걸자. 긴급은 `scheduler_choice`, 연장은 `user_action`이 아니라서 늘어날 근거는 일시 중지 하나뿐이고, CHECK 없는 append-only 로그의 오염이 더 무겁다.
- **재검토 조건**: 앱 밖 쓰기 경로(튜닝 스크립트의 쓰기, 라벨셋 가져오기)가 생기면 다시 본다(plan 위험 3).
- **`UserAction` 값 범위 (plan "가정")**: 열거형에는 이번에 쓰는 `done`·`skip`·`switch`만 둔다. PRD의 `carry_today`·`carry_drop`·`carry_move`·`working`·`first_action_ok`는 쓰는 단계에서 덧붙인다. TEXT 칸이라 스키마 변경이 아니다. `SchedulerChoice`는 `rotate_by_id_v0` 하나다(R18).
- **`contexts.impact` 값**: 저장과 코드는 `normal`·`high`·`critical`, 화면 이름은 "중요도"이고 차례로 조금·꽤·아주다(시안 v2, GLOSSARY). 판단 질문 `impact`(손해 확률)와 이름이 같지만 다른 것이다.

## R4. 할 일 삭제와 보존 (P4 (a), 3:0)

- **Decision**: 할 일은 지우지 않는다. 설정 창의 "지우기"는 `status = 'dropped'`로 바꾸는 소프트 삭제다. `checkpoints.task_id`, `decisions_log.task_id`는 `REFERENCES tasks(id) ON DELETE RESTRICT`. 버린 할 일은 노치 후보(R-104)와 반복 리셋(R-113)에서 빠진다. 두 규칙을 Red 시험으로 먼저 둔다. 설정 창 목록은 버린 할 일을 보이지 않는다.
- **가정**: 설정 창 지움·고침은 행동 로그와 체크포인트를 남기지 않는다. R-112의 로그 대상은 완료와 미루기·바꾸기의 등록·안 적기다. 도는 할 일을 지우면 그 회차의 경과 분도 남지 않는다.
- **알려진 위험**: 버린 할 일의 제목은 영구히 남는다(plan 위험 4).
- **Rationale**: spec Edge Cases "지운 할 일의 로그와 체크포인트는 남는다", 설계서 §2 "외래 키는 전부 ON DELETE RESTRICT". RESTRICT는 실수로 들어간 실제 DELETE를 DB가 막는다.
- **Alternatives**: 실제 삭제 + 외래 키 없이 `task_id`만 남김(고아 줄), `ON DELETE SET NULL`(튜닝이 할 일과 로그를 잇지 못함).
- 컨텍스트는 다른 표가 가리키지 않으므로 실제로 지운다(`DELETE`).

## R5. `decisions_log` 열과 마일스톤 2 값 (P5 (a), 3:0, `model_snapshot` 사용자 위임)

- **Decision**: 열은 PRD 9장 전부(`id`, `task_id`, `question_version`, `provider`, `probs_json`, `state_hash`, `scheduler_choice`, `user_action`, `created_at`)에 `model_snapshot`을 더한다. 판단 칸 `question_version`, `provider`, `probs_json`, `state_hash`, `model_snapshot`은 NULL 허용. 마일스톤 2 줄은 판단 칸이 모두 NULL이고 `scheduler_choice = 'rotate_by_id_v0'`이다. 원문 텍스트(제목, 두 줄, 컨텍스트 이름)는 판단 칸에 넣지 않는다. 저장 프로토콜에는 덧붙이기만 있고 수정·삭제 메서드가 없다.
- **CHECK (F5, 3:0, P5 문구 변경 사용자 재승인, EGM 뒤 Q2d 3:0으로 유지)**: 두 개다. `CHECK(provider IS NOT NULL OR (question_version IS NULL AND probs_json IS NULL AND state_hash IS NULL))`와 `CHECK(model_snapshot IS NULL OR provider IS NOT NULL)`. 뜻: 공급자가 없으면 다른 판단 칸과 `model_snapshot`도 모두 비어야 한다. 공급자가 있으면 나머지는 비어도 된다.
- **지금 두는 이유(Q2d)**: SQLite는 기존 표에 CHECK를 더하는 `ALTER`가 없어 표를 다시 만드는 일반 절차가 필요하다(https://www.sqlite.org/lang_altertable.html, "adding CHECK or FOREIGN KEY or NOT NULL constraints"). 마일스톤 3으로 미루면 실제 로그가 쌓인 표를 다시 만들어야 한다. 지금은 표가 비어 있고, 마일스톤 2 줄은 판단 칸이 모두 NULL이라 이 CHECK에 걸릴 일이 없다.
- **처음 안(넷 전부-NULL/전부-값)에서 바꾼 이유**: 코드 폴백은 공급자 `fallback`으로 로그하지만 질문 버전·확률이 없을 수 있다(tech-design.md:155). 처음 안은 이 줄을 막는다. 공급자를 기준으로 삼으면 "판단 없는 줄"(공급자 NULL)과 "판단 있는 줄"(공급자 있음)이 여전히 갈리고(R-112), 폴백 줄도 들어간다. `model_snapshot`은 응답에 모델 이름 필드가 없을 수 있어(응답 형식은 마일스톤 3에서 확인, 미확인) 공급자가 있어도 비어도 된다.
- 형태 소수 의견(C): 두 CHECK를 한 식으로 묶자. 허용 집합은 같다.
- **Rationale**: 나중에 `ADD COLUMN`으로 더해도 NULL 허용 열만 될 수 있다. 지금 넣으면 마일스톤 3에서 튜닝 계약 변경이 한 번 준다(토론 A 추천, 사용자 위임). 판단 칸이 비어 있는 줄이 점수 있는 줄과 구분되어야 한다(R-112).
- **Alternatives**: 마일스톤 2는 최소 열만, 판단 칸은 마일스톤 3에서 `ADD COLUMN`(계약 승인이 두 번). EGM 리뷰 권고 "F5 CHECK를 마일스톤 3으로"(Q2d, 위 이유로 기각).
- `question_version`은 TEXT다. `questions.json` 버전 표기가 아직 없어서 정수로 고정하지 않는다.
- 남은 사실: 폴백 모양이 PRD(prd.md:74, 마감일 정렬)와 설계서(tech-design.md:155, 0.5 합성 확률)에서 다르다. 마일스톤 3에서 정한다(plan 위험 2).

## R6. `moka-sim` 확장 (P6 (a) 3:0, 이벤트 범위는 EGM 뒤 Q2c 3:0)

- **Decision**: [contracts/moka-sim-v1-additions.md](contracts/moka-sim-v1-additions.md). `version: 1`을 유지하고 최상위 선택 필드 `storage`(불리언)를 더한다. `storage: true`일 때만 새 이벤트를 받고, 모든 출력 줄 끝에 새 키를 덧붙인다. 없거나 `false`면 지금 v1 동작 그대로다. 그래서 기존 golden 출력은 바이트 그대로 통과한다. 이것이 통과 조건이다. 출력에 제목·두 줄 본문은 넣지 않고 "비었는지"만 넣는다. DB 경로 인자는 없다(메모리 저장소). 계약 원본 `specs/001-notch-timer/contracts/moka-sim-v1.md`는 구현 PR(작업 단위 3)에서 반영한다.
- **새 이벤트는 R-117 목록과 `activate`만 (Q2c, 사용자 결정 2026-10-30)**: `add_task`(추가), `skip`·`switch`(미루기·바꾸기와 두 줄), `quit`(종료), `relaunch`(재시작), `activate`(시각 경과 뒤 하루 판정). 완료·체크포인트·시간 끝은 기존 `complete`·`start`·`tick`에 두 줄 필드를 붙여 쓴다. 고침(`edit_task`)·지움(`delete_task`)·하루 시작 변경(`set_day_start`)·잠자기(`sleep`)는 넣지 않는다. 같은 규칙은 MokaCore 단위 시험(세션 지움·고침, 잠자기 체크포인트, 하루 시작 변경 뒤 되돌리지 않음)이 덮는다. 계약은 덧붙이기가 싸고 빼기는 계약 위반이라, 필요해지면 그때 v1 규칙대로 덧붙인다.
- **그대로 못 지키면**: 계약 2026-10-29 단서(moka-sim-v1.md:110)대로 바뀐 기대 출력을 그 PR "사람이 볼 결정"에 올리고 같은 PR에서 기대 출력 파일을 고친다.
- **Rationale**: 계약 버전 규칙 "선택 필드와 이벤트 종류를 덧붙이는 것은 `version: 1`을 유지한다". 모드 필드로 갈라 두면 기존 시나리오의 코드 경로가 바뀌지 않는다.
- **Alternatives**: v2 계약 문서를 따로(시나리오 두 벌, 같은 실행기에 분기 둘), 모드 없이 기존 이벤트에 저장을 붙임(기존 시나리오의 `enter_title`이 할 일을 만들어 출력이 바뀔 위험), 이벤트 열 종을 모두 넣음(처음 안, Q2c로 기각: 승인 표면과 오류 규칙만 늘고 같은 규칙을 두 번 고정).
- **이벤트 모양 (F6, 3:0 승인)**: 버튼과 두 줄 입력은 한 이벤트다(`switch` + 선택 필드 `done_note`·`next_note`). 앱에서도 버튼 → 입력 → 등록/안 적기가 한 동작이라, 입력 대기 단계를 시뮬레이터에 두지 않는다. 완료 버튼은 기존 `complete`를 쓴다. 같은 버튼에 이름 둘을 두지 않는다. 돌아가기와 "다른 할 일"(초안 넘기기)은 기록이 없는 화면 동작이라 이벤트가 없다.

## R7. 저장소 모듈 경계 (P7 (a), 3:0)

- **Decision**: 저장 프로토콜(`TaskRepository`, `ContextStore`)과 메모리 구현은 MokaCore, GRDB 구현은 MokaStore. `moka-sim`은 MokaCore만 의존하고 메모리 구현으로 돈다. 규칙(R-104 고르기, R-113 리셋·멱등, R-114 하루 경계, R-111 복구)은 MokaCore 순수 함수다. 버튼 하나의 쓰기는 MokaCore가 값(`StoreBatch`)으로 만들고 저장소가 한 트랜잭션으로 적용한다.
- **공용 계약 시험**: `MokaStoreTests`에 둔다. 이 타깃은 MokaCore와 MokaStore를 둘 다 보므로 Sendable 구현 선택 열거형을 인자로 같은 시험을 두 구현에 돌린다(data-model §3). `Package.swift`를 바꾸지 않는다.
- **GRDB로 storage golden 다시 돌리기는 뺐다 (Q2e, 2:1 A·B / C, 사용자 결정 2026-10-30)**: 대신 공용 계약 시험에 두 사례를 더한다(초 아래 값이 든 시각 왕복, `StoreBatch` 셋 이상 뒤 id 순서·값, data-model §3). 그래서 `SimRunner`에 저장소를 주입하는 공개 진입점이 필요 없고, 단위 3이 단위 2에 기대지 않는다. 소수 의견(C): 대체 시험이 목록에 생기기 전에는 유일한 종단 저장 검증이라 남기자 — 다수안이 그 대체 시험을 함께 넣는 것으로 답했다.
- **`latestCheckpoint`는 뺐다 (Q2e, 3:0)**: 이어서 할 일은 `tasks.first_action`에서 읽으므로 이번 단계에 쓰는 곳이 없다. 판단 state(마일스톤 3)에서 쓸 때 더한다.
- **Rationale**: spec 001 plan:71에서 `moka-sim`의 MokaStore 의존을 사용자 승인으로 뺐다. 같은 패턴(`SettingsStore`)이 이미 있다. 버튼 쓰기를 값으로 만들면 GRDB 쓰기 재진입(`write` 안에서 `write`) 없이 트랜잭션 하나로 묶인다.
- **Alternatives**: 저장 로직을 MokaStore에만 두고 `moka-sim`이 MokaStore 메모리 DB에 의존(사용자가 뺀 의존을 되돌림), 시험 지원 타깃을 새로 둠(`Package.swift` 변경).

## R8. API 키 보관 — 마일스톤 3으로 미룸 (P8 (a) 3:0, Q2a 3:0, 사용자 결정 2026-10-30)

- **Decision**: 이번 단계에는 키를 다루는 코드와 화면이 없다. 온보딩은 두 단계(일정 한 건, 기본값 확인)다. `KeyStore` 프로토콜, `KeychainKeyStore`, 온보딩 키 단계는 키를 처음 읽는 마일스톤 3에서 설정 창 키 칸(PRD FR-16 "API 키")과 함께 만든다.
- **미룬 이유(Q2a)**: 이번 단계에 키를 읽는 곳이 없어, 저장만 해서는 저장·읽기를 한 증거로 확인할 수 없다. Keychain 구현은 앱 타깃 전용이라 리눅스 CI와 무인 실행으로 확인할 수 없고, 개인 팀 서명 빌드의 확인 창 반복 여부·접근성 속성 같은 미확인 셋이 하루 일정에 몰린다. 키를 건너뛴 사용자가 키를 다시 넣을 화면(설정 창 키 칸)은 어차피 마일스톤 3에 필요하다.
- **마일스톤 3에서 지킬 결정(기록 보존)**:
  - P8 (a): `KeyStore` 프로토콜은 MokaCore(저장·존재 여부·삭제, 값 읽기는 그 단계에서), Keychain 구현은 앱 타깃(ADR-0001, ADR-0005·헌법 보안 절). 시험·`moka-sim`은 가짜 구현.
  - 키 종류(사용자 결정 2026-10-30): MVP 시험 단계의 판단 공급자는 Jev(TypeSafe 직접)만 쓴다. Keychain은 generic password, service `dev.dongwon.moka`, account `typesafe`. OpenRouter(Decision-1)는 나중에 account `openrouter`로 더한다. 범위 토론 Q6의 "OpenRouter 키 하나"를 대체한다.
  - 미확인: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` 같은 접근성 속성과 data protection keychain 사용 조건, 존재 여부 질의가 확인 창을 띄우는지, 다시 빌드할 때 확인 창이 반복되는지(개인 팀 서명 빌드로 사람이 확인, ad-hoc 빌드로는 확인 불가, ADR-0005).
- **Alternatives**: 온보딩 1단계에 키 칸을 두고 Keychain 저장만(처음 안, P8 (a)·범위 토론 Q6 (a), Q2a로 기각). 키 단계만 남기고 확인 창 반복을 spike Issue로 사람 세션에서 미리 보는 안(토론 A 자리의 틀리는 조건, 필요하면 마일스톤 3 전에 따로).

## R9. 하루 경계 계산 (R-114)

- **Decision**: MokaCore `DayBoundary.day(containing:dayStart:calendar:) -> LocalDay` 하나. 달력은 [ADR-0010](../../adr/ADR-0010-day-boundary-calendar.md)을 따른다. 시각 `t`의 지역 달력 날짜를 `d`라 하고, `d`의 하루 시작 순간 `b(d)`를 `calendar.date(bySettingHour:minute:second:of:matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)`로 구한다. `t ≥ b(d)`면 하루는 `d`, 아니면 `d − 1일`이다. 마일스톤 4의 하루 경계(FR-08)도 이 함수를 쓴다.
- 일광절약시간: 하루 시작 시각이 건너뛰는 구간에 있으면 그 뒤 첫 순간(`.nextTime`), 두 번 오는 구간에 있으면 첫 번째(`.first`)가 경계다. 그래서 `t1 ≤ t2`이면 `day(containing: t1) ≤ day(containing: t2)`다(data-model §5.4 단조성 시험). 기본 06:00은 두 시간대(`Asia/Seoul`, `America/New_York`) 모두 전환 구간 밖이다. 시험은 두 시간대와 전환일을 넣는다.
- **달력 (F4, 3:0 승인, ADR-0010)**: 하루 경계와 `LocalDay`는 그레고리력으로 고정하고 시간대는 시스템을 따른다. 생성 함수는 MokaCore `GregorianCalendar.make(timeZone:)`이고 앱은 시간대만 넘긴다(data-model §2.2). ADR-0003은 `Calendar.autoupdatingCurrent`를 적었지만, 사용자 설정에 따라 그레고리력이 아닐 수 있고 그러면 `YYYY-MM-DD`와 `cycle_day`가 영구히 어긋난다. ADR-0010이 ADR-0003의 그 한 문장만 대체한다. 시간대를 `.autoupdatingCurrent`로 한 번 넘겨 둘지, 판정마다 `TimeZone.current`로 새로 만들지는 ADR-0010 결정 검증 시험으로 정하고 결과를 ADR-0010에 덧붙인다(tasks). 시험은 그레고리력에 `Asia/Seoul`·`America/New_York`을 고정한다.
- **Rationale**: ADR-0003 "하루 경계는 설정 `day_start`(기본 06:00)와 주입한 `Calendar`로 계산한다". 경계를 순간 비교로 정하면 시간대·일광절약시간 처리를 Foundation에 맡긴다.
- **Alternatives**: 벽시계 시·분 비교(되풀이 구간에서 하루가 거꾸로 감), UTC 오프셋 고정(일광절약시간이 틀림), SQL `date('now','localtime','-6 hours')`(시험할 수 없음).
- **미확인**: `repeatedTimePolicy`·`matchingPolicy`가 리눅스 Foundation(`swift:6.3.3-noble`)에서 macOS와 같은 결과인지. 단위 1의 첫 시험을 두 환경에서 돌린다. 다르면 경계 계산만 `calendar.dateComponents`로 직접 푼다.

## R10. 반복 리셋 규칙과 `cycle_day` (R-113, F2, EGM 뒤 Q3)

- **Decision**: 반복 할 일에 `cycle_day`(그 할 일이 지금 속한 주기의 첫 하루, `YYYY-MM-DD`)를 둔다. 반복 없음이면 NULL. 판정은 `RecurrenceReset.reset(_:now:dayStart:calendar:)`이고 바뀐 할 일만 돌려준다. 규칙은 data-model §5.3. 요점:
  - 지금 주기의 첫 하루 `c`: 매일은 오늘, 매주는 오늘 이하에서 요일이 맞는 가장 늦은 하루.
  - `cycle_day < c`인 반복 할 일(진행 중·버림 제외)만 바꾼다. 상태는 `todo`, `skip_count`는 0, `cycle_day`는 `c`.
  - 연속 기록: `status = done`이고 `cycle_day`가 바로 앞 주기(`c − 1주기`)면 그대로 잇는다. 아니면 0.
  - 완료할 때 반복 할 일의 `streak`이 1 오른다.
- **멱등**: 한 번 돌면 `cycle_day = c`가 되어 같은 하루에 다시 돌아도 바뀌는 행이 없다. `<` 비교라 하루 시작 시각을 늦춰 오늘이 어제로 바뀌어도 이미 돌린 리셋을 되돌리지 않는다(spec Edge Cases).
- **하루 시작을 넘겨 끝낸 반복 할 일 (Q3, 3:0, 사용자 결정 2026-10-30)**: 따로 판정하지 않는다. 진행 중인 할 일은 하루 판정이 건드리지 않고, 끝낼 때는 버튼 규칙만 적용한다. 결과: 그 주기(어제) 몫 완료로 세고(`streak` + 1), 다음 활성화에 오늘 몫이 대기로 뜬다(data-model §4.1 예). 처음 plan의 "끝낼 때 그 할 일만 먼저 판정"은 지웠다. 그 규칙은 리셋 대상 조건(`active` 제외)과 어긋났고, 계산하면 놓치지 않고 끝낸 사람의 연속 기록을 1로 끊었다. 기각한 다른 뜻: 끝낸 순간 오늘 몫으로 귀속(오늘은 다시 안 뜸, 어제 몫은 놓친 것이 됨).
- **Rationale**: 리셋 여부를 "마지막으로 판정한 주기"로 저장하지 않으면 두 번째 판정과 첫 판정을 구분할 수 없다. 완료 시각만으로는 "하지 않고 지나간 주기"(연속 기록 0)를 알 수 없다.
- **Alternatives**: `last_done_at`(놓친 주기를 모름), 설정에 "마지막 판정일" 하나(할 일을 고치거나 새로 만든 순간의 주기를 모름), 주기마다 새 행(FR-09 "항상 1건"과 어긋남).
- 반복을 새로 걸거나 요일을 바꾸면 `cycle_day`를 지금 주기의 첫 하루로 두고 `streak`은 0으로 둔다. 그 순간에는 리셋하지 않는다(data-model §5.8).
- **CHECK (F2, 토론 2:1 A·C / B, 사용자 결정)**: `CHECK((recurrence = 'none') = (cycle_day IS NULL))`. 이유: 반복 할 일의 `cycle_day`가 비면 `cycleDay < c` 비교에서 그 할 일이 리셋 대상에서 소리 없이 빠진다. 설정 창 같은 앱 경로의 버그는 DB만 막는다. MokaCore 값 검증과 `moka-sim` 불변식도 그대로 둔다. 시험: 원시 SQL로 `daily` + `cycle_day` NULL 거부, `none` + NULL 허용(Swift 공용 계약 시험).
- 소수 의견(B): CHECK 없이 GRDB 왕복 시험과 `moka-sim` 불변식 오류 주입으로 충분하다. 표 수준 CHECK는 나중에 `cycle_day`를 지우거나 뜻을 바꿀 때 `DROP COLUMN`을 막아 표를 다시 만들어야 하고, P3의 사용자 판단(로컬 앱이라 엄격히 막지 않음)과 가벼운 쪽이 맞다.

## R11. 활성화의 정의 (F3, 3:0 승인)

- **Decision**: 하루 판정(R-113)을 도는 "활성화"는 넷이다: 앱 시작(재시작 포함, R-111 복구 뒤), 잠자기에서 깨어남(`NSWorkspace.didWakeNotification`, 기존 `AppState.wakeObserver`에 붙임), 노치 펼침(마우스 올림·클릭), 설정 창 열기. `NSApplication.didBecomeActiveNotification`은 쓰지 않는다.
- **Rationale**: `LSUIElement` 앱의 노치 패널은 `.nonactivatingPanel`이라 앱이 활성화되지 않는다(spec 001 R6). "앱 활성화" 알림으로는 판정이 거의 돌지 않는다. 사용자가 노치를 보는 순간이 판정 시점으로 충분하다. 판정은 멱등이라 여러 번 돌아도 된다. 범위 토론 Q7 소수 의견(C)이 지적한 "활성화 정의가 비어 있음"을 여기서 채운다.
- **Alternatives**: 1분 주기 타이머(앱이 쉬는 동안에도 돎), 06:00 예약 타이머(잠자기·시계 변경에 약함). 설계서 tech-design.md:193은 06:00 타이머를 둔다. 뺀 차이는 plan "가정"에 적었다.
- 판정 결과로 노치가 빈 상태(초안 없음)면 R-104로 다시 고른다. 초안이 떠 있으면 그대로 둔다(할 일 탭 "다음" 표시는 초안을 가리킨다, data-model §4.2).

## R12. 종료·잠자기 체크포인트 기록 (R-110)

- **Decision**: 앱은 `NSApplication.willTerminateNotification`(앱 델리게이트 `applicationWillTerminate`와 같은 시점)과 `NSWorkspace.willSleepNotification`(`NSWorkspace.shared.notificationCenter`에 등록)을 받는다. 처리기는 기존 패턴대로 `queue: .main` + `MainActor.assumeIsolated`. 그 순간 타이머가 `running`이면 계기 `quit`/`sleep`, 두 줄은 빈 값, 경과 분만 담은 체크포인트를 저장한다. 입력을 받지 않고, GRDB `write`로 동기 저장한다. `applicationShouldTerminate`로 종료를 미루지 않는다. 잠자기에서는 할 일 상태와 타이머가 그대로다(spec 001 R-005·R-008). 종료에서는 상태를 바꾸지 않는다. 다음 시작의 R-111 복구가 `active`를 `todo`로 되돌린다.
- **보장 범위**: 메뉴 막대 "종료"와 ⌘Q(정상 종료)만 보장한다. 로그아웃·시스템 종료·잠자기는 최선 노력이다(아래 미확인). 기록을 못 남겨도 R-111이 할 일을 지키고, 잃는 것은 경과 분 체크포인트 한 줄이다.
- 시간 끝(`expired`)이나 빈 상태에서는 남기지 않는다(R-110 "도는 중"). 시간 끝 화면에 적던 두 줄은 종료와 함께 사라진다(가정).
- 경과 분: 체크포인트를 저장하는 순간 기준(F6, data-model §5.5).
- **Rationale**: spec 범위 토론 Q4 세부 다수안(B·C: 종료·잠자기는 빈 체크포인트만). 동기 저장은 알림 처리기가 돌아오기 전에 끝난다.
- **Alternatives**: 돌아왔을 때 두 줄을 받음(Q4 소수 의견 A), 종료를 붙잡고 두 줄을 받음(R-110 금지).
- **미확인**: 로그아웃·시스템 종료 때 SwiftUI `App` 수명주기 앱에서 `willTerminate`가 오는지(갑작스러운 종료 `NSSupportsSuddenTermination` 기본값 포함), `willSleepNotification` 처리기에 시스템이 주는 시간. 사람 확인 항목이다(quickstart 7).

## R13. 시각과 날짜의 저장 형식

- **Decision**: 시각(`created_at`)은 UTC `YYYY-MM-DDTHH:MM:SSZ` 문자열(초 단위). 날짜(`tasks.deadline`, `contexts.date`, `tasks.cycle_day`)는 지역 날짜 `YYYY-MM-DD`(시간대 없음). 둘 다 MokaCore가 만들고 읽는다(`UTCTimestamp`, `LocalDay`, data-model §2.1). 두 저장소 구현 모두 시각을 초 단위로 내려 저장하고 돌려준다(메모리와 GRDB가 같은 값을 돌려주게, data-model §3). GRDB의 `Date` 기본 형식과 `ISO8601DateFormatter`는 쓰지 않는다. 그레고리력 날짜 계산은 기존 `SimTimestamp` 코드를 MokaCore 내부 공용으로 옮겨 재사용한다.
- 노치 고르기의 "가장 먼저 만든"은 `id` 오름차순이다. `created_at`은 시계를 되돌리면 순서가 뒤집힐 수 있다.
- **Rationale**: 설계서 §2 "ISO 8601 문자열(UTC)", ADR-0003 "저장 시각은 UTC". 파이썬 튜닝 스크립트가 같은 문자열을 바로 읽는다. 마감은 날짜 고르기로만 받으므로(spec 가정) 시각이 아니다.
- **Alternatives**: 유닉스 초 정수(사람이 DB를 볼 때 읽기 어려움), GRDB 기본 `YYYY-MM-DD HH:MM:SS.SSS`(파이썬과 형식 계약이 하나 더 생김), 메모리 구현은 `Date`를 그대로 둠(두 구현의 왕복 값이 달라짐, EGM 지적).

## R14. 저널 모드 (spec 001 research R2에서 넘어옴)

- **Decision**: GRDB `DatabaseQueue` 기본 저널을 그대로 둔다. WAL은 튜닝 스크립트가 앱이 켜진 동안 DB를 읽는 단계(마일스톤 5)에서 다시 본다.
- **Rationale**: 지금 DB를 여는 프로세스는 앱 하나다. WAL은 `-wal`·`-shm` 파일이 생겨 백업·복사 절차가 바뀐다. 바꿀 이유가 생길 때 바꾼다.
- **Alternatives**: 지금 WAL(`DatabasePool`, 쓰지 않는 동시 읽기를 위해 열기 코드가 바뀜).
- 가정: 같은 DB를 두 앱 빌드(개발 빌드와 매일 쓰는 빌드)가 동시에 열지 않는다. 한쪽의 R-111 복구가 다른 쪽의 `active`를 되돌릴 수 있다.

## R15. 화면 시안 절차 (spec 가정)

- 시안 `~/Dev/ai-platform/projects/moka/design/002-mockup.html`(한 파일, 외부 CDN 없음, 라이트·다크, 가짜 할 일). 담은 화면: 설정 창 탭 셋(기본, 할 일, 일정), 할 일 목록 보기·정렬·"다음" 표시, 할 일 폼(제목, 마감 날짜, 반복과 요일, 예상 소요), 일정 폼, 시작 전 화면의 "다른 할 일", 도는 중 펼친 화면의 완료·미루기·바꾸기, 두 줄 입력, 시간 끝 화면의 두 줄과 버튼, 이어서 할 일 줄(접힘 2초, 펼침), 온보딩 두 단계.
- 확정(2026-10-30): v2를 사용자가 확정했다. C1~C4(접힌 노치에 회색 제목, 두 줄 질문은 라벨, 두 줄 화면 돌아가기, 칸 안 Enter는 첫 칸 = 다음 칸), 버튼 이름 "바꾸기", 할 일 목록 보기·정렬(R-118), 화면 이름(일정·중요도·이어서 할 일·추가 시간)이 사용자 선택이다. 화면 문구는 처음 쓰는 사람 관점의 리뷰를 한 번 거쳤다.
- EGM 뒤 고침(2026-10-30, 사용자 결정 Q1·Q2a·Q4): 시작 전 화면에 "다른 할 일" 버튼, 온보딩은 두 단계(TypeSafe 키 단계 제거), 시간 끝 둘째 칸 Enter는 아무 동작 없음(C4-B의 둘째 칸만 바꿈).
- 구현 뒤 스냅샷은 spec 001과 같이 `~/Dev/ai-platform/projects/moka/design/pr-<번호>/index.html`에서 시안과 나란히 사람이 본다(ADR-0009).

## R16. 튜닝 스크립트 계약 시험 (EGM 뒤 Q2e로 범위 줄임)

- **Decision**: `tuning/tests/test_schema_contract.py`를 더한다. `schema/moka-schema.sql`을 파이썬 `sqlite3` 메모리 DB에 실행하고, `decisions_log`의 열 이름 집합이 R5 목록과 같은지, 판단 칸이 모두 NULL인 가짜 줄과 공급자만 있는 폴백 줄(`provider = 'fallback'`, 나머지 NULL)을 넣을 수 있는지, 공급자 없이 다른 판단 칸이나 `model_snapshot`이 있는 줄이 거부되는지 본다. 새 파이썬 의존성은 없다(표준 라이브러리).
- `decisions_log` 밖 표의 CHECK(`tasks.cycle_day` 짝 등)는 Swift 시험이 덮으므로 pytest에 두지 않는다(Q2e, 3:0). ADR-0004가 pytest에 정한 범위는 Swift–Python 공유 계약인 튜닝 표다.
- **Rationale**: ADR-0004 "pytest는 같은 `schema/moka-schema.sql`로 가짜 SQLite를 만들고 튜닝 스크립트가 읽는 열이 있는지 확인한다". spec 001 research R2가 "튜닝 테이블이 생기는 spec에서"로 미뤘다.
- 오류 주입: 마이그레이션에서 `decisions_log` 열 하나를 지우면 Swift 스냅샷 시험과 이 pytest가 함께 FAIL해야 한다(ADR-0004 결정 검증, quickstart 3).
- 확인한 것: F2·F5를 반영한 SQL(data-model §7)을 macOS 파이썬 `sqlite3`(SQLite 3.54.0) 메모리 DB에서 실행해 CHECK 21건(허용·거부 기대값)·외래 키 동작과 `trigger` 열 이름이 따옴표 없이 쓰이는지 확인했다(2026-10-30, 버리는 스크립트, 21/21 PASS). 리눅스 CI의 SQLite 버전에서는 미확인이다.

## R17. 범위 결정과 기각한 안 (범위 토론 2026-10-29, 사용자 2026-10-30)

토론 기록(`.audit/debate/20261029-1800-spec002-r1-scope.md`)은 커밋하지 않으므로 질문마다 고른 안과 기각한 안을 여기 적는다.

| Q | 정한 것 | 기각한 안과 이유 |
|---|---|---|
| Q1 저장 직후 점수(FR-01) | 마일스톤 2는 저장까지만, 점수 요청 자리만 둠(3:0) | 가짜 공급자로 점수 흐름까지(점수를 쓰는 곳이 없는데 판단 계약을 먼저 고정) |
| Q2 스케줄러 전 고르기 | 만든 순, 바꾸기·미루기 직후 그 할 일 제외, 메모리만(3:0). EGM 뒤 id 커서 순환으로 고침(R18) | 마감 가까운 순(마감 없는 할 일이 많으면 같은 할 일만 뜸, 스케줄러 규칙을 미리 정함), 목록에서 직접 고름(새 화면·새 로그 값) |
| Q3 할 일·컨텍스트 폼 위치 | 설정 창 탭, 폼은 독립 뷰(3:0) | 메뉴 막대에 별도 창(ADR-0005 "설정과 종료만"을 바꿈), 노치 펼친 판 안(좁은 판에 폼이 들어가지 않음) |
| Q4 체크포인트 시점 | 시간 끝·바꾸기·미루기는 두 줄, 종료·잠자기는 빈 체크포인트(3:0, 세부 2:1) | 종료·잠자기를 마일스톤 4로(완료 조건 "재진입 시 보인다"를 못 채움), 돌아왔을 때 두 줄을 받음(소수 A: next_note가 낡지 않게. 다수: 묻는 화면이 늘고 R-110 "묻지 않음"과 같은 취지) |
| Q5 재시작 뒤 타이머 | 타이머 저장 안 함, 켤 때 `active` → `todo`, NFR 타이머 복구는 Non-Goals(3:0) | 남은 시간부터 이어 돎(잠자기·시계 변경·끝 시각 지남 처리가 늘고, 다시 시작은 클릭 한 번) |
| Q6 온보딩 키 단계 | 처음엔 키 칸 하나(3:0). EGM 뒤 마일스톤 3으로 미룸(R8) | 온보딩 전체를 마일스톤 3으로(일정·기본값은 이번에 필요) |
| Q7 반복의 하루 경계 | `day_start`만 먼저, 반복 리셋은 그 기준(2:1) | FR-09 전체를 마일스톤 4로(소수 C: 활성화 정의가 비어 있음 → R11로 채움) |

## R18. 노치 고르기 — id 커서 순환 (EGM 🔴, Q1 3:0, 사용자 결정 2026-10-30)

- **Decision**: `RotateByIDRule.pick(from:after:)`(data-model §5.1). 커서(`previousTaskID`)보다 id가 큰 첫 대기 할 일, 없으면 가장 작은 id. 시작 전(초안) 화면에 "다른 할 일" 버튼을 두어 기록·체크포인트 없이 커서만 옮긴다. 초안 단계에서도 빠른 입력을 받는다(spec 001 `NotchTimer`가 원래 받음). 로그의 `scheduler_choice`는 `rotate_by_id_v0`.
- **Rationale**: 처음 규칙("가장 작은 id, 직전 하나만 뺌")은 대기 할 일이 셋 이상이면 앞의 둘만 번갈아 띄운다(EGM critic D-B1). 셋째 할 일로 가려면 시작·바꾸기를 되풀이해야 하고, 그때마다 지울 수 없는 `decisions_log`에 의도 아닌 `switch` 줄과 체크포인트가 쌓인다. 실제 데이터는 11월 초부터 쌓인다(ADR-0006). 순환은 새 상태 없이 기존 커서 하나로 풀리고, 할 일 둘까지는 처음 규칙과 결과가 같다(계약 예시 출력 줄 순서 그대로). `scheduler_choice`는 CHECK 없는 TEXT라 스키마 변경이 없고, 실제 줄이 0개인 지금 이름을 바꾸는 비용이 가장 싸다.
- **Alternatives**: 처음 규칙 유지(셋째 할 일에 갈 수 없음), 설정 창 목록에 "노치에 띄우기" + `manual_v0`(임시 규칙 하나에 영구 로그 값과 새 화면을 늘림, EGM Stage 8과 토론 3:0으로 기각), "가장 오래 안 뽑힌 순"(뽑은 이력을 따로 들어야 함).
- 조건(토론 A·B·C 공통): 초안 버튼 이름은 "바꾸기"와 다르게("다른 할 일") 두어 기록이 남는 동작과 구분한다. 커서 수명을 data-model §4.2에 표로 둔다.
- 알려진 한계: 초안에서 커서를 넘겨 고른 할 일도 그 뒤 버튼 로그에는 규칙 값으로 남는다. 마일스톤 2 줄은 판단 칸이 모두 비어 튜닝 집계 대상이 아니고, 마일스톤 4 스케줄러는 자기 이름을 쓴다.
- 튜닝 계약 값 변경이라 단위 1·3 PR "사람이 볼 결정"에 올린다.

## R19. 시간 끝 화면 둘째 칸 Enter (EGM, Q4 3:0, 사용자 결정 2026-10-30)

- **Decision**: 시간 끝 화면에서 둘째 칸 Enter는 아무 동작 없음. 첫 칸 Enter·Tab은 둘째 칸으로, 칸 밖 Enter는 완료(spec 001 R-003), 직접 입력 칸이 열려 있으면 Enter는 다시 시작(spec 001 R-003 예외) 그대로다. 두 줄 화면(바꾸기·미루기)의 둘째 칸 Enter는 등록 그대로다(data-model §8).
- **Rationale**: 완료는 끝 상태이고 마일스톤 2에는 되돌릴 화면이 없다. 반복 할 일이면 `streak`이 오르고 지울 수 없는 `done` 줄이 남는다. 두 줄 화면에서는 사용자가 이미 동작(바꾸기·미루기)을 고른 뒤라 Enter가 그것을 확정하지만, 시간 끝 화면에서는 아직 넷(완료·미루기·바꾸기·다시 시작) 가운데 고르지 않았다. "열린 입력 칸 안 Enter ≠ 완료"는 spec 001 R-003 예외(사용자 결정 2026-10-29)가 이미 둔 모양이다. 잘못 판단한 비용이 (b)는 클릭 한 번, (a)는 되돌릴 수 없는 기록이다.
- **Alternatives**: 시안 C4-B 그대로(둘째 칸 Enter = 완료), 둘째 칸 Enter = 다시 시작(R-003 예외와 같은 모양이지만 칸 안 Enter가 상태를 바꾸는 점은 같음).

## R20. 저장 실패 정책 (EGM, Q5 3:0, 사용자 결정 2026-10-30)

- **Decision**: 앱 DB 열기나 마이그레이션이 실패하면 할 일·일정·체크포인트·로그 저장소를 메모리로 대체하지 않는다. 노치는 spec 001처럼 타이머만 되고, 노치 빈 상태에 해요체 이유 안내를 보인다(R-119). 설정은 spec 001처럼 메모리 대체를 유지한다. 앱은 DB 파일을 지우거나, 새로 만들거나, 옮기지 않는다. 버튼 쓰기가 실패하면 세션을 바꾸지 않는다(data-model §8).
- **Rationale**: spec 001의 메모리 대체(`App/Sources/MokaApp.swift:86-98`)는 설정 하나일 때의 결정이다. 같은 방식을 할 일·로그에 넓히면 재시작 때 기록이 조용히 사라지고, 지우지 않는다고 약속한 로그(R-112)가 사용자 모르게 깨진다. 표시를 메뉴 막대 항목으로 만들면 ADR-0005:31 "메뉴 막대 항목은 설정과 종료만"에 닿으므로 노치 빈 상태 문구로 둔다. DB 파일을 건드리지 않는 것은 ADR-0004의 `eraseDatabaseOnSchemaChange` 금지와 같은 취지다(실제 데이터 삭제는 되돌릴 수 없음).
- **Alternatives**: 지금처럼 메모리 대체(기록이 조용히 사라짐), 재시도·복구 절차(하루 일정에 과함, EGM Stage 8), 메뉴 막대 "저장할 수 없어요" 항목(ADR-0005 정정 필요).

## R21. 세션이 회차 값과 제목 사본을 다루는 방식 (EGM 🔴, 승인 불필요한 내부 설계)

- **Decision**: `NotchSession`이 시작 순간의 `startedAt`·`quantumMin`을 `RunInfo`로 메모리에 든다. 시간 끝 체크포인트의 경과 분은 `RunInfo.quantumMin`이다. 화면 제목의 원본은 `MokaTask.title`이고, 노치의 할 일을 고치면 세션 함수 `edited`가 타이머 안 제목 사본만 바꾼다. 동작마다 입력(`SessionInput`)과 결과(`SessionStep`) 모양을 정했다(data-model §4.2).
- **Rationale**: spec 001 `NotchTimer`는 `running → expired`에서 `quantumMin`·`startedAt`을 버리고 칩을 기본값으로 채운다(`Sources/MokaCore/NotchTimer.swift:44-45`). 그래서 기본값이 아닌 칩으로 돌렸다면 시간 끝 `elapsed_min`이 틀린다(EGM 리뷰 5·6·9단계가 같은 결함을 지적, 코드로 확인).
- **Alternatives**: `NotchTimer.expired`에 작업 시간을 더함(spec 001 공개 값 타입과 기존 golden 바이트 불변 조건에 닿음, EGM Stage 8로 기각), 화면이 제목을 늘 저장소에서 읽고 타이머 사본은 무시(시뮬레이터 출력과 화면이 어긋날 수 있음).
