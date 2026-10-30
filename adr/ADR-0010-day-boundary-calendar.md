# ADR-0010: 하루 경계와 지역 날짜는 그레고리력으로 고정한다 (ADR-0003 일부 대체)

- 상태: Accepted
- 작성일 / 사람 승인일: 2026-10-30 / 2026-10-30(사용자 승인). 이 문서는 PR 병합으로 확정한다
- 결정 책임자: 저장소 소유자
- 관련 Spec/R-ID: spec 002 R-113·R-114, FR-08·FR-09, research R9·R10, plan 후속 결정 F4
- 대체 범위: ADR-0003 "Agent의 추천과 근거" 30행의 "앱은 `Calendar.autoupdatingCurrent`" 부분만 대체한다. 같은 줄의 나머지(하루 경계는 `day_start`와 주입한 `Calendar`로 계산, 테스트는 `Asia/Seoul`과 `America/New_York`을 고정 주입)와 ADR-0003의 다른 내용(Swift Testing, `MokaClock` 주입, MokaCore에서 `Date()`·`TimeZone.current`를 직접 읽지 않음, 저장 시각 UTC)은 그대로다. ADR-0003 본문은 그 줄 끝에 포인터만 붙이고 고치지 않는다.
- 사용한 외부 근거: 없음(Foundation `Calendar` 동작은 아래 "미확인"과 결정 검증 시험으로 확인)

## 맥락

spec 002는 하루 경계(R-114)와 반복 리셋(R-113)을 만든다. 하루는 `LocalDay`(`YYYY-MM-DD`)로 계산하고, 반복 할 일의 `tasks.cycle_day`와 마감·컨텍스트 날짜가 같은 문자열로 DB에 남는다. ADR-0003은 앱이 `Calendar.autoupdatingCurrent`를 주입한다고 적었다. 이 달력은 사용자의 시스템 설정을 따르므로 그레고리력이 아닐 수 있다(예: 불교력, 일본력). 그러면 같은 순간의 연·월·일 숫자가 달라지고, 이미 저장된 `cycle_day`와 새로 계산한 하루를 비교할 때 영구히 어긋난다(research.md:75).

## 평가 기준

1. 저장된 날짜 문자열이 사용자 설정과 무관하게 같은 뜻인가 2. 시간대·일광절약시간은 시스템을 따르는가 3. 리눅스 시험과 앱이 같은 규칙인가 4. 채택된 ADR을 제자리에서 고치지 않는가(AGENTS.md "채택된 ADR을 바꾸려면 새 ADR")

## 대안

| 대안 | 장점 | 단점·위험 |
|---|---|---|
| A. 새 ADR로 그레고리력 고정 + ADR-0003 해당 줄 끝에 포인터 | 저장 날짜의 뜻이 하나, 이력이 남음, ADR-0007 선례(ADR-0007:30-31)와 같음 | 문서 하나 늘어남 |
| B. ADR-0003 안에 정정 줄 | 문서 수 그대로 | 결정을 제자리에서 바꾸는 길이 열림(ADR-0007이 거부한 이유) |
| C. `Calendar.autoupdatingCurrent` 그대로 | 일 없음 | 그레고리력이 아닌 설정에서 `cycle_day`·마감이 어긋남 |

## Agent의 추천과 근거

A를 추천한다(추천안 토론 F4, 3라운드 끝 3:0, 소수 의견 없음, `.audit/debate/20261030-plan002-followups.md`, 커밋 안 함).
- 하루 경계(`DayBoundary`)와 `LocalDay` 계산은 `Calendar(identifier: .gregorian)`로 고정한다.
- 시간대는 시스템을 따른다. 앱은 그레고리력 달력에 시스템 시간대를 넣어 주입한다. MokaCore는 주입받은 `Calendar`만 쓴다.
- 시험은 그레고리력에 `Asia/Seoul`과 `America/New_York`을 고정 주입한다(ADR-0003 그대로). `moka-sim`은 그레고리력에 시나리오 `timezone`을 넣는다.
- 저장 형식(`YYYY-MM-DD`)과 하루 경계 규칙은 spec 002 data-model §5.4·§7이 원본이다.

## 사람의 최종 결정과 실제 판단 이유

Agent 추천안 채택(사용자 승인 2026-10-30). 판단 이유: 사용자 위임(토론 채택안 승인).

## 포기하는 것·운영 영향

- 트레이드오프: 사용자가 시스템 달력을 그레고리력이 아닌 것으로 바꿔도 앱 안의 날짜 계산은 그레고리력이다. 화면에 날짜를 보일 때의 표기는 이 결정의 범위 밖이다(화면 형식은 구현 PR에서 정한다).
- 되돌리기: 코드는 쉬움(달력 생성 한 곳). 다만 이미 저장된 날짜 문자열은 그레고리력 기준이므로 다른 달력으로 바꾸려면 데이터 이전이 필요하다.

## 결정 검증

- 실행할 실험: 단위 1(MokaCore)에서 시간대를 바꾼 뒤 하루 판정이 새 시간대를 따르는지 시험한다. 이 결과로 둘 중 하나를 정한다. (a) 달력에 `timeZone = .autoupdatingCurrent`를 넣어 한 번 만들어 두기, (b) 판정마다 `TimeZone.current`로 새 달력을 만들어 주입하기. 정한 쪽과 시험 이름을 이 ADR에 덧붙인다.
- 그레고리력이 아닌 달력을 주입해도 `LocalDay` 텍스트가 바뀌지 않는지(앱 생성 함수가 늘 그레고리력을 만드는지) 시험한다.
- 성공 판정: 위 시험 PASS, 리눅스(`swift:6.3.3-noble`)와 macOS에서 같은 결과.
- 재검토 트리거: 여행 등 시간대 이동을 지원하게 될 때(ADR-0003 트레이드오프), 화면 날짜 표기를 시스템 달력으로 바꾸자는 요구.

## 미확인

- `TimeZone.autoupdatingCurrent`를 넣은 `Calendar`가 시스템 시간대 변경을 앱 재시작 없이 따르는지.
- `Calendar.date(bySettingHour:minute:second:of:matchingPolicy:repeatedTimePolicy:direction:)`의 일광절약시간 처리가 리눅스 Foundation에서 macOS와 같은지(research R9).
