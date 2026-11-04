# 계약: `moka-sim` 시나리오 형식 v1

공개 계약이다(헌법 I). 바꾸려면 사람 승인이 필요하다. 출처: spec 001 R-015, D2 채택(사용자 승인 2026-10-28), EGM 리뷰 뒤 보강(토론 Q1 (b), 사용자 승인 2026-10-28). 아래 "storage 모드" 절은 spec 002 R-117([contracts/moka-sim-v1-additions.md](../../002-storage-checkpoint/contracts/moka-sim-v1-additions.md))을 옮긴 것이다.

## 실행

```
moka-sim run <scenario.json>
```

- 표준 출력: 시나리오 전체가 성공했을 때만 이벤트마다 JSON 한 줄(JSON Lines). 오류가 나면 표준 출력은 비어 있다.
- 표준 오류: 오류 설명 한 줄(사람용, 형식 보장 없음). 실행 중 오류면 실패한 이벤트의 `seq`를 넣는다.
- 종료 코드: `0` 정상, `1` 불변식 위반, `2` 입력 오류. 아래 "오류" 절이 기준이다.
- DB, 네트워크, Keychain, 환경 변수, 시스템 시계(`Date()`), 시스템 시간대(`TimeZone.current`)를 쓰지 않는다. v1은 DB를 쓰지 않으므로 DB 경로 인자가 없다. DB를 쓰는 버전에서는 ADR-0006대로 경로 인자를 필수로 넣는다.

## 입력

```json
{
  "version": 1,
  "timezone": "Asia/Seoul",
  "settings": { "default_quantum_min": 25 },
  "events": [
    { "at": "2026-11-02T09:00:00+09:00", "type": "enter_title", "title": "가짜 할 일 A" },
    { "at": "2026-11-02T09:00:03+09:00", "type": "choose_quantum", "quantum_min": 45 },
    { "at": "2026-11-02T09:00:04+09:00", "type": "start" },
    { "at": "2026-11-02T09:30:04+09:00", "type": "tick" },
    { "at": "2026-11-02T09:45:04+09:00", "type": "tick" },
    { "at": "2026-11-02T09:46:00+09:00", "type": "complete" }
  ]
}
```

| 필드 | 필수 | 규칙 |
|---|---|---|
| `version` | 예 | JSON 정수 `1` |
| `timezone` | 예 | IANA 이름. `TimeZone(identifier:)`가 nil이면 입력 오류. v1 계산에는 쓰지 않는다(이후 하루 경계용 자리) |
| `settings` | 아니오 | 없으면 `{}`. 키: `default_quantum_min`(정수 1~180). 없으면 25 |
| `events` | 예 | 배열(비어도 된다, 출력 없음). `at`은 줄어들지 않아야 한다(같은 순간은 허용) |
| `events[].at` | 예 | ISO 8601, 오프셋 필수(`Z` 허용), 초 단위까지(소수 초는 입력 오류) |
| `events[].type` | 예 | 아래 표의 값만 |

| `type` | 추가 필드 | 의미 |
|---|---|---|
| `enter_title` | `title`(문자열, 앞뒤 공백을 뺀 뒤 비어 있으면 입력 오류) | 제목 입력 → 칩이 기본값으로 채워짐 |
| `choose_quantum` | `quantum_min`(정수 1~180) | 칩 값을 바꿈 |
| `start` | 없음 | 칩 값으로 타이머 시작 |
| `tick` | 없음 | 그 시각으로 상태를 갱신 |
| `complete` | 없음 | 할 일을 비움 |
| `set_default_quantum` | `quantum_min`(정수 1~180) | 설정의 기본값 변경. 직접 고르지 않은 칩도 새 값이 됨(R-013) |

정수 필드는 JSON 정수만 받는다(`45.0`, `"45"`는 입력 오류).

## 상태와 이벤트

내부 단계는 넷이다. 출력 `timer_state`는 셋이며, 시작 전 단계(`empty` + 초안)는 `timer_state: "empty"`에 `chip_min`이 null이 아닌 것으로 드러난다. 규칙의 원본은 MokaCore 값 타입이고(data-model §2), 앱과 시뮬레이터가 같은 전이 함수를 쓴다.

**암묵 tick:** 모든 이벤트는 처리하기 전에 그 `at`으로 tick을 먼저 적용한다. 그래서 끝 시각이 지난 뒤 온 이벤트는 `expired`에서 처리된다. 출력은 입력 이벤트마다 한 줄이고, 암묵 tick은 줄을 만들지 않는다. 출력 줄은 이벤트를 적용한 **뒤** 상태다.

| 단계 \ 이벤트 | `enter_title` | `choose_quantum` | `start` | `tick` | `complete` | `set_default_quantum` |
|---|---|---|---|---|---|---|
| `empty` | 초안 생성, 칩 = 기본값 | 2 | 2 | 변화 없음 | 2 | 기본값 변경 |
| `empty` + 초안 | 제목만 바꿈, 칩 유지 | 칩 = 값 | `running`(제목, 칩) | 변화 없음 | 2 | 기본값 변경. 칩을 `choose_quantum`으로 고르지 않았으면 칩 = 새 기본값, 골랐으면 칩 유지 |
| `running` | 2 | 2 | 2 | 끝 시각 이후면 `expired`, 칩 = 기본값 | `empty`(초안 없음) | 기본값 변경, 타이머·칩 유지 |
| `expired` | 2 | 칩 = 값 | `running`(같은 제목, 칩) | 변화 없음 | `empty`(초안 없음) | 기본값 변경. 시간 끝 뒤 `choose_quantum`이 없었으면 칩 = 새 기본값, 있었으면 칩 유지 |

"2"는 종료 코드 2(입력 오류)다.

## 출력 (이벤트마다 한 줄)

위 입력의 출력 전체:

```
{"seq":1,"at":"2026-11-02T00:00:00Z","event":"enter_title","timer_state":"empty","chip_min":25,"remaining_s":null}
{"seq":2,"at":"2026-11-02T00:00:03Z","event":"choose_quantum","timer_state":"empty","chip_min":45,"remaining_s":null}
{"seq":3,"at":"2026-11-02T00:00:04Z","event":"start","timer_state":"running","chip_min":45,"remaining_s":2700}
{"seq":4,"at":"2026-11-02T00:30:04Z","event":"tick","timer_state":"running","chip_min":45,"remaining_s":900}
{"seq":5,"at":"2026-11-02T00:45:04Z","event":"tick","timer_state":"expired","chip_min":25,"remaining_s":0}
{"seq":6,"at":"2026-11-02T00:46:00Z","event":"complete","timer_state":"empty","chip_min":null,"remaining_s":null}
```

| 필드 | 규칙 |
|---|---|
| `seq` | 1부터 입력 이벤트 순서(`tick` 포함) |
| `at` | 입력 시각을 UTC `YYYY-MM-DDTHH:MM:SSZ`로 |
| `event` | 입력 `type` 그대로 |
| `timer_state` | `empty` / `running` / `expired` 중 하나 |
| `chip_min` | 초안이 없는 `empty`면 `null`. 초안이 있는 `empty`와 `expired`는 칩 값, `running`은 도는 작업 시간 |
| `remaining_s` | `running`이면 `min(ceil(끝 시각 − at), 작업 시간 × 60)`초, `expired`면 `0`, `empty`면 `null` |

바이트 형식(golden 시험은 바이트 단위로 비교한다):
- 키 순서는 위 표 순서로 고정한다. `JSONEncoder`는 이 순서를 보장하지 않으므로 문자열을 직접 조립한다.
- 공백 없음, `null`은 리터럴, 정수는 10진, 문자열 값은 ASCII뿐이라 이스케이프하지 않는다.
- 줄마다 끝에 `\n` 하나(마지막 줄 포함).
- 제목은 출력하지 않는다(가짜 시나리오도 출력에 할 일 텍스트를 남기지 않는다).

## 오류

| 종료 코드 | 경우 |
|---|---|
| 2 | 인자 없음, 모르는 하위 명령, 파일 없음, JSON 파싱 실패, 모르는 `version`, 어느 깊이든 모르는 키(그 `type`에 없는 필드 포함), 필수 필드 없음, 타입 틀림, 범위 밖 값, 시각 역행, 소수 초, 모르는 `timezone`, 상태 표의 "2" |
| 1 | 불변식 위반: 이벤트마다 적용 뒤 검사한다(`running`이면 `remaining_s ≥ 1`, `expired`면 0, 끝 시각 > 시작 시각, 작업 시간 ∈ 1…180). 유효한 입력으로는 나오지 않아야 한다(MokaCore 버그 신호). 검사 함수에 깨진 상태를 직접 넣는 단위 시험으로 확인한다 |

픽스처: 정상 시나리오는 `Tests/MokaCoreTests/Fixtures/sim/<이름>.json` + `<이름>.expected.jsonl`. 오류 시나리오는 `Tests/MokaCoreTests/Fixtures/sim/errors/<이름>.json`이고 golden 대상이 아니다. 기대 종료 코드와 오류 종류는 시험 코드의 표로 둔다.

## storage 모드 (spec 002 R-117)

출처: spec 002 R-117, P6 (a) 채택(토론 3:0, 사용자 승인 2026-10-30), 이벤트 범위는 EGM 뒤 Q2c(토론 3:0, 사용자 결정 2026-10-30, spec 002 research R6).

### 원칙

- `version`은 `1` 그대로다. 아래 "버전 규칙"의 "선택 필드와 이벤트 종류를 덧붙이는 것"에 해당한다.
- 최상위 선택 필드 `storage`가 `true`일 때만 아래 이벤트·필드·출력 키가 생긴다. 없거나 `false`면 위 절들의 동작과 출력이 바이트 단위로 같다.
- 기존 golden 불변 조건: `Tests/MokaCoreTests/Fixtures/sim/`의 `storage` 없는 시나리오는 기대 출력 파일을 고치지 않고 통과해야 한다. 못 지키면 "버전 규칙"의 단서대로 바뀐 기대 출력과 이유를 그 PR "사람이 볼 결정"에 올리고 같은 PR에서 기대 출력을 고친다.
- DB, 네트워크, Keychain, 환경 변수, 시스템 시계, 시스템 시간대를 쓰지 않는다. 저장은 MokaCore 메모리 저장소(`InMemoryTaskRepository`)다. DB 경로 인자는 없다.
- 출력에 할 일 제목, 체크포인트 두 줄 본문을 넣지 않는다. 두 줄과 이어서 할 일은 "비어 있지 않은지"만 낸다. 입력의 텍스트도 가짜만 쓴다.
- 버튼 규칙, 고르기, 하루 판정, 재시작 복구는 spec 002 [data-model.md](../../002-storage-checkpoint/data-model.md) §4·§5가 원본이다. 시뮬레이터는 앱과 같은 MokaCore 함수(`NotchSession`, `RotateByIDRule`, `RecurrenceReset`, `LaunchRecovery`, `TaskWriteRules`)를 부른다.

### 입력 덧붙임

```json
{
  "version": 1,
  "timezone": "Asia/Seoul",
  "storage": true,
  "settings": { "default_quantum_min": 25, "day_start": "06:00" },
  "events": [
    { "at": "2026-11-02T09:00:00+09:00", "type": "add_task", "title": "가짜 할 일 A" },
    { "at": "2026-11-02T09:00:10+09:00", "type": "add_task", "title": "가짜 할 일 B", "recurrence": "daily" },
    { "at": "2026-11-02T09:01:00+09:00", "type": "start" },
    { "at": "2026-11-02T09:13:30+09:00", "type": "switch", "done_note": "가짜 한 일", "next_note": "가짜 첫 행동" },
    { "at": "2026-11-02T09:14:00+09:00", "type": "start" },
    { "at": "2026-11-02T09:20:00+09:00", "type": "complete" },
    { "at": "2026-11-02T09:21:00+09:00", "type": "start" },
    { "at": "2026-11-02T09:30:00+09:00", "type": "quit" },
    { "at": "2026-11-03T07:00:00+09:00", "type": "relaunch" }
  ]
}
```

| 필드 | 필수 | 규칙 |
|---|---|---|
| `storage` | 아니오 | JSON 불리언. 없으면 `false` |
| `timezone` | 예(기존) | storage 모드에서는 하루 경계 계산에 쓴다(그레고리력 + 이 시간대, `GregorianCalendar.make(timeZone:)`) |
| `settings.day_start` | 아니오 | `HH:MM`(24시간, 두 자리). 없으면 `06:00`. `storage: true`일 때만 받는다 |

#### 이벤트 (storage 모드에서만)

날짜는 `YYYY-MM-DD` 문자열, 요일은 정수 1(일)~7(토)이다.

| `type` | 추가 필드 | 의미(앱의 무엇) |
|---|---|---|
| `add_task` | `title`(필수), `deadline`(`recurrence`가 `none`일 때만, 2026-11-04 정정), `recurrence`(`none`/`daily`/`weekly`, 없으면 `none`), `weekday`(`weekly`일 때만, 없으면 그 순간이 속한 하루의 요일), `est_min`(정수 1 이상) | 설정 창 할 일 탭에서 더함(data-model §5.8 `prepareNew` → `insertTask` → `tasks()` 다시 읽기 → `picked`. 빈 상태일 때만 고르고 초안이면 그대로다. 초안을 새 할 일로 바꾸는 `addedTask`는 노치 빠른 입력 `enter_title`(R-103) 전용) |
| `skip` | `done_note`, `next_note`(문자열, 없으면 빈 줄) | 미루기 + 두 줄 등록/안 적기 |
| `switch` | `done_note`, `next_note` | 바꾸기 + 두 줄 |
| `quit` | 없음 | 앱 종료(메뉴 막대 "종료") |
| `relaunch` | 없음 | 앱 시작(메모리 상태를 버리고 저장소는 남김) |
| `activate` | 없음 | 활성화(노치 펼침, 깨어남, 설정 창 열기). 하루 판정이 돈다 |

돌아가기와 "다른 할 일"(목록에서 고르기)은 기록이 없는 화면 동작이라 이벤트가 없다. 설정 창 고침·지움, 하루 시작 시각 변경, 잠자기는 이 계약에 없고 MokaCore 단위 시험이 덮는다(spec 002 research R6). 필요해지면 "버전 규칙"대로 덧붙인다.

기존 이벤트의 storage 모드 의미:

| `type` | storage 모드 의미 |
|---|---|
| `enter_title` | 노치 빠른 입력. `empty`(초안 없음)과 초안에서 받고 할 일(반복 없음)을 만든다. 초안이면 초안이 새 할 일로 바뀐다(칩 유지). 그 밖의 단계는 종료 코드 2 |
| `start` | 초안이면 시작(할 일 `active`). 시간 끝이면 다시 시작이고 `done_note`·`next_note`를 받는다(계기 `quantum`) |
| `complete` | 완료 버튼. 시간 끝이면 `done_note`·`next_note`를 받는다(계기 `quantum`). 도는 중에 두 줄 필드가 있으면 종료 코드 2 |
| `choose_quantum`, `tick`, `set_default_quantum` | 위 "상태와 이벤트"와 같다. 꺼짐 단계에서는 종료 코드 2 |

- `skip`·`switch`는 도는 중이면 계기 `skip`/`switch`, 시간 끝이면 `quantum`으로 체크포인트를 남긴다.
- 시간 끝 체크포인트의 `elapsed_min`은 시작할 때 고른 작업 시간이다(data-model §4.2 `RunInfo`). 시간 끝 화면에서 칩을 바꿔도 달라지지 않는다.
- 시작 직후 상태: 저장소 비어 있음, 노치 `empty`(초안 없음), 하루 판정 한 번(대상 없음).

#### 단계 × 이벤트 (storage 모드)

칸의 "2"는 종료 코드 2(입력 오류)다.

| 단계 \ 이벤트 | `add_task` | `enter_title` | `start` | `complete` | `skip`·`switch` | `choose_quantum`·`tick`·`set_default_quantum` | `quit` | `relaunch` | `activate` |
|---|---|---|---|---|---|---|---|---|---|
| 꺼짐(`quit` 뒤) | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 시작 | 2 |
| `empty`(초안 없음) | 적용 → 고르기 | 할 일 만듦, 초안 | 2 | 2 | 2 | 위와 같음 | 꺼짐 | 시작 | 판정 → 고르기 |
| `empty` + 초안 | 적용(초안 그대로) | 할 일 만듦, 초안 교체 | 시작 | 2 | 2 | 위와 같음 | 꺼짐 | 시작 | 판정 |
| `running` | 적용 | 2 | 2 | 완료 | 체크포인트 + 로그 | 위와 같음 | 체크포인트 `quit`, 꺼짐 | 시작 | 판정 |
| `expired` | 적용 | 2 | 다시 시작 | 완료 | 체크포인트 `quantum` + 로그 | 위와 같음 | 꺼짐 | 시작 | 판정 |

"시작"은 메모리 상태(타이머, 고르기 커서, 회차 값)를 버리고 R-111 복구 → 하루 판정 → 고르기 순서로 돈다. `relaunch`는 `quit` 없이도 받는다(비정상 종료). 암묵 tick은 위 절 그대로 모든 이벤트 앞에서 돈다(꺼짐 단계 제외). 같은 규칙의 원본은 data-model §4.2 표다. 이 표는 시뮬레이터에만 있는 꺼짐 단계와 종료 코드 2를 더한 것이다.

### 출력 덧붙임

storage 모드에서는 모든 줄(기존 이벤트 포함)에 위 "출력" 절의 여섯 키 뒤로 아래 키를 이 순서로 덧붙인다.

| 키 | 규칙 |
|---|---|
| `notch_task` | 노치의 초안·도는 중·시간 끝이 가리키는 할 일 id. 없거나 꺼짐이면 `null` |
| `has_first_action` | `notch_task`의 이어서 할 일(첫 행동)이 있으면 `true`, 없으면 `false`, `notch_task`가 `null`이면 `null` |
| `tasks` | 모든 할 일(버림 포함, id 오름차순) 배열. 원소는 `{"id":N,"status":"…","skip_count":N,"streak":N}` 키 순서 고정 |
| `checkpoint` | 이 이벤트가 남긴 체크포인트, 없으면 `null`. `{"task_id":N,"trigger":"…","elapsed_min":N,"has_done_note":B,"has_next_note":B}` |
| `decision` | 이 이벤트가 남긴 행동 로그 줄, 없으면 `null`. `{"task_id":N,"user_action":"…","scheduler_choice":"…"}` |

- 꺼짐 단계의 줄(`quit`)은 `timer_state` `"empty"`, `chip_min`·`remaining_s`·`notch_task`·`has_first_action` `null`이다. `tasks`는 저장소 그대로다(도는 중이던 할 일은 `active`로 남는다).
- 이벤트 하나는 체크포인트를 최대 하나, 로그를 최대 하나 남긴다. 행동 로그의 판단 칸은 늘 비어 있으므로 내지 않는다.
- 바이트 형식은 위 "출력" 절과 같다(키 순서 고정, 공백 없음, 직접 조립, 줄 끝 `\n`). 불리언은 `true`/`false` 리터럴, 배열은 `[`·`,`·`]`이고 할 일이 없으면 `[]`.

위 입력의 출력 전체:

```
{"seq":1,"at":"2026-11-02T00:00:00Z","event":"add_task","timer_state":"empty","chip_min":25,"remaining_s":null,"notch_task":1,"has_first_action":false,"tasks":[{"id":1,"status":"todo","skip_count":0,"streak":0}],"checkpoint":null,"decision":null}
{"seq":2,"at":"2026-11-02T00:00:10Z","event":"add_task","timer_state":"empty","chip_min":25,"remaining_s":null,"notch_task":1,"has_first_action":false,"tasks":[{"id":1,"status":"todo","skip_count":0,"streak":0},{"id":2,"status":"todo","skip_count":0,"streak":0}],"checkpoint":null,"decision":null}
{"seq":3,"at":"2026-11-02T00:01:00Z","event":"start","timer_state":"running","chip_min":25,"remaining_s":1500,"notch_task":1,"has_first_action":false,"tasks":[{"id":1,"status":"active","skip_count":0,"streak":0},{"id":2,"status":"todo","skip_count":0,"streak":0}],"checkpoint":null,"decision":null}
{"seq":4,"at":"2026-11-02T00:13:30Z","event":"switch","timer_state":"empty","chip_min":25,"remaining_s":null,"notch_task":2,"has_first_action":false,"tasks":[{"id":1,"status":"todo","skip_count":0,"streak":0},{"id":2,"status":"todo","skip_count":0,"streak":0}],"checkpoint":{"task_id":1,"trigger":"switch","elapsed_min":12,"has_done_note":true,"has_next_note":true},"decision":{"task_id":1,"user_action":"switch","scheduler_choice":"rotate_by_id_v0"}}
{"seq":5,"at":"2026-11-02T00:14:00Z","event":"start","timer_state":"running","chip_min":25,"remaining_s":1500,"notch_task":2,"has_first_action":false,"tasks":[{"id":1,"status":"todo","skip_count":0,"streak":0},{"id":2,"status":"active","skip_count":0,"streak":0}],"checkpoint":null,"decision":null}
{"seq":6,"at":"2026-11-02T00:20:00Z","event":"complete","timer_state":"empty","chip_min":25,"remaining_s":null,"notch_task":1,"has_first_action":true,"tasks":[{"id":1,"status":"todo","skip_count":0,"streak":0},{"id":2,"status":"done","skip_count":0,"streak":1}],"checkpoint":null,"decision":{"task_id":2,"user_action":"done","scheduler_choice":"rotate_by_id_v0"}}
{"seq":7,"at":"2026-11-02T00:21:00Z","event":"start","timer_state":"running","chip_min":25,"remaining_s":1500,"notch_task":1,"has_first_action":true,"tasks":[{"id":1,"status":"active","skip_count":0,"streak":0},{"id":2,"status":"done","skip_count":0,"streak":1}],"checkpoint":null,"decision":null}
{"seq":8,"at":"2026-11-02T00:30:00Z","event":"quit","timer_state":"empty","chip_min":null,"remaining_s":null,"notch_task":null,"has_first_action":null,"tasks":[{"id":1,"status":"active","skip_count":0,"streak":0},{"id":2,"status":"done","skip_count":0,"streak":1}],"checkpoint":{"task_id":1,"trigger":"quit","elapsed_min":9,"has_done_note":false,"has_next_note":false},"decision":null}
{"seq":9,"at":"2026-11-02T22:00:00Z","event":"relaunch","timer_state":"empty","chip_min":25,"remaining_s":null,"notch_task":1,"has_first_action":true,"tasks":[{"id":1,"status":"todo","skip_count":0,"streak":0},{"id":2,"status":"todo","skip_count":0,"streak":1}],"checkpoint":null,"decision":null}
```

읽는 법: 4에서 바꾸기로 커서가 할 일 1이 되어 그다음 id 2를 골랐다(R-104). 6에서 완료 뒤 커서가 비어 가장 작은 대기 할 일 1이 뽑히고 이어서 할 일이 보인다(R-109). 8에서 종료 체크포인트는 경과 분만 남는다(R-110). 9는 다음 날 07:00(서울)이라 R-111이 1을 `todo`로 되돌리고, 하루 판정이 매일 반복 2를 `todo`로 되돌리며 연속 기록 1을 잇는다(R-113).

### 오류 덧붙임

| 종료 코드 | 경우 |
|---|---|
| 2 | `storage`가 불리언이 아님. `storage` 없이 새 이벤트 종류나 `settings.day_start`를 씀. 새 이벤트의 모르는 키·필수 필드 없음·타입 틀림. 빈 제목. `recurrence` 값 밖. `weekday`가 1~7 밖이거나 `recurrence`가 `weekly`가 아닌데 `weekday`를 줌. `recurrence`가 `none`이 아닌데 `deadline`을 줌(반복 할 일은 마감 없음, R-101, 2026-11-04 사용자 결정). `est_min` 0 이하. 날짜가 `YYYY-MM-DD`가 아니거나 없는 날짜. `day_start`가 `HH:MM`이 아님. 위 "단계 × 이벤트" 표의 "2". 도는 중 `complete`나 초안 `start`에 두 줄 필드 |
| 1 | 위 "오류" 절의 불변식에 더해, 이벤트마다 적용 뒤 검사한다: `active` 할 일은 최대 하나. 꺼짐이 아니면 타이머가 `running`·`expired`일 때만 `active`가 있고 그것이 `notch_task`다. 초안의 `notch_task`는 `todo`다. `recurrence`가 `weekly` ⇔ `weekday` 있음, `none` ⇔ `cycle_day` 없음. `skip_count`·`streak` ≥ 0. 체크포인트·로그 수는 줄지 않고 이전 줄이 바뀌지 않는다 |

오류 종류(`SimErrorKind`)와 픽스처별 기대 값은 시험 코드의 표(`Tests/MokaCoreTests/SimScenarioTests.swift` `errorFixtures`)에 둔다.

### 픽스처

- 정상: `Tests/MokaCoreTests/Fixtures/sim/storage-<이름>.json` + `.expected.jsonl`.
- 오류: `Tests/MokaCoreTests/Fixtures/sim/errors/storage-<이름>.json`.
- GRDB 저장소로 storage golden을 다시 돌리지 않는다. 두 저장소의 같음은 MokaStore 공용 계약 시험이 맡는다(spec 002 data-model §3, research R7). CLI와 시험 모두 메모리 저장소만 쓰므로 `SimRunner`에 저장소 주입 진입점을 두지 않는다.

## 버전 규칙

- 선택 필드와 이벤트 종류를 덧붙이는 것은 `version: 1`을 유지한다. 그래도 공개 계약 변경이므로 PR "사람이 볼 결정"에 올린다.
- 의미 변경, 필드 삭제, 이름 변경은 `version: 2`. 기존 시나리오는 같은 PR에서 옮긴다.
  - 단서: `moka-sim`을 이 저장소 밖에서 쓰는 사용자가 없는 동안은 의미 변경도 `version: 1`을 유지할 수 있다. 그때는 바뀐 의미와 기존 시나리오의 기대 출력 변화를 같은 PR "사람이 볼 결정"에 적고, 바뀐 기대 출력 파일을 같은 PR에서 고친다. 외부 사용자가 생기면 위 규칙(의미 변경은 `version: 2`)을 따른다(사용자 결정 2026-10-29, PR #44).
- 덧붙이기(선택 필드·이벤트 종류)일 때 기존 v1 시나리오 파일은 같은 출력으로 통과해야 한다(golden 시험). 위 단서로 `version: 1`에서 의미를 바꿀 때는 이 문장이 적용되지 않고, 그 PR에서 고친 기대 출력으로 통과해야 한다.
