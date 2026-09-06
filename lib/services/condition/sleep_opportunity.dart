// lib/services/condition/sleep_opportunity.dart
//
// ⭐ Sleep Opportunity Detection(수면기록_자동추정_설계.md 3장, 2026-09-01 후속3
// 재설계) - "지금이 수면 가능성이 높은 시간대인가"를 계산하는 순수 로직. 자동
// 수면 감지의 백그라운드 실행부(Kotlin `SleepScheduleResolver.kt`)가 반드시 이
// 파일과 동일한 알고리즘을 유지해야 한다 - 알람 생성 로직
// (alarm_generation_service.dart ↔ AlarmRefreshEngine.kt)의 Dart/Kotlin
// 이중구현과 동일한 선례. ⚠️ 이 파일은 실제 앱에서 직접 호출되지 않는 "참조
// 구현"이다(백그라운드 감지는 Kotlin이 전담) - Kotlin을 고칠 때 반드시 이
// 파일도 같이 고쳐서 두 구현이 벌어지지 않게 할 것.
//
// ⚠️ 생체리듬 모델을 만들지 않는다(스펙 9장 지시) - "일정상 수면 가능성이 높은
// 시간대"를 계산하는 것으로 정의를 한정한다.
//
// ⭐ 2026-09-01 - 원래는 사용자가 입력한 "근무별 평균 취침시각"을 1순위로 쓰다가
// 삭제하고, "근무 종료~다음 근무 시작"(회복구간) 전체를 창으로 쓰는 방식으로
// 통일했었음.
//
// ⭐ 2026-09-01 후속3 재설계 - "자동인식은 메인 잠 트래킹만, 폭을 최대한
// 줄이자"는 요청으로 다시 좁힘. 회복구간 전체(며칠까지 늘어날 수 있음) 대신:
//
// 1. **야간 근무**(시작 시각이 17:00~04:59, `ShiftTimeCategory.night`) —
//    "근무 종료 1시간 전"부터 창 시작. 근무 중엔 절대 트래킹하지 않되, 퇴근
//    직전 잠깐 조는 경우나 칼퇴 오차를 대비해 1시간의 여유를 둠.
// 2. **그 외(주간/오후 근무, 휴무일)** — "일상적인 수면 시간대"인 21시 이후에
//    창을 연다. 다만 2026-09-06(사용자 논의) - 21시를 넘겨 끝나는 주간/오후
//    근무(예: 12시간 주간 10~22시)라면 아직 근무 중에 창이 열리는 걸 막기
//    위해 "21시와 실제 종료시각 중 더 늦은 쪽"부터 연다(휴무일은 비교할
//    종료시각이 없으니 그대로 21시).
// 3. 두 경우 다 창의 최대 길이는 [kSleepTrackingWindowMaxHours]시간으로 캡을
//    씌운다(다음 근무 시작이 더 이르면 그걸로 컷) — 예전처럼 "다음 근무가 며칠
//    뒤"라서 그 사이 내내(며칠간) 20분마다 계속 깨어나 샘플링하는 낭비를 막음.
// 4. 근무 중 짧은 낮잠/쪽잠은 이 파일이 계산하는 창 안에 절대 포함되지 않는다 -
//    그런 수면은 오직 위젯 수동 기록으로만 남긴다(자동 감지는 메인 잠 전용).

import 'shift_pattern_analyzer.dart';
import 'shift_time_category.dart';

class SleepOpportunityWindow {
  final DateTime start;
  final DateTime end;

  const SleepOpportunityWindow({required this.start, required this.end});

  bool contains(DateTime time) => !time.isBefore(start) && time.isBefore(end);
}

/// "야간 근무는 종료 몇 분 전부터" - 근거자료 값이 아니라 순수 UX 여유값.
const int kNightShiftPreEndMinutes = 60;

/// "야간 근무가 아니면 몇 시부터" - 일상적인 취침 시각대의 하한선(순수 관례값).
const int kFlatSleepStartHour = 21;

/// 창의 최대 길이(시간) - 다음 근무 시작이 이보다 늦어도 여기서 컷.
const int kSleepTrackingWindowMaxHours = 9;

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// ⭐ 2026-09-05 - "야간 근무 후 수면이 어느 날 것으로 귀속되는지"(sleep_day_slots.dart
/// _attributedDay)와 "이 수면이 근무 중이었는지"(sleep_shift_relation.dart
/// classifySleepRelation 등) 판정이 전부 [ShiftInstance.end]를 분 단위로 정확히
/// 비교하고 있었는데, 실제 퇴근 시각은 설정값과 정확히 일치하지 않는 게 정상이다
/// (자동 감지 자체가 "칼퇴 오차를 대비해 1시간의 여유를 둔다"고 이미 가정하고
/// 창을 종료 1시간 전부터 열어놓는데 - 위 kNightShiftPreEndMinutes 참고 - 정작
/// 그렇게 잡힌 수면을 "며칠 것으로 볼지/근무 중이었는지" 판정하는 쪽은 그 여유를
/// 전혀 안 봐주고 있었음). 그 결과 "어제 야간 퇴근하고 설정보다 조금 이르게
/// 잠들었다"는 흔한 케이스가 "아직 근무 중"으로 오판정되어, 그 수면이 어제
/// 야간근무의 회복수면이 아니라 오늘 것으로 잘못 잡히는 버그가 있었다.
///
/// 그래서 "이 근무가 실질적으로 끝난 것으로 볼 시각"을 여기 하나로 통일한다 -
/// 야간 근무만(주간/오후는 이 여유 개념 자체가 없음 - sleep_opportunity 설계와
/// 동일 원칙) 설정된 종료 시각보다 [kNightShiftPreEndMinutes] 만큼 당겨서 본다.
/// 근무 "시작" 몇 시간 전인지와는 무관 - 이 여유는 오직 근무의 마지막
/// [kNightShiftPreEndMinutes]분 구간에만 적용되고, 그보다 이전에 시작하는
/// 수면은 여전히 정상적으로 "근무 중"으로 판정된다.
DateTime graceAdjustedShiftEnd(ShiftInstance inst) {
  final end = inst.end!;
  if (inst.category != ShiftTimeCategory.night) return end;
  return end.subtract(const Duration(minutes: kNightShiftPreEndMinutes));
}

/// [now] 기준 "수면 추적 창"을 계산한다. 지금 창 안이면 [now]가 [start]~[end] 사이에
/// 있고, 아직 창이 시작 전(예: 오늘 밤 21시 예정)이면 [start]가 미래 시각으로
/// 반환된다 - 호출부(스케줄러)가 그 차이로 "지금 샘플링할지/다음 시작까지
/// 기다릴지"를 판단한다. 스케줄 자체가 없어 계산할 수 없으면 null.
SleepOpportunityWindow? sleepOpportunityWindowFor(
  DateTime now, {
  required ShiftPatternAnalyzer analyzer,
}) {
  final today = _dayOnly(now);

  // 1) 야간 근무 기준 - 오늘부터 최대 2일 전까지의 후보를 전부 모은 뒤,
  //    "이미 시작된(활성) 창"을 최우선으로 쓰고, 활성 창이 없으면 그중 가장
  //    먼저 시작하는(가장 이른 windowStart) 아직 시작 전 창을 쓴다.
  //
  //    ⚠️ 2026-09-01 버그 수정(백업_수면_컨디션_기능_검토_2026-09-01.md B1) -
  //    이전엔 offset을 0(오늘)→2(그제) 순으로 보다가 "now가 windowEnd보다만
  //    이르면" 무조건 첫 매치를 반환했음. 연속 야간근무(오늘도 야간 예정)일
  //    때 offset=0(오늘, 아직 시작도 안 한 밤 근무)의 창은 windowEnd가 아주
  //    먼 미래라 이 조건을 쉽게 통과해버려서, 실제로 지금 진행 중인
  //    offset=1(어제 근무의 활성 회복 창)을 확인하지도 못한 채 엉뚱한(미래)
  //    창을 반환했다 - 그 결과 어제 근무 후 낮잠을 자야 할 실제 구간에서
  //    자동 감지가 통째로 멈추는 버그였음. "이미 시작됐는지"를 먼저 따지도록
  //    고침 - `SleepScheduleResolver.kt`의 `computeWindowForNow`도 동일하게
  //    고칠 것(Dart/Kotlin 알고리즘 동일 유지 원칙).
  SleepOpportunityWindow? activeWindow;
  SleepOpportunityWindow? earliestUpcoming;
  for (var offset = 0; offset <= 2; offset++) {
    final d = today.subtract(Duration(days: offset));
    final inst = analyzer.instanceForDate(d);
    if (inst.isWorkDay && inst.category == ShiftTimeCategory.night && inst.end != null) {
      final windowStart = inst.end!.subtract(const Duration(minutes: kNightShiftPreEndMinutes));
      final windowEnd = _cappedEnd(analyzer, afterDate: d, from: windowStart);
      if (!now.isBefore(windowEnd)) continue; // 이미 끝난 창 - 후보 아님

      if (!now.isBefore(windowStart)) {
        // 지금 이미 이 창 안(진행 중) - 정상 스케줄에서는 활성 창이 동시에
        // 두 개일 수 없지만, 방어적으로 더 늦게 시작한(더 최신인) 쪽을 택함.
        if (activeWindow == null || windowStart.isAfter(activeWindow.start)) {
          activeWindow = SleepOpportunityWindow(start: windowStart, end: windowEnd);
        }
      } else {
        // 아직 시작 전 - 가장 이르게 시작하는 후보만 남겨둠(활성 창이 끝내
        // 없을 때의 폴백용).
        if (earliestUpcoming == null || windowStart.isBefore(earliestUpcoming.start)) {
          earliestUpcoming = SleepOpportunityWindow(start: windowStart, end: windowEnd);
        }
      }
    }
  }
  if (activeWindow != null) return activeWindow;
  if (earliestUpcoming != null) return earliestUpcoming;

  // 2) 그 외 - "일상적인 수면 시간대"(21시~) 플랫 규칙. now가 자정~06시 사이면
  //    어젯밤 21시가 앵커, 그 외(06시~21시, 21시~자정)면 오늘 21시가 앵커 -
  //    이렇게 하면 자정을 넘긴 새벽 시각도, 아직 오늘 밤을 기다리는 낮 시각도,
  //    이미 시작된 오늘 밤 21시 이후도 전부 올바르게 계산된다.
  final anchorDay = now.hour < 6 ? today.subtract(const Duration(days: 1)) : today;
  var flatStart = DateTime(anchorDay.year, anchorDay.month, anchorDay.day, kFlatSleepStartHour);
  // ⭐ 2026-09-06(사용자 논의) - 21시가 "그 외"(주간/오후/휴무) 전체에 무조건
  // 적용되다 보니, 21시를 넘겨 끝나는 주간/오후 근무(예: 12시간 주간 10~22시)
  // 에서는 아직 근무 중인데 창이 열려버렸다. 앵커 날짜 자신의 근무가 실제로
  // 21시 이후에 끝난다면(=night이 아닌 workday) 창 시작을 그 실제 종료시각까지
  // 늦춘다 - 야간이 이미 "실제 퇴근시각-60분" 기준을 쓰는 것과 같은 원칙을
  // 주간/오후에도 일관되게 적용하는 것(하드코딩된 시각을 늘리는 게 아니라,
  // 21시와 실제 종료시각 중 "더 늦은 쪽"을 취하는 것 - 휴무일처럼 근무 자체가
  // 없는 날은 비교할 종료시각이 없으니 그대로 21시).
  final anchorInst = analyzer.instanceForDate(anchorDay);
  if (anchorInst.isWorkDay &&
      anchorInst.category != ShiftTimeCategory.night &&
      anchorInst.end != null &&
      anchorInst.end!.isAfter(flatStart)) {
    flatStart = anchorInst.end!;
  }
  final flatEnd = _cappedEnd(analyzer, afterDate: anchorDay, from: flatStart);
  if (now.isBefore(flatEnd)) {
    return SleepOpportunityWindow(start: flatStart, end: flatEnd);
  }

  return null;
}

/// [from](창 시작 시각)부터 [kSleepTrackingWindowMaxHours]를 더한 시각과, [afterDate]
/// 이후 가장 가까운 다음 근무 시작 시각 중 더 이른 쪽을 창의 끝으로 쓴다.
DateTime _cappedEnd(ShiftPatternAnalyzer analyzer, {required DateTime afterDate, required DateTime from}) {
  final cap = from.add(const Duration(hours: kSleepTrackingWindowMaxHours));
  final nextStart = _findNextWorkStart(analyzer, afterDate);
  if (nextStart != null && nextStart.isBefore(cap)) return nextStart;
  return cap;
}

DateTime? _findNextWorkStart(ShiftPatternAnalyzer analyzer, DateTime afterDate, {int lookaheadDays = 14}) {
  for (var i = 1; i <= lookaheadDays; i++) {
    final inst = analyzer.instanceForDate(afterDate.add(Duration(days: i)));
    if (inst.isWorkDay && inst.start != null) return inst.start;
  }
  return null;
}
