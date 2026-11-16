# 계약: `moka-sim` 덧붙임 (spec 005)

spec 001 `contracts/moka-sim-v1.md`, spec 002 `contracts/moka-sim-v1-additions.md`, spec 003 `contracts/moka-sim-v1-additions-003.md`에 덧붙인다. 근거: spec R-432, data-model §5~§12. 승인 항목 4(헌법 I). 시나리오 형식과 출력 키는 golden과 튜닝 쪽이 읽는 계약이다.

## 켜는 법

시나리오에 `carry`·`budget`·`more` 가운데 하나라도 있으면 이월 판정·이월 카드·가용 시간 질문·오늘 끝과 아래 출력 키를 켠다(Q3-C, debate 3:0, 2026-11-16). spec 003 `judge`·`key`가 출력 키를 붙이던 무늬와 같다. `version`은 1 그대로다. 새 이벤트가 없는 storage 시나리오는 카드·질문·오늘 끝 없이 새 고르기 규칙만 쓴다.

고르기 규칙은 storage 모드 전체에서 바뀐다. 그래서 기존 `storage-*` golden의 `notch_task` 순서와 `scheduler_choice` 값(`priority_rotate_v0` → `weighted_rotate_v1`·`warmup_v1`)이 바뀐다. 바뀐 줄과 이유를 단위 1 PR에 적는다(spec 위험 5, 시험 약화가 아니라 규칙 교체). spec 001 타이머 golden은 바이트 그대로다.

이하 "켜짐"은 새 이벤트가 하나라도 있는 시나리오를 뜻한다.

## 입력 덧붙임 (storage 모드에서만)

| 이벤트 | 필드 | 규칙 |
|---|---|---|
| `carry` | `task`(할 일 id), `answer`(`"today"`·`"drop"`·`"move"`), `date`(`"YYYY-MM-DD"`, `move`일 때만 필수, 그 밖에는 있으면 오류) | 지금 카드에 떠 있는 할 일에 답한다(data-model §10). 카드 맨 앞 할 일이 아니면 종료 코드 2 |
| `budget` | `minutes`(정수, 30~960이고 30의 배수. 선택지 다섯은 60·120·240·360·480) | 가용 시간 답(data-model §11, 직접 적기 포함). 질문 중이 아니면 종료 코드 2 |
| `start`(기존 이벤트에 필드 하나) | `extend`(불리언, 생략하면 `false`) | 시작 전 화면에서 칩이 오늘 남은 분보다 길 때 `true`면 늘리기 확인을 받아들인 것으로 보고 모자란 분만큼 오늘 가용 시간을 늘린 뒤 시작한다(data-model §11 "늘리기"). 칩이 남은 분보다 긴데 `extend`가 없거나 `false`면 종료 코드 2. 칩이 남은 분 이하인데 `extend: true`면 종료 코드 2. 시간 끝의 `start`("N분 더")에는 받지 않는다(종료 코드 2) |
| `more` | 없음 | "더 할래요"(data-model §12). 오늘 끝이 아니면 종료 코드 2 |

- 기존 `activate`·`relaunch`가 활성화 순서(data-model §15)를 따른다. `relaunch`는 R-111이 되돌린 할 일을 같은 시작의 판정에 넘긴다.
- 기존 `judge`의 `concrete`가 워밍업에 쓰이고, 기존 `add_task`의 `est_min`이 워밍업·마무리 규칙(순수 함수만)·"내일"에 쓰인다. 새 필드는 없다.
- 종료 코드 2를 더하는 경우: 모르는 `answer`, `date` 형식 틀림, `date`가 그 하루보다 뒤가 아님, `minutes`가 범위 밖이거나 30의 배수가 아님, `extend` 조건 위반, 위 상태 조건 위반. 오류 픽스처는 `Tests/MokaCoreTests/Fixtures/sim/errors/`에 하나씩 더하고 `SimScenarioTests` 표에 넣는다.

## 출력 덧붙임

켜짐일 때 storage 모드의 모든 줄에 spec 002·003 키 뒤로 아래를 이 순서로 붙인다.

| 키 | 규칙 |
|---|---|
| `notch_rule` | 지금 노치 할 일을 띄운 규칙 이름(`weighted_rotate_v1`·`warmup_v1`), 노치 할 일이 없으면 `null` |
| `mode` | `"session"`·`"carry_card"`·`"ask_budget"`·`"day_end"`(data-model §12. `storageUnavailable`은 시뮬레이터에 없음) |
| `carry_card` | 카드에 떠 있는 할 일 id, 없으면 `null` |
| `carry_left` | 카드에 오를 할 일 수(지금 것 포함), 정수 |
| `budget` | 오늘 기록 `{"min":M,"extended_min":E,"used_s":S,"more":B}`(M은 늘린 분 포함 가용 시간), 없으면 `null` |

그리고 켜짐이면 `tasks` 배열의 각 객체에 `streak` 뒤로 `carry_count`(정수)와 `due`(불리언)를 붙인다.

켜짐이 아니면 출력 키는 spec 002·003 그대로다.

## 새 불변식 (종료 코드 1)

- `timer_state`가 `empty`(빈 상태와 초안)이면 `notch_task`가 `due == true`인 할 일이 아니다(R-413). 도는 중·시간 끝에는 걸지 않는다. 하루 경계를 넘긴 진행 중 할 일은 `due`가 붙은 채 노치에 남기 때문이다(R-417).
  - 손 확인(`storage-005-boundary-running`): 05:50 시작 → 06:00 넘겨 `activate`에서 그 할 일이 `due: true`, `timer_state: running`, `notch_task` 그 할 일(불변식 적용 안 됨) → `skip`이면 대기·`due`, `mode: carry_card`, `timer_state: empty`, `notch_task: null`(통과) → 다른 갈래에서 `complete`이면 `due: false`, 이월 대상이 없으면 `mode: ask_budget`, `notch_task: null`(통과). 시간 끝에서 `start`("N분 더", spec 6c)이면 다시 `running`이고 `due`가 붙은 채 노치에 남는다(불변식 적용 안 됨).
- `mode`가 `carry_card`·`ask_budget`·`day_end`이면 `timer_state`가 `empty`이고 초안이 없다(R-413, R-419, R-422).
- 어느 하루의 기록이든 `more == false`인 동안 그 기록의 `used_s ≤ min × 60`이다(늘린 분 포함, SC-405). 출력 `budget`은 오늘 기록이지만, 러너는 하루 경계를 넘긴 작업 시간과 그 "N분 더"를 시작한 하루의 기록(전날 기록)에 더하고 돌려주므로 전날 기록에도 같은 검사를 한다(data-model §11 `budgetDay`). `used_s`는 시작 때 고른 분 × 60을 더하고 일찍 끝나면 남은 초를 돌려준 값이다(data-model §11, Q4-B). 시작한 작업 시간의 분 합은 돌려받은 시간 때문에 `hours × 60`을 넘을 수 있어 불변식으로 두지 않는다.
- `carry` 이벤트 한 번에 `decision` 줄이 정확히 하나이고 `user_action`이 `carry_*`, `scheduler_choice`가 `carry_card_v1`이며 `checkpoint`는 `null`이다(R-416).
- `budget`·`more` 이벤트와 `extend: true`로 늘린 `start` 줄은 늘리기 몫의 `decision`을 남기지 않는다(R-416). `budget`·`more` 줄은 `decision`과 `checkpoint`가 `null`이다.
- `extend: true`인 `start` 뒤 `budget.min`은 직전 값 + (칩 − 직전 남은 분)이고 `extended_min`도 같은 만큼 는다.

## 예

입력(가짜):

```json
{"version":1,"timezone":"Asia/Seoul","storage":true,"events":[
 {"at":"2026-11-15T00:00:00Z","type":"add_task","title":"가짜 할 일 A","deadline":"2026-11-15","est_min":50},
 {"at":"2026-11-15T00:00:05Z","type":"add_task","title":"가짜 할 일 B"},
 {"at":"2026-11-15T00:00:10Z","type":"budget","minutes":120},
 {"at":"2026-11-15T00:00:20Z","type":"start"},
 {"at":"2026-11-15T00:05:00Z","type":"skip"},
 {"at":"2026-11-15T22:00:00Z","type":"activate"},
 {"at":"2026-11-15T22:00:05Z","type":"carry","task":1,"answer":"today"},
 {"at":"2026-11-15T22:00:10Z","type":"budget","minutes":240}
]}
```

읽는 법: 첫 줄들에서는 오늘 기록이 없어 `mode`가 `ask_budget`이고 고르기가 없다. 2시간을 답하면 마감이 있는 A가 순서 앞이라 초안이 되고(점수 없음, 순위 몫), 시작 뒤 미루면 B가 초안이 된다. 서울 11월 16일 07:00(`22:00Z`) 활성화에서 하루가 바뀐다. A는 미루기로 손댔고 마감(11월 15일)도 지나 `due`가 되고, B는 손대지 않았고 마감이 없어 후보로 남는다. `mode`가 `carry_card`가 되며 어제 초안 B는 비워진다. "오늘 할래요"로 A의 `carry_count`가 1이 되고, 4시간을 답하면 `mode`가 `session`이 되어 그 하루 첫 고르기(워밍업 후보가 없으므로 가중 순환)가 돈다. 정확한 출력 바이트는 단위 1의 첫 Red 커밋에서 golden으로 둔다.
