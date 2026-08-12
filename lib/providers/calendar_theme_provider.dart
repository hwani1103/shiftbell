// lib/providers/calendar_theme_provider.dart
//
// ⭐ 선택된 달력 테마 상태 관리 - 예전 theme_provider.dart(다크모드 on/off)를
// 대체함. "다크모드"라는 전역 토글은 이제 없고, 9개 테마 중 하나를 고르는
// 것뿐이라 상태 타입 자체가 ThemeMode가 아니라 CalendarThemeId임.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/calendar_theme.dart';
import '../services/widget_refresh_service.dart';

class CalendarThemeNotifier extends StateNotifier<CalendarThemeId> {
  CalendarThemeNotifier() : super(kDefaultCalendarThemeId);

  CalendarThemeNotifier.withInitial(CalendarThemeId initial) : super(initial);

  static const _prefsKey = 'calendar_theme_id';

  Future<void> setTheme(CalendarThemeId id) async {
    state = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, id.name);
    } catch (e) {
      print('❌ 달력 테마 저장 실패: $e');
    }
    // ⭐ 위젯도 즉시 같은 테마(다크 여부)로 갱신 - 예전 theme_provider.dart의
    // setThemeMode()가 하던 것과 동일한 역할. 위젯 자체가 9개 디자인을 전부
    // 재현하진 못하지만(별도 후속 작업), 최소한 밝기(라이트/다크 배경·글자색)는
    // 선택한 테마를 따라감.
    WidgetRefreshService.pushTheme(id.isDark);
  }

  static Future<CalendarThemeId> loadInitial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == null) return kDefaultCalendarThemeId;
      return CalendarThemeId.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => kDefaultCalendarThemeId,
      );
    } catch (e) {
      print('❌ 달력 테마 로드 실패: $e');
      return kDefaultCalendarThemeId;
    }
  }
}

final calendarThemeProvider = StateNotifierProvider<CalendarThemeNotifier, CalendarThemeId>((ref) {
  return CalendarThemeNotifier();
});
