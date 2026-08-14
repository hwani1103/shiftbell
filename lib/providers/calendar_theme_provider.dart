// lib/providers/calendar_theme_provider.dart
//
// ⭐ 선택된 달력 테마 상태 관리 - 예전 theme_provider.dart(다크모드 on/off)를
// 대체함. "다크모드"라는 전역 토글은 이제 없고, 9개 테마 중 하나를 고르는
// 것뿐이라 상태 타입 자체가 ThemeMode가 아니라 CalendarThemeId임.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/calendar_theme.dart';

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
    // ⭐ 위젯은 항상 라이트(메인·화이트) 고정이라(2026-08-13 결정, CalendarWidgetProvider.kt
    // 참고) 여기서 위젯에 테마를 따로 안 알려줌 - 근무 데이터 자체가 바뀐 경우(근무변경 등)만
    // WidgetRefreshService.refresh()로 다시 그리면 충분함(그건 schedule_provider.dart 쪽에서 함).
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
