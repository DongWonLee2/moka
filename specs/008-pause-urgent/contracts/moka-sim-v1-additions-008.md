# 계약: `moka-sim` 덧붙임 (spec 008)

spec 001 `contracts/moka-sim-v1.md`, spec 002 `contracts/moka-sim-v1-additions.md`, spec 003 `contracts/moka-sim-v1-additions-003.md`, spec 005 `contracts/moka-sim-v1-additions-005.md`에 덧붙인다. 근거: spec R-834, data-model §1~§10. 승인 항목 4(헌법 I).

**상태: 초안.** 일시 중지 입력 모양은 research P8이 정해지면 아래 "입력 덧붙임" 표를 확정한다. 나머지 절은 P8과 상관없다.

## 켜는 법

시나리오에 이 문서의 새 이벤트가 하나라도 있으면 아래 출력 키를 켜고 spec 005 켜짐(이월·가용 시간)도 함께 켠다(research R18). `version`은 1 그대로다. 새 이벤트가 없는 시나리오의 출력은 spec 001·002·003·005 golden과 바이트까지 같아야 한다.

## 입력 덧붙임 (storage 모드에서만)

공통 이벤트:

| 이벤트 | 필드 | 규칙 |
|---|---|---|
| `resume` | 없음 | "다시 시작". 일시 중지 중이 아니면 종료 코드 2 |
| `urgent` | `title`(문자열), `quantum_min`(정수 1~180), `done_note`·`next_note`(문자열, 생략하면 안 적기), `extend`(불리언, 생략하면 `false`) | 도는 중에만 받는다. 칩이 남은 분보다 긴데 `extend`가 없거나 `false`면 종료 코드 2. 남은 분이 0일 때는 research P2, 입력 동안 모자라는 경우는 research P9가 정한다 |

일시 중지 입력(research P8에서 하나를 고른다). 어느 안이든 `length`는 정수 분 1~180 또는 문자열 `"until_morning"`이고, 초안에서 멈출 때 두 줄 필드가 있으면 종료 코드 2다.

| 안 | 이벤트 | 필드 |
|---|---|---|
| A | `pause` | `length`, `done_note`, `next_note` |
| B | `pause_begin` / `pause_commit` / `pause_cancel` | 없음 / `length`, `done_note`, `next_note` / 없음 |
| C | `pause` | `pressed_at`, `length`, `done_note`, `next_note` |

- 시간 끝, 빈 상태, 이월 카드, 가용 시간 질문, 오늘 끝에서 일시 중지 입력이면 종료 코드 2(R-801).
- 멈춘 동안 `complete`, `skip`, `switch`, `urgent`, `start`, `choose_quantum`은 종료 코드 2(R-803).
- 기존 `add_task`는 멈춘 동안 저장만 하고 초안을 바꾸지 않는다.
- 기존 `quit`은 멈춘 채면 `quit` 체크포인트와 저장한 남은 초 돌려주기를 한다. 기존 `activate`와 `resume`은 하루 경계를 넘겼으면 data-model §4를 한다.
- 기존 `tick`은 정한 길이가 끝났는지 본다. 초안에서 멈췄으면 그 시각에 일시 중지가 끝난다.
- 오류 픽스처는 `Tests/MokaCoreTests/Fixtures/sim/errors/`에 하나씩 더하고 `SimScenarioTests` 표에 넣는다.

## 출력 덧붙임

켜짐일 때 storage 모드의 모든 줄에 spec 005 키 뒤로 아래를 이 순서로 붙인다.

| 키 | 규칙 |
|---|---|
| `pause` | 일시 중지 중이 아니면 `null`. 중이면 `{"origin":"run"\|"draft","stage":"choosing"\|"notes"\|"holding"\|"waiting","left_s":N\|null,"frozen_s":N\|null}` |
| `urgent_pin` | 긴급 고정된 할 일 id, 없으면 `null` |
| `return_task` | 복귀 제안을 기다리는 끊긴 할 일 id, 없으면 `null` |

- `left_s`는 남은 일시 중지 초(올림)이고, 길이가 정해지기 전이거나 0 이하이면 `null`이다. `stage`의 `waiting`은 `holding`이고 끝 시각이 지난 때다.
- `frozen_s`는 멈춘 작업 시간의 남은 초(올림)이고, 초안에서 멈췄으면 `null`이다.

기존 키에 더해지는 값:

| 키 | 더해지는 값 |
|---|---|
| `timer_state` | `"paused"`(도는 중에서 멈춤). 초안에서 멈추면 그대로 `"empty"`이고 `chip_min`이 있다 |
| `remaining_s` | 멈춘 동안 `frozen_s`와 같다 |
| `chip_min` | 멈춘 동안 고른 분 |
| `mode` | `"paused"` |
| `notch_rule` | `urgent_pin_v1`, `urgent_return_v1` |
| `decision.user_action` | `pause`, `resume`, `urgent` |
| `decision.scheduler_choice` | `urgent_pin_v1`, `urgent_return_v1` |
| `checkpoint.trigger` | `pause`, `urgent` |

`timer_state: "paused"`는 research P1의 어느 안이든 같은 출력이다. 출력에 할 일 제목과 두 줄 본문을 내지 않는다(ASCII만).

## 새 불변식 (종료 코드 1)

- 도는 중에서 멈춘 동안 줄마다 `frozen_s`가 같고 `timer_state`가 `expired`로 바뀌지 않는다(R-803).
- 멈춘 동안 `budget.used_s`가 바뀌지 않는다(R-805). 끝나는 이벤트의 줄은 뺀다.
- `mode`가 `paused`인 동안 `notch_task`가 바뀌지 않고, `add_task` 뒤에도 그대로다.
- `timer_state`가 `paused`이면 `notch_task`가 `active`다.
- 이어 돈 줄의 `remaining_s`는 직전 줄의 `frozen_s`와 같다(같은 시각일 때).
- `urgent` 이벤트 한 번에 `decision`이 정확히 하나이고 `user_action`이 `urgent`이며, 그 줄의 `task_id`는 끊긴 할 일이다(R-815).
- `urgent_pin`이 대기 할 일이면 `order`가 있을 때 그 맨 앞이다(R-813).
- 어느 하루의 기록이든 `more == false`인 동안 `used_s ≤ min × 60`이다(spec 005 불변식을 긴급 시작까지 그대로 적용, SC-806).

## 예

입력(가짜, 일시 중지 입력은 P8이 정해진 뒤 확정):

```json
{"version":1,"timezone":"Asia/Seoul","storage":true,"events":[
 {"at":"2026-11-18T01:00:00Z","type":"add_task","title":"가짜 할 일 A"},
 {"at":"2026-11-18T01:00:05Z","type":"budget","minutes":120},
 {"at":"2026-11-18T01:00:10Z","type":"start"},
 {"at":"2026-11-18T01:10:10Z","type":"urgent","title":"가짜 긴급 일 U","quantum_min":15},
 {"at":"2026-11-18T01:20:10Z","type":"complete"}
]}
```

읽는 법: A를 25분으로 시작하고 10분 뒤 U를 넣는다. A는 대기가 되고 계기 `urgent` 체크포인트(경과 10분)와 로그 줄 `urgent`가 남으며 쓴 시간에서 15분을 돌려받는다. U가 15분으로 돌고 `urgent_pin`은 U, `return_task`는 A다. U를 완료하면 `notch_task`가 A이고 `notch_rule`은 `urgent_return_v1`이다. 정확한 출력 바이트는 단위 2의 첫 Red 커밋에서 golden으로 둔다.
