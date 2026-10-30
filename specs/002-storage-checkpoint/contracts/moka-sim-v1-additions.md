# 계약 덧붙임: `moka-sim` v1 storage 모드

공개 계약이다(헌법 I). 원본은 [`specs/001-notch-timer/contracts/moka-sim-v1.md`](../../001-notch-timer/contracts/moka-sim-v1.md)이고 이 문서는 거기에 덧붙이는 부분만 적는다. 출처: spec 002 R-117, P6 (a) 채택(토론 3:0, 사용자 승인 2026-10-30). 원본 계약 파일은 이 PR에서 고치지 않는다. 구현 PR(plan 작업 단위 3)이 이 문서 내용을 원본에 옮기고, 그 PR "사람이 볼 결정"에 계약 변경으로 올린다.

## 원칙

- `version`은 `1` 그대로다. 버전 규칙의 "선택 필드와 이벤트 종류를 덧붙이는 것"에 해당한다.
- 최상위 선택 필드 `storage`가 `true`일 때만 아래 이벤트·필드·출력 키가 생긴다. 없거나 `false`면 원본 v1 동작과 출력이 바이트 단위로 같다.
- **기존 golden 불변 조건**: `Tests/MokaCoreTests/Fixtures/sim/`의 기존 시나리오(`storage` 없음)는 기대 출력 파일을 고치지 않고 통과해야 한다. 그대로 못 지키면 원본 계약의 2026-10-29 단서(moka-sim-v1.md:110)대로 바뀐 기대 출력과 이유를 그 PR "사람이 볼 결정"에 올리고 같은 PR에서 기대 출력을 고친다.
- DB, 네트워크, Keychain, 환경 변수, 시스템 시계, 시스템 시간대를 쓰지 않는다. 저장은 MokaCore 메모리 저장소(`InMemoryTaskRepository`)다. DB 경로 인자는 없다.
- 출력에 할 일 제목, 체크포인트 두 줄 본문, 컨텍스트 이름을 넣지 않는다. 두 줄과 첫 행동은 "비어 있지 않은지"만 낸다. 입력의 텍스트도 가짜만 쓴다.

## 입력 덧붙임

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
| `timezone` | 예(기존) | storage 모드에서는 하루 경계 계산에 쓴다(그레고리력 + 이 시간대) |
| `settings.day_start` | 아니오 | `HH:MM`(24시간, 두 자리). 없으면 `06:00`. `storage: true`일 때만 받는다 |

### 이벤트 (storage 모드에서만)

할 일은 `task`(만든 순서의 id, 1부터)로 가리킨다. 날짜는 `YYYY-MM-DD` 문자열, 요일은 정수 1(일)~7(토)이다.

| `type` | 추가 필드 | 의미(앱의 무엇) |
|---|---|---|
| `add_task` | `title`(필수), `deadline`, `recurrence`(`none`/`daily`/`weekly`, 없으면 `none`), `weekday`(`weekly`일 때만, 없으면 그 순간이 속한 하루의 요일), `est_min`(정수 1 이상) | 설정 창 할 일 탭에서 더함 |
| `edit_task` | `task`(필수), 그 밖은 `add_task`와 같은 필드 중 하나 이상. `deadline`·`est_min`은 `null`로 비움 | 설정 창에서 고침 |
| `delete_task` | `task`(필수) | 설정 창에서 지움(`dropped`) |
| `skip` | `done_note`, `next_note`(문자열, 없으면 건너뜀) | 미루기 + 두 줄 저장/건너뛰기 |
| `switch` | `done_note`, `next_note` | 바꿔줘 + 두 줄 |
| `sleep` | 없음 | 맥이 잠듦(깨어남은 다음 이벤트의 `at`과 `activate`로 표현) |
| `quit` | 없음 | 앱 종료 |
| `relaunch` | 없음 | 앱 시작(메모리 상태를 버리고 저장소는 남김) |
| `activate` | 없음 | 활성화(노치 펼침, 깨어남, 설정 창 열기). 하루 판정이 돈다 |
| `set_day_start` | `day_start`(`HH:MM`) | 설정의 하루 시작 시각 변경. 다음 판정부터 씀 |

기존 이벤트의 storage 모드 의미:

| `type` | storage 모드 의미 |
|---|---|
| `enter_title` | 노치 빠른 입력. `empty`(초안 없음)에서만 받고 할 일(반복 없음)을 만든다. 그 밖의 단계는 2 |
| `start` | 초안이면 시작(할 일 `active`). 시간 끝이면 다시 시작이고 `done_note`·`next_note`를 받는다(계기 `quantum`) |
| `complete` | 완료 버튼. 시간 끝이면 `done_note`·`next_note`를 받는다(계기 `quantum`). 도는 중에는 두 줄 필드가 2 |
| `choose_quantum`, `tick`, `set_default_quantum` | 원본과 같다 |

- `skip`·`switch`는 도는 중이면 계기 `skip`/`switch`, 시간 끝이면 `quantum`으로 체크포인트를 남긴다.
- 버튼 규칙, 고르기, 하루 판정, 재시작 복구는 [data-model.md](../data-model.md) §4·§5가 원본이다. 시뮬레이터는 앱과 같은 MokaCore 함수를 부른다.
- 시작 직후 상태: 저장소 비어 있음, 노치 `empty`(초안 없음), 하루 판정 한 번(대상 없음).

### 단계 × 이벤트 (storage 모드, "2"는 종료 코드 2)

| 단계 \ 이벤트 | `add_task`·`edit_task`·`delete_task`·`set_day_start` | `enter_title` | `start` | `complete` | `skip`·`switch` | `sleep` | `quit` | `relaunch` | `activate` |
|---|---|---|---|---|---|---|---|---|---|
| 꺼짐(`quit` 뒤) | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 시작 | 2 |
| `empty`(초안 없음) | 적용 → 고르기 | 할 일 만듦, 초안 | 2 | 2 | 2 | 기록 없음 | 꺼짐 | 시작 | 판정 → 고르기 |
| `empty` + 초안 | 적용(초안 할 일을 지우면 고르기) | 2 | 시작 | 2 | 2 | 기록 없음 | 꺼짐 | 시작 | 판정 |
| `running` | 적용(도는 할 일을 지우면 타이머 멈춤 → 고르기) | 2 | 2 | 완료 | 체크포인트 + 로그 | 체크포인트 `sleep` | 체크포인트 `quit`, 꺼짐 | 시작 | 판정 |
| `expired` | 같음 | 2 | 다시 시작 | 완료 | 체크포인트 `quantum` + 로그 | 기록 없음 | 꺼짐 | 시작 | 판정 |

"시작"은 메모리 상태(타이머, 직전 할 일)를 버리고 R-111 복구 → 하루 판정 → 고르기 순서로 돈다. `relaunch`는 `quit` 없이도 받는다(비정상 종료). 암묵 tick은 원본 그대로 모든 이벤트 앞에서 돈다.

## 출력 덧붙임

storage 모드에서는 모든 줄(기존 이벤트 포함)에 원본 여섯 키 뒤로 아래 키를 이 순서로 덧붙인다.

| 키 | 규칙 |
|---|---|
| `notch_task` | 노치의 초안·도는 중·시간 끝이 가리키는 할 일 id. 없거나 꺼짐이면 `null` |
| `has_first_action` | `notch_task`의 첫 행동이 있으면 `true`, 없으면 `false`, `notch_task`가 `null`이면 `null` |
| `tasks` | 모든 할 일(버림 포함, id 오름차순) 배열. 원소는 `{"id":N,"status":"…","skip_count":N,"streak":N}` 키 순서 고정 |
| `checkpoint` | 이 이벤트가 남긴 체크포인트, 없으면 `null`. `{"task_id":N,"trigger":"…","elapsed_min":N,"has_done_note":B,"has_next_note":B}` |
| `decision` | 이 이벤트가 남긴 행동 로그 줄, 없으면 `null`. `{"task_id":N,"user_action":"…","scheduler_choice":"…"}` |

- 꺼짐 단계의 줄(`quit`)은 `timer_state` `"empty"`, `chip_min`·`remaining_s`·`notch_task`·`has_first_action` `null`이다. `tasks`는 저장소 그대로다(도는 중이던 할 일은 `active`로 남는다).
- 이벤트 하나는 체크포인트를 최대 하나, 로그를 최대 하나 남긴다. 행동 로그의 판단 칸은 늘 비어 있으므로 내지 않는다.
- 바이트 형식은 원본과 같다(키 순서 고정, 공백 없음, 직접 조립, 줄 끝 `\n`). 불리언은 `true`/`false` 리터럴, 배열은 `[`·`,`·`]`이고 할 일이 없으면 `[]`.

위 입력의 출력 전체:

```
{"seq":1,"at":"2026-11-02T00:00:00Z","event":"add_task","timer_state":"empty","chip_min":25,"remaining_s":null,"notch_task":1,"has_first_action":false,"tasks":[{"id":1,"status":"todo","skip_count":0,"streak":0}],"checkpoint":null,"decision":null}
{"seq":2,"at":"2026-11-02T00:00:10Z","event":"add_task","timer_state":"empty","chip_min":25,"remaining_s":null,"notch_task":1,"has_first_action":false,"tasks":[{"id":1,"status":"todo","skip_count":0,"streak":0},{"id":2,"status":"todo","skip_count":0,"streak":0}],"checkpoint":null,"decision":null}
{"seq":3,"at":"2026-11-02T00:01:00Z","event":"start","timer_state":"running","chip_min":25,"remaining_s":1500,"notch_task":1,"has_first_action":false,"tasks":[{"id":1,"status":"active","skip_count":0,"streak":0},{"id":2,"status":"todo","skip_count":0,"streak":0}],"checkpoint":null,"decision":null}
{"seq":4,"at":"2026-11-02T00:13:30Z","event":"switch","timer_state":"empty","chip_min":25,"remaining_s":null,"notch_task":2,"has_first_action":false,"tasks":[{"id":1,"status":"todo","skip_count":0,"streak":0},{"id":2,"status":"todo","skip_count":0,"streak":0}],"checkpoint":{"task_id":1,"trigger":"switch","elapsed_min":12,"has_done_note":true,"has_next_note":true},"decision":{"task_id":1,"user_action":"switch","scheduler_choice":"oldest_unpicked_v0"}}
{"seq":5,"at":"2026-11-02T00:14:00Z","event":"start","timer_state":"running","chip_min":25,"remaining_s":1500,"notch_task":2,"has_first_action":false,"tasks":[{"id":1,"status":"todo","skip_count":0,"streak":0},{"id":2,"status":"active","skip_count":0,"streak":0}],"checkpoint":null,"decision":null}
{"seq":6,"at":"2026-11-02T00:20:00Z","event":"complete","timer_state":"empty","chip_min":25,"remaining_s":null,"notch_task":1,"has_first_action":true,"tasks":[{"id":1,"status":"todo","skip_count":0,"streak":0},{"id":2,"status":"done","skip_count":0,"streak":1}],"checkpoint":null,"decision":{"task_id":2,"user_action":"done","scheduler_choice":"oldest_unpicked_v0"}}
{"seq":7,"at":"2026-11-02T00:21:00Z","event":"start","timer_state":"running","chip_min":25,"remaining_s":1500,"notch_task":1,"has_first_action":true,"tasks":[{"id":1,"status":"active","skip_count":0,"streak":0},{"id":2,"status":"done","skip_count":0,"streak":1}],"checkpoint":null,"decision":null}
{"seq":8,"at":"2026-11-02T00:30:00Z","event":"quit","timer_state":"empty","chip_min":null,"remaining_s":null,"notch_task":null,"has_first_action":null,"tasks":[{"id":1,"status":"active","skip_count":0,"streak":0},{"id":2,"status":"done","skip_count":0,"streak":1}],"checkpoint":{"task_id":1,"trigger":"quit","elapsed_min":9,"has_done_note":false,"has_next_note":false},"decision":null}
{"seq":9,"at":"2026-11-02T22:00:00Z","event":"relaunch","timer_state":"empty","chip_min":25,"remaining_s":null,"notch_task":1,"has_first_action":true,"tasks":[{"id":1,"status":"todo","skip_count":0,"streak":0},{"id":2,"status":"todo","skip_count":0,"streak":1}],"checkpoint":null,"decision":null}
```

읽는 법: 4에서 바꿔줘로 할 일 1을 빼고 2를 골랐다(R-104). 6에서 완료 뒤 1이 다시 뽑히고 첫 행동이 보인다(R-109). 8에서 종료 체크포인트는 경과 분만 남는다(R-110). 9는 다음 날 07:00(서울)이라 R-111이 1을 `todo`로 되돌리고, 하루 판정이 매일 반복 2를 `todo`로 되돌리며 연속 기록 1을 잇는다(R-113).

## 오류 덧붙임

| 종료 코드 | 경우 |
|---|---|
| 2 | `storage`가 불리언이 아님. `storage` 없이 새 이벤트 종류나 `settings.day_start`를 씀. 새 이벤트의 모르는 키·필수 필드 없음·타입 틀림. 없는 `task` id. 버린 할 일을 고치거나 지움. 빈 제목. `recurrence` 값 밖. `weekday`가 1~7 밖이거나 결과 반복이 `weekly`가 아닌데 `weekday`를 줌. `est_min` 0 이하. 날짜가 `YYYY-MM-DD`가 아니거나 없는 날짜. `day_start`가 `HH:MM`이 아님. `edit_task`에 고칠 필드가 없음. 위 "단계 × 이벤트" 표의 "2". 도는 중 `complete`나 초안 `start`에 두 줄 필드 |
| 1 | 원본 불변식에 더해, 이벤트마다 적용 뒤 검사한다: `active` 할 일은 최대 하나. 꺼짐이 아니면 타이머가 `running`·`expired`일 때만 `active`가 있고 그것이 `notch_task`다. 초안의 `notch_task`는 `todo`다. `recurrence`가 `weekly` ⇔ `weekday` 있음, `none` ⇔ `cycle_day` 없음. `skip_count`·`streak` ≥ 0. 체크포인트·로그 수는 줄지 않고 이전 줄이 바뀌지 않는다 |

## 픽스처

- 정상: `Tests/MokaCoreTests/Fixtures/sim/storage-<이름>.json` + `.expected.jsonl`. 최소 시나리오는 quickstart 2.
- 오류: `Tests/MokaCoreTests/Fixtures/sim/errors/storage-<이름>.json`. 기대 종료 코드와 오류 종류는 시험 코드의 표로 둔다.
- `MokaStoreTests`는 `storage-*.json`을 GRDB 저장소(메모리 DB)로 한 번 더 돌려 같은 기대 출력과 바이트 비교한다(P7). 이를 위해 MokaCore `SimRunner`에 저장소를 주입하는 공개 진입점을 둔다. CLI는 메모리 저장소만 쓴다.
