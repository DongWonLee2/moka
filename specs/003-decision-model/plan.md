# Implementation Plan: 판단 모델 연동 MVP (마일스톤 3)

**Branch**: `chore/spec-003-decision-model` (구현은 Issue별 `feat/<issue>-<slug>`) | **Date**: 2026-11-06 | **Spec**: [spec.md](spec.md)

**Input**: `specs/003-decision-model/spec.md`(R-201~R-216), EGM 리뷰 뒤 결정(research R17·R18)

## Summary

할 일 한 건과 일정만 담은 판단 입력을 TypeSafe Jev에 보내 질문 넷(urgency, impact, concrete, avoiding)의 확률을 받고, 새 표 `scores`에 할 일당 한 줄로 저장한다. priority는 저장하지 않고 고를 때 PRD 7장 식(blocked 항 없음)으로 계산해, 노치가 spec 002 순환을 priority 순으로 고른다. 키가 없거나 실패하면 점수 없이 마감일 순이다. 다시 물을 할 일은 "판단 입력 해시가 저장된 것과 다른가" 한 규칙으로 정한다(research R17). 요청 조립·응답 해석·점수·순서·다시 물을 할 일 판정은 MokaCore 순수 함수로 두어 리눅스 `swift test`로 확인하고, 앱은 URLSession 전송·Keychain·`Task` 호출과 설정 창 키 칸·priority 칸만 맡는다. 질문은 `questions.json` v1 한 벌이다. 규칙 원본은 [data-model.md](data-model.md), 결정 근거는 [research.md](research.md).

## Technical Context

**Language/Version**: Swift 6(언어 모드 6, ADR-0001). Python 3(튜닝 계약 시험)

**Primary Dependencies**: GRDB 7.11.1(기존). 새 의존성 없음. 앱은 Foundation `URLSession`과 `Security`(Keychain)를 쓴다(시스템 프레임워크)

**Storage**: SQLite(ADR-0004). 새 마이그레이션 `v3_scores`로 표 `scores` 하나. 키는 macOS Keychain(앱 DB 밖). 질문은 MokaCore 리소스 `questions.json`

**Testing**: Swift Testing(`MokaCoreTests`, `MokaStoreTests`, 리눅스 CI `core-test`), pytest(`tuning/tests`), XCTest 스냅샷 `MokaAppTests`(macOS 로컬). 실제 API·Keychain은 시험에서 쓰지 않는다

**Target Platform**: macOS 14+ 메뉴 막대 앱(ADR-0005), Package는 리눅스에서도 빌드

**Project Type**: 데스크톱 앱 + Swift Package(라이브러리 2개 + CLI) + Python 튜닝 스크립트

**Performance Goals**: 판단 질의 전체 3초 상한. 저장 뒤 10초 안에 점수(SC-201). 질의는 MainActor를 막지 않는다. 질의는 할 일마다 하나씩 보내고 동시에 최대 4개(research R17 E2)

**Constraints**: 실제 시간을 기다리는 시험 금지(헌법 II). 실제 판단 API는 시험·CI·`moka-sim`·무인 실행에서 부르지 않는다(헌법 VIII, ADR-0001 빌드 구조). 판단 입력 금지 필드 시험(헌법 VIII). 키는 Keychain에만, 로그·DB·화면에 없음(헌법 보안). 기존 golden 바이트 그대로. `decisions_log`는 INSERT만. `eraseDatabaseOnSchemaChange` 금지

**Scale/Scope**: 표 1개, 질문 파일 1개, 공급자 1개, `moka-sim` 이벤트 2종, 설정 창 화면 상태 약 6개

## Constitution Check

*GATE: Phase 0 전 확인, Phase 1 설계 뒤 다시 확인함.*

요구 다지기(2026-11-06) 질문 Q1~Q9·R2-1~R2-7과 plan 승인 항목 P1~P8은 토론(`.audit/debate/20261106-*.md`, 커밋 안 함)으로 추천안을 만들고 사용자가 정했다. 결정 로그 `.audit/spec003.tsv`. 결정 요지와 기각 이유는 research에 있다.

| 원칙 | 판정 | 근거 |
|---|---|---|
| I 승인 없는 계약 변경 금지 | 통과(승인 받음) | 아래 "승인 항목" 표. 구현 PR마다 "사람이 볼 결정"에 다시 적는다: 스키마 스냅샷(`v3_scores`), `questions.json` v1, DecisionProvider 경계, `scheduler_choice` `priority_rotate_v0`, `moka-sim` 덧붙임 |
| II 테스트 먼저, 약화 금지 | 통과 | R-ID마다 Red 커밋 → Green 커밋. 타임아웃·실패는 가짜 공급자가 오류를 돌려주는 것으로 시험하고 시간을 기다리지 않는다. 하루가 바뀌는 경우는 주입한 시각, 동시 개수는 가짜 공급자가 센다 |
| III 네 가지로만 보고 | 통과 | quickstart. 실제 호출·Keychain은 사람 확인이며 자동 PASS로 적지 않는다 |
| IV 같은 실패 2회 중단 | 통과 | 실제 응답이 문서와 다르면 해석 함수만 고친다. 두 번째 우회 없음 |
| V 작은 PR | 통과 | 아래 작업 단위 다섯을 각각 PR로 |
| VI ID로 추적 | 통과 | 시험 표시 이름에 R-ID(ADR-0003 규칙), tasks·Issue·PR 표 |
| VII 보호 장치 우회 금지 | 통과 | 해당 없음 |
| VIII 판단 모델은 판단만 | 통과 | 판단 입력은 할 일 한 건·일정·체크포인트·오늘만, 키 집합 시험. 순서·필터는 코드. `TypeSafeProvider`는 앱 타깃에만 있어 시험·`moka-sim`이 링크하지 않는다 |
| 보안·사용자 데이터 | 통과 | 키는 Keychain(R-214), 에이전트는 값을 조회하지 않는다. 판단 칸·`scores`에 제목 없음. 픽스처는 가짜. 첫 실제 호출 결과는 필드 이름만 |

설계 뒤 재확인: 위반 없음. Complexity Tracking 해당 없음.

### 승인 항목 (사용자 2026-11-06)

| # | 결정 | 표결 | 근거 |
|---|---|---|---|
| Q3·P2 | `scores` 표, `v3_scores`, 열(data-model §2), priority 열 없음, CHECK 없음 | 3:0(3라운드), 3:0 | research R3 |
| Q7·P4 | `questions.json` v1: PRD 6장 문구, impact "조금/꽤/아주"(사용자 결정), TypeSafe 모양 그대로, `model` 칸, 모델별 임계값 | 3:0 | R2·R9 |
| R2-5 | `questions.json` 위치 `Sources/MokaCore/Resources/` | 2:1(A·B / C) | R9 |
| R2-6 | blocked 없앰 | 사용자 결정(토론은 2:1, 수렴 안 함) | R2 |
| P1 | DecisionProvider 경계(Core 조립·해석·가짜, 앱 전송) | 3:0 | R7 |
| P3 | `scheduler_choice` `priority_rotate_v0` | 3:0(사용자 확인) | R8 |
| P5 | `moka-sim` `judge`·`key` | 2:1(A·C / B, 3라운드) | R13 |
| P6 | KeyStore, 로그인 키체인, 접근성 속성 없음 | 3:0 | R10 |
| P7 | 비동기는 앱, Core는 순수 함수 | 3:0 | R11 |
| P8 | FNV-1a 64, 의존성 없음 | 3:0(사용자 위임) | R12 |
| E1 | 질의 시점 = 판단 입력 해시 규칙(Q4 대체) | 3:0 | R17 |
| E2 | 동시 질의 상한 4 | 3:0(사용자 위임) | R17 |
| E3 | 키 없어도 마감일 순, spec 002 storage golden 갱신 | 3:0 | R17 |
| E4 | 실패한 할 일은 다음 활성화 때 한 번 다시, 401 뒤 멈춤 | 사용자 결정(토론 2:1, 셋째 안) | R17 |
| E5 | `moka-sim` 확장 유지 | 2:1(B·C / A) | R13·R17 |

### 가정

- `Package.swift`에 MokaCore 리소스 한 줄을 더한다(의존성 변경 아님). `Bundle.module`이 리눅스 CI 컨테이너에서도 읽히는지는 단위 1의 첫 시험에서 확인한다.
- spec 002 research R8의 "온보딩 키 단계 마일스톤 3"은 이 spec R1로 바뀐다(다음 spec).

## Project Structure

### Documentation (this feature)

```text
specs/003-decision-model/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── decision-provider.md
│   ├── questions-json.md
│   └── moka-sim-v1-additions-003.md
├── checklists/requirements.md
└── tasks.md            # /speckit-tasks
```

### Source Code (repository root)

```text
Package.swift                                   # MokaCore resources 한 줄
Sources/MokaCore/
├── Resources/questions.json                    # 새: v1
├── Decision/QuestionSet.swift                  # 새: 질문 파일 읽기
├── Decision/DecisionProvider.swift             # 새: 프로토콜·요청·응답·오류·가짜
├── Decision/TypeSafeCodec.swift                # 새: 요청 본문·응답 해석·상태 코드
├── Decision/JudgmentState.swift                # 새: 판단 입력 조립·정준 바이트·FNV-1a
├── Decision/ScoreRules.swift                   # 새: 해석 → TaskScore, 정규화·priority
├── Decision/ScoringPlan.swift                  # 새: 질의 대상·답 받기
├── Decision/KeyStore.swift                     # 새: 프로토콜·메모리 구현
├── PriorityOrder.swift                         # 새: 순서·순환
├── Storage.swift                               # ScoreStore·InMemoryScoreStore 덧붙임
├── DecisionLog.swift                           # SchedulerChoice 값 덧붙임
├── NotchSession.swift                          # 고르기·nextMark·logLine이 점수를 씀
├── Defaults.swift                              # 가중치·시간 값
└── Sim/                                        # judge·key 이벤트(단위 5)
Sources/MokaStore/
├── Migrations.swift                            # v3_scores
└── GRDBScoreStore.swift                        # 새
App/Sources/
├── Decision/TypeSafeProvider.swift             # 새: URLSession
├── Decision/KeychainKeyStore.swift             # 새: Security
├── AppState.swift                              # 트리거·Task·답 받기·화면 값
└── Views/BasicTabView.swift, TaskListTabView.swift  # 키 칸, priority 칸
Tests/MokaCoreTests/, Tests/MokaStoreTests/, App/Tests/MokaAppTests/, tuning/tests/
schema/moka-schema.sql                          # 스냅샷 갱신
```

**Structure Decision**: ADR-0001 구조 그대로다. 새 타깃·의존성 없음. 판단 관련 Core 파일은 `Sources/MokaCore/Decision/` 아래에 모은다. 화면 뷰는 스냅샷 번들이 컴파일하는 `App/Sources/Views/`에 두고 `AppState`를 모르게 한다(ADR-0009).

### 앱 연결

- `MokaApp`이 DB를 열 때 `GRDBScoreStore`도 만들어 `AppStorage.scores`로 넘긴다. `KeychainKeyStore`와 `TypeSafeProvider`(키는 질의 때마다 `KeyStore.read`)를 만든다.
- 질의 흐름은 data-model §6·§9. 진행 중 `Task`를 할 일별로 들고 있지 않는다. 보내기 장부 `attempted`는 해시 사전이고 취소 기능은 없다. 겹친 답은 답 받기 판정(해시 비교)이 거른다. 앱 종료 때 진행 중 질의는 버린다.
- 묻는 곳은 `reloadTasks`·`reloadContexts`·`activate`·키 저장·"다시 물어보기"에서 부르는 `requestScores()` 하나다. 노치 빠른 입력(`enterTitle`)도 `reloadTasks`를 거치므로 따로 잇지 않는다.
- 노치 고르기는 기존 `pickIfEmpty`가 `NotchSession`에 점수를 넘겨 그대로 돈다. 점수가 들어와도 초안·도는 중은 바꾸지 않는다.

## 작업 단위 (tasks.md의 뼈대, Issue 후보)

| # | 단위 | R-ID | 시안 확정 | 무인 가능 | 앞선 단위 |
|---|---|---|---|---|---|
| 1a | MokaCore 판단 입력과 점수: `questions.json`·`QuestionSet`, 판단 입력·해시, 판단 결과 해석·정규화·priority·`usable` | R-201·202·203·204·205(값) | 아니오 | 예 | — |
| 1b | MokaCore 공급자와 질의: 공급자·오류·가짜, TypeSafe 조립·해석, 다시 물을 할 일·답 받기, `KeyStore`, `ScoreStore` 프로토콜·메모리 | R-206·210·211·214(프로토콜) | 아니오 | 예 | 1a |
| 2 | 순서와 로그: `PriorityOrder`, `NotchSession` 고르기·`nextMark`·`logLine`, `scheduler_choice`, spec 002 storage golden 갱신 | R-208·209·212 | 아니오 | 예(golden 갱신은 "사람이 볼 결정") | 1a |
| 3 | MokaStore `v3_scores`·`GRDBScoreStore`·공용 계약·스냅샷 + pytest(`scores` 열, `questions.json` 경로) | R-205 | 아니오 | 예(스키마는 "사람이 볼 결정") | 1b |
| 4 | 앱: `TypeSafeProvider`, `KeychainKeyStore`, AppState 질의·보내기 장부·답 받기, 설정 창 키 칸·priority 칸, 스냅샷 | R-207·211(연결)·213·214·215 | 예(설정 창 시안) | 코드는 가능, 화면·실제 호출·Keychain은 사람 | 1b·2·3 |
| 5 | `moka-sim` `judge`·`key` + golden | R-216 | 아니오 | 예(계약은 "사람이 볼 결정") | 2 |

순서: 1a → 1b와 2 병렬 → 3(1b 뒤) → 4(시안은 1a와 함께 먼저 만들어 확정) → 5. 2026-11-08까지 1~4가 끝나지 않으면 5와 R-215를 다음 spec으로 넘긴다(spec 위험 1).

## 설계서 대조

| 설계서 | 이 plan | 처리 |
|---|---|---|
| 3장 기본 경로 OpenRouter, 키 하나로 두 모델 | TypeSafe 직접 하나 | 사용자 결정 2026-10-30(spec 002 research R8) |
| 3.1 `ProviderID` 열거형, `usage.costUSD` | 공급자 이름 문자열, 비용 없음 | R7, TypeSafe 응답에 cost 없음 |
| 3.2 질문 문구·impact 4단계·blocked | PRD 6장 문구, impact 3단계 "조금/꽤/아주", blocked 없음 | R2 |
| 3.3 폴백 합성 확률 0.5 | 마감일 정렬만 | R5 |
| 3.4 401 노치 "키 확인", 429 백오프, 서킷브레이커 | 설정 창 문구만, 그 자리 재시도 없음, 실패는 다음 활성화 때 한 번 | R5·R17, 마일스톤 5·다음 spec |
| PRD 7장 7번 재점수 시점·6시간 캐시 | 판단 입력 해시 규칙 | R17 |
| 2장 `scores` 열(priority, confidence_json) | priority 없음, `probs_json`·`state_hash` | R3 |

## 위험

spec "대안과 위험"의 번호와 같다.

- 위험 1(일정): 검증 시작 11/10 고정, 마일스톤 4·5가 남았다. 필수는 R-201~R-214(단위 1~3과 단위 4의 공급자·Keychain·질의 연결·키 칸). 밀리면 R-215(priority 칸) → R-216(단위 5) 순서로 다음 spec에 넘기고 PR에 적는다.
- 위험 2(실제 응답 형식): 공식 문서와 실제가 다르면 `TypeSafeCodec.response`만 고친다. 확인은 사람만 할 수 있다(quickstart 6-3).
- 위험 3(Keychain): 확인 창 반복·접근성 속성은 리눅스 CI로 확인할 수 없다. 개인 팀 서명 빌드에서 사람이 본다(quickstart 6-2).
- 위험 4(되돌리기 어려운 계약): `scores` 열, `questions.json` 형식, `priority_rotate_v0`. 열·값을 적게 두었다.
- 위험 5(개인정보): 할 일 제목과 일정 이름이 TypeSafe로 간다. 로그·`scores`·`moka-sim` 출력에는 제목이 없다.
- 위험 6(PRD와 다름): blocked 삭제, impact 옵션, 6시간 캐시 대신 해시 규칙. 사람이 PRD 6·7·9장을 고친다.
- 위험 7(실패 뒤 순서): 오늘 마감 할 일의 질의가 실패하면 점수 없는 무리로 뒤에 선다. 다음 활성화 때 한 번 다시 묻고, "다시 물어보기"·앱 재시작·다음 날에도 회복된다. 설정 창 priority 칸이 비어 알아챌 수 있다. 사람 확인(quickstart 6-4)에서 자주 보이면 다음 spec에서 정렬 예외를 다시 본다.
- 위험 8(`Bundle.module` 리눅스): 리눅스 Foundation에서 리소스 번들이 읽히지 않으면 단위 1a 첫 시험에서 드러난다. 그때 대안(시험은 파일 경로로 읽기)을 PR "가정"에 적는다.

## 다음 단계

1. `/speckit-tasks`
2. EGM 금붕어 리뷰(spec·plan·tasks 묶음, `uninterrupted`), 판단이 필요한 지적은 토론 뒤 사용자 확인
3. 설정 창 HTML 시안(키 칸 상태 다섯, priority 칸) → 사용자 확정
4. spec·plan·tasks PR → Issue 큐(단위 1a → 1b·2 → 3 → 4 → 5)
