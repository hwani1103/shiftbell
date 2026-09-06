// lib/services/condition/shift_pattern_analyzer.dart
//
// ⭐ 컨디션 매니저 Phase 1 - Shift Pattern Analysis Engine (컨디션매니저_설계.md
// 1장). 기존 ShiftSchedule(근무 패턴)과 condition_shift_times(신규, 근무명별
// 출퇴근 시각)만 입력받아 순수 계산만 한다 - DB/네트워크/Provider 어디에도
// 의존하지 않는 순수 Dart 클래스라 단위 테스트하기 쉽게 분리함.
//
// ⚠️ 여기서 다루는 값(카테고리 분류, 연속일수, 회복시간, 교대 방향)은 전부
// "사실 계산"이다. 이 값들에 "위험하다/안전하다" 같은 판정을 붙이는 건
// condition_rule_engine.dart의 역할이고, 그 판정은 반드시 근거(Evidence)와
// 연결돼야 한다(컨디션매니저_근거자료.md). 이 파일 자체는 어떤 건강 판정도
// 내리지 않는다.

import '../../models/shift_schedule.dart';
import '../../models/shift_time_range.dart';
import '../../utils/shift_name_util.dart';
import 'shift_time_category.dart';

/// 특정 날짜에 배정된 근무 1건의 계산된 정보.
class ShiftInstance {
  final DateTime date; // 근무가 "배정된" 달력 날짜(자정 0시 기준)
  final String shiftName;
  final ShiftTimeCategory category;
  final DateTime? start; // null이면 미설정(휴무 제외) 또는 휴무
  final DateTime? end;

  const ShiftInstance({
    required this.date,
    required this.shiftName,
    required this.category,
    this.start,
    this.end,
  });

  bool get isOff => category == ShiftTimeCategory.off;

  /// 근무 일정 자체가 아예 없는 날(스케줄 미설정 상태에서 계산된 경우).
  bool get isUnset => shiftName == kUnsetShiftSentinel;

  /// "근무하는 날"인지 - 휴무/미설정이 아니면 true. 출퇴근 시각을 아직 안
  /// 넣었어도(category==unspecified) 근무일 자체는 맞으므로 true.
  bool get isWorkDay => !isOff && !isUnset;

  /// 실제 근무시간(분). 시각을 모르면 null.
  int? get durationMinutes =>
      (start != null && end != null) ? end!.difference(start!).inMinutes : null;
}

/// 교대 방향(정방향/역방향) 판정 결과. `null`을 반환하는 경우(analyzeDirection)는
/// "이 스케줄에는 이 개념이 성립하지 않음"을 뜻함 - 억지로 방향을 매기지 않음.
enum ShiftDirection { forward, backward, mixed }

class ShiftDirectionResult {
  final ShiftDirection direction;
  final List<ShiftTimeCategory> sequence; // 대표 순환 순서(휴무/미입력 제외, 중복 연속 제거)

  const ShiftDirectionResult({required this.direction, required this.sequence});
}

/// 한 주(월~일)의 패턴 요약. "이번 주 특징"(스펙 28장) 화면에 그대로 씀.
class WeeklyPatternSummary {
  final DateTime weekStart;
  final DateTime weekEnd;
  final Map<ShiftTimeCategory, int> categoryCounts; // day/evening/night/off/unspecified별 일수
  final int maxConsecutiveWorkDays; // 이 7일 구간 내에서의 최대치(주 경계를 넘는 연속은 포함 안 함)
  final int maxConsecutiveNightDays;
  final int knownDurationSampleCount;
  final int knownDurationTotalMinutes;

  const WeeklyPatternSummary({
    required this.weekStart,
    required this.weekEnd,
    required this.categoryCounts,
    required this.maxConsecutiveWorkDays,
    required this.maxConsecutiveNightDays,
    required this.knownDurationSampleCount,
    required this.knownDurationTotalMinutes,
  });

  /// 출퇴근 시각이 입력된 근무만 대상으로 한 평균 근무시간(분). 표본이 없으면 null.
  double? get averageDurationMinutes =>
      knownDurationSampleCount == 0 ? null : knownDurationTotalMinutes / knownDurationSampleCount;
}

class ShiftPatternAnalyzer {
  final ShiftSchedule schedule;
  final Map<String, ShiftTimeRange> shiftTimes; // shiftName -> 출퇴근 시각

  const ShiftPatternAnalyzer({required this.schedule, required this.shiftTimes});

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 특정 날짜의 ShiftInstance 계산.
  ShiftInstance instanceForDate(DateTime date) {
    final d = _dayOnly(date);
    final name = schedule.getShiftForDate(d);

    if (name == kUnsetShiftSentinel) {
      return ShiftInstance(date: d, shiftName: name, category: ShiftTimeCategory.unspecified);
    }

    if (isRestShiftName(name)) {
      return ShiftInstance(date: d, shiftName: name, category: ShiftTimeCategory.off);
    }

    final range = shiftTimes[name];
    if (range == null) {
      return ShiftInstance(date: d, shiftName: name, category: ShiftTimeCategory.unspecified);
    }

    final start = d.add(Duration(minutes: range.startMinutes));
    final end = range.crossesMidnight
        ? d.add(Duration(days: 1, minutes: range.endMinutes))
        : d.add(Duration(minutes: range.endMinutes));

    return ShiftInstance(
      date: d,
      shiftName: name,
      category: classifyByStartMinutes(range.startMinutes),
      start: start,
      end: end,
    );
  }

  /// [start, end] 범위(둘 다 포함, 날짜 단위)의 인스턴스 목록.
  List<ShiftInstance> instancesForRange(DateTime start, DateTime end) {
    final result = <ShiftInstance>[];
    final s = _dayOnly(start);
    final e = _dayOnly(end);
    for (var d = s; !d.isAfter(e); d = d.add(const Duration(days: 1))) {
      result.add(instanceForDate(d));
    }
    return result;
  }

  /// date를 마지막 날로 하는 연속 야간근무 일수(0이면 date 자체가 야간이 아님).
  /// ⭐ 2026-09-04 - [maxLookbackDays] 캡 추가(전체_코드_점검_리포트_2026-09-04.md H1).
  /// 쉬는 날이 하루도 없는 규칙적 패턴(매일 야간만 도는 스케줄 등)에서는
  /// `getShiftForDate`가 과거 어느 날짜든 답을 내주기 때문에 캡이 없으면 이
  /// 루프가 끝나지 않아 ANR로 이어짐 - `recoveryWindowContaining`과 동일하게 캡을 둠.
  int consecutiveNightStreakEndingAt(DateTime date, {int maxLookbackDays = 180}) {
    var count = 0;
    var d = _dayOnly(date);
    while (count < maxLookbackDays && instanceForDate(d).category == ShiftTimeCategory.night) {
      count++;
      d = d.subtract(const Duration(days: 1));
    }
    return count;
  }

  /// date를 마지막 날로 하는 연속 근무일수(휴무/미설정이면 0).
  /// ⭐ 2026-09-04 - H1: maxLookbackDays 캡 추가(위 함수와 동일 이유).
  int consecutiveWorkStreakEndingAt(DateTime date, {int maxLookbackDays = 180}) {
    var count = 0;
    var d = _dayOnly(date);
    while (count < maxLookbackDays && instanceForDate(d).isWorkDay) {
      count++;
      d = d.subtract(const Duration(days: 1));
    }
    return count;
  }

  /// date를 마지막 날로 하는 "연속 장시간(>=thresholdMinutes) 근무" 일수.
  /// 출퇴근 시각이 없는 날을 만나면 스트릭이 끊긴 것으로 봄(과대 판정 방지).
  /// ⭐ 2026-09-04 - H1: maxLookbackDays 캡 추가(위 함수와 동일 이유).
  int consecutiveLongShiftStreakEndingAt(DateTime date, {int thresholdMinutes = 12 * 60, int maxLookbackDays = 180}) {
    var count = 0;
    var d = _dayOnly(date);
    while (count < maxLookbackDays) {
      final inst = instanceForDate(d);
      final duration = inst.durationMinutes;
      if (!inst.isWorkDay || duration == null || duration < thresholdMinutes) break;
      count++;
      d = d.subtract(const Duration(days: 1));
    }
    return count;
  }

  /// date가 속한 "근무 사이 회복구간"을 찾는다 - date 이전(포함) 가장 가까운
  /// 근무 종료 시각 ~ 그 다음(포함하지 않음) 가장 가까운 근무 시작 시각.
  /// date가 근무일 자체면 "오늘 퇴근 ~ 다음 근무 출근"이 되고, date가 휴무일이면
  /// "그 휴무가 낀 회복구간 전체"가 된다. 둘 중 하나라도 시각을 모르면 null.
  ({DateTime end, DateTime start})? recoveryWindowContaining(DateTime date, {int lookbackDays = 14, int lookaheadDays = 14}) {
    ShiftInstance? lastWork;
    for (var i = 0; i <= lookbackDays; i++) {
      final inst = instanceForDate(date.subtract(Duration(days: i)));
      if (inst.isWorkDay && inst.end != null) {
        lastWork = inst;
        break;
      }
    }
    if (lastWork == null) return null;

    ShiftInstance? nextWork;
    // 다음 근무는 lastWork 당일 다음날부터 탐색(당일 자체가 lastWork일 수 있으므로)
    for (var i = 1; i <= lookaheadDays; i++) {
      final inst = instanceForDate(lastWork.date.add(Duration(days: i)));
      if (inst.isWorkDay && inst.start != null) {
        nextWork = inst;
        break;
      }
    }
    if (nextWork == null) return null;

    return (end: lastWork.end!, start: nextWork.start!);
  }

  /// 교대 방향(정방향/역방향) 판정. 규칙적 스케줄이면서 패턴 안에 주간/오후/야간
  /// 3종류가 모두 있을 때만 의미가 성립한다(2교대 등은 방향 개념 자체가 없다고
  /// 보고 null 반환 - 억지 판정 금지, 컨디션매니저_근거자료.md 12장 "판단 불가"
  /// 원칙과 동일).
  ShiftDirectionResult? analyzeDirection() {
    if (!schedule.isRegular) return null;
    final pattern = schedule.pattern;
    if (pattern == null || pattern.isEmpty) return null;

    final categories = <ShiftTimeCategory>[];
    for (final name in pattern) {
      if (isRestShiftName(name)) continue;
      final range = shiftTimes[name];
      if (range == null) continue; // 시각 미입력 근무는 방향 판정에서 제외
      categories.add(classifyByStartMinutes(range.startMinutes));
    }

    // 연속 중복 제거(패턴 슬롯이 하루 단위라 보통 안 겹치지만 방어적으로)
    final seq = <ShiftTimeCategory>[];
    for (final c in categories) {
      if (seq.isEmpty || seq.last != c) seq.add(c);
    }

    final distinct = seq.toSet();
    if (!(distinct.contains(ShiftTimeCategory.day) &&
        distinct.contains(ShiftTimeCategory.evening) &&
        distinct.contains(ShiftTimeCategory.night))) {
      return null; // 3종류가 다 있어야 "정방향/역방향"이라는 개념이 성립
    }
    if (seq.length < 2) return null;

    const order = [ShiftTimeCategory.day, ShiftTimeCategory.evening, ShiftTimeCategory.night];
    var forwardVotes = 0;
    var backwardVotes = 0;
    for (var i = 0; i < seq.length; i++) {
      final from = seq[i];
      final to = seq[(i + 1) % seq.length];
      if (from == to) continue;
      final fromIdx = order.indexOf(from);
      final toIdx = order.indexOf(to);
      if (fromIdx == -1 || toIdx == -1) continue;
      final step = (toIdx - fromIdx) % 3; // Dart의 %는 양수 나눗셈에서 항상 0 이상
      if (step == 1) {
        forwardVotes++;
      } else if (step == 2) {
        backwardVotes++;
      }
    }

    final ShiftDirection direction;
    if (forwardVotes > 0 && backwardVotes == 0) {
      direction = ShiftDirection.forward;
    } else if (backwardVotes > 0 && forwardVotes == 0) {
      direction = ShiftDirection.backward;
    } else {
      direction = ShiftDirection.mixed;
    }
    return ShiftDirectionResult(direction: direction, sequence: seq);
  }

  /// weekStart(월요일)~weekStart+6(일요일)의 패턴 요약.
  WeeklyPatternSummary weeklySummary(DateTime weekStart) {
    final start = _dayOnly(weekStart);
    final end = start.add(const Duration(days: 6));
    final instances = instancesForRange(start, end);

    final counts = <ShiftTimeCategory, int>{
      for (final c in ShiftTimeCategory.values) c: 0,
    };
    var maxWork = 0;
    var curWork = 0;
    var maxNight = 0;
    var curNight = 0;
    var durationSamples = 0;
    var durationTotal = 0;

    for (final inst in instances) {
      counts[inst.category] = (counts[inst.category] ?? 0) + 1;

      if (inst.isWorkDay) {
        curWork++;
        maxWork = curWork > maxWork ? curWork : maxWork;
      } else {
        curWork = 0;
      }

      if (inst.category == ShiftTimeCategory.night) {
        curNight++;
        maxNight = curNight > maxNight ? curNight : maxNight;
      } else {
        curNight = 0;
      }

      final duration = inst.durationMinutes;
      if (duration != null) {
        durationSamples++;
        durationTotal += duration;
      }
    }

    return WeeklyPatternSummary(
      weekStart: start,
      weekEnd: end,
      categoryCounts: counts,
      maxConsecutiveWorkDays: maxWork,
      maxConsecutiveNightDays: maxNight,
      knownDurationSampleCount: durationSamples,
      knownDurationTotalMinutes: durationTotal,
    );
  }
}
