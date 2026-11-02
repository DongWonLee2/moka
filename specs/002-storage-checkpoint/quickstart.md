# Quickstart: 저장과 체크포인트 검증 (spec 002)

화면 없는 검증(1~4)은 무인으로 돌 수 있다. 화면과 앱 수명 검증(5~7)은 사람이 한다. 결과는 PASS / FAIL / SKIP / NOT_RUN으로만 적는다. 시나리오·픽스처·스냅샷은 가짜 할 일만 쓴다. 규칙의 원본은 [data-model.md](data-model.md)이고 아래는 무엇을 돌려 무엇을 보는지만 적는다.

## 1. 핵심 로직과 스키마 (리눅스·macOS)

```
swift test
```

기대: 기존 시험과 새 R-ID 시험(`@Test("FR-07 R-108: …")` 등)이 모두 PASS. 포함 범위:
- MokaCore: 값 타입과 검증(data-model §2·§5.6), `UTCTimestamp`·`GregorianCalendar`(§2.1·§2.2), 노치 고르기 순환(§5.1), 세션 동작과 커서 수명·회차 값(§4.2), 버튼 → `StoreBatch`(§4.1), 재시작 복구(§5.2), 반복 리셋(§5.3), 하루 경계와 단조성(§5.4), 경과 분과 이어서 할 일 2초(§5.5), 목록 보기(§5.7), 할 일 쓰기 규칙(§5.8), 설정 읽기 규칙과 온보딩 끝내기(§6)
- MokaStore: 마이그레이션 이름 리터럴, 스키마 스냅샷, 경로 가드(기존), 공용 계약 시험(메모리·GRDB, §3 항목 전부), GRDB 전용 CHECK·RESTRICT 시험
- `moka-sim` golden: 기존 시나리오(기대 출력 파일 변경 없음)와 storage 시나리오

리눅스 컨테이너에서도 같은 결과인지 확인(스냅샷 텍스트와 하루 경계, research R9·R16):

```
docker run --rm -v "$PWD":/w -w /w swift:6.3.3-noble bash -c "apt-get update -qq && apt-get install -y -qq --no-install-recommends libsqlite3-dev >/dev/null && swift test --scratch-path /tmp/.build-linux"
```

기존 golden 불변 확인(`storage-*` 밖 파일만 본다):

```
git diff --stat main -- 'Tests/MokaCoreTests/Fixtures/sim/*.expected.jsonl' ':(exclude)Tests/MokaCoreTests/Fixtures/sim/storage-*'
```

기대: 출력 없음(변경 0줄).

## 2. 시뮬레이터

```
swift run moka-sim run Tests/MokaCoreTests/Fixtures/sim/<시나리오>.json
```

기대: [contracts/moka-sim-v1-additions.md](contracts/moka-sim-v1-additions.md) 형식의 JSON Lines, 종료 코드 0. 출력에 제목·두 줄 본문이 없다. 최소 storage 시나리오:
- 계약 예시(추가 둘 → 시작 → 바꾸기 → 할 일 2 시작 → 완료 → 할 일 1 시작 → 종료 → 다음 날 재시작)
- 대기 할 일 셋에서 시작·바꾸기를 이어서 → `notch_task` 1 → 2 → 3 → 1(순환)
- 할 일 하나뿐일 때 미루기 → 같은 할 일이 다시 뽑힘, `skip_count` 1
- 초안에서 `enter_title` → 새 할 일이 초안, 먼저 초안이던 할 일은 `todo`
- 시간 끝에서 미루기·바꾸기·완료·다시 시작 → 계기 `quantum`, 두 줄이 비어도 체크포인트가 남음
- 칩 45분으로 시작(기본값 25) → 시간 끝에서 완료 → `elapsed_min` 45
- 두 줄 모두 비움 → 체크포인트는 빈 줄, `has_first_action`은 이전 값 유지
- `quit` 뒤 `relaunch` → 대기 + `has_first_action` true. `quit` 없이 `relaunch` → `active`가 `todo`로, 타이머 없음
- 매일 반복: 완료 → 다음 날 06:00 뒤 `activate` → `todo`, 연속 기록 유지. 하지 않은 채 하루 지남 → 연속 기록 0, 할 일 수 그대로. 같은 하루에 `activate` 두 번 → 두 번째 줄의 `tasks`가 첫 번째와 같음. 05:50 시작 → 06:10 완료 → 다음 `activate`에 `todo`, 연속 기록 유지
- 매주 수요일: 목~화 `activate`에서는 그대로, 다음 수요일 06:00 뒤에 `todo`
- `America/New_York` 시간대로 3월 전환일을 넘는 매일 반복
- 오류 입력(`Fixtures/sim/errors/storage-*.json`: `storage` 없이 새 이벤트, `weekday` 8, 꺼짐 뒤 `start`, 도는 중 `complete`에 두 줄 필드 등) → 종료 코드 2, 표준 출력 비어 있음

설정 창 고침·지움, 하루 시작 시각 변경, 잠자기는 시뮬레이터 이벤트가 없다. 단위 시험(1)이 덮는다(research R6).

## 3. 오류 주입 (검증기 검증)

커밋하지 않는다. 각각 FAIL과 종료 코드 0 아님을 확인하고 되돌린다.
- 기대 출력 한 줄의 `elapsed_min`을 바꿈 → golden FAIL
- 마이그레이션에서 `decisions_log.model_snapshot`을 지움 → 스냅샷 시험 FAIL, pytest 계약 시험 FAIL(ADR-0004)
- 가짜 마이그레이션 하나를 더 등록 → 이름 시험 FAIL(ADR-0007)
- `RecurrenceReset`의 `<`를 `!=`로 바꿈 → 하루 시작 시각 변경 시험 FAIL
- 고르기에서 `dropped` 제외를 뺌 → R-104 시험 FAIL
- 고르기의 순환(`id > previous`)을 "가장 작은 id"로 바꿈 → 순환 시험 FAIL
- 메모리 저장소의 `apply`에서 되돌림을 뺌 → 공용 계약 시험(메모리 쪽) FAIL
- 메모리 저장소의 시각 내림을 뺌 → 공용 계약 시험(초 아래 왕복) FAIL

## 4. 튜닝 스크립트

```
cd tuning && python3 -m pytest
```

기대: `test_schema_contract.py`가 `schema/moka-schema.sql`로 메모리 DB를 만들고 `decisions_log` 열 이름(research R5), 판단 칸이 모두 NULL인 가짜 줄과 폴백 줄 넣기, 공급자 없이 다른 판단 칸이나 `model_snapshot`이 있는 줄 거부를 확인해 PASS.

## 5. 앱 빌드와 스냅샷

```
xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodegen generate && TEST_RUNNER_MOKA_SNAPSHOT_DIR="$PWD/.verify/snapshots/002" xcodebuild test -scheme Moka -destination 'platform=macOS' -only-testing:MokaAppTests
```

스냅샷 폴더는 환경 변수로 준다(`SnapshotHelper` 기본값은 `.verify/snapshots/001`). CI에는 필수가 아닌 `app-snapshots` job이 이미 있다(ADR-0009 보완). 빌드 성공은 완료가 아니다. 스냅샷 기대: 새 화면 상태마다 PNG 라이트·다크(설정 탭 셋, 할 일 목록 보기, 할 일 폼, 일정 폼, 시작 전 + 다른 할 일, 버튼 줄이 있는 도는 중, 두 줄 입력, 시간 끝 + 두 줄, 이어서 할 일 접힘·펼침, 저장할 수 없는 빈 상태, 온보딩 두 단계). sanity 시험 PASS. 사람이 `~/Dev/ai-platform/projects/moka/design/pr-<번호>/index.html`에서 시안 `002-mockup.html`과 나란히 본다(ADR-0009).

## 6. 사람이 손으로 볼 것 (화면)

- 노치에 가짜 할 일 셋을 넣고 앱을 종료 → 다시 켬 → 셋이 남아 있고, 가장 먼저 만든 할 일이 시간 고르기 단계로 보임(SC-101, US1)
- 시작 전 화면에서 "다른 할 일"을 눌러 셋째 할 일까지 가고 처음으로 돌아옴. 로그 줄 수 그대로(R-104)
- 설정 창 할 일 탭에서 제목만 넣어 저장, 마감·반복·예상 소요 고치기, 지우기 → 지운 할 일이 노치 후보에서 빠짐(R-102)
- 매주를 고르면 요일 칸에 오늘(하루 시작 시각 기준) 요일이 미리 골라져 있음(R-101)
- 바꾸기 → 두 줄 → 등록 → 다른 할 일이 뜸. 나중에 그 할 일이 다시 뽑히면 "이어서 할 일" 줄이 접힌 화면에 2초, 펼친 화면에 계속 보임(SC-103)
- 바꾸기 → 돌아가기(Esc) → 도는 중 화면, 타이머 계속, 로그 줄 수 그대로(R-106·R-112)
- 시간 끝 화면에 두 줄 칸과 미루기·바꾸기가 더해져 보임. 칸 밖 Enter = 완료, 첫 칸 Enter = 둘째 칸, 둘째 칸 Enter = 아무 일 없음(R-107)
- 일정 탭에서 이름·날짜·중요도(조금/꽤/아주)를 넣고 지우기(R-115)
- 할 일 탭 보기(전체·오늘·이번 주)·정렬(만든 순·마감 순)을 바꿔도 "다음" 표시가 노치에 뜨거나 다음에 뜰 할 일과 같음(SC-107)
- 반복 리셋은 시스템 시계를 바꾸지 않는다. 시뮬레이터 시나리오(2의 반복 항목)로 확인한다. 앱에서는 다음 날 아침 실제로 한 번 본다
- 온보딩(새 사용자 상태): 일정 건너뛰기 → 시작하기(조작 2번, SC-105) → 노치에 할 일이 뜸 → 다시 켜면 온보딩 없음. 사람이 macOS 새 사용자 계정에서 본다. 에이전트는 실제 앱 DB를 지우거나 열지 않는다
- 저장 불가 화면(R-119)은 스냅샷으로만 본다. 실제 DB를 망가뜨려 확인하지 않는다

## 7. 사람이 손으로 볼 것 (앱 수명, 개인 팀 서명 빌드)

- 할 일이 도는 중 메뉴 막대 "종료" → 묻지 않고 바로 꺼짐 → 다시 켬 → 그 할 일이 대기로 노치에 보이고 마지막 이어서 할 일이 보임(US3, R-110·111)
- 도는 중 덮개를 닫아 재움 → 깨움 → 타이머 동작은 spec 001 그대로(R-008). 잠자기 체크포인트가 남았는지는 단위 시험으로 본다(실제 DB를 열어 보지 않는다)
- 강제 종료(활성 상태 보기에서 강제 종료) → 다시 켬 → 대기로 돌아옴(R-111)
- 로그아웃·시스템 종료 때 종료 체크포인트가 남는지는 미확인 항목이다(research R12, 최선 노력). 확인 방법이 실제 DB 조회뿐이면 NOT_RUN으로 적고 이유를 남긴다
