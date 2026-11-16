# 계약: `moka-sim` 덧붙임 (spec 005)

spec 001 `contracts/moka-sim-v1.md`, spec 002 `contracts/moka-sim-v1-additions.md`, spec 003 `contracts/moka-sim-v1-additions-003.md`에 덧붙인다. 근거: spec R-432, data-model §5~§12. 승인 항목 4(헌법 I). 시나리오 형식과 출력 키는 golden과 튜닝 쪽이 읽는 계약이다.

## 켜는 법 (확정할 것 Q3)

이월 판정·이월 카드·가용 시간 질문·오늘 끝이 언제 시뮬레이터에서 동작하는지는 plan "확정할 것" Q3의 답으로 정한다. 아래 입력·출력 모양은 어느 안이든 같다.

- Q3-A: 시나리오 `version: 2`이면 켠다. `version: 1`은 새 고르기 규칙(가중 순환·워밍업)만 쓰고 카드·질문·오늘 끝이 없다.
- Q3-B: storage 모드면 늘 켠다. 기존 `storage-*` 시나리오에 `budget` 이벤트를 넣어 다시 만든다.
- Q3-C: 시나리오에 `carry`·`budget`·`more` 가운데 하나라도 있으면 켠다(spec 003 `judge`·`key`가 출력 키를 붙이던 무늬).

어느 안이든 고르기 규칙은 storage 모드 전체에서 바뀐다. 그래서 기존 `storage-*` golden의 `notch_task` 순서와 `scheduler_choice` 값(`priority_rotate_v0` → `weighted_rotate_v1`·`warmup_v1`)이 바뀐다. 바뀐 줄과 이유를 단위 1 PR에 적는다(spec 위험 5, 시험 약화가 아니라 규칙 교체). spec 001 타이머 golden은 바이트 그대로다.

이하 "켜짐"은 Q3의 조건이 참인 시나리오를 뜻한다.

## 입력 덧붙임 (storage 모드에서만)

| 이벤트 | 필드 | 규칙 |
|---|---|---|
| `carry` | `task`(할 일 id), `answer`(`"today"`·`"drop"`·`"move"`), `date`(`"YYYY-MM-DD"`, `move`일 때만 필수, 그 밖에는 있으면 오류) | 지금 카드에 떠 있는 할 일에 답한다(data-model §10). 카드 맨 앞 할 일이 아니면 종료 코드 2 |
| `budget` | `hours`(정수, 1·2·4·6·8) | 가용 시간 답(data-model §11). 질문 중이 아니면 종료 코드 2 |
| `more` | 없음 | "더 할래요"(data-model §12). 오늘 끝이 아니면 종료 코드 2 |

- 기존 `activate`·`relaunch`가 활성화 순서(data-model §15)를 따른다. `relaunch`는 R-111이 되돌린 할 일을 같은 시작의 판정에 넘긴다.
- 기존 `judge`의 `concrete`가 워밍업에 쓰이고, 기존 `add_task`의 `est_min`이 워밍업·마무리 규칙(순수 함수만)·"내일"에 쓰인다. 새 필드는 없다.
- 켜짐이 아닐 때 새 이벤트는 종료 코드 2다(Q3-C에서는 생기지 않음).
- 종료 코드 2를 더하는 경우: 모르는 `answer`, `date` 형식 틀림, `date`가 그 하루보다 뒤가 아님, `hours`가 다섯 값 밖, 위 상태 조건 위반. 오류 픽스처는 `Tests/MokaCoreTests/Fixtures/sim/errors/`에 하나씩 더하고 `SimScenarioTests` 표에 넣는다.

## 출력 덧붙임

켜짐일 때 storage 모드의 모든 줄에 spec 002·003 키 뒤로 아래를 이 순서로 붙인다.

| 키 | 규칙 |
|---|---|
| `notch_rule` | 지금 노치 할 일을 띄운 규칙 이름(`weighted_rotate_v1`·`warmup_v1`), 노치 할 일이 없으면 `null` |
| `mode` | `"session"`·`"carry_card"`·`"ask_budget"`·`"day_end"`(data-model §12. `storageUnavailable`은 시뮬레이터에 없음) |
| `carry_card` | 카드에 떠 있는 할 일 id, 없으면 `null` |
| `carry_left` | 카드에 오를 할 일 수(지금 것 포함), 정수 |
| `budget` | 오늘 기록 `{"hours":H,"used_s":S,"more":B}`, 없으면 `null` |

그리고 켜짐이면 `tasks` 배열의 각 객체에 `streak` 뒤로 `carry_count`(정수)와 `due`(불리언)를 붙인다.

켜짐이 아니면 출력 키는 spec 002·003 그대로다.

## 새 불변식 (종료 코드 1)

- `notch_task`가 `due == true`인 할 일이 아니다(R-413).
- `mode`가 `carry_card`·`ask_budget`·`day_end`이면 `timer_state`가 `empty`이고 초안이 없다(R-413, R-419, R-422).
- 오늘 기록이 있고 `more == false`인 동안, 그 하루에 시작한 작업 시간과 "N분 더"의 분 합이 `hours × 60` 이하다(SC-405).
- `carry` 이벤트 한 번에 `decision` 줄이 정확히 하나이고 `user_action`이 `carry_*`, `scheduler_choice`가 `carry_card_v1`이며 `checkpoint`는 `null`이다(R-416).
- `budget`·`more` 이벤트의 줄은 `decision`과 `checkpoint`가 `null`이다(R-416).

## 예

입력(가짜, Q3-C 기준):

```json
{"version":1,"timezone":"Asia/Seoul","storage":true,"events":[
 {"at":"2026-11-15T00:00:00Z","type":"add_task","title":"가짜 할 일 A","deadline":"2026-11-15","est_min":50},
 {"at":"2026-11-15T00:00:05Z","type":"add_task","title":"가짜 할 일 B"},
 {"at":"2026-11-15T00:00:10Z","type":"budget","hours":2},
 {"at":"2026-11-15T00:00:20Z","type":"start"},
 {"at":"2026-11-15T00:05:00Z","type":"skip"},
 {"at":"2026-11-15T22:00:00Z","type":"activate"},
 {"at":"2026-11-15T22:00:05Z","type":"carry","task":1,"answer":"today"},
 {"at":"2026-11-15T22:00:10Z","type":"budget","hours":4}
]}
```

읽는 법: 첫 줄들에서는 오늘 기록이 없어 `mode`가 `ask_budget`이고 고르기가 없다. 2시간을 답하면 마감이 있는 A가 순서 앞이라 초안이 되고(점수 없음, 순위 몫), 시작 뒤 미루면 B가 초안이 된다. 서울 11월 16일 07:00(`22:00Z`) 활성화에서 하루가 바뀐다. A는 미루기로 손댔고 마감(11월 15일)도 지나 `due`가 되고, B는 손대지 않았고 마감이 없어 후보로 남는다. `mode`가 `carry_card`가 되며 어제 초안 B는 비워진다. "오늘 할래요"로 A의 `carry_count`가 1이 되고, 4시간을 답하면 `mode`가 `session`이 되어 그 하루 첫 고르기(워밍업 후보가 없으므로 가중 순환)가 돈다. 정확한 출력 바이트는 단위 1의 첫 Red 커밋에서 golden으로 둔다.
