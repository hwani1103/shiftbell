# G3 연결 요청

> 다른 그룹 소유 파일이나 공통 파일(main.dart, MainActivity.kt, DB 서비스, pubspec, Gradle, Manifest, l10n)이 필요하면 직접 고치지 말고 여기에 적는다. 통합 담당자(Claude)가 연결 단계(T10 등)에서 반영한다.

| # | 대상 파일 | 이유 | 필요 API / 변경 | 호출 시점 | 실패 시 의미 | 반영 SHA |
|---|---|---|---|---|---|---|
| 1 | G1의 `date_overtime`, `shift_schedule`, `condition_shift_times` 저장 소유 경로 | G3 계산 provider가 공통 revision을 소비하도록 동결됨 | `dataRevisionProvider(DataDomain.overtime/shiftSchedule/shiftTimes)`를 각 원본의 커밋·저장 성공 뒤에만 `+1`; 실패·롤백 때 증가 금지 | 추가·수정·삭제 및 동일값 재저장 성공 직후 | #15 최신 OT/계산 반영이 일어나지 않거나 실패값을 잘못 반영 | G1 `9b8a586`(release/g1)에서 구현 — 두 그룹 결합 확인은 5단계 순차 통합 뒤(T14 G3 단독 테스트는 revision 수동 증가로) |
| 2 | G4 복원 gate 구현부 | T08에서 수면 후보 DB writer와 행 기반 9시간 AlarmManager 예약 trigger가 추가됨 | handoff의 writer 목록에 있는 Flutter/Native 수면 DB 쓰기와 수면 감지 예약을 복원 중 차단·연기. 빈 G3 gate 스텁은 만들지 않음 | 복원 lock 획득부터 owner 최종 reconcile 전까지 | 복원 DB 교체와 후보 종료/재예약이 경합하여 일부 복원·잘못된 OS 예약 가능 | G4 대상(T18) — T10 반영 없음 |
