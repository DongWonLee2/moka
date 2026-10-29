# 계약: `moka-sim` 시나리오 형식 v1

공개 계약이다(헌법 I). 바꾸려면 사람 승인이 필요하다. 출처: spec 001 R-015, D2 채택(사용자 승인 2026-10-28), EGM 리뷰 뒤 보강(토론 Q1 (b), 사용자 승인 2026-10-28).

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

## 버전 규칙

- 선택 필드와 이벤트 종류를 덧붙이는 것은 `version: 1`을 유지한다. 그래도 공개 계약 변경이므로 PR "사람이 볼 결정"에 올린다.
- 의미 변경, 필드 삭제, 이름 변경은 `version: 2`. 기존 시나리오는 같은 PR에서 옮긴다.
  - 단서: `moka-sim`을 이 저장소 밖에서 쓰는 사용자가 없는 동안은 의미 변경도 `version: 1`을 유지할 수 있다. 그때는 바뀐 의미와 기존 시나리오의 기대 출력 변화를 같은 PR "사람이 볼 결정"에 적고, 바뀐 기대 출력 파일을 같은 PR에서 고친다. 외부 사용자가 생기면 위 규칙(의미 변경은 `version: 2`)을 따른다(사용자 결정 2026-10-29, PR #44).
- 덧붙이기(선택 필드·이벤트 종류)일 때 기존 v1 시나리오 파일은 같은 출력으로 통과해야 한다(golden 시험). 위 단서로 `version: 1`에서 의미를 바꿀 때는 이 문장이 적용되지 않고, 그 PR에서 고친 기대 출력으로 통과해야 한다.
