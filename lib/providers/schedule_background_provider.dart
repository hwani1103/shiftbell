// lib/providers/schedule_background_provider.dart
//
// ⭐ 2026-08-27 - 일정관리 탭 전용 배경색 설정(새 설정 화면, 날짜 스트립 우측
// 톱니바퀴 아이콘에서 진입). 지금은 "배경색 적용"만 함 - 배경이 바뀌면서
// 헤더/날짜스트립의 기존 불투명 흰 배경 등과 부딪히는 부분은 다음에 다듬을 것
// (요청: "일단 여기까지만 시작해봐").

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 10개 프리셋 - 기본(지금 쓰던 색) + 파스텔 계열 + 다크 계열 몇 개.
const List<Color> kScheduleBackgroundColors = [
  Color(0xFFFAFBFF), // 기본
  Color(0xFFFFF8F0), // 아이보리
  Color(0xFFF0F7FF), // 하늘
  Color(0xFFF3F0FF), // 라벤더
  Color(0xFFF0FFF4), // 민트
  Color(0xFFFFF0F5), // 핑크
  Color(0xFFFFFDE7), // 레몬
  Color(0xFFECEFF1), // 그레이
  Color(0xFF1A1F2E), // 다크 네이비
  Color(0xFF2D2320), // 다크 브라운
];

const _prefKey = 'schedule_management_bg_color_index';

final scheduleBackgroundProvider =
    StateNotifierProvider<ScheduleBackgroundNotifier, int>((ref) {
  return ScheduleBackgroundNotifier();
});

class ScheduleBackgroundNotifier extends StateNotifier<int> {
  ScheduleBackgroundNotifier() : super(0) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_prefKey) ?? 0;
    if (idx >= 0 && idx < kScheduleBackgroundColors.length) {
      state = idx;
    }
  }

  Future<void> setColorIndex(int index) async {
    if (index < 0 || index >= kScheduleBackgroundColors.length) return;
    state = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, index);
  }

  Color get color => kScheduleBackgroundColors[state];
}
