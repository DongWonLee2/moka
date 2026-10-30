# Implementation Plan: 저장과 체크포인트 (마일스톤 2)

**Branch**: `chore/spec-002-storage-checkpoint` (구현은 Issue별 `feat/<issue>-<slug>`) | **Date**: 2026-10-30 | **Spec**: [spec.md](spec.md)

**Input**: `specs/002-storage-checkpoint/spec.md`(R-101~R-117)

## Summary

할 일, 컨텍스트, 체크포인트, 행동 로그를 GRDB에 저장한다. 새 마이그레이션 `v2_tasks_contexts_checkpoints_log` 하나가 표 넷을 만든다. 노치 고르기(R-104), 체크포인트 기록, 반복 리셋(R-113), 하루 경계(R-114), 재시작 복구(R-111)는 MokaCore 순수 함수와 값 타입으로 두고 리눅스 `swift test`와 `moka-sim`으로 화면 없이 검증한다. 저장 프로토콜과 메모리 구현은 MokaCore, GRDB 구현은 MokaStore다. 같은 계약 시험을 두 구현에 돌린다. `moka-sim`은 v1에 시나리오 선택 필드 `storage`와 이벤트를 덧붙이고, 기존 golden 출력은 바이트 그대로 둔다. API 키는 앱 타깃의 Keychain 구현에만 저장한다. 화면(설정 탭, 버튼, 두 줄 입력, 온보딩)은 HTML 시안을 사용자가 확정한 뒤 만든다. 결정 근거는 [research.md](research.md).

## Technical Context

**Language/Version**: Swift 6(언어 모드 6, ADR-0001). Python 3(튜닝 계약 시험)

**Primary Dependencies**: GRDB 7.11.1(`MokaStore`, 기존). 새 의존성 없음. Keychain은 시스템 `Security` 프레임워크(앱 타깃만)

**Storage**: SQLite `~/Library/Application Support/dev.dongwon.moka/moka.sqlite`(ADR-0004). 표: 기존 `settings` + 새 `tasks`, `contexts`, `checkpoints`, `decisions_log`. 저널은 GRDB `DatabaseQueue` 기본값 유지(research R14). API 키는 Keychain(service `dev.dongwon.moka`, account `openrouter`). 타이머와 "직전 할 일"은 메모리

**Testing**: Swift Testing(`MokaCoreTests`, `MokaStoreTests`, 리눅스 CI `core-test`), pytest(`tuning/tests`, CI `tuning-test`), XCTest 스냅샷 번들 `MokaAppTests`(macOS 로컬)

**Target Platform**: macOS 14+, `LSUIElement` 메뉴 막대 앱(ADR-0005). Package 타깃은 리눅스(`swift:6.3.3-noble`)에서도 빌드

**Project Type**: 데스크톱 앱 + Swift Package(라이브러리 2개 + CLI) + Python 튜닝 스크립트

**Performance Goals**: 버튼 한 번의 저장(할 일 갱신 + 체크포인트 + 로그 한 줄)은 한 트랜잭션. 계기 측정은 하지 않는다. 할 일 수는 수십 건 규모라 색인을 두지 않는다

**Constraints**: 실제 시간을 기다리는 시험 금지(헌법 II). MokaCore에서 `Date()`·`TimeZone.current`를 직접 읽지 않음(ADR-0003). 테스트·`moka-sim`은 실제 앱 DB와 실제 Keychain을 열지 않음(SC-106, ADR-0004·0006). `eraseDatabaseOnSchemaChange` 금지. `decisions_log`는 INSERT만. 종료를 붙잡지 않음(R-110). 로그·`moka-sim` 출력에 할 일 제목·체크포인트 본문·키 없음

**Scale/Scope**: 사용자 1명, 할 일 수십 건, 표 4개 추가, 설정 키 3개 추가, `moka-sim` 이벤트 10종 추가, 화면 상태 약 10개 추가

## Constitution Check

*GATE: Phase 0 전 확인, Phase 1 설계 뒤 다시 확인함.*

승인 항목 P1~P8은 토론(`.audit/debate/20261030-plan002-approvals.md`, 커밋 안 함, 3라운드)으로 추천안을 만들고 사용자가 2026-10-30 정했다. 설계 중 생긴 후속 결정 F1~F6은 토론(`.audit/debate/20261030-plan002-followups.md`, 커밋 안 함)을 거쳐 같은 날 사용자가 정했다(아래 "후속 결정").

| 원칙 | 판정 | 근거 |
|---|---|---|
| I 승인 없는 계약 변경 금지 | 통과(승인 받음) | P1 새 마이그레이션 하나에 표 넷(3:0), P2 `tasks.weekday` 1~7과 짝 CHECK(3:0), P3 닫힌 칸에만 CHECK·`user_action`·`scheduler_choice`는 TEXT(2:1, A·B / C, 사용자 결정 (c)), P4 소프트 삭제·`ON DELETE RESTRICT`(3:0), P5 `decisions_log` PRD 9장 열 + 판단 칸 NULL 허용(3:0), `model_snapshot` 추가는 사용자 위임(토론 A 추천), P6 `moka-sim` v1 덧붙이기·기존 golden 바이트 불변(3:0), P7 프로토콜·메모리는 MokaCore·GRDB는 MokaStore(3:0), P8 키 프로토콜 MokaCore·Keychain은 앱 타깃(3:0). 후속: F1 `tasks` 열 범위(3:0), F2 `cycle_day` 짝 CHECK(2:1, A·C / B, 사용자 결정), F3 활성화 정의(3:0), F4 하루 경계 달력 ADR-0010(3:0), F5 `decisions_log` 판단 칸 CHECK 문구 변경(3:0, P5 사용자 재승인), F6 `moka-sim` 이벤트 모양(3:0). 구현 PR마다 "사람이 볼 결정"에 다시 적는다 |
| II 테스트 먼저, 약화 금지 | 통과 | R-ID마다 Red 커밋 → Green 커밋. 하루 경계·반복 리셋은 주입한 `MokaClock`·`Calendar`(`Asia/Seoul`, `America/New_York`). 리셋 멱등, dropped 제외, 모르는 열거 값 읽기 실패를 Red 시험으로 먼저 둔다. 오류 주입은 quickstart 3 |
| III 네 가지로만 보고 | 통과 | quickstart 결과는 PASS/FAIL/SKIP/NOT_RUN. Keychain 확인 창과 종료·잠자기 기록은 사람 확인이며 자동 PASS로 적지 않는다 |
| IV 같은 실패 2회 중단 | 통과 | Keychain 확인 창이 개인 팀 서명에서 반복되면 키 단계만 마일스톤 3으로 미룬다(spec 위험 4). 두 번째 시도 없음 |
| V 작은 PR | 통과 | 아래 "작업 단위" 5개를 각각 PR로. 단위 1·2·3은 Issue 여러 개로 더 쪼갠다 |
| VI ID로 추적 | 통과 | 테스트 표시 이름 `FR-07 R-108: …`(ADR-0003). tasks·Issue·PR 표에 R-ID |
| VII 보호 장치 우회 금지 | 통과 | 해당 없음. 앱 DB 경로 deny 규칙(ADR-0006)은 그대로 |
| VIII 판단 모델은 판단만 | 통과 | 판단 질의 없음. 키는 저장·존재 여부·삭제만, 값 읽기는 마일스톤 3. 외부 호출 없음. `moka-sim`은 네트워크·DB·Keychain 인자 없음. 판단 칸에 원문 텍스트를 넣지 않는다 |
| 보안·사용자 데이터 | 통과 | 시나리오·스냅샷·픽스처는 가짜 할 일만. `moka-sim` 출력에 제목·두 줄 본문 없음. 가짜 키 문자열이 settings·로그에 없는지 시험. 키 값 print 금지 |

설계 뒤 재확인: 위반 없음. Complexity Tracking 해당 없음.

### 후속 결정 (설계 중 생김, 사용자 2026-10-30)

토론 `.audit/debate/20261030-plan002-followups.md`(커밋 안 함)의 추천안을 사용자가 정했다.

| # | 결정 | 표결 | 사람 |
|---|---|---|---|
| F1 | `tasks`에는 이번 단계가 쓰는 열만 둔다. `quantum_min`, `is_urgent`, `carry_count`, `due_decision`, 설계서의 `paused_until`은 쓰는 단계에서 `ADD COLUMN`(research R1) | 3:0 | 승인 |
| F2 | `tasks.cycle_day` 열과 `CHECK((recurrence = 'none') = (cycle_day IS NULL))`(research R10) | 2:1(A·C / B) | 사용자 결정(다수안) |
| F3 | 활성화 = 앱 시작, 잠자기에서 깨어남, 노치 펼침, 설정 창 열기(research R11) | 3:0 | 승인 |
| F4 | 하루 경계·`LocalDay`는 `Calendar(identifier: .gregorian)` 고정, 시간대는 시스템. [ADR-0010](../../adr/ADR-0010-day-boundary-calendar.md)이 ADR-0003의 한 문장을 대체(research R9) | 3:0 | 승인 |
| F5 | `decisions_log`: `CHECK(provider IS NOT NULL OR (question_version IS NULL AND probs_json IS NULL AND state_hash IS NULL))` + `CHECK(model_snapshot IS NULL OR provider IS NOT NULL)`. 공급자만 있는 폴백 줄을 받는다(research R5) | 3:0(형태 2:1, 의미 같음) | P5 문구 변경 재승인 |
| F6 | `moka-sim` 버튼과 두 줄은 한 이벤트, 완료는 기존 `complete`([contracts/moka-sim-v1-additions.md](contracts/moka-sim-v1-additions.md)). 경과 분은 저장 순간 기준(data-model §5.5) | 3:0 | 승인 |

소수 의견:
- F2(B): CHECK 없이 GRDB 왕복 시험과 `moka-sim` 불변식 오류 주입으로 지킨다. 표 수준 CHECK가 있으면 `cycle_day`를 지우거나 뜻을 바꿀 때 `DROP COLUMN`을 못 해 표를 다시 만들어야 하고, P3의 사용자 판단(로컬 앱이라 엄격히 막지 않음)과도 가벼운 쪽이 맞다.
- F5 형태(C): `model_snapshot`까지 한 식으로 묶자. 허용 집합은 같다.

### 가정

- F3 차이: 설계서 tech-design.md:193은 하루 경계 판정을 앱 활성화·잠자기 해제·매일 06:00 타이머 세 곳에서 부른다. 이 plan은 06:00 타이머를 두지 않고 노치 펼침·설정 창 열기를 더한다. 판정이 멱등이고, 사용자가 노치를 보는 순간에 돌면 충분하며, 예약 타이머는 잠자기·시계 변경에 약하다(research R11).
- `UserAction` 열거형은 이번에 쓰는 `done`·`skip`·`switch`만 둔다. PRD의 나머지 값은 쓰는 단계에서 덧붙인다. TEXT 칸이라 스키마 변경이 아니다(research R3).

## Project Structure

### Documentation (this feature)

```text
specs/002-storage-checkpoint/
├── spec.md
├── plan.md               # 이 파일
├── research.md           # R1~R16 결정(후속 F1~F6 반영)
├── data-model.md         # 값 타입, 상태 전이, 고르기·리셋 규칙, v2 SQL, 설정 키
├── quickstart.md         # 검증 절차 1~7
├── contracts/
│   └── moka-sim-v1-additions.md   # v1에 덧붙이는 이벤트·출력. 원본 계약은 구현 PR에서 고친다
├── checklists/requirements.md
└── tasks.md              # 시안 확정 뒤 작성
```

시안: `~/Dev/ai-platform/projects/moka/design/002-mockup.html`(저장소 밖, 로컬 전용, 아직 없음).

### Source Code (repository root)

```text
Sources/MokaCore/
├── Defaults.swift                    # 기존 + extendMin 10, extendMinRange 1…180, dayStart 06:00
├── QuantumSettings.swift             # 기존(SettingsStore). 바꾸지 않음
├── AppSettings.swift                 # 새: default_extend_min·day_start·onboarding_done 읽기·쓰기 규칙
├── TaskModel.swift                   # 새: MokaTask, TaskStatus, Recurrence, Weekday, NewTask
├── ContextModel.swift                # 새: MokaContext, ContextImpact, NewContext
├── CheckpointModel.swift             # 새: Checkpoint, CheckpointTrigger, CheckpointNotes, 경과 분 계산
├── DecisionLog.swift                 # 새: DecisionLogEntry, UserAction, SchedulerChoice
├── LocalDay.swift                    # 새: LocalDay, DayStart, DayBoundary(하루 경계, R-114)
├── TaskRules.swift                   # 새: OldestUnpickedRule(R-104), RecurrenceReset(R-113), LaunchRecovery(R-111)
├── NotchSession.swift                # 새: 타이머 + 할 일 연결 + 직전 할 일, 버튼 → StoreBatch
├── Storage.swift                     # 새: TaskRepository, ContextStore, StoreBatch, StoreError + 메모리 구현
├── KeyStore.swift                    # 새: KeyStore 프로토콜 + InMemoryKeyStore(가짜)
├── Onboarding.swift                  # 새: 온보딩 끝내기 규칙(설정 쓰기, 키는 KeyStore로만)
└── Sim/                              # 기존 + storage 모드 디코딩·실행·출력
Sources/MokaStore/
├── Migrations.swift                  # v2_tasks_contexts_checkpoints_log 덧붙임
├── GRDBTaskRepository.swift          # 새
└── GRDBContextStore.swift            # 새
Tests/MokaCoreTests/                  # 규칙·값 타입·Sim storage golden
Tests/MokaCoreTests/Fixtures/sim/     # 기존 그대로 + storage 시나리오(storage-*.json)
Tests/MokaStoreTests/                 # 이름 리터럴 갱신, 스냅샷, 공용 계약 시험(메모리·GRDB), GRDB로 golden 재실행
schema/moka-schema.sql                # 스냅샷 갱신(표 넷 추가)
tuning/tests/test_schema_contract.py  # 새: 스냅샷으로 가짜 DB를 만들어 decisions_log 열 확인
App/Sources/
├── MokaApp.swift                     # DB 하나를 열어 저장소들에 나눠 줌, 온보딩 창, 종료 알림
├── AppState.swift                    # NotchSession 보관, 버튼·두 줄 입력, 잠자기·종료·활성화 처리
├── Keychain/KeychainKeyStore.swift   # 새: KeyStore 구현(앱 타깃만)
├── Settings/SettingsView.swift       # 탭(기본·할 일·컨텍스트) 틀
└── Views/                            # 새 뷰: 할 일 목록·폼, 컨텍스트 목록·폼, 버튼 줄, 두 줄 입력, 첫 행동 줄, 온보딩 3단계(스냅샷 대상)
App/Tests/MokaAppTests/               # 새 화면 상태 스냅샷
project.yml                           # 바뀌지 않음(새 파일은 폴더 단위로 잡힘). 확인만
adr/ADR-0010-day-boundary-calendar.md # 새(F4): ADR-0003의 앱 달력 문장 대체. ADR-0003:30 끝에 포인터만
```

**Structure Decision**: ADR-0001 구조 그대로다. 새 타깃·의존성 없음. `Package.swift`는 바꾸지 않는다. 공용 계약 시험은 MokaCore와 MokaStore를 둘 다 보는 `MokaStoreTests`에 둔다(research R7). 새 화면 뷰는 스냅샷 번들이 컴파일하는 `App/Sources/Views/`에 둔다(ADR-0009).

## 작업 단위 (tasks.md의 뼈대, Issue 후보)

| # | 단위 | R-ID | 시안 확정 필요 | 무인 가능 | 앞선 단위 |
|---|---|---|---|---|---|
| 1 | MokaCore 값 타입·규칙: 열거형, `LocalDay`·`DayBoundary`, R-104 고르기, R-111 복구, R-113 리셋·멱등, `NotchSession` 버튼 → `StoreBatch`, 경과 분, 설정 읽기 규칙, 저장 프로토콜·메모리 구현, `KeyStore`·가짜, 온보딩 끝내기 규칙 | R-101(값 검증)·104·106·107·108·109·111·112·113·114·116(규칙) | 아니오 | 예 | — |
| 2 | MokaStore v2 마이그레이션·스냅샷·`GRDBTaskRepository`·`GRDBContextStore` + 공용 계약 시험(메모리·GRDB) + pytest 스키마 계약 시험 | R-101·108·112·115, SC-101·106 | 아니오 | 예(스키마 스냅샷 변경은 "사람이 볼 결정") | 1의 프로토콜 |
| 3 | `moka-sim` storage 모드 + storage golden + 오류 픽스처 + MokaStoreTests에서 GRDB로 golden 재실행 + 계약 원본 반영 | R-117, SC-102·103·104 | 아니오 | 예(계약 변경은 "사람이 볼 결정") | 1, GRDB 재실행은 2 |
| 4 | 앱 화면: 설정 탭(할 일·컨텍스트)과 폼, 완료·미루기·바꿔줘 버튼, 두 줄 입력, 첫 행동 표시, 온보딩 3단계, `KeychainKeyStore`, 스냅샷 | R-102·103·105·106·107·109·115·116 | 예 | 화면 확인은 사람. Keychain 확인 창은 개인 팀 서명 빌드로 사람 | 1·2, 시안 확정 |
| 5 | 앱 수명 연결: 종료·잠자기 체크포인트, 켤 때 R-111 복구, 활성화 때 하루 판정, 노치 고르기 연결 | R-104(연결)·110·111·113(연결) | 아니오 | 코드는 무인 가능, 앱 확인은 사람 | 1·2 |

순서: 1 → 2 → (3, 5 병렬) → 4. 단위 3의 시뮬레이터 본체는 1만 있으면 시작할 수 있고, GRDB 재실행 시험만 2 뒤에 붙인다. 단위 4는 시안 확정 전에 시작하지 않는다. 일정이 밀리면 spec 위험 1대로 큐 뒤쪽(반복 리셋 연결, 온보딩 키 단계, 종료·잠자기 연결)을 버퍼로 넘긴다.

## 설계서 대조

| 설계서 | 이 plan | 처리 |
|---|---|---|
| §2 표 7개(`scores`, `labels` 포함) | 표 넷만 | P1 (b). `scores`·`labels`는 쓰는 단계에서 |
| §2 `tasks.paused_until` | 없음 | 일시 중지(FR-20) 단계에서 `ADD COLUMN` |
| §2 `decisions_log.model_snapshot` | 둠(NULL 허용) | 사용자 위임, 토론 A 추천 |
| §2 외래 키 `ON DELETE RESTRICT`, 소프트 삭제 | 같음 | P4 (a) |
| §2 `decisions_log` INSERT만 | 같음(저장 프로토콜에 수정·삭제 메서드 없음) | P5 |
| §2 반복: 주기 시작에 status·카운트 리셋, streak 이어감 | 같음 + `cycle_day`로 멱등 | research R10 |
| §2 날짜·시각 ISO 8601 UTC 문자열, "오늘" 열 없음 | 시각은 UTC 문자열. 날짜(마감, 컨텍스트 날짜, `cycle_day`)는 `YYYY-MM-DD` 지역 날짜 | research R13. `cycle_day`는 "오늘" 열이 아니라 주기 표시다 |
| §2 경로 `Application Support/Moka/`, WAL | `dev.dongwon.moka/`, 기본 저널 | ADR-0004, research R14 |
| §2 Core의 DayBoundary 06:00 | `DayBoundary`(`day_start` 설정) | 같음(ADR-0003) |
| §1 AppCoordinator | `AppState` 하나 | spec 001 R6 그대로 |

## 위험

- 위험 1(일정): 마일스톤 2는 하루(11/3)다. 단위 1~3은 무인으로 앞당기고, 4는 시안 확정이 늦으면 밀린다. 밀리면 큐 뒤쪽을 버퍼(11/8~9)로 넘기고 PR에 적는다.
- 위험 2(되돌리기 어려운 스키마): CHECK와 열은 표를 다시 만들어야 바꿀 수 있다. 코드 폴백 줄이 막히는 문제는 F5로 해소했다: 공급자만 있고 다른 판단 칸이 비어 있는 줄(`provider = 'fallback'`)을 받는다. 남은 사실: 폴백의 모양이 문서마다 다르다. PRD prd.md:74는 "마감일 정렬"만 적었고, 설계서 tech-design.md:155는 "concrete = first_action 유무, 나머지 0.5"로 확률을 합성하고 `provider = fallback`으로 로그한다. 합성 확률을 `probs_json`에 넣을지는 마일스톤 3에서 정한다. 넣어도 F5 CHECK에 걸리지 않는다.
- 위험 3(앱 밖 쓰기 경로): `user_action`·`scheduler_choice`는 DB가 막지 않는다(P3 (c)). 지금 쓰는 곳은 앱 하나다. 튜닝 스크립트가 쓰기를 하거나 라벨셋 가져오기처럼 앱 밖 쓰기 경로가 생기면 CHECK를 다시 본다.
- 위험 4(제목 영구 보존): 버린 할 일의 제목은 행에 남는다(P4). 로그·체크포인트가 할 일을 가리키므로 지울 수 없다. 앱 DB는 저장소에 들어오지 않지만, 공유·백업 때 함께 나간다.
- 위험 5(Keychain): 개인 팀 서명에서도 확인 창이 반복될 수 있다(ADR-0005, 미확인). 반복되면 키 단계만 마일스톤 3으로 미룬다. `ThisDeviceOnly` 접근성 속성과 data protection keychain 사용 조건은 미확인이다.
- 위험 6(종료·잠자기 기록): 로그아웃·종료·잠자기 때 알림 처리 시간이 보장되는지 미확인이다. 기록을 못 남겨도 R-111 복구가 할 일을 대기로 되돌리므로 할 일은 잃지 않는다. 잃는 것은 경과 분 체크포인트 한 줄이다.
- 위험 7(리눅스·macOS 차이): 스냅샷 텍스트(ADR-0004 재검토 트리거)와 `Calendar`의 일광절약시간 처리(`repeatedTimePolicy`)가 리눅스 Foundation에서 같은지 미확인이다. 단위 1·2의 첫 시험을 두 환경에서 돌린다.

## 다음 단계

1. HTML 시안 `002-mockup.html` 작성 → 사용자 확정(research R15)
2. `/speckit-tasks`
3. EGM 금붕어 리뷰, 승인 항목은 토론 뒤 사용자 확인
4. Issue 큐(단위 1·2를 먼저, 3·5는 그 뒤, 4는 시안 확정 뒤)
