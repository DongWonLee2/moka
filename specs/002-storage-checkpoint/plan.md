# Implementation Plan: 저장과 체크포인트 (마일스톤 2)

**Branch**: `chore/spec-002-storage-checkpoint` (구현은 Issue별 `feat/<issue>-<slug>`) | **Date**: 2026-10-30 | **Spec**: [spec.md](spec.md)

**Input**: `specs/002-storage-checkpoint/spec.md`(R-101~R-119)

## Summary

할 일, 컨텍스트(일정), 체크포인트, 행동 로그를 GRDB에 저장한다. 새 마이그레이션 `v2_tasks_contexts_checkpoints_log` 하나가 표 넷을 만든다. 노치 고르기(R-104, id 순환), 노치 세션과 버튼 쓰기, 반복 리셋(R-113), 하루 경계(R-114), 재시작 복구(R-111), 목록 보기(R-118)는 MokaCore 순수 함수와 값 타입으로 두고 리눅스 `swift test`와 `moka-sim`으로 화면 없이 검증한다. 저장 프로토콜과 메모리 구현은 MokaCore, GRDB 구현은 MokaStore다. 같은 계약 시험을 두 구현에 돌린다. `moka-sim`은 v1에 시나리오 선택 필드 `storage`와 R-117 이벤트를 덧붙이고, 기존 golden 출력은 바이트 그대로 둔다. 판단 공급자 키 보관은 마일스톤 3이다. 화면(설정 탭, 버튼, 두 줄 입력, 온보딩 두 단계)은 사용자가 확정한 HTML 시안 v2를 따른다. 규칙 원본은 [data-model.md](data-model.md), 결정 근거는 [research.md](research.md).

## Technical Context

**Language/Version**: Swift 6(언어 모드 6, ADR-0001). Python 3(튜닝 계약 시험)

**Primary Dependencies**: GRDB 7.11.1(`MokaStore`, 기존). 새 의존성 없음

**Storage**: SQLite `~/Library/Application Support/dev.dongwon.moka/moka.sqlite`(ADR-0004). 표: 기존 `settings` + 새 `tasks`, `contexts`, `checkpoints`, `decisions_log`. 저널은 GRDB `DatabaseQueue` 기본값 유지(research R14). 타이머, 고르기 커서, 회차 값은 메모리

**Testing**: Swift Testing(`MokaCoreTests`, `MokaStoreTests`, 리눅스 CI `core-test`), pytest(`tuning/tests`, CI `tuning-test`), XCTest 스냅샷 번들 `MokaAppTests`(macOS 로컬, CI에 필수가 아닌 `app-snapshots` job이 있음)

**Target Platform**: macOS 14+, `LSUIElement` 메뉴 막대 앱(ADR-0005). Package 타깃은 리눅스(`swift:6.3.3-noble`)에서도 빌드

**Project Type**: 데스크톱 앱 + Swift Package(라이브러리 2개 + CLI) + Python 튜닝 스크립트

**Performance Goals**: 버튼 한 번의 저장(할 일 갱신 + 체크포인트 + 로그 한 줄)은 한 트랜잭션. 성능 측정은 하지 않는다. 할 일 수는 수십 건 규모라 색인을 두지 않는다

**Constraints**: 실제 시간을 기다리는 시험 금지(헌법 II). MokaCore에서 `Date()`·`TimeZone.current`를 직접 읽지 않음(ADR-0003). 테스트·`moka-sim`은 실제 앱 DB를 열지 않음(SC-106, ADR-0004·0006). `eraseDatabaseOnSchemaChange` 금지, DB 파일을 지우거나 다시 만들지 않음(R-119). `decisions_log`는 INSERT만. 종료를 붙잡지 않음(R-110). 로그·`moka-sim` 출력에 할 일 제목·체크포인트 본문 없음. `NotchTimer`(spec 001 공개 값 타입)와 기존 golden은 바꾸지 않음

**Scale/Scope**: 사용자 1명, 할 일 수십 건, 표 4개 추가, 설정 키 3개 추가, `moka-sim` 이벤트 6종 추가, 화면 상태 약 12개 추가

## Constitution Check

*GATE: Phase 0 전 확인, Phase 1 설계 뒤 다시 확인함, EGM 리뷰 뒤 다시 확인함.*

승인 항목 P1~P8은 토론(`.audit/debate/20261030-plan002-approvals.md`, 커밋 안 함, 3라운드)으로 추천안을 만들고 사용자가 2026-10-30 정했다. 설계 중 생긴 후속 결정 F1~F6과 EGM 리뷰 뒤 승인 항목 Q1~Q5도 각각 토론(`.audit/debate/20261030-plan002-followups.md`, `.audit/debate/20261030-1720-spec002-egm-approvals.md`, 둘 다 커밋 안 함)을 거쳐 같은 날 사용자가 정했다(아래 두 표). 결정 요지와 기각 이유는 research에 있다.

| 원칙 | 판정 | 근거 |
|---|---|---|
| I 승인 없는 계약 변경 금지 | 통과(승인 받음) | P1~P8, F1~F6, EGM Q1~Q5(아래 표). 구현 PR마다 "사람이 볼 결정"에 다시 적는다: 스키마 스냅샷(단위 2), `moka-sim` 계약과 `scheduler_choice` 값 `rotate_by_id_v0`(단위 1·3) |
| II 테스트 먼저, 약화 금지 | 통과 | R-ID마다 Red 커밋 → Green 커밋. 하루 경계·반복 리셋은 주입한 시각과 `GregorianCalendar.make(timeZone:)`(`Asia/Seoul`, `America/New_York`). 리셋 멱등, dropped 제외, 순환, 모르는 열거 값 읽기 실패를 Red 시험으로 먼저 둔다. 오류 주입은 quickstart 3 |
| III 네 가지로만 보고 | 통과 | quickstart 결과는 PASS/FAIL/SKIP/NOT_RUN. 종료·잠자기 기록과 화면은 사람 확인이며 자동 PASS로 적지 않는다 |
| IV 같은 실패 2회 중단 | 통과 | 리눅스·macOS 하루 경계 결과가 다르면 경계 계산만 직접 푼다(research R9). 두 번째 우회 없음 |
| V 작은 PR | 통과 | 아래 "작업 단위" 5개를 각각 PR로. 단위 1·3은 Issue 여러 개로 더 쪼갠다 |
| VI ID로 추적 | 통과 | 테스트 표시 이름 규칙은 tasks "공통 규칙"(ADR-0003). tasks·Issue·PR 표에 R-ID |
| VII 보호 장치 우회 금지 | 통과 | 해당 없음. 앱 DB 경로 deny 규칙(ADR-0006)은 그대로 |
| VIII 판단 모델은 판단만 | 통과 | 판단 질의·키 코드 없음. 외부 호출 없음. `moka-sim`은 네트워크·DB·Keychain 인자 없음. 판단 칸에 원문 텍스트를 넣지 않는다 |
| 보안·사용자 데이터 | 통과 | 시나리오·스냅샷·픽스처는 가짜 할 일만. `moka-sim` 출력에 제목·두 줄 본문 없음. 저장 실패 때 메모리 대체·DB 파일 조작 없음(R-119) |

설계 뒤 재확인: 위반 없음. Complexity Tracking 해당 없음.

### 후속 결정 (설계 중 생김, 사용자 2026-10-30)

| # | 결정 | 표결 | 사람 |
|---|---|---|---|
| F1 | `tasks`에는 이번 단계가 쓰는 열만 둔다(research R1) | 3:0 | 승인 |
| F2 | `tasks.cycle_day` 열과 `CHECK((recurrence = 'none') = (cycle_day IS NULL))`(research R10) | 2:1(A·C / B) | 사용자 결정(다수안) |
| F3 | 활성화 = 앱 시작, 잠자기에서 깨어남, 노치 펼침, 설정 창 열기(research R11) | 3:0 | 승인 |
| F4 | 하루 경계·`LocalDay`는 그레고리력 고정, 시간대는 시스템. [ADR-0010](../../adr/ADR-0010-day-boundary-calendar.md)이 ADR-0003의 한 문장을 대체(research R9) | 3:0 | 승인 |
| F5 | `decisions_log` 판단 칸 CHECK 둘, 공급자만 있는 폴백 줄을 받는다(research R5) | 3:0(형태 2:1, 의미 같음) | P5 문구 변경 재승인 |
| F6 | `moka-sim` 버튼과 두 줄은 한 이벤트, 완료는 기존 `complete`. 경과 분은 저장 순간 기준(research R6, data-model §5.5) | 3:0 | 승인 |

### EGM 리뷰 뒤 결정 (사용자 2026-10-30, 추천안 그대로)

리뷰 보고는 `.audit/egm/002/consolidated_review_report.md`(커밋 안 함).

| # | 결정 | 표결 | 근거 |
|---|---|---|---|
| Q1 | 노치 고르기를 id 커서 순환으로, 시작 전 화면 "다른 할 일"(기록 없음), 초안 빠른 입력 허용, `scheduler_choice` = `rotate_by_id_v0` | 3:0 | research R18 |
| Q2a | 판단 공급자 키 단계를 마일스톤 3으로, 온보딩 두 단계 | 3:0 | research R8 |
| Q2b | R-118은 유지, 밀리면 가장 먼저 버퍼로 | 3:0 | spec 위험 1 |
| Q2c | `moka-sim` 새 이벤트는 R-117 목록 + `activate`만 | 3:0 | research R6 |
| Q2d | F5 CHECK는 지금 둠 | 3:0 | research R5 |
| Q2e | `latestCheckpoint`, GRDB golden 재실행, pytest의 `decisions_log` 밖 CHECK 시험을 뺌. 대신 공용 계약 시험 두 사례 | `latestCheckpoint`·pytest 3:0, GRDB golden 2:1(A·B / C) | research R7·R16 |
| Q3 | 하루 시작을 넘겨 끝낸 반복 할 일은 그 주기 몫("먼저 판정" 삭제) | 3:0 | research R10 |
| Q4 | 시간 끝 둘째 칸 Enter는 아무 동작 없음 | 3:0 | research R19 |
| Q5 | 저장 실패 때 할 일 저장소 메모리 대체 금지, 노치 빈 상태 안내, DB 파일 불변, 쓰기 실패 시 세션 유지 | 3:0 | research R20, spec R-119 |

소수 의견: F2(B) CHECK 없이 왕복 시험과 불변식으로, F5 형태(C) 한 식으로 묶자, Q2e(C) 대체 시험이 생기기 전엔 GRDB golden 유지.

### 가정

- F3 차이: 설계서 tech-design.md:193은 하루 경계 판정을 앱 활성화·잠자기 해제·매일 06:00 타이머 세 곳에서 부른다. 이 plan은 06:00 타이머를 두지 않고 노치 펼침·설정 창 열기를 더한다(research R11).
- `UserAction` 열거형은 이번에 쓰는 `done`·`skip`·`switch`만 둔다(research R3).
- 세션 회차 값과 제목 사본 처리는 승인이 필요 없는 내부 설계로 정했다(research R21).

## Project Structure

### Documentation (this feature)

```text
specs/002-storage-checkpoint/
├── spec.md               # 범위·요구(R-101~R-119)
├── plan.md               # 이 파일
├── research.md           # R1~R21 결정 근거와 대안
├── data-model.md         # 규칙 원본: 값 타입, 세션, 고르기·리셋·쓰기 규칙, v2 SQL, 설정 키, 화면 상태
├── quickstart.md         # 검증 절차 1~7
├── contracts/
│   └── moka-sim-v1-additions.md   # v1에 덧붙이는 이벤트·출력. 원본 계약은 구현 PR에서 고친다
├── checklists/requirements.md
└── tasks.md
```

시안: `~/Dev/ai-platform/projects/moka/design/002-mockup.html` v2(저장소 밖, 로컬 전용, 2026-10-30 사용자 확정, EGM 뒤 고침 포함).

### Source Code (repository root)

```text
Sources/MokaCore/
├── Defaults.swift                    # 기존 + extendMin 10, extendMinRange 1…180, dayStart 06:00
├── QuantumSettings.swift             # 기존(SettingsStore). 바꾸지 않음
├── CoreSettings.swift                # 새: default_extend_min·day_start·onboarding_done 읽기·쓰기 규칙(앱 AppSettings와 이름이 겹치지 않게)
├── UTCTimestamp.swift                # 새: UTCTimestamp(공개) + 내부 GregorianCivil(SimTimestamp에서 옮김)
├── TaskModel.swift                   # 새: MokaTask, TaskStatus, Recurrence, Weekday, NewTask, TaskEdit
├── ContextModel.swift                # 새: MokaContext, ContextImpact, NewContext
├── CheckpointModel.swift             # 새: Checkpoint, CheckpointTrigger, CheckpointNotes, 경과 분, 첫 행동 표시
├── DecisionLog.swift                 # 새: DecisionLogEntry, UserAction, SchedulerChoice, Judgment
├── LocalDay.swift                    # 새: LocalDay, DayStart, DayBoundary, GregorianCalendar
├── TaskRules.swift                   # 새: RotateByIDRule, RecurrenceReset, LaunchRecovery, TaskWriteRules
├── TaskListView.swift                # 새: TaskListScope, TaskListOrder, TaskListView
├── NotchSession.swift                # 새: NotchSession, RunInfo, SessionInput, SessionStep, PendingAction
├── NotchStatus.swift                 # 기존 + 두 줄 입력 중 상태 글자(pending 매개변수, 기본값 nil)
├── Storage.swift                     # 새: TaskRepository, ContextStore, StoreBatch, StoreError + 메모리 구현
├── Onboarding.swift                  # 새: Onboarding.finish
└── Sim/                              # 기존 + storage 모드 디코딩·실행·출력. SimTimestamp는 GregorianCivil을 씀
Sources/MokaStore/
├── Migrations.swift                  # v2_tasks_contexts_checkpoints_log 덧붙임
├── GRDBTaskRepository.swift          # 새
└── GRDBContextStore.swift            # 새
Tests/MokaCoreTests/                  # 규칙·값 타입·세션·Sim storage golden
Tests/MokaCoreTests/Fixtures/sim/     # 기존 그대로 + storage 시나리오(storage-*.json)
Tests/MokaStoreTests/                 # 이름 리터럴 갱신, 스냅샷, 공용 계약 시험(StoreKind 메모리·GRDB), GRDB 전용 CHECK 시험. GRDB는 TestDatabase.migratedInMemory()
schema/moka-schema.sql                # 스냅샷 갱신(표 넷 추가)
tuning/tests/test_schema_contract.py  # 새: decisions_log 열·판단 칸 CHECK만
App/Sources/
├── MokaApp.swift                     # DB 하나를 열어 저장소들에 나눠 줌(실패하면 R-119), 온보딩 창, 종료 알림
├── AppState.swift                    # timer → session 전환, tasks 목록, 버튼·두 줄 입력, 잠자기·종료·활성화
├── Notch/NotchPanelHost.swift        # NotchPanelRoot가 session·콜백(미루기·바꾸기·등록·안 적기·돌아가기·다른 할 일)을 넘김
├── Settings/SettingsView.swift       # 탭 셋 틀만(내용은 Views/의 탭 뷰)
└── Views/
    ├── NotchContentView.swift        # 새 인자 전달
    ├── NotchLayout.swift             # 초안 접힘 폭 28 → 104pt, 패널 높이를 가장 긴 판(시간 끝 + 두 줄)에 맞춤
    ├── CollapsedView.swift, ExpandedView.swift, ExpiredView.swift   # 고침
    ├── CheckpointNotesView.swift     # 새: 두 줄 입력
    ├── BasicTabView.swift, TaskListTabView.swift, TaskFormView.swift, ContextTabView.swift, ContextFormView.swift   # 새: 값·콜백만 받음(스냅샷 대상)
    ├── StorageUnavailableView.swift  # 새: 저장할 수 없는 빈 상태 안내(R-119)
    └── OnboardingView.swift          # 새: 두 단계
App/Tests/MokaAppTests/               # ScreenStateSnapshotTests 호출부 갱신 + 새 화면 상태 스냅샷
project.yml                           # 바뀌지 않음(새 파일은 폴더 단위로 잡힘). 확인만
adr/ADR-0010-day-boundary-calendar.md # 기존. 결정 검증 결과((a)/(b), 시험 이름)만 덧붙임
```

**Structure Decision**: ADR-0001 구조 그대로다. 새 타깃·의존성 없음. `Package.swift`는 바꾸지 않는다. 공용 계약 시험은 MokaCore와 MokaStore를 둘 다 보는 `MokaStoreTests`에 둔다(research R7). 새 화면 뷰는 스냅샷 번들이 컴파일하는 `App/Sources/Views/`에 두고 `AppState`를 모르게 한다(ADR-0009, `project.yml`의 `MokaAppTests` 소스는 `App/Sources/Views`와 `App/Tests/MokaAppTests`). `App/Sources/Settings/`는 스냅샷 대상이 아니므로 탭 내용을 두지 않는다.

### 앱 연결 (단위 4·5의 경계)

- `AppDelegate`가 `AppState`를 만들고 저장소들을 넘긴다. 설정 창(`SettingsView`)에는 `AppState`를 SwiftUI 환경(`@Environment` 또는 생성자)으로 넘긴다. 정확한 방식은 구현 PR "가정".
- 탭 뷰에 넘기는 값: 할 일 목록 행(`TaskListView.rows` 결과), "다음" 표시 id(data-model §4.2), 보기·정렬 값, 일정 목록, 설정 값 셋. 콜백: 할 일 추가·고침·지움, 보기·정렬 바꿈, 일정 추가·지움, 설정 쓰기.
- 노치 뷰에 넘기는 값: 세션 상태, 이어서 할 일, `showsInCollapsed` 결과, 상태 글자(`NotchStatus.label(for:pending:)`), 경과 분, 저장 불가 여부. 콜백: 시작, 완료, 미루기, 바꾸기, 등록, 안 적기, 돌아가기, 다른 할 일, 다시 시작, 빠른 입력.
- 모든 쓰기는 `AppState` 한 곳에서 한다: 세션 함수 → `apply` → 성공하면 `tasks()` 다시 읽기 → 세션 교체 → 빈 상태면 고르기 → `pickedAt` 갱신.
- 활성화 판정: 앱 시작(복구 뒤), 기존 `wakeObserver`(`App/Sources/AppState.swift:41`), 노치 펼침 콜백, 설정 창 `onAppear`. 같은 함수 하나를 부른다.
- 초안의 이어서 할 일 2초 표시: 초안 상태에는 1초 타이머가 돌지 않으므로(`AppState` refresh timer) `pickedAt` + 2초에 한 번 다시 그리는 일회성 `Task.sleep`을 둔다(취소 가능).
- 온보딩 창: `LSUIElement` 앱에서 SwiftUI `Window`는 저절로 열리지 않으므로(spec 001 research, `MokaApp.swift:102`) AppKit `NSWindow` + `NSHostingController`로 띄우고 `NSApp.activate()`로 앞에 둔다. `windowWillClose`에서 끝내지 않은 것으로 본다. 온보딩 중에도 노치 패널은 그대로 뜬다.
- 종료·잠자기 알림 처리기는 기존 패턴(`queue: .main` + `MainActor.assumeIsolated`)을 따른다.
- 재사용: 숫자 칸 해석과 이유 안내는 `QuantumChip.parseCustom`·`customIssue`, 펼침을 다시 그릴 때 포커스를 한 번만 주는 것은 `OneShotRequest`.

## 작업 단위 (tasks.md의 뼈대, Issue 후보)

| # | 단위 | R-ID | 시안 확정 필요 | 무인 가능 | 앞선 단위 |
|---|---|---|---|---|---|
| 1 | MokaCore 값 타입·규칙: 열거형, `UTCTimestamp`, `LocalDay`·`DayBoundary`·`GregorianCalendar`, 고르기 순환, 세션과 버튼 → `StoreBatch`, 복구, 리셋, 쓰기 규칙, 경과 분, 설정 읽기, 저장 프로토콜·메모리 구현, 온보딩 끝내기, 목록 보기, 상태 글자 | R-101(값)·103·104·105·106·107·108·109·110·111·112·113·114·116(규칙)·118 | 아니오 | 예 | — |
| 2 | MokaStore v2 마이그레이션·스냅샷·`GRDBTaskRepository`·`GRDBContextStore` + 공용 계약 시험(메모리·GRDB) + pytest 계약 시험 | R-101·108·112·115, SC-101·106 | 아니오 | 예(스키마 스냅샷 변경은 "사람이 볼 결정") | 1a(저장 프로토콜) |
| 3 | `moka-sim` storage 모드 + storage golden + 오류 픽스처 + 계약 원본 반영 | R-117, SC-102·103·104·108 | 아니오 | 예(계약 변경은 "사람이 볼 결정") | 1 |
| 4 | 앱 화면: 설정 탭(기본·할 일·일정)과 폼, 할 일 목록 보기·정렬, 다른 할 일, 세 버튼, 두 줄 입력, 이어서 할 일 표시, 저장 불가 안내, 온보딩 두 단계, 스냅샷 | R-102·103·105·106·107·109·115·116·118·119 | 예(확정됨) | 화면 확인은 사람 | 1·2·5 |
| 5 | 앱 수명 연결: `AppState` 세션 전환, DB 열기와 실패 처리, 종료·잠자기 체크포인트, 켤 때 복구, 활성화 판정, 고르기 연결 | R-104(연결)·110·111·113(연결)·119 | 아니오 | 코드는 무인 가능, 앱 확인은 사람 | 1·2 |

순서: 단위 1 → 단위 2와 단위 3을 병렬 → 단위 5(단위 2 뒤) → 단위 4(단위 2·5 뒤). 단위 2는 단위 1a(값 타입·저장 프로토콜)만 병합되면 시작할 수 있다. 일정이 밀리면 spec 위험 1의 덜어낼 순서를 따른다.

## 설계서 대조

| 설계서 | 이 plan | 처리 |
|---|---|---|
| §2 표 7개(`scores`, `labels` 포함) | 표 넷만 | P1 (b). `scores`·`labels`는 쓰는 단계에서 |
| §2 `tasks.paused_until` | 없음 | 일시 중지(FR-20) 단계에서 `ADD COLUMN` |
| §2 `decisions_log.model_snapshot` | 둠(NULL 허용) | 사용자 위임, 토론 A 추천 |
| §2 외래 키 `ON DELETE RESTRICT`, 소프트 삭제 | 같음 | P4 (a) |
| §2 `decisions_log` INSERT만 | 같음(저장 프로토콜에 수정·삭제 메서드 없음) | P5 |
| §2 반복: 주기 시작에 status·카운트 리셋, streak 이어감 | 같음 + `cycle_day`로 멱등 | research R10 |
| §2 날짜·시각 ISO 8601 UTC 문자열, "오늘" 열 없음 | 시각은 UTC 문자열(초 단위). 날짜(마감, 컨텍스트 날짜, `cycle_day`)는 `YYYY-MM-DD` 지역 날짜 | research R13. `cycle_day`는 "오늘" 열이 아니라 주기 표시다 |
| §2 경로 `Application Support/Moka/`, WAL | `dev.dongwon.moka/`, 기본 저널 | ADR-0004, research R14 |
| §2 Core의 DayBoundary 06:00 | `DayBoundary`(`day_start` 설정) | 같음(ADR-0003) |
| §1 AppCoordinator | `AppState` 하나 | spec 001 R6 그대로 |

## 위험

spec "대안과 위험"의 위험 번호와 같다.

- 위험 1(일정): 마일스톤 2는 하루(2026-11-03)다. 단위 1~3은 무인으로 앞당긴다. 필수는 US1·US2와 R-111·R-119. 밀리면 R-118 보기·정렬 화면 → US5 화면(일정 탭·온보딩) → US4 반복 리셋 연결 → US3 종료·잠자기 연결 순서로 버퍼(2026-11-08~09)에 넘기고 PR에 적는다.
- 위험 2(되돌리기 어려운 스키마): CHECK와 열은 표를 다시 만들어야 바꿀 수 있다. 코드 폴백 줄은 F5로 받는다(공급자만 있는 줄). 폴백 모양이 문서마다 다르다: PRD prd.md:74는 "마감일 정렬"만, 설계서 tech-design.md:155는 확률 0.5 합성 + `provider = fallback`. 합성 확률을 `probs_json`에 넣을지는 마일스톤 3에서 정한다. 넣어도 F5 CHECK에 걸리지 않는다.
- 위험 3(앱 밖 쓰기 경로): `user_action`·`scheduler_choice`는 DB가 막지 않는다(P3 (c)). 튜닝 스크립트의 쓰기나 라벨셋 가져오기처럼 앱 밖 쓰기 경로가 생기면 CHECK를 다시 본다.
- 위험 4(제목 영구 보존, 개인정보): 버린 할 일의 제목은 행에 남는다(P4). 로그·체크포인트가 할 일을 가리키므로 지울 수 없다. 앱 DB는 저장소에 들어오지 않지만, 공유·백업 때 함께 나간다.
- 위험 5(종료·잠자기 기록): 로그아웃·시스템 종료·잠자기 때 알림 처리 시간이 보장되는지 미확인이다. 정상 종료만 보장한다(R-110). 기록을 못 남겨도 R-111 복구가 할 일을 대기로 되돌리므로 할 일은 잃지 않는다. 잃는 것은 경과 분 체크포인트 한 줄이다.
- 위험 6(리눅스·macOS 차이): 스냅샷 텍스트(ADR-0004 재검토 트리거), `Calendar`의 일광절약시간 처리(`repeatedTimePolicy`), `trigger` 열 이름이 리눅스 Foundation·SQLite에서 같은지 미확인이다. 단위 1·2의 첫 시험을 두 환경에서 돌린다.
- 위험 7(저장 실패): 앱 DB를 열지 못하거나 마이그레이션이 실패하면 그날은 타이머만 된다(R-119). 메모리로 대체하면 기록이 조용히 사라지므로 대체하지 않는다. 사람이 원인을 고친다. 앱은 DB 파일을 건드리지 않는다.
- 위험 8(반복 리셋은 실제 행을 바꿈): 같은 행 갱신과 멱등을 시험으로 고정한다(data-model §5.3).

## 다음 단계

1. HTML 시안 `002-mockup.html` 작성 → 사용자 확정(research R15) — v2 확정(2026-10-30), EGM 뒤 고침
2. `/speckit-tasks` — 끝남
3. EGM 금붕어 리뷰, 승인 항목은 토론 뒤 사용자 확인 — 끝남(위 "EGM 리뷰 뒤 결정")
4. spec·plan·tasks PR → Issue 큐(단위 1을 먼저, 2·3은 그 뒤 병렬, 5, 4)
