# Quickstart: 저장과 체크포인트 검증 (spec 002)

화면 없는 검증(1~4)은 무인으로 돌 수 있다. 화면과 앱 수명 검증(5~7)은 사람이 한다. 결과는 PASS / FAIL / SKIP / NOT_RUN으로만 적는다. 시나리오·픽스처·스냅샷은 가짜 할 일과 가짜 키만 쓴다.

## 1. 핵심 로직과 스키마 (리눅스·macOS)

```
swift test
```

기대: 기존 시험과 새 R-ID 시험(`@Test("FR-07 R-108: …")` 등)이 모두 PASS. 포함 범위:
- MokaCore: 노치 고르기(R-104, 버림 제외·후보 하나·직전 할 일 제외), 버튼 → `StoreBatch`(R-106·107·108·109·112, 버튼 한 번 = 로그 한 줄), 재시작 복구(R-111), 반복 리셋(R-113: 매일·매주, 연속 기록 잇기·0, 두 번 돌려도 같음, 버림 제외), 하루 경계(R-114: 05:59:59/06:00:00, `Asia/Seoul`·`America/New_York`, 일광절약 전환일), 경과 분, 첫 행동 접힘 2초, 설정 읽기 규칙(`default_extend_min`, `day_start`, `onboarding_done`), 온보딩 끝내기(가짜 키가 settings·로그·체크포인트에 없음)
- MokaStore: 마이그레이션 이름 리터럴 `["v1_settings", "v2_tasks_contexts_checkpoints_log"]`, 스키마 스냅샷, 경로 가드, 공용 계약 시험(메모리·GRDB 두 구현), 모르는 `user_action`·`scheduler_choice` 읽기 실패, `ON DELETE RESTRICT`, 판단 칸 일부만 채운 줄 거부, storage golden을 GRDB로 다시 돌림
- `moka-sim` golden: 기존 시나리오(기대 출력 파일 변경 없음)와 storage 시나리오

리눅스 컨테이너에서도 같은 결과인지 확인(스냅샷 텍스트와 하루 경계, research R9·R16):

```
docker run --rm -v "$PWD":/w -w /w swift:6.3.3-noble bash -c "apt-get update -qq && apt-get install -y -qq --no-install-recommends libsqlite3-dev >/dev/null && swift test --scratch-path /tmp/.build-linux"
```

기존 golden 불변 확인:

```
git diff --stat main -- Tests/MokaCoreTests/Fixtures/sim/*.expected.jsonl
```

기대: storage 아닌 기대 출력 파일의 변경 0줄(새 `storage-*` 파일만 추가).

## 2. 시뮬레이터

```
swift run moka-sim run Tests/MokaCoreTests/Fixtures/sim/<시나리오>.json
```

기대: [contracts/moka-sim-v1-additions.md](contracts/moka-sim-v1-additions.md) 형식의 JSON Lines, 종료 코드 0. 출력에 제목·두 줄 본문이 없다. 최소 storage 시나리오:
- 계약 예시(추가 → 시작 → 바꿔줘 → 다른 할 일 → 완료 → 종료 → 다음 날 재시작)
- 할 일 하나뿐일 때 미루기 → 같은 할 일이 다시 뽑힘, `skip_count` 1
- 시간 끝에서 미루기·바꿔줘·완료·다시 시작 → 계기 `quantum`, 두 줄이 비어도 체크포인트가 남음
- 두 줄 모두 건너뜀 → 체크포인트는 빈 줄, `has_first_action`은 이전 값 유지
- 잠자기(도는 중) → 계기 `sleep`, 그 뒤 끝 시각을 넘긴 이벤트에서 `expired`(체크포인트 둘)
- `quit` 없이 `relaunch` → `active`가 `todo`로, 타이머 없음
- 매일 반복: 완료 → 다음 날 06:00 뒤 `activate` → `todo`, 연속 기록 유지. 하지 않은 채 하루 지남 → 연속 기록 0, 할 일 수 그대로. 같은 날 `activate` 두 번 → 두 번째 줄의 `tasks`가 첫 번째와 같음
- 매주 수요일: 목~화 `activate`에서는 그대로, 다음 수요일 06:00 뒤에 `todo`
- `America/New_York` 시간대로 3월 전환일을 넘는 매일 반복
- `set_day_start`로 06:00 → 09:00(07:00에) → 이미 돈 오늘 리셋이 되돌려지지 않음
- 도는 할 일을 `delete_task` → 타이머 멈춤, 다음 할 일 고름, 로그·체크포인트 수 그대로
- 오류 입력(`Fixtures/sim/errors/storage-*.json`: `storage` 없이 새 이벤트, 없는 `task`, 버린 할 일 고침, `weekday` 8, 꺼짐 뒤 `start` 등) → 종료 코드 2, 표준 출력 비어 있음

## 3. 오류 주입 (검증기 검증)

커밋하지 않는다. 각각 FAIL과 종료 코드 0 아님을 확인하고 되돌린다.
- 기대 출력 한 줄의 `elapsed_min`을 바꿈 → golden FAIL(메모리, GRDB 둘 다)
- 마이그레이션에서 `decisions_log.model_snapshot`을 지움 → 스냅샷 시험 FAIL, pytest 계약 시험 FAIL(ADR-0004)
- 가짜 마이그레이션 하나를 더 등록 → 이름 시험 FAIL(ADR-0007)
- `RecurrenceReset`의 `<`를 `!=`로 바꿈 → 하루 시작 시각 변경 시험 FAIL
- 고르기에서 `dropped` 제외를 뺌 → R-104 시험 FAIL
- 메모리 저장소의 `apply`에서 되돌림을 뺌 → 공용 계약 시험(메모리 쪽) FAIL

## 4. 튜닝 스크립트

```
cd tuning && python3 -m pytest
```

기대: `test_schema_contract.py`가 `schema/moka-schema.sql`로 메모리 DB를 만들고 `decisions_log` 열 이름(R5), 판단 칸이 모두 NULL인 가짜 줄 넣기, 판단 칸 일부만 채운 줄 거부를 확인해 PASS.

## 5. 앱 빌드와 스냅샷

```
xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodegen generate && TEST_RUNNER_MOKA_SNAPSHOT_DIR="$PWD/.verify/snapshots/002" xcodebuild test -scheme Moka -destination 'platform=macOS' -only-testing:MokaAppTests
```

빌드 성공은 완료가 아니다. 스냅샷 기대: 새 화면 상태마다 PNG 라이트·다크(설정 탭 셋, 할 일 폼, 컨텍스트 폼, 버튼 줄이 있는 도는 중, 두 줄 입력, 시간 끝 + 두 줄, 첫 행동 접힘·펼침, 온보딩 3단계). sanity 시험 PASS. 사람이 `~/Dev/ai-platform/projects/moka/design/pr-<번호>/index.html`에서 시안 `002-mockup.html`과 나란히 본다(ADR-0009).

## 6. 사람이 손으로 볼 것 (화면)

- 노치에 가짜 할 일 셋을 넣고 앱을 종료 → 다시 켬 → 셋이 남아 있고, 가장 먼저 만든 할 일이 시간 고르기 단계로 보임(SC-101, US1)
- 설정 창 할 일 탭에서 제목만 넣어 저장, 마감·반복·예상 소요 고치기, 지우기 → 지운 할 일이 노치 후보에서 빠짐(R-102)
- 매주를 고르면 요일 칸에 오늘(하루 시작 시각 기준) 요일이 미리 골라져 있음(R-101)
- 바꿔줘 → 두 줄 → 저장 → 다른 할 일이 뜸. 나중에 그 할 일이 다시 뽑히면 "다음엔 뭐부터" 줄이 접힌 화면에 2초, 펼친 화면에 계속 보임(SC-103)
- 시간 끝 화면에 두 줄 칸과 미루기·바꿔줘가 더해져 보이고, Enter와 다시 시작 동작은 spec 001 그대로(R-107)
- 컨텍스트 탭에서 이름·날짜·영향(보통/큼/치명적)을 넣고 지우기(R-115)
- 반복 리셋은 시스템 시계를 바꾸지 않는다. 시뮬레이터 시나리오(2의 반복 항목)로 확인한다. 앱에서는 다음 날 아침 실제로 한 번 본다
- 온보딩(새 사용자 상태): 키 단계 건너뛰기 → 컨텍스트 건너뛰기 → 끝내기(조작 3번, SC-105) → 노치에 할 일이 뜸 → 다시 켜면 온보딩 없음. 사람이 macOS 새 사용자 계정에서 본다. 에이전트는 실제 앱 DB를 지우거나 열지 않는다

## 7. 사람이 손으로 볼 것 (앱 수명, 개인 팀 서명 빌드)

- 할 일이 도는 중 메뉴 막대 "종료" → 묻지 않고 바로 꺼짐 → 다시 켬 → 그 할 일이 대기로 노치에 보이고 마지막 "다음엔 뭐부터" 줄이 보임(US3, R-110·111)
- 도는 중 덮개를 닫아 재움 → 깨움 → 타이머 동작은 spec 001 그대로(R-008). 잠자기 체크포인트가 남았는지는 시뮬레이터와 단위 시험으로 본다(실제 DB를 열어 보지 않는다)
- 강제 종료(활성 상태 보기에서 강제 종료) → 다시 켬 → 대기로 돌아옴(R-111)
- 로그아웃·시스템 종료 때 종료 체크포인트가 남는지는 미확인 항목이다(research R12). 확인 방법이 실제 DB 조회뿐이면 NOT_RUN으로 적고 이유를 남긴다
- 온보딩 키 단계: 가짜가 아닌 자기 키는 사람이 직접 넣는다. 입력이 가려지는지, 저장 뒤 외부 호출이 없는지, 앱을 다시 빌드·실행할 때 Keychain 확인 창이 반복되지 않는지(ADR-0005, research R8). ad-hoc 빌드(`CODE_SIGNING_ALLOWED=NO`)로는 확인할 수 없다. 반복되면 키 단계만 마일스톤 3으로 미루고 기록한다
