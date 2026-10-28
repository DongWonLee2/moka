# 계약: `moka-sim` 시나리오 형식 v1

공개 계약이다(헌법 I). 바꾸려면 사람 승인이 필요하다. 출처: spec 001 R-015, D2 채택(사용자 승인 2026-10-28).

## 실행

```
moka-sim run <scenario.json>
```

- 표준 출력: 이벤트마다 JSON 한 줄(JSON Lines). 그 밖의 출력은 없다.
- 표준 오류: 오류 설명 한 줄(사람용, 형식 보장 없음).
- 종료 코드: `0` 정상, `1` 불변식 위반(예: 음수 남은 시간, 끝 시각이 시작 시각보다 앞섬), `2` 입력 오류(모르는 `version`·키·`type`, 필수 필드 없음, 시각이 거꾸로 감, 범위 밖 값).
- DB, 네트워크, Keychain, 환경 변수, 시스템 시계(`Date()`), 시스템 시간대(`TimeZone.current`)를 쓰지 않는다. DB 경로 인자는 없다.

## 입력

```json
{
  "version": 1,
  "timezone": "Asia/Seoul",
  "settings": { "default_quantum_min": 25 },
  "events": [
    { "at": "2026-11-02T09:00:00+09:00", "type": "enter_title", "title": "가짜 할 일 A" },
    { "at": "2026-11-02T09:00:03+09:00", "type": "choose_quantum", "minutes": 45 },
    { "at": "2026-11-02T09:00:04+09:00", "type": "start" },
    { "at": "2026-11-02T09:30:04+09:00", "type": "tick" },
    { "at": "2026-11-02T09:45:04+09:00", "type": "tick" },
    { "at": "2026-11-02T09:46:00+09:00", "type": "complete" }
  ]
}
```

| 필드 | 필수 | 규칙 |
|---|---|---|
| `version` | 예 | 정수 `1` |
| `timezone` | 예 | IANA 이름. 기본값 없음 |
| `settings` | 아니오 | 없으면 `{}`. 키: `default_quantum_min`(정수 1~180). 없으면 25 |
| `events` | 예 | 배열. `at`은 줄어들지 않아야 한다 |
| `events[].at` | 예 | ISO 8601, 오프셋 필수, 초 단위까지(소수 초 없음) |
| `events[].type` | 예 | 아래 표의 값만 |

| `type` | 추가 필드 | 의미 |
|---|---|---|
| `enter_title` | `title`(문자열, 앞뒤 공백을 뺀 뒤 비어 있으면 입력 오류) | 빈 상태에서 제목 입력 → 칩이 기본값으로 채워짐 |
| `choose_quantum` | `minutes`(정수 1~180) | 칩 값을 바꿈. 제목 입력 뒤나 시간 끝 상태에서만 |
| `start` | 없음 | 칩 값으로 타이머 시작(제목 입력 뒤, 또는 시간 끝 상태에서 다시 시작) |
| `tick` | 없음 | 그 시각으로 상태를 갱신 |
| `complete` | 없음 | 할 일을 비움(도는 중 또는 시간 끝에서) |
| `set_default_quantum` | `minutes`(정수 1~180) | 설정의 기본값 변경. 도는 타이머에는 영향 없음 |

상태에 맞지 않는 이벤트(예: 빈 상태에서 `start`)는 종료 코드 2다.

## 출력 (이벤트마다 한 줄)

```json
{"seq":1,"at":"2026-11-02T00:00:00Z","event":"enter_title","state":"empty","chip_min":25,"remaining_s":null}
{"seq":3,"at":"2026-11-02T00:00:04Z","event":"start","state":"running","chip_min":45,"remaining_s":2700}
{"seq":5,"at":"2026-11-02T00:45:04Z","event":"tick","state":"expired","chip_min":45,"remaining_s":0}
```

| 필드 | 규칙 |
|---|---|
| `seq` | 1부터 이벤트 순서 |
| `at` | 입력 시각을 UTC(`Z`)로 |
| `event` | 입력 `type` 그대로 |
| `state` | `empty` / `running` / `expired` 중 하나 |
| `chip_min` | 현재 칩 값(분). 제목 입력 전이면 `null` |
| `remaining_s` | `running`이면 끝 시각까지 남은 초를 올림한 정수, `expired`면 `0`, `empty`면 `null` |

- 키 순서는 위 표 순서로 고정한다.
- 제목은 출력하지 않는다(가짜 시나리오도 출력에 할 일 텍스트를 남기지 않는다).

## 버전 규칙

- 선택 필드와 이벤트 종류를 덧붙이는 것은 `version: 1`을 유지한다. 그래도 공개 계약 변경이므로 PR "사람이 볼 결정"에 올린다.
- 의미 변경, 필드 삭제, 이름 변경은 `version: 2`. 기존 시나리오는 같은 PR에서 옮긴다.
- 기존 v1 시나리오 파일은 덧붙이기 뒤에도 같은 출력으로 통과해야 한다(golden 시험).
