import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/widget_refresh_service.dart';

// 테마 모드 상태 관리
class ThemeNotifier extends StateNotifier<ThemeMode> {
  // 기본 생성자 (앱 시작 시 사용 안 함, override로 대체)
  ThemeNotifier() : super(ThemeMode.light);

  // 초기 테마와 함께 생성 (깜빡임 방지)
  ThemeNotifier.withInitialTheme(ThemeMode initialTheme) : super(initialTheme) {
    print('✅ 초기 테마로 시작: $initialTheme');
  }

  static const String _themeKey = 'theme_mode';
  static const String _themeManuallySetKey = 'theme_manually_set';

  // 테마 변경 및 저장
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, mode.toString());
      await prefs.setBool(_themeManuallySetKey, true); // 수동 설정 플래그
      print('✅ 테마 저장: $mode (수동 설정됨)');
    } catch (e) {
      print('❌ 테마 저장 실패: $e');
    }
    // ⭐ 홈 화면 위젯도 같은 테마로 즉시 갱신 (앱 재시작 없이)
    WidgetRefreshService.pushTheme(mode == ThemeMode.dark);
  }

  // 다크모드 토글
  Future<void> toggleTheme() async {
    final newMode = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await setThemeMode(newMode);
  }

  // 현재 다크모드 여부
  bool get isDarkMode => state == ThemeMode.dark;
}

// Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});
