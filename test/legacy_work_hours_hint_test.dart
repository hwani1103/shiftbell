import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/screens/work_hours_settings_screen.dart';

void main() {
  test('예전 총 근무시간만 있으면 출퇴근 시각 입력 안내가 필요하다', () {
    expect(needsLegacyClockTimeHint(720, null), isTrue);
  });

  test('실제 출퇴근 시각을 입력하면 안내가 자동으로 사라진다', () {
    const range = ShiftTimeRange(
      shiftName: '주간',
      startMinutes: 7 * 60,
      endMinutes: 19 * 60,
    );
    expect(needsLegacyClockTimeHint(720, range), isFalse);
  });

  test('예전 총 근무시간도 없는 신규 사용자는 안내하지 않는다', () {
    expect(needsLegacyClockTimeHint(0, null), isFalse);
  });
}
