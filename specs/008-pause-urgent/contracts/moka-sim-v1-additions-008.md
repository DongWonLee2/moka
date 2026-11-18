# 계약: `moka-sim` 덧붙임 (spec 008)

spec 001 `contracts/moka-sim-v1.md`, spec 002 `contracts/moka-sim-v1-additions.md`, spec 003 `contracts/moka-sim-v1-additions-003.md`, spec 005 `contracts/moka-sim-v1-additions-005.md`에 덧붙인다. 근거: spec R-834, data-model §1~§10. 승인 항목 4(헌법 I). 입력 모양은 research P8 A(토론 3:0, 2026-11-18)다.

## 켜는 법

시나리오에 이 문서의 새 이벤트가 하나라도 있으면 아래 출력 키를 켜고 spec 005 켜짐(이월·가용 시간)도 함께 켠다(research R18). `version`은 1 그대로다. 새 이벤트가 없는 시나리오의 출력은 spec 001·002·003·005 golden과 바이트까지 같아야 한다.

## 입력 덧붙임 (storage 모드에서만)

| 이벤트 | 필드 | 규칙 |
|---|---|---|
| `pause` | `length`(정수 분 1~180 또는 문자열 `"until_morning"`), `done_note`·`next_note`(문자열, 생략하면 안 적기) | 도는 중이나 초안에서 받는다. 누름과 제출이 같은 시각이다. 초안에서 두 줄 필드가 있으면 종료 코드 2 |
| `resume` | 없음 | "다시 시작". 일시 중지 중이 아니면 종료 코드 2 |
| `urgent` | `title`(문자열), `quantum_min`(정수 1~180), `done_note`·`next_note`(문자열, 생략하면 안 적기), `extend`(불리언, 생략하면 `false`) | 도는 중에만 받는다. 이벤트 시각 하나로 남은 초를 계산한다(data-model §8). `extend: true`는 두 줄 뒤 늘리기 확인의 수락이다. 칩이 남은 분보다 긴데 `extend`가 없거나 `false`면 종료 코드 2. 늘릴 필요가 없을 때, 오늘 기록이 없을 때, "더 할래요" 뒤에 `extend: true`도 종료 코드 2. 확인의 "N분만 할래요"는 `quantum_min`을 남은 분으로 적어 나타낸다 |

- 시간 끝, 빈 상태, 이월 카드, 가용 시간 질문, 오늘 끝에서 `pause`이면 종료 코드 2(R-801).
- 멈춘 동안 `pause`, `complete`, `skip`, `switch`, `urgent`, `start`, `choose_quantum`은 종료 코드 2(R-803). 초안에서 멈춘 동안 다시 `pause`도 같다.
- 기존 `add_task`와 `enter_title`은 멈춘 동안(타이머 `paused` 포함) 저장만 하고 초안을 바꾸지 않는다. 제목이 비면 지금처럼 종료 코드 2다.
- 기존 `set_default_quantum`은 멈춘 동안 설정만 바꾸고 타이머와 초안 칩은 그대로 둔다(research R15).
- 기존 `quit`은 멈춘 채면 `quit` 체크포인트와 저장한 남은 초 돌려주기를 한다. 기존 `activate`와 `resume`은 끝 시각 전이거나 이미 `waiting`일 때 하루 경계를 넘겼으면 data-model §4를 한다.
- 모든 이벤트는 처리하기 전에 그 `at`으로 암묵 tick과 함께 정한 길이의 끝을 판정한다. 출력은 지금처럼 입력 이벤트마다 한 줄이다.
- 끝 시각을 처음 지난 이벤트(`tick` 포함)는 그 이벤트를 처리하기 전에 활성화 차례를 한 번 돈다(R-804의 펼침). 초안에서 멈췄으면 일시 중지가 끝나고, 도는 중에서 멈췄으면 `stage`가 `waiting`이 되며, 하루 경계를 넘겼으면 data-model §4를 한다.
- `tick` 없이 끝 시각을 지난 이벤트도 같다. 그 판정 뒤의 상태로 이벤트를 처리한다. 예: 초안 멈춤의 끝을 지난 `start`는 시작하고, `resume`은 일시 중지가 이미 끝났으므로 종료 코드 2다.
- 끝 시각과 하루 경계를 모두 지난 첫 이벤트가 `resume`이면, 처리 전 활성화가 data-model §4로 일시 중지를 끝내므로 `resume`은 종료 코드 2다. US1-9(05:20에 30분으로 멈춤, 06:30에 다시 시작)를 재현하려면 05:50에 `tick`을 두어 먼저 `waiting`으로 만든다.
- 오류 픽스처는 `Tests/MokaCoreTests/Fixtures/sim/errors/`에 하나씩 더하고 `SimScenarioTests` 표에 넣는다. 기존 `unknown-type.json`은 `pause`를 모르는 값으로 쓰므로 단위 1에서 예약되지 않은 이름으로 바꾸고, storage 없이 `pause`를 쓴 `storageOnly` 픽스처를 더한다. `urgent`의 `extend` 거부는 `storage-008-urgent-extend-not-needed`, `storage-008-urgent-extend-no-cap`, `storage-008-urgent-extend-after-more`, 수락 없이 긴 칩은 `storage-008-urgent-extend-missing`으로 둔다(`storage-005-extend-*` 무늬).

시뮬레이터로 재현하지 않는 경우(누른 시각의 남은 초, 돌아가기, 두 줄을 적는 동안 하루 경계, 입력 중 활성화)는 단위 시험이 맡는다(data-model §12).

## 출력 덧붙임

켜짐일 때 storage 모드의 모든 줄에 spec 005 키 뒤로 아래를 이 순서로 붙인다.

| 키 | 규칙 |
|---|---|
| `pause` | 일시 중지 중이 아니면 `null`. 중이면 `{"origin":"run"\|"draft","stage":"holding"\|"waiting","left_s":N\|null,"frozen_s":N\|null}` |
| `urgent_pin` | 긴급 고정된 할 일 id, 없으면 `null`. 단위 1부터 `null`로 낸다 |
| `return_task` | 복귀 제안을 기다리는 끊긴 할 일 id, 없으면 `null`. 단위 1부터 `null`로 낸다 |

- `left_s`는 남은 일시 중지 초(올림)이고, 0 이하이면 `null`이다. `stage`의 `waiting`은 끝 시각이 지난 때다.
- `frozen_s`는 멈춘 작업 시간의 남은 초(올림)이고, 초안에서 멈췄으면 `null`이다.
- 세 키는 단위 1에서 함께 넣어, 단위 2가 긴급을 더해도 긴급 이벤트가 없는 golden의 바이트가 바뀌지 않게 한다.

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

출력에 할 일 제목과 두 줄 본문을 내지 않는다(ASCII만).

## 새 불변식 (종료 코드 1)

- 도는 중에서 멈춘 동안 줄마다 `frozen_s`가 같고 `timer_state`가 `expired`로 바뀌지 않는다(R-803).
- 멈춘 동안 `budget.used_s`가 바뀌지 않는다(R-805). 끝나는 이벤트의 줄은 뺀다.
- `mode`가 `paused`인 동안 `notch_task`가 바뀌지 않고, `add_task` 뒤에도 그대로다.
- `timer_state`가 `paused`이면 `notch_task`가 `active`다.
- 이어 돈 줄의 `remaining_s`는 직전 줄의 `frozen_s`와 같다(같은 시각일 때).
- `urgent` 이벤트 한 번에 `decision`이 정확히 하나이고 `user_action`이 `urgent`이며, 그 줄의 `task_id`는 끊긴 할 일이다(R-815).
- `urgent_pin`이 후보이면 `order`가 있을 때 그 맨 앞이다(R-813). 하루 경계로 대기가 되어 이월 답 대기인 할 일은 후보가 아니라 `order`에 없다.
- 어느 하루의 기록이든 `more == false`인 동안 `used_s ≤ min × 60`이다(spec 005 불변식을 긴급 시작까지 그대로 적용, SC-806).

## 예

입력(가짜):

```json
{"version":1,"timezone":"Asia/Seoul","storage":true,"events":[
 {"at":"2026-11-18T01:00:00Z","type":"add_task","title":"가짜 할 일 A"},
 {"at":"2026-11-18T01:00:05Z","type":"budget","minutes":120},
 {"at":"2026-11-18T01:00:10Z","type":"start"},
 {"at":"2026-11-18T01:05:10Z","type":"pause","length":30,"next_note":"가짜 다음 줄"},
 {"at":"2026-11-18T01:15:10Z","type":"resume"},
 {"at":"2026-11-18T01:20:10Z","type":"urgent","title":"가짜 긴급 일 U","quantum_min":15},
 {"at":"2026-11-18T01:30:10Z","type":"complete"}
]}
```

읽는 법: A를 25분으로 시작하고 5분 뒤 멈춘다. `timer_state`는 `paused`, `frozen_s`는 1200이고 체크포인트 `pause`(경과 5분)와 로그 줄 `pause`가 남는다. 10분 뒤 이어 돌면 로그 줄 `resume`이 남고 `remaining_s`는 1200이다. 5분 더 돌고 U를 넣으면 A는 대기가 되고 계기 `urgent` 체크포인트(경과 10분)와 로그 줄 `urgent`가 남으며 쓴 시간에서 15분을 돌려받는다. U가 15분으로 돌고 `urgent_pin`은 U, `return_task`는 A다. U를 완료하면 `notch_task`가 A이고 `notch_rule`은 `urgent_return_v1`이다. 정확한 출력 바이트는 단위 1·2의 첫 Red 커밋에서 golden으로 둔다.
