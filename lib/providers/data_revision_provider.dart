// lib/providers/data_revision_provider.dart
//
// ⭐ 2026-09-14 (출시전 수정작업 T05 공통 계약 - docs/release_audit/contracts.md "변경 통지")
// 원본 데이터 변경 통지. 출시전 감사 #15(OT 수정이 컨디션 판정에 반영 안 됨)의 근본 원인이
// "쓰는 쪽과 계산하는 쪽이 서로 모른다"는 것이라, 두 작업 그룹(G1 쓰기 / G3 계산)이 같은
// 기준 커밋에서 이 선언을 함께 쓴다.
//
// 규칙
// - 쓰는 쪽(G1: 근무 배정·패턴, OT, 근무시간 설정, 출퇴근 시각 저장)은 DB 트랜잭션 커밋 또는
//   SharedPreferences 저장이 **성공한 뒤에만** 해당 영역의 revision을 올린다.
//   저장 실패·롤백이면 올리지 않는다. 같은 값을 다시 저장한 경우에는 올려도 된다.
// - 계산하는 쪽(G3: 컨디션·수면 계산 provider)은 필요한 영역의 revision을 watch해서 다시 계산한다.
//   재계산은 여러 번 불려도 결과가 같아야 한다(멱등).
// - revision 값 자체에는 의미가 없다(앱 재시작 시 0부터). 영속 저장하지 않는다.
//
// 사용 예
//   ref.read(dataRevisionProvider(DataDomain.overtime).notifier).state++;   // 저장 성공 후
//   ref.watch(dataRevisionProvider(DataDomain.overtime));                     // 계산 provider 안
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DataDomain {
  /// shift_schedule — 패턴·배정·근무명·색상
  shiftSchedule,

  /// date_overtime — 날짜별 OT
  overtime,

  /// 근무시간/급여기간 설정 — SharedPreferences work_hours_*, shift_schedule.shift_durations
  workHoursSettings,

  /// condition_shift_times — 근무명별 출퇴근 시각
  shiftTimes,
}

final dataRevisionProvider = StateProvider.family<int, DataDomain>((ref, domain) => 0);
