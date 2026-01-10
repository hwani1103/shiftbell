import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 테마 모드 상태 관리
class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.light) {
    _loadTheme();
  }

  static const String _themeKey = 'theme_mode';
  static const String _themeManuallySetKey = 'theme_manually_set';

  // 저장된 테마 로드
  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isManuallySet = prefs.getBool(_themeManuallySetKey) ?? false;

      if (isManuallySet) {
        // 사용자가 한번이라도 변경했으면 저장된 값 사용
        final themeModeString = prefs.getString(_themeKey);
        if (themeModeString != null) {
          state = ThemeMode.values.firstWhere(
            (mode) => mode.toString() == themeModeString,
            orElse: () => ThemeMode.light,
          );
          print('✅ 사용자 설정 테마 로드: $state');
        }
      } else {
        // 첫 설치: 시스템 설정 따라감
        final platformBrightness = PlatformDispatcher.instance.platformBrightness;
        state = platformBrightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
        print('✅ 시스템 설정 테마 로드: $state (시스템: $platformBrightness)');
      }
    } catch (e) {
      print('❌ 테마 로드 실패: $e');
    }
  }

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
