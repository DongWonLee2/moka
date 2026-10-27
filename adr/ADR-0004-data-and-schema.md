# ADR-0004: 데이터 저장, 스키마 계약, DB 경로

- 상태: Accepted
- 작성일 / 사람 승인일: 2026-10-28 / 2026-10-28
- 결정 책임자: 저장소 소유자
- 관련 Spec/R-ID: PRD 9장 데이터 모델(`decisions_log` 삭제 없음, 스키마 변경 시 마이그레이션), FR-18, 헌법 I(스키마는 승인 항목)
- 사용한 외부 근거: GRDB Migrations 문서

## 맥락

`decisions_log`와 `labels`는 Python 튜닝 스크립트가 직접 읽으므로 스키마가 Swift와 Python 사이의 계약이다. 사용자는 11월 초부터 Xcode로 빌드한 앱을 매일 쓰며 실제 기록을 쌓는다. 밤 PR이 스키마를 바꿀 수 있다. GRDB `eraseDatabaseOnSchemaChange`는 스키마가 바뀌면 DB 내용을 지운다.

## 평가 기준

1. 사용자 데이터가 지워질 경로가 없는가 2. 스키마 변경이 PR에서 사람 눈에 보이는가 3. Swift와 Python이 같은 계약을 보는가 4. 거짓 PASS가 없는가

## 대안

| 대안 | 장점 | 단점·위험 | 근거·실험 |
|---|---|---|---|
| A. 마이그레이션 이름 목록 고정 + `sqlite_master` SQL 스냅샷(`schema.sql`) + pytest가 같은 파일로 가짜 DB 생성 | 계약 원본 하나, 제약·외래 키까지 비교 | 리눅스와 macOS SQLite의 텍스트 차이(미확인) | GRDB 문서: "A good migration is a migration that is never modified once it has shipped." |
| B. `PRAGMA table_info` 정규화 텍스트 비교 | GRDB 버전 변화에 덜 민감 | CHECK·외래 키를 담지 않아 거짓 PASS, pytest가 실행할 수 없음 | — |
| C. DEBUG에서 `eraseDatabaseOnSchemaChange` 켬 | 개발 편함 | Debug 빌드로 쓰는 실제 데이터가 지워짐 | GRDB 문서: "Warning: This option can destroy your precious users' data!" |

## Agent의 추천과 근거

A를 추천하고 C는 쓰지 않는다(추천안 토론 3:0).
- 앱 DB 경로: `~/Library/Application Support/dev.dongwon.moka/moka.sqlite`. 경로는 주입 가능한 값이다. `moka-sim`과 튜닝 스크립트에는 기본 경로를 두지 않는다.
- `eraseDatabaseOnSchemaChange`는 DEBUG에서도 켜지 않는다. 마이그레이션은 이름 붙인 전진 마이그레이션만, 배포한 마이그레이션은 고치지 않는다. 개발용 초기화는 명시적인 인자(예: `moka-sim --fresh`)로만 한다.
- 마이그레이션 이름 목록을 고정 배열과 비교한다(덧붙이기만 허용). GRDB 문서에 등록 목록을 읽는 API가 없으므로 이름 배열 상수로 등록하고 그 상수를 시험한다.
- 메모리 DB에 전부 마이그레이션한 뒤 정렬한 `sqlite_master` SQL을 커밋된 `schema/moka-schema.sql`과 비교한다. 테스트는 비교만 하고 파일을 쓰지 않으며, 실패하면 새 스키마를 출력한다.
- pytest는 같은 `schema/moka-schema.sql`로 가짜 SQLite를 만들고 튜닝 스크립트가 읽는 열이 있는지 확인한다.
- 테스트는 테스트마다 새 메모리 DB를 쓰고, DB 경로가 메모리나 임시 디렉터리인지 확인하는 가드 테스트를 둔다.
- 스냅샷 파일이 바뀌면 PR "사람이 볼 결정"에 올린다.

## 사람의 최종 결정과 실제 판단 이유

Agent 추천안 채택. 판단 이유: 사용자 위임(토론 채택안 "전부 승인", 2026-10-28)

## 포기하는 것·운영 영향

- 트레이드오프: 개발 중 스키마가 흔들리면 마이그레이션 사슬이 길어진다. 그래도 자동 삭제 대신 명시적 초기화로 푼다.
- 되돌리기: 시험 방식은 쉬움. 실제 데이터 삭제는 되돌릴 수 없으므로 erase 옵션 금지는 바꾸지 않는다.

## 결정 검증

- 실행할 실험: 마이그레이션에서 열 하나를 지운 뒤 스냅샷 시험과 pytest 계약 시험이 FAIL하는지 확인(커밋하지 않음).
- 성공 판정: 주입 시 둘 다 FAIL, 원복 시 PASS.
- 재검토 트리거: 리눅스와 macOS의 `sqlite_master` 텍스트가 달라 거짓 FAIL(그때 PRAGMA 기준으로 바꿈), GRDB 버전 변경.
