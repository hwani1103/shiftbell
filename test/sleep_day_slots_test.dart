// test/sleep_day_slots_test.dart
//
// ⭐ 2026-09-01 후속16 - "근무 중 수면은 아무리 길어도 주 수면 칸에 넣지 말고
// 낮잠 칸으로" 요청 검증. "최근 수면 기록" 미니 달력의 슬롯 배정 로직
// (sleep_day_slots.dart)이 근무 겹침 여부를 다시 보게 됐는지 확인.

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/models/sleep_record.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';
import 'package:shiftbell/services/condition/sleep_day_slots.dart';

const _kDay = '주간';
const _kNight = '야간';
const _kOff = '휴무';
const List<String> _pattern = [_kDay, _kDay, _kOff, _kOff, _kOff, _kOff, _kOff];
final _shiftTimes = <String, ShiftTimeRange>{
  _kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 19 * 60),
  _kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 19 * 60, endMinutes: 7 * 60),
};

SleepRecord _record(DateTime start, int minutes) => SleepRecord(
      start: start,
      end: start.add(Duration(minutes: minutes)),
      source: SleepSource.manual,
      status: SleepStatus.confirmed,
    );

void main() {
  final today = DateTime(2026, 9, 6); // todayIndex=0(주간) 기준으로 스케줄 구성

  ShiftPatternAnalyzer buildAnalyzer() {
    final schedule = ShiftSchedule(
      isRegular: true,
      pattern: _pattern,
      todayIndex: 0,
      startDate: today,
      shiftTypes: const [_kDay, _kOff],
    );
    return ShiftPatternAnalyzer(schedule: schedule, shiftTimes: _shiftTimes);
  }

  test('1. 근무 중 6시간 수면 - 길어도 낮잠 칸에 들어가야 함(주 수면 아님)', () {
    final analyzer = buildAnalyzer();
    final inst = analyzer.instanceForDate(today); // 07~19시 주간
    final records = [_record(inst.start!.add(const Duration(hours: 1)), 6 * 60)]; // 08~14시, 근무 중
    final slots = buildSleepDaySlots(records: records, from: today, to: today, analyzer: analyzer);
    final today0 = slots.first;
    expect(today0.mainSleep, null, reason: '근무 중 수면은 아무리 길어도 주 수면 칸에 들어가면 안 됨');
    expect(today0.nap1, isNotNull, reason: '대신 낮잠 칸에 들어가야 함');
  });

  test('2. 근무 중 수면(4시간) + 퇴근 후 진짜 주 수면(7시간) - 각각 낮잠/주 수면 칸에 분리 배정', () {
    final analyzer = buildAnalyzer();
    final inst = analyzer.instanceForDate(today);
    final records = [
      _record(inst.start!.add(const Duration(hours: 1)), 4 * 60), // 근무 중 낮잠
      _record(inst.end!.add(const Duration(minutes: 30)), 7 * 60), // 퇴근 후 주 수면
    ];
    final slots = buildSleepDaySlots(records: records, from: today, to: today, analyzer: analyzer);
    final today0 = slots.first;
    expect(today0.mainSleep, isNotNull, reason: '퇴근 후 7시간 수면이 주 수면 칸을 차지해야 함');
    expect(today0.mainSleep!.start, inst.end!.add(const Duration(minutes: 30)));
    expect(today0.nap1, isNotNull, reason: '근무 중 4시간 수면은 낮잠 칸에 들어가야 함');
  });

  test('3. 근무와 무관한 평범한 6시간 수면 - 여전히 주 수면 칸(회귀 확인)', () {
    final analyzer = buildAnalyzer();
    // 휴무일(offset+2, index2)의 밤 수면 - 근무와 전혀 안 겹침.
    final offDay = today.add(const Duration(days: 2));
    final start = DateTime(offDay.year, offDay.month, offDay.day, 23);
    final records = [_record(start, 6 * 60)];
    final slots = buildSleepDaySlots(records: records, from: offDay, to: offDay, analyzer: analyzer);
    final day0 = slots.first;
    expect(day0.mainSleep, isNotNull, reason: '근무와 무관한 평범한 수면은 그대로 주 수면 칸(길이 기준 분류 유지)');
  });

  // ⭐ 2026-09-01 후속17(사용자 시나리오 그대로) - "어제 휴무, 오늘 야간"일 때:
  // 어제 밤잠(8시간)은 주 수면, 오늘 출근 전 낮잠(길게 5시간을 자도)은 낮잠
  // 칸에 들어가야 함 - "내일 퇴근하고 아침에 자는 게 진짜 주 수면"이므로
  // 오늘 낮 동안엔 주 수면 자리를 미리 차지하면 안 됨.
  test('4. 어제=휴무(밤잠 8h) / 오늘=야간(출근 전 낮잠 5h, 19시 출근)', () {
    final pattern = [_kOff, _kNight, _kOff, _kOff, _kOff, _kOff, _kOff];
    final schedule = ShiftSchedule(
      isRegular: true,
      pattern: pattern,
      todayIndex: 1, // 오늘 = 야간, 어제(index0) = 휴무
      startDate: today,
      shiftTypes: const [_kOff, _kNight],
    );
    final analyzer = ShiftPatternAnalyzer(schedule: schedule, shiftTimes: _shiftTimes);

    final yesterday = today.subtract(const Duration(days: 1));
    final lastNightSleep = _record(DateTime(yesterday.year, yesterday.month, yesterday.day, 23), 8 * 60); // 어제 23시~오늘 07시
    final preShiftNap = _record(DateTime(today.year, today.month, today.day, 13), 5 * 60); // 오늘 13~18시(19시 출근 전), 일부러 길게(5h)

    final slots = buildSleepDaySlots(
      records: [lastNightSleep, preShiftNap],
      from: yesterday,
      to: today,
      analyzer: analyzer,
    );
    final yesterdaySlot = slots.firstWhere((s) => s.date == DateTime(yesterday.year, yesterday.month, yesterday.day));
    final todaySlot = slots.firstWhere((s) => s.date == DateTime(today.year, today.month, today.day));

    expect(yesterdaySlot.mainSleep, isNotNull, reason: '어제 밤잠은 정상적인 주 수면');
    expect(yesterdaySlot.mainSleep!.start, lastNightSleep.start);
    expect(todaySlot.mainSleep, null, reason: '오늘 출근 전 낮잠은 길어도(5시간) 주 수면이면 안 됨 - 진짜 주 수면은 내일 퇴근 후');
    expect(todaySlot.nap1, isNotNull, reason: '대신 낮잠 칸에 들어가야 함');
  });

  // ⭐ 2026-09-05 버그 수정(사용자 신고) - "어제 야간 퇴근하고 오늘 아침에 잔
  // 수면이 어제가 아니라 오늘 주 수면으로 잡힌다". 실제 퇴근은 설정된 근무
  // 종료 시각(07:00)과 분 단위로 정확히 일치하지 않는 게 정상인데(특히 자동
  // 감지 - 창 자체가 "종료 1시간 전부터" 열려 있음), 예전 코드는 그 오차를
  // 전혀 안 봐주고 "설정된 종료 시각보다 1분이라도 이르면 아직 근무 중"으로
  // 오판정했다.
  test('5. 어제=야간(설정상 07시 종료)/오늘=휴무, 실제 취침이 설정보다 10분 이른 06:50', () {
    final pattern = [_kNight, _kOff, _kOff, _kOff, _kOff, _kOff, _kOff];
    final schedule = ShiftSchedule(
      isRegular: true,
      pattern: pattern,
      todayIndex: 1, // 오늘 = 휴무, 어제(index0) = 야간
      startDate: today,
      shiftTypes: const [_kNight, _kOff],
    );
    final analyzer = ShiftPatternAnalyzer(schedule: schedule, shiftTimes: _shiftTimes);

    final yesterday = today.subtract(const Duration(days: 1));
    // 설정상 07:00 퇴근인데 실제로는 06:50에 잠듦(자동 감지 창은 06:00부터 열려
    // 있어 이런 기록이 정상적으로 생길 수 있음) - 4시간 수면.
    final record = _record(DateTime(today.year, today.month, today.day, 6, 50), 4 * 60);

    final slots = buildSleepDaySlots(records: [record], from: yesterday, to: today, analyzer: analyzer);
    final yesterdaySlot = slots.firstWhere((s) => s.date == DateTime(yesterday.year, yesterday.month, yesterday.day));
    final todaySlot = slots.firstWhere((s) => s.date == DateTime(today.year, today.month, today.day));

    expect(yesterdaySlot.mainSleep, isNotNull, reason: '설정보다 10분 이른 취침도 어제 야간근무의 회복수면으로 잡혀야 함');
    expect(yesterdaySlot.mainSleep!.start, record.start);
    expect(todaySlot.mainSleep, null, reason: '오늘 것으로 잘못 넘어가면 안 됨(수정 전엔 여기로 잘못 들어갔었음)');
  });

  // ⭐ 2026-09-06 재설계(사용자 논의, 실사용 신고 케이스 그대로) - 어제=야간
  // 퇴근~"오늘 21시" 이내 = 어제 근무의 회복수면, 21시 이후 = 오늘 자신의
  // 정상 주수면. 어제=야간(19~07시)/오늘=휴무일 때 하루에 주 수면이 "두 번"
  // 있을 수 있다는 걸 검증(회복수면 vs 그날 밤 정상 취침) - 실제 폰 데이터에서
  // 재현된 시나리오.
  test('6. 어제=야간(19~07시 종료)/오늘=휴무 - 회복수면(07~13시)은 어제 주수면, '
      '그날 밤(23~06시)은 오늘 자신의 주수면으로 각각 분리돼야 함', () {
    final pattern = [_kNight, _kOff, _kOff, _kOff, _kOff, _kOff, _kOff];
    final schedule = ShiftSchedule(
      isRegular: true,
      pattern: pattern,
      todayIndex: 1, // 오늘 = 휴무, 어제(index0) = 야간
      startDate: today,
      shiftTypes: const [_kNight, _kOff],
    );
    final analyzer = ShiftPatternAnalyzer(schedule: schedule, shiftTimes: _shiftTimes);

    final yesterday = today.subtract(const Duration(days: 1));
    final recovery = _record(DateTime(today.year, today.month, today.day, 7), 6 * 60); // 오늘 07~13시
    final ownNightSleep = _record(DateTime(today.year, today.month, today.day, 23), 7 * 60); // 오늘 23시~내일 06시

    final slots = buildSleepDaySlots(
      records: [recovery, ownNightSleep],
      from: yesterday,
      to: today,
      analyzer: analyzer,
    );
    final yesterdaySlot = slots.firstWhere((s) => s.date == DateTime(yesterday.year, yesterday.month, yesterday.day));
    final todaySlot = slots.firstWhere((s) => s.date == DateTime(today.year, today.month, today.day));

    expect(yesterdaySlot.mainSleep, isNotNull, reason: '어제 야간 퇴근 직후(07~13시) 회복수면은 어제 주수면 칸');
    expect(yesterdaySlot.mainSleep!.start, recovery.start);
    expect(todaySlot.mainSleep, isNotNull, reason: '오늘 밤(23시 이후) 취침은 오늘 자신의 주수면 칸');
    expect(todaySlot.mainSleep!.start, ownNightSleep.start);
  });

  // ⭐ 2026-09-06 - 예전 "고정 16시간" 방식이었다면 깨졌을 케이스. 야간 퇴근이
  // 늦은(09시) 사람은 09시+16시간=다음날 01시가 경계가 돼서, 그날 밤 22시의
  // 진짜 자기 주수면까지 어제 근무의 회복수면으로 잘못 삼켰을 것 - "21시 앵커"
  // 방식은 퇴근 시각과 무관하게 항상 21시가 경계라 이 문제가 없어야 한다.
  test('7. 어제=야간(퇴근이 09시로 늦음) - 그날 밤 22시 취침은 "16시간 이내"라도 '
      '오늘 자신의 주수면이어야 함(고정 16시간 방식이었다면 실패했을 케이스)', () {
    final lateNightShiftTimes = <String, ShiftTimeRange>{
      _kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 21 * 60, endMinutes: 9 * 60), // 21~09시
    };
    final pattern = [_kNight, _kOff, _kOff, _kOff, _kOff, _kOff, _kOff];
    final schedule = ShiftSchedule(
      isRegular: true,
      pattern: pattern,
      todayIndex: 1,
      startDate: today,
      shiftTypes: const [_kNight, _kOff],
    );
    final analyzer = ShiftPatternAnalyzer(schedule: schedule, shiftTimes: lateNightShiftTimes);

    // 09시 퇴근 + 16시간 = 다음날 01시가 옛 경계. 22시는 그 경계보다 한참
    // 이르므로(=아직 "16시간 이내") 옛 로직이면 어제로 잘못 귀속됐을 것.
    final lateBedtime = _record(DateTime(today.year, today.month, today.day, 22), 7 * 60);

    final slots = buildSleepDaySlots(records: [lateBedtime], from: today, to: today, analyzer: analyzer);
    final todaySlot = slots.first;

    expect(todaySlot.mainSleep, isNotNull, reason: '21시 이후 취침은 항상 그날 자신의 주수면이어야 함');
    expect(todaySlot.mainSleep!.start, lateBedtime.start);
  });

  // ⭐ 2026-09-06 재설계(사용자 지적) - 주 수면 "자격"이 있는 후보가 하루에
  // 둘 이상이면(휴무일 낮잠 4시간 + 그날 밤 정상 취침 7시간, 둘 다 근무와
  // 안 겹치고 2시간 이상) 예전엔 시작시각이 이른 낮잠이 이겼는데, 이제는
  // 가장 긴 쪽이 주 수면이어야 함.
  test('8. 휴무일 - 낮 4시간 낮잠 + 그날 밤 7시간 정상 취침이 같이 있으면 '
      '더 긴 밤잠이 주 수면, 낮잠은 낮잠 칸으로', () {
    final pattern = [_kOff, _kOff, _kOff, _kOff, _kOff, _kOff, _kOff];
    final schedule = ShiftSchedule(
      isRegular: true,
      pattern: pattern,
      todayIndex: 0,
      startDate: today,
      shiftTypes: const [_kOff],
    );
    final analyzer = ShiftPatternAnalyzer(schedule: schedule, shiftTimes: _shiftTimes);

    final afternoonNap = _record(DateTime(today.year, today.month, today.day, 14), 4 * 60); // 14~18시
    final nightSleep = _record(DateTime(today.year, today.month, today.day, 23), 7 * 60); // 23시~06시

    final slots = buildSleepDaySlots(records: [afternoonNap, nightSleep], from: today, to: today, analyzer: analyzer);
    final todaySlot = slots.first;

    expect(todaySlot.mainSleep, isNotNull);
    expect(todaySlot.mainSleep!.start, nightSleep.start, reason: '더 긴 쪽(7시간 밤잠)이 주 수면이어야 함');
    expect(todaySlot.nap1, isNotNull);
    expect(todaySlot.nap1!.start, afternoonNap.start, reason: '짧은 쪽(4시간 낮잠)은 낮잠 칸으로');
  });
}
