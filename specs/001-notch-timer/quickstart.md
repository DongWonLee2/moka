# Quickstart: 노치와 타이머 검증 (spec 001)

화면 없는 검증(1~3)은 무인으로 돌 수 있다. 화면 검증(4~6)은 사람이 한다. 결과는 PASS / FAIL / SKIP / NOT_RUN으로만 적는다.

## 1. 핵심 로직과 스키마 (리눅스·macOS)

```
swift test
```

기대: PRD FR과 spec R-ID로 시작하는 시험(`@Test("FR-06 R-005: …")` 등, ADR-0003 표시 이름 규칙)이 모두 PASS. 포함 범위는 타이머 상태기계(R-005·R-007·R-008·R-010), 칩 규칙(R-003·R-004), 설정 읽기 규칙(R-012·R-013), 표시 위치 선택(R-011), 마이그레이션 이름 배열·스키마 스냅샷·DB 경로 가드(D1), `moka-sim` golden(R-015).

리눅스 컨테이너에서도 같은 결과인지 확인(D1 보강):

```
docker run --rm -v "$PWD":/w -w /w swift:6.3.3-noble bash -c "apt-get update -qq && apt-get install -y -qq libsqlite3-dev >/dev/null && swift test"
```

## 2. 시뮬레이터

```
swift run moka-sim run Tests/MokaCoreTests/Fixtures/sim/<시나리오>.json
```

기대: [contracts/moka-sim-v1.md](contracts/moka-sim-v1.md) 형식의 JSON Lines, 종료 코드 0. 시나리오는 가짜 할 일만 쓴다. 최소 시나리오:
- 기본 25분 시작 → 끝 시각에 `expired`, `remaining_s` 0
- 45분 선택 → 다시 시작(R-010) → 완료
- 도는 중 `set_default_quantum` → 남은 시간 그대로, 다음 `enter_title`의 `chip_min`이 새 값(R-013)
- 잠자기를 `at` 건너뛰기로 표현 → 깨어난 첫 `tick`이 `expired`(R-008)
- 오류 입력(모르는 `type`, 시각 역행) → 종료 코드 2

## 3. 오류 주입 (검증기 검증)

기대값 하나를 일부러 틀리게 바꿔 `swift test`가 FAIL하고 종료 코드가 0이 아닌지 본다. 마이그레이션에서 열 하나를 지워 스냅샷 시험이 FAIL하는지 본다(ADR-0004). 커밋하지 않는다.

## 4. 앱 빌드

```
xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

빌드 성공은 완료가 아니다.

## 5. 화면 스냅샷 (macOS 로컬)

```
xcodegen generate && MOKA_SNAPSHOT_DIR="$PWD/.verify/snapshots/001" xcodebuild test -scheme Moka -destination 'platform=macOS' -only-testing:MokaAppTests
```

기대: 화면 상태마다 PNG 라이트·다크(빈 상태, 입력, 칩 펼침, 도는 중, 시간 끝, 떠 있는 창). sanity 시험 PASS. 사람이 `~/Dev/ai-platform/projects/moka/design/pr-<번호>/index.html`에서 시안과 나란히 본다.

## 6. 사람이 손으로 볼 것

- 노치에 마우스를 올리면 바로 펼쳐지는지(SC-004), 제목 입력 → Enter → Enter로 시작(SC-001)
- 1분 타이머로 시간 끝 자동 펼침, 그동안 다른 앱에 타이핑한 글자가 노치로 0자(SC-003), 마우스를 넣었다 빼도 펼친 채 유지(R-009)
- 덮개를 닫고 외부 모니터만: 메뉴 막대 아래 중앙 떠 있는 창, 타이머 끊김 없음(R-011, SC-005)
- 설정에서 45분으로 바꾸고 앱 재시작 → 기본값 45, DB 파일이 `~/Library/Application Support/dev.dongwon.moka/moka.sqlite`에 생김(ADR-0005 결정 검증)
