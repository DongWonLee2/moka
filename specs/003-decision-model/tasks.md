---

description: "spec 003 판단 모델 연동 MVP 작업 목록"
---

# Tasks: 판단 모델 연동 MVP (마일스톤 3)

**Input**: `specs/003-decision-model/`의 plan.md, spec.md(R-201~R-215), research.md(R1~R16), data-model.md, contracts/(decision-provider.md, questions-json.md, moka-sim-v1-additions-003.md), quickstart.md. 설정 창 시안 `~/Dev/ai-platform/projects/moka/design/003-mockup.html`(T028에서 만들고 사용자 확정, 저장소 밖)

**Tests**: 넣는다. 헌법 II와 AGENTS.md "실패하는 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다". 테스트 태스크마다 Red 커밋 → 구현 태스크에서 Green 커밋.

**Organization**: 사용자 이야기(US1~US3)별로 묶는다. 각 태스크 끝의 `〔단위 N〕`은 plan "작업 단위" 번호이고 Issue 하나가 된다(아래 "작업 단위 ↔ Issue").

**원본 규칙**: 규칙·값·모양은 data-model.md와 contracts가 원본이다. 태스크는 절 번호를 가리키고 문장을 옮겨 적지 않는다. 시험은 그 절의 규칙을 빠짐없이 덮는다.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 다른 파일을 고치고 아직 안 끝난 태스크에 기대지 않아 병렬로 할 수 있다
- **[Story]**: US1~US3(spec.md)
- **🔒**: 화면·실제 호출·Keychain을 사람이 확인해야 끝난다
- **👁 사람이 볼 결정**: PR "사람이 볼 결정"에 올린다(스키마 스냅샷, `questions.json`, DecisionProvider 경계, `scheduler_choice` 값, `moka-sim` 계약)
- 이 파일의 "확인 지점"은 Phase 완료 조건이다

## 공통 규칙 (모든 태스크)

- 테스트 표시 이름은 PRD FR과 R-ID로 시작한다(ADR-0003): R-201·202·203·206 `FR-03`, R-204·205·214 `FR-04`, R-207 `FR-05`, R-208·209·210 `FR-14`, R-211 `FR-11`, R-212·213 `FR-16`, R-215 `ADR-0003 R-215:`. Swift Testing. 앱 시험 번들(`MokaAppTests`)만 XCTest.
- 타입·함수 이름과 모양은 data-model §1과 contracts를 따른다. 거기 없는 작은 이름은 구현 PR에서 정하고 PR "가정"에 적는다.
- 시각은 주입한 값과 `GregorianCalendar.make(timeZone:)`(고정 `Asia/Seoul`)로 시험한다. MokaCore에서 `Date()`, `TimeZone.current`, `Calendar.current`를 읽지 않는다. 실제 시간을 기다리지 않는다. 타임아웃은 가짜 공급자가 `.timeout`을 돌려주는 것으로 시험한다.
- 실제 판단 API(TypeSafe, OpenRouter)를 시험·CI·`moka-sim`·무인 실행에서 부르지 않는다. `FakeDecisionProvider`와 `InMemoryKeyStore`만 쓴다. 실제 Keychain과 앱 DB를 시험에서 열지 않는다(SC-206). 에이전트는 Keychain 값을 조회하지 않는다.
- 가짜 할 일·가짜 일정만 쓴다(예: "가짜 할 일 A"). 픽스처의 응답 값도 가짜다.
- 새 의존성을 두지 않는다. `Package.swift`는 T003의 MokaCore 리소스 한 줄만 바꾼다. 기존 golden 기대 출력은 바이트 그대로다. `@unchecked Sendable`을 쓰지 않는다.
- 로그·`moka-sim` 출력·`scores`·행동 로그 판단 칸에 할 일 제목, 체크포인트 본문, 일정 이름, 키 값을 남기지 않는다.
- 화면 문구는 고객용 해요체이고 확정 시안 글자를 그대로 쓴다.
- 검증 명령: `swift test`, `cd tuning && python3 -m pytest`, 앱은 `xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. 결과는 PASS/FAIL/SKIP/NOT_RUN.

---

## Phase 1: Setup

- [ ] T001 기준 상태 확인: `swift test`, `cd tuning && python3 -m pytest`, 앱 빌드를 돌려 기존 시험이 PASS인지 기록하고, 기존 golden(`Tests/MokaCoreTests/Fixtures/sim/*.expected.jsonl`) 해시를 PR "완료 증거"에 적는다 〔단위 1〕
- [ ] T002 [P] `Sources/MokaCore/Defaults.swift`에 data-model §1 "Defaults에 더하는 값"(가중치 셋, `avoidingAgingFactor`, `rescoreAfter`, `decisionTimeout`)을 더한다. PR "사람이 볼 결정"에 이전 값(없음)·새 값·근거(PRD 7장)를 적는다 〔단위 1〕
- [ ] T003 `Sources/MokaCore/Resources/questions.json`을 contracts/questions-json.md "v1 내용" 그대로 만들고, `Package.swift` MokaCore 타깃에 `resources: [.copy("Resources/questions.json")]`를 더한다. `AGENTS.md` 저장소 지도에 "`Sources/MokaCore/Resources/questions.json` 판단 질문 파일(Swift·pytest 공유 계약)" 한 줄을 더한다. 👁 〔단위 1〕

---

## Phase 2: Foundational (모든 이야기가 기대는 판단 코어와 저장)

**순서**: 단위 1(T004~T009, T012~T017)이 병합되기 전에는 단위 3 구현(T018)을 병합하지 않는다. 단위 3의 Red 시험(T010·T011)은 미리 써도 된다.

### Tests (Red)

- [ ] T004 [P] `Tests/MokaCoreTests/QuestionSetTests.swift`: contracts/questions-json.md "읽기 시험" 전부(넷, 타입, `thresholds[model]`, 임계값 범위, blocked 없음, `Bundle.module`에서 읽힘)를 쓰고 실패를 확인한다(`FR-03 R-202`, `FR-03 R-203`) 〔단위 1〕
- [ ] T005 [P] `Tests/MokaCoreTests/JudgmentStateTests.swift`: data-model §4(키 집합이 표와 정확히 같음 = 금지 필드 없음, 값 없는 칸은 키를 뺌, 일정 순서, impact "조금/꽤/아주", 오늘·요일 문자열, 체크포인트 두 줄이 비면 뺌, 문자열 이스케이프)와 §5(FNV-1a golden: 정한 state 셋 → 정한 16자 해시)를 쓰고 실패를 확인한다(`FR-03 R-201`, SC-202) 〔단위 1〕
- [ ] T006 [P] `Tests/MokaCoreTests/TypeSafeCodecTests.swift`와 픽스처 `Tests/MokaCoreTests/Fixtures/decision/`(가짜 값 응답: 정상, 질문 빠짐, 타입 다름, 범위 밖, `model` 없음, 모르는 칸): contracts/decision-provider.md 요청 본문 바이트, 응답 해석, 상태 코드 → 오류 표 전부를 쓰고 실패를 확인한다(`FR-14 R-208`, `FR-14 R-209`) 〔단위 1〕
- [ ] T007 [P] `Tests/MokaCoreTests/ScoreRulesTests.swift`: data-model §3 전부(해석 → `TaskScore`, 정규화 분모가 옵션 수에서 옴, urgency 하한은 저장이 아니라 계산 때, aging과 avoiding 임계값, priority 식, "쓰는 점수" 조건: 키 없음·버전 다름이면 점수 없음, 6시간 지난 점수는 씀)를 쓰고 실패를 확인한다(`FR-04 R-204`) 〔단위 1〕
- [ ] T008 [P] `Tests/MokaCoreTests/ScoringPlanTests.swift`: data-model §6 트리거 표 전부(키 없음이면 빈 목록, 완료·버림 제외, 6시간 경계, 버전 다름)와 답 받기(state 해시가 같을 때만, 질의 중 고침·일정 변경·버림이면 버림, 겹친 질의는 마지막 내용과 맞는 답만)를 쓰고 실패를 확인한다(`FR-03 R-206`, spec 엣지) 〔단위 1〕
- [ ] T009 [P] `Tests/MokaStoreTests/StorageContractTests.swift`에 `ScoreStore` 공용 계약 시험(왕복, 같은 할 일 덮어쓰기, 초 아래 시각, `model_snapshot` 없음)을 `StoreKind.allCases`로 덧붙이고 실패를 확인한다. 이 태스크에서는 `.memory`만 통과 대상이고 `.grdb`는 T018에서 켠다(`FR-04 R-205`) 〔단위 1·3〕
- [ ] T010 [P] `Tests/MokaStoreTests/MigrationTests.swift`: 이름 리터럴을 `["v1_settings", "v2_tasks_contexts_checkpoints_log", "v3_scores"]`로, 스키마 스냅샷에 data-model §2 표가 있는지 실패로 확인한다(ADR-0007) 〔단위 3〕
- [ ] T011 [P] `tuning/tests/test_schema_contract.py`에 `scores` 열 이름 집합 시험, `tuning/tests/test_questions_contract.py`에 `Sources/MokaCore/Resources/questions.json`을 저장소 루트 상대 경로로 읽어 넷·`thresholds[model]`을 확인하는 시험을 쓰고 실패를 확인한다 〔단위 3〕

### Implementation (Green)

- [ ] T012 `Sources/MokaCore/Decision/QuestionSet.swift`: data-model §1 `QuestionSet`·`Question`, `QuestionSet.bundled()`. T004 PASS. `Bundle.module`이 리눅스 CI에서 읽히지 않으면 PR "가정"에 대안을 적고 멈춘다(plan 위험 7) 〔단위 1〕
- [ ] T013 `Sources/MokaCore/Decision/JudgmentState.swift`: data-model §4 조립·정준 바이트, §5 FNV-1a. T005 PASS 〔단위 1〕
- [ ] T014 `Sources/MokaCore/Decision/DecisionProvider.swift`(프로토콜, `DecisionRequest`·`DecisionResponse`·`Answer`·`DecisionError`, `FakeDecisionProvider`)와 `Sources/MokaCore/Decision/TypeSafeCodec.swift`. T006 PASS. 👁(DecisionProvider 경계) 〔단위 1〕
- [ ] T015 `Sources/MokaCore/Decision/ScoreRules.swift`와 `TaskScore`. T007 PASS 〔단위 1〕
- [ ] T016 `Sources/MokaCore/Decision/ScoringPlan.swift`(`ScoreTrigger`, `targets`, `accepts`). T008 PASS 〔단위 1〕
- [ ] T017 `Sources/MokaCore/Decision/KeyStore.swift`(프로토콜, `InMemoryKeyStore`)와 `Sources/MokaCore/Storage.swift`에 `ScoreStore`·`InMemoryScoreStore`. T009(`.memory`) PASS 〔단위 1〕
- [ ] T018 `Sources/MokaStore/Migrations.swift`에 `v3_scores`(data-model §2 SQL 그대로), `Sources/MokaStore/GRDBScoreStore.swift`(UPSERT), `schema/moka-schema.sql` 갱신, `StoreKind.grdb`에 점수 저장소. T009(`.grdb`)·T010·T011 PASS. 👁(스키마 스냅샷) 〔단위 3〕

**확인 지점**: `swift test`·pytest PASS. 판단 코어가 가짜 공급자로 리눅스에서 돈다.

---

## Phase 3: User Story 1 - 키를 넣으면 노치가 점수 순으로 할 일을 띄운다 (Priority: P1) 🎯 MVP

**Goal**: 저장 직후 질의 → 점수 저장 → 노치가 priority 순으로 돈다. 설정 창에 priority 칸.

**Independent Test**: spec US1 Independent Test.

### Tests (Red)

- [ ] T019 [P] [US1] `Tests/MokaCoreTests/PriorityOrderTests.swift`: data-model §7(점수 있는 할 일 priority 내림차순 → 같으면 마감·id, 점수 없는 할 일 마감 순 뒤, 키 없음이면 전부 마감 순, 순환: 처음·완료 뒤 1위, 바꾸기·미루기 뒤 다음, 끝이면 1위, 후보 하나)를 쓰고 실패를 확인한다(`FR-05 R-207`) 〔단위 2〕
- [ ] T020 [P] [US1] `Tests/MokaCoreTests/NotchSessionPriorityTests.swift`: `NotchSession`이 점수를 받아 빈 상태에서 1위를 고르고, 바꾸기 뒤 다음 순위, 초안·도는 중은 점수가 바뀌어도 그대로, `nextMark`가 같은 순서, `logLine` 판단 칸이 data-model §8 표대로(점수 있음·없음), `scheduler_choice` `priority_rotate_v0`. `ValueTypeTests`에 `SchedulerChoice.priorityRotateV0` rawValue를 더한다. 실패를 확인한다(`FR-05 R-207`, `FR-11 R-211`, SC-203) 〔단위 2〕
- [ ] T021 [US1] `App/Tests/MokaAppTests/AppDecisionTests.swift`(XCTest, `FakeDecisionProvider`·`InMemoryScoreStore`·`InMemoryKeyStore` 주입): data-model §9 연결 지점마다 가짜 공급자가 맞는 할 일로 불리는지, 답이 오면 저장되고 "다음" 표시가 바뀌는지, 질의 중 고침이면 버리는지, 키 저장 뒤 전체 질의. 실패를 확인한다(`FR-03 R-206`, SC-201) 〔단위 4〕

### Implementation (Green)

- [ ] T022 [US1] `Sources/MokaCore/PriorityOrder.swift`(`PriorityOrder`, `PriorityRotateRule`), `Sources/MokaCore/DecisionLog.swift`에 `priorityRotateV0`. T019 PASS. 👁(`scheduler_choice` 값) 〔단위 2〕
- [ ] T023 [US1] `Sources/MokaCore/NotchSession.swift`: `SessionInput`에 점수·키 유무·질문 세트를 받아 `picked`·`nextMark`·`logLine`이 data-model §7·§8을 따른다. 기존 spec 002 시험은 점수 없는 입력에서 순서가 마감 순으로 바뀌는 곳만 기대를 고치고 이유를 PR에 적는다(테스트 약화 아님: R-104 → R-207 규칙 교체). T020 PASS 〔단위 2〕
- [ ] T024 [US1] `App/Sources/AppState.swift`: `AppStorage`에 `scores`·`keyStore`·공급자 주입, data-model §9 질의 흐름과 연결 지점, 화면 값(할 일별 priority). T021 PASS 〔단위 4〕
- [ ] T025 [P] [US1] `App/Sources/Decision/TypeSafeProvider.swift`: contracts/decision-provider.md HTTP 표(URLSession, `timeoutIntervalForResource = Defaults.decisionTimeout`, 상태 코드 → 오류, 본문은 `TypeSafeCodec`). 시험에서 링크하지 않는다 〔단위 4〕
- [ ] T026 [US1] `App/Sources/MokaApp.swift`: DB를 열 때 `GRDBScoreStore`, `KeychainKeyStore`(T034), `TypeSafeProvider`를 만들어 넘긴다. DB를 못 열면 `scores` nil(spec 002 R-119) 〔단위 4〕
- [ ] T027 🔒 [US1] 설정 창 시안 `~/Dev/ai-platform/projects/moka/design/003-mockup.html`: data-model §10 키 칸 상태 다섯과 할 일 탭 priority 칸(점수 있음·없음 섞임). 사용자 확정을 받는다. 하루 넘게 밀리면 R-214를 다음 spec으로(plan 위험 1) 〔단위 4〕
- [ ] T028 [US1] `App/Sources/Views/TaskListTabView.swift` 줄에 priority 칸(소수 둘째 자리, 점수 없으면 빈칸)과 `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 스냅샷 `test_R214_priorityColumn`. 확정 시안대로(`FR-04 R-214`) 〔단위 4〕
- [ ] T029 🔒 [US1] 사람 확인 quickstart 6-3·6-4(확인용 빌드, 개인 팀 서명, `codesign -dv` TeamIdentifier 먼저). 결과는 PASS/FAIL과 응답 필드 이름만 〔단위 4〕

**확인 지점**: SC-201·SC-203. 노치가 점수 순으로 돈다.

---

## Phase 4: User Story 2 - 키가 없거나 실패해도 앱은 그대로 돈다 (Priority: P1)

**Goal**: 키 없음·실패에서 마감일 순, 버튼·타이머 그대로, 401 문구, 다시 물어보기.

**Independent Test**: spec US2 Independent Test.

### Tests (Red)

- [ ] T030 [US2] `App/Tests/MokaAppTests/AppDecisionTests.swift`에 덧붙인다: 실패 다섯 종류(`missingKey`, `unauthorized`, `timeout`, `rateLimited`·`overloaded`, `malformed`)에서 저장 없음·노치 상태 그대로, `unauthorized` 뒤 `keyNeedsCheck` 켜짐·다음 성공에 꺼짐, `retry`가 점수 없는 할 일만 부름, 키 지운 뒤 마감 순, 주입한 시계로 1시간 동안 시작·완료·바꾸기가 동작(`FR-14 R-209`, `FR-14 R-210`, SC-204, SC-205). 실패를 확인한다 〔단위 4〕

### Implementation (Green)

- [ ] T031 [US2] `App/Sources/AppState.swift`: `keyNeedsCheck`, `retry` 트리거, 키 지움 뒤 순서만 다시. T030 PASS 〔단위 4〕
- [ ] T032 🔒 [US2] 사람 확인 quickstart 6-5·6-6 〔단위 4〕

**확인 지점**: SC-204·SC-205.

---

## Phase 5: User Story 3 - 키는 Keychain에만 있고 화면에 다시 보이지 않는다 (Priority: P1)

**Goal**: 설정 창 키 칸, Keychain 저장, 값이 다시 보이지 않음.

**Independent Test**: spec US3 Independent Test.

### Tests (Red)

- [ ] T033 [P] [US3] `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 기본 탭 키 칸 상태 다섯 스냅샷(data-model §10, 확정 시안), `AppDecisionTests`에 키 저장·지우기 트리거와 앱 DB·설정 저장소에 키 값이 없음(`InMemoryKeyStore` 밖 어디에도 없음)을 쓰고 실패를 확인한다(`FR-16 R-212`, `FR-16 R-213`, SC-207) 〔단위 4〕

### Implementation (Green)

- [ ] T034 [US3] `App/Sources/Decision/KeychainKeyStore.swift`: research R10(로그인 키체인 generic password, service `dev.dongwon.moka`, account `typesafe`, `hasKey`는 `kSecReturnAttributes`만, 접근성 속성 없음). 시험에서 쓰지 않는다 〔단위 4〕
- [ ] T035 [US3] `App/Sources/Views/BasicTabView.swift` 키 칸(가림 입력, 저장·지우기·다시 물어보기, 안내·401 문구, 확정 시안 글자)과 `AppState` 키 저장·지우기. T033 PASS 〔단위 4〕
- [ ] T036 🔒 [US3] 사람 확인 quickstart 6-1·6-2(다시 빌드해도 확인 창이 반복되지 않는지). 접근성 속성이 로그인 키체인에서 지켜지는지는 공식 문서로 확인해 PR "사람이 볼 결정"에 적는다(미확인이면 미확인) 〔단위 4〕

**확인 지점**: SC-207.

---

## Phase 6: 시뮬레이터 (R-215, 마지막 단위)

**순서**: 2026-11-08까지 단위 1~4가 끝나지 않으면 이 Phase를 다음 spec으로 넘기고 PR에 적는다(research R13).

- [ ] T037 [P] `Tests/MokaCoreTests/Fixtures/sim/storage-judge-order.json`·`.expected.jsonl`(contracts/moka-sim-v1-additions-003.md 예를 기반으로 바꾸기 뒤 다음 순위까지), `errors/storage-judge-*.json` 오류 픽스처, `SimGoldenTests`에 기존 golden 바이트 동일 시험을 쓰고 실패를 확인한다(`ADR-0003 R-215`) 〔단위 5〕
- [ ] T038 `Sources/MokaCore/Sim/`에 `judge`·`key` 이벤트와 조건부 출력 칸(`order`, `has_key`, `decision.provider`). T037 PASS. 👁(`moka-sim` 계약) 〔단위 5〕
- [ ] T039 [P] spec 001 `contracts/moka-sim-v1.md`의 storage 절 끝에 spec 003 덧붙임 링크 한 줄 〔단위 5〕

---

## Phase 7: Polish & Cross-Cutting

- [ ] T040 [P] `GLOSSARY.md`: 판단 질문 넷(blocked 없앰, 2026-11-06 사용자 결정), impact 옵션 "조금/꽤/아주", `scores`(priority 저장 안 함), `priority_rotate_v0`, 키 보관함("마일스톤 3에서 만든다" → 만들었음, 온보딩 키 단계는 다음 spec) 〔단위 1〕
- [ ] T041 🔒 quickstart 1~6 전체를 돌려 결과 표를 마지막 PR에 붙인다 〔단위 4〕
- [ ] T042 PRD 고칠 문장(6장 blocked 줄·impact 옵션, 7장 w_b·정책 1, 9장 `scores` 열)을 마지막 PR "사람이 볼 결정"에 적는다. PRD는 저장소 밖이라 고치지 않는다 〔단위 4〕

---

## Dependencies & Execution Order

### Phase 순서

Setup → Foundational(단위 1, 그 뒤 단위 3) → US1(단위 2 → 단위 4) → US2·US3(단위 4) → 시뮬레이터(단위 5) → Polish.

### 태스크 사이 의존

- T012~T017은 각 Red(T004~T009) 뒤. T018은 T017 뒤.
- T019·T020은 T015(점수 규칙) 뒤. T022·T023은 T019·T020 뒤.
- 단위 4(T021, T024~T036)는 단위 1·2·3 병합 뒤. T027(시안)은 단위 1과 함께 먼저 만들어 확정을 받아 둔다.
- T037·T038은 단위 2 뒤.

### 작업 단위 ↔ Issue (plan "작업 단위")

| 단위 | 태스크 | Issue 제목 후보 |
|---|---|---|
| 1 | T001~T009(단위 1 몫), T012~T017, T040 | spec 003 단위 1: MokaCore 판단 코어(질문 파일·판단 입력·TypeSafe 조립·점수·질의 대상·키 보관함) |
| 2 | T019, T020, T022, T023 | spec 003 단위 2: 점수 순 고르기와 로그 판단 칸 |
| 3 | T009(`.grdb`), T010, T011, T018 | spec 003 단위 3: MokaStore v3_scores와 튜닝 계약 시험 |
| 4 | T021, T024~T036, T041, T042 | spec 003 단위 4: 앱 공급자·Keychain·질의 연결·설정 창(사람 세션) |
| 5 | T037~T039 | spec 003 단위 5: moka-sim judge·key |

### Parallel Opportunities

- T004~T011의 Red 시험은 모두 다른 파일이라 병렬.
- 단위 2와 단위 3은 단위 1 병합 뒤 병렬.
- T025(TypeSafeProvider)와 T034(KeychainKeyStore)는 서로 다른 파일이라 병렬.

### Parallel Example: 단위 1 병합 뒤

```text
implementer A: 단위 2 (T019, T020 → T022, T023)
implementer B: 단위 3 (T010, T011 → T018)
```

## Implementation Strategy

### MVP First

단위 1 → 2·3 → 4의 US1(T021·T024~T026·T029)까지 가면 완료 조건("모델 점수로 정렬된 할 일이 노치에 뜬다")이 선다. US2·US3은 같은 단위 4 안에서 이어 간다. R-214(priority 칸, T027·T028)와 단위 5는 밀리면 넘긴다.

### 무인 실행 경계

moka는 2026-11-02부터 무인 실행을 하지 않는다(메모리). 단위 1·2·3·5는 사람 세션에서 `implementer`로 돌릴 수 있다. 단위 4는 화면·실제 호출·Keychain 확인(🔒)이 있어 사람 세션 전용이다.

## R-ID ↔ 태스크

| R-ID | Red | Green | 사람 확인 |
|---|---|---|---|
| R-201 판단 입력·금지 필드 | T005 | T013 | — |
| R-202 질문 파일 | T004, T011 | T003, T012 | — |
| R-203 blocked 없음 | T004 | T003, T012 | — |
| R-204 priority 식 | T007 | T015 | — |
| R-205 판단 결과 저장 | T009, T010, T011 | T017, T018 | — |
| R-206 질의 시점 | T008, T021 | T016, T024 | T029 |
| R-207 노치 순서 | T019, T020 | T022, T023 | T029 |
| R-208 공급자 경계 | T006 | T014, T025 | T029 |
| R-209 실패 처리 | T006, T030 | T014, T031 | T032 |
| R-210 폴백 | T019, T030 | T022, T031 | T032 |
| R-211 로그 판단 칸 | T020 | T023 | — |
| R-212 키 칸 | T033 | T035 | T036 |
| R-213 Keychain | T033 | T017, T034 | T036 |
| R-214 priority 칸 | T028 | T028 | T027, T029 |
| R-215 시뮬레이터 | T037 | T038 | — |
| SC-201 10초 | T021 | T024 | T029 |
| SC-202 금지 필드 | T005 | T013 | — |
| SC-203 순서 | T019, T020 | T022, T023 | T029 |
| SC-204 키 없이 1시간 | T030 | T031 | T032 |
| SC-205 실패 다섯 | T030 | T031 | — |
| SC-206 실제 API·Keychain·DB 안 엶 | 공통 규칙, T025·T034가 앱 타깃에만 | — | — |
| SC-207 키 값 없음 | T033 | T035 | T036 |
| SC-208 첫 실제 호출 | — | — | T029 |
