// lib/services/condition/sleep_day_slots.dart
//
// ⭐ "최근 수면 기록" 미니 달력 카드 / 전체보기 화면이 공유하는 순수 그룹핑
// 로직. DB 스키마는 전혀 바뀌지 않는다 - `sleep_records`는 여전히 평범한 행의
// 나열일 뿐이고, 여기서는 그 중 상태가 confirmed인 기록을 "귀속되는 날짜"
// (아래 _attributedDay 참고) 기준으로 하루씩 묶어서 하루 최대 3칸(주 수면
// 1칸 + 낮잠 2칸)으로 뽑아낸다.
//
// ⭐ 2026-09-01 후속5 재설계 - 처음엔 낮잠을 "근무 중 낮잠"/"근무 외 낮잠"으로
// 라벨을 나눠 보여줬는데, 사용자 피드백으로 그 "표시상의" 구분을 없앰("근무 중
// 낮잠"이라는 말을 앱에서 아예 안 쓰기로 함) - 낮잠 2칸끼리는 근무 겹침과
// 무관하게 그냥 시작 시각이 이른 순으로 채워진다(어느 게 근무 중이었는지 화면에
// 라벨을 안 붙인다는 뜻).
//
// ⭐ 후속16(사용자 요청) - 다만 "주 수면이냐 낮잠이냐" 분류 자체는 근무 겹침을
// 다시 봄 - 근무 중에 잔 수면은 아무리 길어도 주 수면 칸에 넣지 않고 낮잠으로
// 보낸다(퇴근 후 진짜 주 수면을 할 수도 있으니 그 자리를 비워두기 위함,
// _isMainSleep 참고) - 후속5가 없앤 "화면에 라벨을 다르게 붙이는 것"과는 다른
// 얘기다(그건 여전히 안 함 - 낮잠 칸에 들어간 이상 "이게 근무 중이었다"는 표시
// 없이 그냥 낮잠으로만 보임).
//
// ⭐ 2026-09-01 후속7 - "야간 근무 다음날 아침에 잔 수면은 그 다음날이 아니라
// 야간 근무 당일에 매칭돼야 한다"는 요청으로 `ShiftPatternAnalyzer`를 다시
// 받게 됨(이건 오직 "어느 날짜 칸에 보여줄지"만 바꾸는 별도 로직, 아래
// _attributedDay 참고).
//
// ⚠️ 컨디션 예측(today_forecast_engine.dart 등)은 이 슬롯 "배정" 개념 자체는
// 전혀 모르고 여전히 원본 `sleep_records`를 직접 읽어 합산한다(완전 분리
// 원칙 유지) - 다만 후속16부터는 "근무 중 수면도 낮잠으로 쳐서 합산한다"는
// 결론 자체는 sleep_history.dart의 collectRecentWorkNights와 이 파일이 각자
// 독립적으로 동일하게 구현함(둘 다 classifySleepRelation을 직접 부름 - 목적이
// 달라 로직을 공유하진 않지만 결론이 어긋나면 안 됨). 실제로는 이 화면들을
// 통해서만 기록이 생성되므로 하루 3건 이하로 자연히 맞춰지고, 그 결과 "세 칸의
// 합"과 "그날 실제 수면 총합"이 사실상 같은 값이 된다. 하루에 우연히 낮잠이
// 3건 이상(레거시 데이터, 위젯 연타 등) 걸리면 이 화면에는 먼저(시작 시각
// 기준) 2건만 보이지만, 예측 계산에는 전부 그대로 반영된다.

import '../../models/sleep_record.dart';
import 'shift_pattern_analyzer.dart';
import 'shift_time_category.dart';
import 'sleep_opportunity.dart';
import 'sleep_shift_relation.dart';

enum SleepSlotCategory { main, nap1, nap2 }

extension SleepSlotCategoryLabel on SleepSlotCategory {
  String get label => this == SleepSlotCategory.main ? '주 수면' : '낮잠';
}

/// "슬롯 분류" 전용 임계값 - `sleep_shift_relation.dart`의 3시간 기준(근무
/// 겹침 라벨링용, 목적이 다름)과는 별개 값이다. 이쪽은 "그날의 메인 잠인가/짧은
/// 낮잠인가"를 가르는 기준 - 근거자료 값이 아니라 순수 UI 분류 편의값.
/// ⭐ 2026-09-04 - 4시간 → 2시간으로 낮춤(사용자 요청) - 야간근무 후 짧게(2시간
/// 안팎) 자는 회복수면까지 낮잠으로 밀려나는 게 실제 사용 패턴과 안 맞는다는
/// 지적. "낮잠은 2시간 미만, 2시간 이상은 주 수면"으로 기준 이동.
const int kMainSleepSlotThresholdMinutes = 2 * 60;

// ⭐ 2026-09-06 재설계(사용자 논의) - 예전엔 여기 "야간 근무 종료로부터 16시간
// 이내"라는 고정 길이 상수(_kNightRecoveryWindowHours)가 있었는데, 퇴근 시각에
// 따라 경계가 들쭉날쭉해지는 문제가 있었다: 예를 들어 야간 퇴근이 09시인
// 사람은 09시+16시간=다음날 새벽 01시가 경계가 되어, 그날 밤 22~23시경(본인의
// 평소 취침시각)에 잠들어도 아직 "16시간 이내"라서 그 진짜 "오늘 자신의
// 주수면"까지 어제(야간 근무일)의 회복수면으로 잘못 삼켜버렸다.
//
// "근무 종료 후 몇 시간 지났나"가 아니라 "오늘 자신의 평소 취침시각(21시)을
// 넘겼는가"로 기준을 바꾸면, 퇴근 시각이 몇 시든(06시든 09시든) 항상 같은
// 기준으로 갈린다 - 아래 _attributedDay 참고. 이 앵커는 자동 감지 창의
// "그 외/휴무는 21시부터"(sleep_opportunity.dart의 kFlatSleepStartHour)와
// 완전히 동일한 값 - 캡처 쪽과 표시 쪽이 "평소 취침시각"이라는 같은 개념을
// 공유하게 함으로써 두 로직이 서로 다른 기준으로 어긋나는 걸 방지한다.
//
// ⚠️ sleep_history.dart/sleep_stats.dart의 searchAheadHours(16)는 이것과 값만
// 같을 뿐 완전히 다른 목적(어느 근무의 회복수면으로 통계에 매칭할지 찾는 검색
// 상한 캡)이라 그쪽은 그대로 둔다 - 거긴 "고정 시간 캡"이 여전히 맞는
// 선택이다(며칠씩 기록이 비어도 무관한 미래 수면을 잘못 엮지 않기 위한 안전판).

/// 기록 하나가 "주 수면"인지 "낮잠"인지만 분류(둘 중 어느 낮잠 칸인지는
/// [buildSleepDaySlots]가 그날 시작 시각 순으로 정한다).
///
/// ⭐ 2026-09-01 후속16(사용자 요청) - 근무 중에 잔 수면(위젯 '수면' 버튼을
/// 근무시간에 눌러 기록한 경우 등)은 아무리 길어도 "주 수면" 칸에 넣지 않고
/// 낮잠 칸으로 보낸다 - 퇴근 후에 진짜 주 수면을 또 잘 수도 있으니, 주 수면
/// 자리는 그걸 위해 비워둬야 한다는 취지. [analyzer]가 없으면(근무시간
/// 미설정) 판단 불가하니 기존 길이 기준으로만 분류.
///
/// ⭐ 2026-09-01 후속17(사용자 지적으로 발견) - "야간 근무 출근 전에 미리 자는
/// 잠"도 같은 이유로 주 수면이면 안 됨(예: 어제 휴무·오늘 야간일 때 오늘
/// 출근 전 2시간 눈을 붙이는 것 - 사용자 표현으로도 "그게 주 수면이나
/// 마찬가지지만 주 수면으로 기록할 순 없다. 내일 퇴근하고 아침에 자는 게
/// 진짜 주 수면"). workShiftOverlap은 근무 "중"에만 걸리는 판정이라 출근
/// "전"에 끝나는 낮잠은 안 걸렀었음 - 짧으면(4시간 미만) 어차피 길이
/// 기준으로 낮잠이 됐지만, 길게(4시간 이상) 미리 자면 이 길이 기준만으로는
/// 주 수면 칸을 차지해버렸음. 그래서 "이 기록이 끝나는 시각이, 같은 날
/// 예정된 야간 근무 시작 시각보다 앞선다"면 길이와 무관하게 낮잠으로 본다.
bool _isMainSleep(SleepRecord r, ShiftPatternAnalyzer? analyzer) {
  if (analyzer != null && classifySleepRelation(r, analyzer) == SleepRelation.workShiftOverlap) {
    return false;
  }

  if (analyzer != null && r.end != null) {
    final sameDayInst = analyzer.instanceForDate(_dayOnly(r.start));
    if (sameDayInst.isWorkDay &&
        sameDayInst.category == ShiftTimeCategory.night &&
        sameDayInst.start != null &&
        !r.end!.isAfter(sameDayInst.start!) &&
        // ⭐ 2026-09-04 - M7 수정(전체_코드_점검_리포트_2026-09-04.md). 이 규칙은
        // 원래 "오늘 밤 야간 근무 출근 전에 미리 자는 낮잠"만 걸러내려던 것인데,
        // 당일 근무만 보고 전날 근무를 안 봐서 "연속 야간근무 사이 회복수면"
        // (어제 야간근무 끝나고 자는 잠인데 오늘도 야간이라 그 출근 전에 끝나는
        // 경우)까지 같이 낮잠으로 오분류됐다. 어제가 야간근무였고 그 종료 직후
        // (_attributedDay와 동일한 회복window 이내) 시작한 수면이면 이 규칙에서
        // 제외해 길이 기준(아래)으로 정상 판단하게 한다.
        !_isRecoverySleepFromYesterdayNightShift(r, analyzer)) {
      return false; // 오늘 예정된 야간 근무 출근 전에 끝난 잠 - 길이와 무관하게 낮잠
    }
  }

  final minutes = r.durationMinutes;
  if (minutes == null) {
    // ⭐ 아직 진행 중(기상 전)이라 실제 길이를 모름 - 취침 시작 시각으로
    // 잠정 분류해둔다(밤 8시~새벽 6시대면 주 수면으로 간주). 나중에 기상해서
    // 길이가 확정되면(다음 조회 때) 실제 길이 기준으로 자동 재분류된다(저장은
    // 그대로, 여기 계산만 다시 도는 것).
    final h = r.start.hour;
    return h >= 20 || h < 6;
  }
  return minutes >= kMainSleepSlotThresholdMinutes;
}

/// M7에서 씀 - [r]이 "어제 야간근무가 끝난 직후 시작한 회복수면"인지(즉, 오늘
/// 예정된 야간근무 때문에 강제로 낮잠 취급되면 안 되는 케이스인지).
///
/// ⭐ 2026-09-06 재설계 - [_attributedDay]가 내리는 결론과 정확히 같은 질문이다
/// ("이 수면이 어제 칸으로 재귀속되는가?"). 예전엔 이 함수가 같은 규칙을
/// 독자적으로 다시 구현하고 있어서(16시간 비교를 두 곳에 따로 두는 바람에
/// truncate 버그도 한쪽만 고쳐질 위험이 있었음) 두 곳이 어긋날 여지가 있었다 -
/// 이제 [_attributedDay] 하나에만 규칙을 두고 여기선 그 결과만 재사용한다.
bool _isRecoverySleepFromYesterdayNightShift(SleepRecord r, ShiftPatternAnalyzer analyzer) {
  return _attributedDay(r, analyzer) != _dayOnly(r.start);
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 이 수면 기록을 "며칠 칸"에 보여줄지. 기본은 시작한 날짜 그대로지만,
/// **어제가 야간 근무였고 그 근무 종료 직후 시작해서 아직 오늘 자신의 평소
/// 취침시각(21시)을 넘기지 않은 수면이면 어제(야간 근무 당일)로 귀속시킨다** -
/// 예: 21일이 야간 근무(19시~다음날 07시)이고 22일 07시~13시에 잤다면, 이
/// 수면은 날짜상 22일에 시작했지만 "21일 야간 근무의 회복 수면"이므로 21일
/// 칸에 표시돼야 한다는 요청 반영. [analyzer]가 없으면(근무시간 미설정) 판단
/// 불가하니 그냥 시작 날짜를 그대로 씀.
///
/// ⭐ 2026-09-06 재설계(사용자 논의) - "야간 근무 퇴근~21시 이내" 구간에
/// 시작하는 수면 = 어제(야간 근무일)의 회복수면, "21시 이후" = 오늘 자신의
/// 정상 주수면. 예전엔 "퇴근 후 16시간 이내"라는 고정 길이로 갈랐는데, 퇴근이
/// 이르면(예: 05시) 경계가 너무 일찍(21시) 닫히고 늦으면(예: 09시) 경계가 너무
/// 늦게(다음날 새벽 01시) 열려서 그날 밤의 진짜 자기 주수면까지 어제 것으로
/// 삼켜버리는 문제가 있었다. "고정 시간 경과"가 아니라 "오늘 자신의 평소
/// 취침시각을 넘겼는가"로 기준을 바꾸면 퇴근 시각이 몇 시든 항상 같은 기준으로
/// 갈린다(21일이 야간이고 22일이 휴무인 경우: 22일 07~13시의 회복수면은 21일
/// 칸, 22일 23시부터의 정상 취침은 22일 자신의 주수면 - 둘 다 정확히 갈라짐).
DateTime _attributedDay(SleepRecord r, ShiftPatternAnalyzer? analyzer) {
  final startDay = _dayOnly(r.start);
  if (analyzer == null) return startDay;

  final prevDay = startDay.subtract(const Duration(days: 1));
  final prevInst = analyzer.instanceForDate(prevDay);
  if (!prevInst.isWorkDay || prevInst.category != ShiftTimeCategory.night || prevInst.end == null) {
    return startDay;
  }
  // ⭐ 2026-09-05 버그 수정(사용자 신고) - "어제 야간 퇴근하고 오늘 아침에 잔
  // 수면이 어제가 아니라 오늘 주 수면으로 잡힌다". 원인: 여기서 실제 퇴근
  // 시각을 설정된 근무 종료 시각과 분 단위로 정확히 비교하고 있었는데, 실제
  // 퇴근은 설정보다 조금(자동 감지 창이 이미 허용하는 오차만큼) 이를 수 있다 -
  // graceAdjustedShiftEnd 참고(sleep_shift_relation.dart의 classifySleepRelation도
  // 동일한 값을 써서 "근무 중이었는지" 판정이 여기와 어긋나지 않게 함).
  // 근무 종료(유예 적용) 이후 시작하는 수면이어야 함(더 이전에 시작한 건
  // 진짜 근무 중 수면 - workShiftOverlap이 별도로 처리).
  final effectiveEnd = graceAdjustedShiftEnd(prevInst);
  if (r.start.isBefore(effectiveEnd)) return startDay;

  // 오늘(=수면이 시작한 날) 자신의 평소 취침시각 앵커 - 자동 감지 창의
  // kFlatSleepStartHour(sleep_opportunity.dart)와 동일 값을 재사용한다.
  final todayBedtimeAnchor =
      DateTime(startDay.year, startDay.month, startDay.day, kFlatSleepStartHour);
  if (!r.start.isBefore(todayBedtimeAnchor)) return startDay; // 오늘 21시 이후 - 오늘 자신의 주수면
  return prevDay;
}

class SleepDaySlots {
  final DateTime date; // 자정 0시 기준 - "귀속되는 날짜"(_attributedDay 참고)
  final SleepRecord? mainSleep;
  final SleepRecord? nap1;
  final SleepRecord? nap2;

  const SleepDaySlots({required this.date, this.mainSleep, this.nap1, this.nap2});

  bool get isEmpty => mainSleep == null && nap1 == null && nap2 == null;

  SleepRecord? forCategory(SleepSlotCategory c) {
    switch (c) {
      case SleepSlotCategory.main:
        return mainSleep;
      case SleepSlotCategory.nap1:
        return nap1;
      case SleepSlotCategory.nap2:
        return nap2;
    }
  }
}

/// [records] 중 status==confirmed인 것만, [_attributedDay] 기준으로 묶어서
/// 하루당 주 수면 1칸 + 낮잠 2칸(시작 시각 오름차순)으로 배정한다. [from]~[to]
/// (둘 다 포함, 날짜 단위) 범위의 날짜를 오름차순으로 전부 반환 - 기록이 없는
/// 날짜도 빈 슬롯으로 포함된다. [analyzer]는 야간 근무 회복 수면을 전날로
/// 귀속시킬 때만 쓰인다(없어도 동작 - 그냥 시작 날짜 기준으로만 묶임).
List<SleepDaySlots> buildSleepDaySlots({
  required List<SleepRecord> records,
  required DateTime from,
  required DateTime to,
  ShiftPatternAnalyzer? analyzer,
}) {
  final byDay = <DateTime, List<SleepRecord>>{};
  for (final r in records) {
    if (r.status != SleepStatus.confirmed) continue;
    final day = _attributedDay(r, analyzer);
    (byDay[day] ??= []).add(r);
  }
  for (final list in byDay.values) {
    list.sort((a, b) => a.start.compareTo(b.start));
  }

  final start = _dayOnly(from);
  final end = _dayOnly(to);
  final result = <SleepDaySlots>[];
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    final dayRecords = byDay[d];
    SleepRecord? main;
    final naps = <SleepRecord>[];
    if (dayRecords != null) {
      for (final r in dayRecords) {
        // ⭐ 2026-09-06 버그 수정(사용자 신고) - 원래 "주 수면 자격이 있는데 그
        // 칸이 이미 찼으면" 그냥 버려서(`main ??= r`이 두 번째부터는 조용히
        // 무시) 실제로 존재하는 수면 기록이 화면에서 통째로 사라졌다(위
        // _attributedDay/_isRecoverySleepFromYesterdayNightShift의 .inHours
        // truncate 버그와 겹치면 특히 잘 발생 - 그 버그로 다른 기록이 같은 날에
        // 잘못 끼어들어와 주 수면 칸을 먼저 차지해버림). 자격이 있어도 칸이
        // 이미 찼으면 낮잠 칸으로 대신 넣어 최소한 화면에서 없어지지는 않게 함.
        if (_isMainSleep(r, analyzer) && main == null) {
          main = r;
        } else {
          naps.add(r);
        }
      }
    }
    result.add(SleepDaySlots(
      date: d,
      mainSleep: main,
      nap1: naps.isNotEmpty ? naps[0] : null,
      nap2: naps.length > 1 ? naps[1] : null,
    ));
  }
  return result;
}

/// 빈 칸을 처음 탭했을 때 다이얼로그에 채워줄 기본 시각. "주 수면"은 그날 밤
/// 10시~다음날 6시(kMainSleepSlotThresholdMinutes 이상 기준과 맞춤), 낮잠 두
/// 칸은 오후 2시/4시에 각각 30분짜리로 - 다이얼로그에서 바로 고쳐 쓰는 게
/// 전제라 정확할 필요는 없고, 탭 수를 줄이기 위한 순수 편의값(연구/근거자료와
/// 무관).
({DateTime start, DateTime end}) defaultSleepSlotTimes(DateTime date, SleepSlotCategory category) {
  final d = _dayOnly(date);
  switch (category) {
    case SleepSlotCategory.main:
      return (start: DateTime(d.year, d.month, d.day, 22), end: DateTime(d.year, d.month, d.day + 1, 6));
    case SleepSlotCategory.nap1:
      return (start: DateTime(d.year, d.month, d.day, 14), end: DateTime(d.year, d.month, d.day, 14, 30));
    case SleepSlotCategory.nap2:
      return (start: DateTime(d.year, d.month, d.day, 16), end: DateTime(d.year, d.month, d.day, 16, 30));
  }
}
