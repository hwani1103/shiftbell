// lib/services/condition/sleep_history.dart
//
// ⭐ 2026-09-01 - "오늘의 컨디션 예측" 킬러 기능(컨디션매니저_설계.md 12장)의
// 데이터 준비 계층. 최근 근무일들 각각에 "그 근무 뒤에 실제로 얼마나 잤는지"를
// 짝지어 시계열로 만들고(SleepHistoryNight), 근무명별 "평소 수면 패턴"(평균
// 취침·기상 시각, 평균 수면시간)을 계산한다.
//
// ⚠️ 순수 계산만 하는 파일 - ConditionRuleEngine을 import하지 않는다(완전 분리
// 원칙, 수면기록_자동추정_설계.md 5장). sleep_stats.dart의 "가장 가까운 주
// 수면 찾기" 로직(computePostInstanceSleepStat)과 동일한 매칭 규칙을 근무명
// 단위로 재사용한다.

import '../../models/sleep_record.dart';
import 'shift_pattern_analyzer.dart';
import 'shift_time_category.dart';
import 'sleep_opportunity.dart';
import 'sleep_shift_relation.dart';

/// 근무 하루치(끝난 근무)와 그 뒤에 실제로 잔 수면을 짝지은 1건. 2026-09-01
/// 버그 수정으로 이제 휴무/미배정일도 포함한다(아래 collectRecentWorkNights
/// 주석 참고) - 그런 날은 [isWorkDay]가 false, [shiftDurationMinutes]는 0.
class SleepHistoryNight {
  final DateTime date; // 그 근무가 배정된(또는 휴무/미배정) 날짜
  final String shiftName;
  final int shiftDurationMinutes;
  final DateTime shiftEnd;

  /// ⭐ 2026-09-01 신설 - 실제 "근무일"(휴무/미배정이 아님)인지. 출퇴근 시각을
  /// 몰라도(그 근무명 시각 미설정) true일 수 있음 - shiftDurationMinutes와는
  /// 다른 축의 정보라 따로 둠(그쪽은 "숫자로 된 근무시간을 아는가"). "최근
  /// 근무일 N일 중 수면 기록 M일" 같은 커버리지 집계는 반드시 이 값으로 걸러
  /// 휴무일이 분모에 섞이지 않게 할 것 - 그래야 "근무일마다 기록했다"가
  /// 정확히 "커버리지 높음"으로 판정됨(휴무일까지 분모에 넣으면 근무일마다
  /// 성실히 기록해도 비율이 희석되어 낮게 나옴).
  final bool isWorkDay;

  /// 매칭된 수면 중 가장 이른 것(취침 시각 계산용, 확정 기록만) - 낮잠을 먼저
  /// 자고 나중에 메인 수면을 잔 경우에도 "몇 시부터 잤나"의 기준점.
  final SleepRecord? sleep;

  /// ⭐ 2026-09-01 후속12(사용자 지적으로 발견한 버그 수정) - 매칭된 수면 중
  /// 가장 늦게 끝난 것(기상 시각 계산용). 예전엔 sleep(가장 이른 것) 하나의
  /// 종료 시각을 그대로 "기상 시각"으로 썼는데, 낮잠을 먼저 자고 나중에 다시
  /// 메인 수면을 잔 경우 낮잠 종료 시각이 기상 시각으로 잘못 쓰였음.
  final SleepRecord? latestSleep;

  /// ⭐ 후속12 - 이 근무 뒤 매칭된 "모든" 수면(낮잠 포함) 시간의 합계(분).
  /// 예전엔 가장 이른 수면 1건의 길이만 셌음 - 근무 후 짧은 낮잠을 먼저 자고
  /// 몇 시간 뒤 긴 메인 수면을 또 잔 경우, 실제로는 총 수면이 충분한데도
  /// "짧게 잤다"로 잘못 판정되는 버그가 있었음(축4 poorRecentSleep,
  /// _findAcuteEvent 등 전부 이 값에 의존). `sleepMinutes`/`hasSleepData`가
  /// 이제 이 합계를 반환함 - 호출부 코드는 안 바뀌어도 의미가 정확해짐.
  final int totalSleepMinutes;

  const SleepHistoryNight({
    required this.date,
    required this.shiftName,
    required this.shiftDurationMinutes,
    required this.shiftEnd,
    required this.isWorkDay,
    this.sleep,
    this.latestSleep,
    this.totalSleepMinutes = 0,
  });

  int? get sleepMinutes => totalSleepMinutes > 0 ? totalSleepMinutes : null;
  bool get hasSleepData => totalSleepMinutes > 0;
}

/// [referenceDate] 기준 최근 [daysBack]일의 **모든 날짜**(근무일/휴무일/미배정일
/// 구분 없이)에 각각 실제 수면을 짝지어 반환한다(오래된 것 → 최신 순).
///
/// ⭐ 2026-09-01 버그 수정 - "실제 주 수면 기록(어제/그저께)이 분명히 있는데
/// '오늘의 컨디션'엔 수면 기록 0일 반영으로 나온다"는 신고로 발견. 원인: 예전엔
/// 이 함수가 "출퇴근 시각이 알려진 근무일"이 아니면(휴무/미배정/그 근무명의
/// 시각을 아직 설정 안 한 경우까지 전부) 그날을 통째로 건너뛰었음 - 그 결과
/// 실제로 잰 수면이 있어도 "짝지어질 날" 자체가 안 만들어져서 영원히 반영될
/// 수 없었음("최근 수면 기록" 미니 달력(sleep_day_slots.dart)은 이런 제약이
/// 전혀 없이 모든 확정 기록을 그대로 보여주므로, 화면엔 보이는데 컨디션엔 안
/// 잡히는 모순이 여기서 생겼던 것). 이제 출퇴근 시각을 모르는 날도 빠짐없이
/// SleepHistoryNight을 만들되, "이 근무 뒤"라는 앵커가 없으므로 그런 날은
/// sleep_opportunity.dart와 동일한 "일상적 취침 시간대"(21시부터 최대
/// [kSleepTrackingWindowMaxHours]시간) 규칙으로 그 날의 주 수면을 찾는다(아래
/// [_collectFlatNight] 참고) - 자동 감지 창(라이브 추적)과 이 값을 공유해서
/// 두 로직이 "언제를 주 수면 시간대로 보는가"에 대해 서로 어긋나지 않게 함.
///
/// 출퇴근 시각이 알려진 근무일의 매칭 규칙(근무 종료 후 [searchAheadHours]
/// 이내 시작, 그 어떤 근무와도 안 겹침)은 기존과 완전히 동일하게 유지함(이미
/// 검증된 로직이라 건드리지 않음) - sleep_stats.dart의
/// computePostInstanceSleepStat과 매칭 조건이 같다. **매칭되는 모든 수면을
/// 합산**한다(후속12 - 낮잠+메인수면처럼 그 근무 뒤 여러 번 나눠 잔 경우도
/// 총 수면시간이 정확히 반영되도록).
///
/// ⚠️ 출퇴근 시각을 모르는 날은 `shiftDurationMinutes`가 항상 0으로 채워짐 -
/// "실제 근무시간"이 아니라 "이 날은 근무시간을 모른다"는 신호로 씀
/// (personalBaselineShiftMinutes/buildPersonalSleepPatterns가 이 값으로
/// 실제 근무일만 걸러냄 - 휴무/미배정일이 "평소 근무시간" 평균에 섞여
/// 오염되지 않도록. today_forecast_engine.dart의 _findAcuteEvent도 동일한
/// 이유로 shiftDurationMinutes <= 0인 날은 "어제 근무 후" 문구를 건너뜀).
List<SleepHistoryNight> collectRecentWorkNights({
  required ShiftPatternAnalyzer analyzer,
  required List<SleepRecord> records,
  required DateTime referenceDate,
  int daysBack = 56, // ⭐ 2026-09-01 - 4주(28일) → 8주(56일)로 확장(사용자 요청 - 짧은 창은 최근 이상치에 데이터가 오염되기 쉬움)
  int searchAheadHours = 16,
}) {
  final confirmedRecords = records
      .where((r) => !(r.source == SleepSource.autoDetected && r.status == SleepStatus.pendingConfirmation))
      .toList();

  final result = <SleepHistoryNight>[];
  for (var i = daysBack - 1; i >= 0; i--) {
    final day = referenceDate.subtract(Duration(days: i));
    final inst = analyzer.instanceForDate(day);
    final hasShiftInfo = inst.isWorkDay && inst.end != null && inst.durationMinutes != null;

    if (!hasShiftInfo) {
      result.add(_collectFlatNight(inst, analyzer, confirmedRecords));
      continue;
    }

    SleepRecord? nearest;
    SleepRecord? latest;
    var totalMinutes = 0;

    // ⭐ 2026-09-01 후속16(사용자 요청) - "근무 중 수면도 피로도에 반영하되,
    // 주 수면과는 구분"할 것. 이 근무 인스턴스 자체와 겹치는 수면(위젯에서
    // 근무 중 '수면' 버튼을 눌러 기록한 경우 등)을 "낮잠 가산"으로 총 수면에
    // 더한다 - sleep/latestSleep(취침·기상 패턴, buildPersonalSleepPatterns가
    // 씀)에는 포함하지 않음(그건 "퇴근 후 진짜 주 수면"의 시각 패턴만 대표해야
    // 하므로 - 근무 중 낮잠까지 섞으면 취침시각 평균이 왜곡됨). 화면 쪽 분류
    // (주 수면 vs 낮잠)는 sleep_day_slots.dart가 별도로 동일한 판정을 함
    // (다른 목적의 동일 로직 - 이 함수는 피로도 계산용, 그쪽은 UI 슬롯 배정용).
    // ⭐ 2026-09-05 - graceAdjustedShiftEnd 참고(sleep_day_slots.dart/
    // sleep_shift_relation.dart/sleep_stats.dart와 동일 원칙 - "실제 퇴근이
    // 설정보다 조금 이르면 아직 근무 중으로 오판정" 버그를 여기도 동일하게
    // 고침). 아래 두 루프가 이 값을 똑같이 쓰는 한, 서로 배타적이라는 기존
    // 전제(후속16 주석)는 그대로 유지된다.
    final effectiveEnd = graceAdjustedShiftEnd(inst);

    for (final r in confirmedRecords) {
      final duration = r.durationMinutes;
      if (duration == null) continue;
      final overlapsThisShift = r.start.isBefore(effectiveEnd) && r.end!.isAfter(inst.start!);
      if (overlapsThisShift) totalMinutes += duration;
    }

    for (final r in confirmedRecords) {
      final duration = r.durationMinutes;
      if (duration == null) continue;
      if (r.start.isBefore(effectiveEnd)) continue;
      // ⭐ 2026-09-06 - .inHours는 나머지 분을 버려서(예: 16시간 47분→16시간)
      // searchAheadHours 상한을 truncate만큼 더 넓게 오판정했다(sleep_day_slots.dart와
      // 동일 버그). Duration 직접 비교로 수정.
      if (r.start.difference(inst.end!) > Duration(hours: searchAheadHours)) continue;
      // ⭐ 2026-09-01 후속4 - 원래는 SleepRelation.mainSleep(3시간 이상)만
      // 인정했는데, 그러면 "근무 후 진짜로 짧게(2~3시간) 잔" 기록이 nap으로
      // 분류돼 여기서 통째로 빠지면서 "데이터 없음"과 구분이 안 됐음 - 정작
      // "메인 수면이 너무 적다"는 걸 보여줘야 할 바로 그 경우가 사라지는 문제.
      // 근무와 안 겹치기만 하면(workShiftOverlap만 제외) 이 근무 뒤의 수면으로
      // 인정한다 - 짧아도 실제 값 그대로 today_forecast_engine.dart의 "짧은
      // 수면" 신호에 반영되게 함. ⚠️ 후속16 - "근무와 안 겹침" 조건은 여기선
      // "이 근무 인스턴스와 안 겹침"이 아니라 "그 어떤 근무와도 안 겹침"
      // (classifySleepRelation이 기록의 [start,end] 구간에 걸치는 모든 날짜를
      // 확인) - 위 근무 중 가산 루프와 겹칠 일이 없다(그쪽은 r.start가 항상
      // inst.end 이전이라 이 루프의 `r.start.isBefore(inst.end!)` 조건에서
      // 이미 걸러짐 - 이중 합산 안 됨).
      if (classifySleepRelation(r, analyzer) == SleepRelation.workShiftOverlap) continue;
      totalMinutes += duration;
      if (nearest == null || r.start.isBefore(nearest.start)) nearest = r;
      if (latest == null || r.end!.isAfter(latest.end!)) latest = r;
    }

    // ⭐ 2026-09-01 후속19(사용자 지적으로 발견/수정) - "야간 근무 출근 전
    // 낮잠은 그냥 그날 수면에 포함하면 되는 거 아니냐"는 질문에 대한 답:
    // 맞고, 원래는 못 하고 있었음(위 두 루프는 각각 "근무 시간과 겹침"/"근무
    // 종료 후"만 보므로, 출근 "전"에 이미 끝나는 잠은 어느 쪽에도 안 걸려서
    // 조용히 통째로 누락됐음) - 이 루프로 그 빈틈을 메움. 오늘이 야간 근무일
    // 때만, 오늘 자정~출근 시각 사이에 끝나는 수면을 낮잠 가산(총 수면엔
    // 포함, sleep/latestSleep엔 미포함 - 위 "근무 중 가산"과 동일한 취급,
    // 이유도 동일: 이건 "퇴근 후 진짜 주 수면"의 시각 패턴을 대표하면 안 됨).
    // ⚠️ 안전장치: 어제도 야간 근무였다면(연속 야간) 이 루프를 아예 안 돈다 -
    // 그 경우엔 어제 몫의 "근무 종료 후 검색"(위 루프, 최대 searchAheadHours)이
    // 이미 오늘 낮 시간대까지 먼저 훑고 지나갈 수 있어서, 같은 수면 기록을
    // 이 루프가 또 세면 이중 합산이 될 위험이 있음 - 어제가 야간이 아닐
    // 때만(휴무/주간/오후/미배정 등) 안전하게 겹칠 일이 없음을 보장할 수
    // 있어서 그 경우로만 한정함.
    if (inst.category == ShiftTimeCategory.night) {
      final prevInst = analyzer.instanceForDate(day.subtract(const Duration(days: 1)));
      final prevIsNight = prevInst.isWorkDay && prevInst.category == ShiftTimeCategory.night && prevInst.end != null;
      if (!prevIsNight) {
        final dayStart = DateTime(day.year, day.month, day.day);
        for (final r in confirmedRecords) {
          final duration = r.durationMinutes;
          if (duration == null) continue;
          if (r.start.isBefore(dayStart)) continue; // 오늘 시작한 것만(어제 몫과 안 겹치게)
          if (r.end!.isAfter(inst.start!)) continue; // 출근 시각 전에 끝난 것만(겹치면 위 "근무 중 가산" 담당)
          if (classifySleepRelation(r, analyzer) == SleepRelation.workShiftOverlap) continue;
          totalMinutes += duration;
        }
      }
    }

    result.add(SleepHistoryNight(
      date: inst.date,
      shiftName: inst.shiftName,
      shiftDurationMinutes: inst.durationMinutes!,
      shiftEnd: inst.end!,
      isWorkDay: true,
      sleep: nearest,
      latestSleep: latest,
      totalSleepMinutes: totalMinutes,
    ));
  }
  return result;
}

/// [inst]가 "출퇴근 시각을 모르는 날"(휴무/미배정/그 근무명 시각 미설정)일 때
/// 전용 - 근무 종료 시각이라는 앵커가 없으므로, sleep_opportunity.dart의 flat
/// 규칙과 똑같은 창(그날 21시 ~ +[kSleepTrackingWindowMaxHours]시간)으로 주
/// 수면을 찾는다. 그 창 안에서 시작하는 기록 중 "그 어떤 근무와도 안 겹치는"
/// 것만 인정(다른 날의 야간 근무와 우연히 겹치는 경계 기록을 제외하기 위함 -
/// 위 본문 루프의 workShiftOverlap 제외와 동일한 이유).
SleepHistoryNight _collectFlatNight(
  ShiftInstance inst,
  ShiftPatternAnalyzer analyzer,
  List<SleepRecord> confirmedRecords,
) {
  final day = inst.date;
  final windowStart = DateTime(day.year, day.month, day.day, kFlatSleepStartHour);
  final windowEnd = windowStart.add(const Duration(hours: kSleepTrackingWindowMaxHours));

  SleepRecord? nearest;
  SleepRecord? latest;
  var totalMinutes = 0;
  for (final r in confirmedRecords) {
    final duration = r.durationMinutes;
    if (duration == null) continue;
    if (r.start.isBefore(windowStart) || !r.start.isBefore(windowEnd)) continue;
    if (classifySleepRelation(r, analyzer) == SleepRelation.workShiftOverlap) continue;
    totalMinutes += duration;
    if (nearest == null || r.start.isBefore(nearest.start)) nearest = r;
    if (latest == null || r.end!.isAfter(latest.end!)) latest = r;
  }

  return SleepHistoryNight(
    date: day,
    shiftName: inst.shiftName,
    shiftDurationMinutes: 0, // ⭐ "근무시간을 모르는 날" 신호 - 실제 0분 근무라는 뜻이 아님(파일 상단 주석 참고)
    shiftEnd: windowStart,
    isWorkDay: inst.isWorkDay, // 휴무/미배정이면 false, "근무일인데 시각만 미설정"이면 true
    sleep: nearest,
    latestSleep: latest,
    totalSleepMinutes: totalMinutes,
  );
}

/// ⭐ 2026-09-01 후속3 - "기본 근무시간이 8시간인 사람과 12시간인 사람은 같은
/// '12시간 근무'라도 부담의 의미가 다르다"는 피드백 반영. 근무명과 무관하게
/// "이 사람이 평소 한 근무에 몇 분을 일하는가"의 평균 - 여러 근무명(주간/야간
/// 등)을 섞어서 계산한다(근무명별로 쪼개면 표본이 부족해지기 쉬움 - 그리고
/// "오늘 이 근무가 평소보다 긴가"는 근무명과 무관하게 성립하는 질문이라 굳이
/// 안 나눔). 표본이 [minSamples] 미만이면 "평소"를 단정하지 않고 null을
/// 반환한다 - 호출부는 이 경우 개인 평소 비교를 건너뛰고 기존 절대 기준으로
/// 폴백해야 한다(today_forecast_engine.dart 참고).
/// ⭐ 2026-09-01 버그 수정 - collectRecentWorkNights가 이제 휴무/미배정일도
/// (shiftDurationMinutes: 0으로) 함께 반환하므로, 그 0들이 섞여서 "평소
/// 근무시간"이 실제보다 낮게 왜곡되지 않도록 실제 근무시간을 아는 날
/// (shiftDurationMinutes > 0)만 걸러서 평균낸다. [minSamples]도 이제 그
/// 걸러진 표본 수 기준(예전엔 daysBack 전체 길이 기준이라 사실상 항상
/// 통과했었는데, 그건 당시엔 어차피 nights가 근무일만 담고 있어서 우연히
/// 맞았던 것 - 이제는 진짜로 표본 수를 세야 함).
double? personalBaselineShiftMinutes(List<SleepHistoryNight> nights, {int minSamples = 5}) {
  final known = nights.where((n) => n.shiftDurationMinutes > 0).toList();
  if (known.length < minSamples) return null;
  final total = known.fold<int>(0, (sum, n) => sum + n.shiftDurationMinutes);
  return total / known.length;
}

/// 근무명별 "평소 수면 패턴"(실제 데이터가 있는 밤들만 평균).
class PersonalSleepPattern {
  final int sampleCount;
  final double avgSleepMinutes;
  final double avgBedtimeMinutesOfDay; // 자정 기준 분(취침 시각 평균, 0~1439)
  final double avgWakeMinutesOfDay;

  const PersonalSleepPattern({
    required this.sampleCount,
    required this.avgSleepMinutes,
    required this.avgBedtimeMinutesOfDay,
    required this.avgWakeMinutesOfDay,
  });
}

/// 근무명 -> 그 근무 뒤 평소 수면 패턴. 표본이 [minSamples] 미만이면 그 근무명은
/// 맵에서 제외(너무 적은 표본으로 "평소"를 단정하지 않기 위함).
Map<String, PersonalSleepPattern> buildPersonalSleepPatterns(
  List<SleepHistoryNight> nights, {
  int minSamples = 3,
}) {
  final byShift = <String, List<SleepHistoryNight>>{};
  for (final n in nights) {
    // ⭐ 후속16 - hasSleepData는 이제 "근무 중 낮잠만" 있어도 true가 될 수 있음
    // (totalSleepMinutes에는 반영되지만 sleep/latestSleep은 null로 남음 - 위
    // collectRecentWorkNights 주석 참고). 취침·기상 "시각" 패턴은 퇴근 후 진짜
    // 주 수면을 기준으로만 계산해야 하므로, sleep이 없는(=근무 중 낮잠만 있는)
    // 밤은 이 평균에서 제외한다(총 수면량 계산엔 여전히 포함됨 - 여긴 시각
    // 패턴 전용).
    // ⭐ 2026-09-01 버그 수정 - 휴무/미배정/시간 미설정일(shiftDurationMinutes
    // == 0)은 "근무명별 평소 패턴"이라는 이 함수의 취지와 안 맞아서(그 이름의
    // "근무" 자체를 실제로 안 했거나 시간을 모르는 날) 제외 - personalPatterns
    // 조회부(today_forecast_engine.dart의 personalPatterns[lastNight.shiftName])가
    // 항상 "실제 근무명"만 키로 기대하므로 이 필터가 그 전제를 지켜줌.
    if (!n.hasSleepData || n.sleep == null || n.shiftDurationMinutes <= 0) continue;
    byShift.putIfAbsent(n.shiftName, () => []).add(n);
  }

  final result = <String, PersonalSleepPattern>{};
  byShift.forEach((shiftName, list) {
    if (list.length < minSamples) return;
    var totalSleep = 0;
    var totalBedtime = 0;
    var totalWake = 0;
    for (final n in list) {
      totalSleep += n.sleepMinutes!; // 후속12 - 이제 낮잠 포함 합계
      totalBedtime += n.sleep!.start.hour * 60 + n.sleep!.start.minute;
      // 후속12 - 기상 시각은 "가장 늦게 끝난" 수면 기준(낮잠 먼저 자고 나중에
      // 메인 수면을 잔 경우 낮잠 종료 시각이 기상 시각으로 잘못 쓰이는 걸 방지).
      final end = (n.latestSleep ?? n.sleep)!.end!;
      totalWake += end.hour * 60 + end.minute;
    }
    result[shiftName] = PersonalSleepPattern(
      sampleCount: list.length,
      avgSleepMinutes: totalSleep / list.length,
      avgBedtimeMinutesOfDay: totalBedtime / list.length,
      avgWakeMinutesOfDay: totalWake / list.length,
    );
  });
  return result;
}
