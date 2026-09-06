// lib/services/condition/sleep_shift_relation.dart
//
// ⭐ 근무시간과 겹치는 수면을 "정상 데이터로 저장 + 조회 시점에 분류"하는 원칙의
// 실제 구현(수면기록_자동추정_설계.md 2장). SleepRecord는 저장 단계에서 어떤
// 겹침 검증도 거치지 않는다 - 여기서는 오직 "읽을 때 어떻게 분류할지"만 계산한다.
//
// ⚠️ 근무 스케줄이 나중에 바뀌면 과거 SleepRecord의 분류도 여기서 다시 계산할
// 때 자동으로 최신 스케줄 기준으로 맞게 나온다 - DB에 분류 라벨을 저장하지 않는
// 이유가 이것.

import '../../models/sleep_record.dart';
import 'shift_pattern_analyzer.dart';
import 'sleep_opportunity.dart';

enum SleepRelation {
  /// 근무 인스턴스와 1분이라도 겹침 - "근무 중 수면"(스펙 6~7장). 일반적인 주수면과
  /// 동일하게 취급하지 않도록 화면에서 항상 구분 표시할 것.
  workShiftOverlap,

  /// 겹치지 않고 3시간 이상 - 그날의 주된 수면으로 취급.
  mainSleep,

  /// 겹치지 않고 3시간 미만 - 낮잠 등 짧은 수면.
  nap,
}

/// mainSleep/nap을 가르는 기준(3시간). 근거자료에서 온 값이 아니라 순수 라벨링
/// 편의상의 임계값 - 위험 판정에는 전혀 쓰이지 않음.
const int kMainSleepMinMinutes = 3 * 60;

/// [record]가 [analyzer]가 아는 근무 인스턴스들과 얼마나/어떻게 겹치는지 분류.
/// end가 아직 null(진행 중)이면 "지금까지" 기준으로 판단.
SleepRelation classifySleepRelation(SleepRecord record, ShiftPatternAnalyzer analyzer) {
  final end = record.end ?? DateTime.now();

  // ⭐ 2026-09-05 - 하루 앞당겨서 시작(record.start의 전날부터) - 야간 근무는
  // 배정된 날짜의 자정을 넘겨 끝나므로, "전날 배정된 야간 근무"의 종료 시각이
  // record가 시작한 바로 그 날짜에 걸쳐 있을 수 있다. 예전엔 record 자신의
  // 시작~종료 날짜만 훑어서 이런 전날 근무를 아예 조회조차 안 했음(그 결과
  // "어제 야간 퇴근 직후" 수면이 전날 근무와 전혀 안 겹치는 것으로 잘못 판정될
  // 여지가 있었다 - graceAdjustedShiftEnd 도입과 별개로 그 자체로도 놓치고
  // 있던 케이스). 전날에 근무가 없거나 휴무면 그냥 무시되므로(아래
  // isWorkDay 체크) 안전하게 범위만 넓힘.
  var day = DateTime(record.start.year, record.start.month, record.start.day).subtract(const Duration(days: 1));
  final lastDay = DateTime(end.year, end.month, end.day);
  while (!day.isAfter(lastDay)) {
    final inst = analyzer.instanceForDate(day);
    if (inst.isWorkDay && inst.start != null && inst.end != null) {
      // ⭐ 2026-09-05 - graceAdjustedShiftEnd 참고. 실제 퇴근이 설정보다 조금
      // 이르면(자동 감지가 원래 허용하는 오차) "근무 중"으로 오판정되지 않게
      // 야간 근무는 종료 유예를 적용한 시각으로 비교한다.
      final effectiveEnd = graceAdjustedShiftEnd(inst);
      final overlaps = record.start.isBefore(effectiveEnd) && end.isAfter(inst.start!);
      if (overlaps) return SleepRelation.workShiftOverlap;
    }
    day = day.add(const Duration(days: 1));
  }

  final minutes = end.difference(record.start).inMinutes;
  return minutes >= kMainSleepMinMinutes ? SleepRelation.mainSleep : SleepRelation.nap;
}

extension SleepRelationLabel on SleepRelation {
  String get label {
    switch (this) {
      case SleepRelation.workShiftOverlap:
        return '근무 중 수면';
      case SleepRelation.mainSleep:
        return '주 수면';
      case SleepRelation.nap:
        return '낮잠';
    }
  }
}
