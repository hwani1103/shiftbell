// lib/providers/tab_visibility_provider.dart
//
// ⭐ 2026-09-13 추가(사용자 요청) - "일정관리"/"컨디션" 탭을 하단 네비게이션에서
// 아예 없앨 수 있게(설정에서 다시 켤 수 있음). 각 탭 화면 맨 아래(광고 우측
// 위)의 빨간 "OO 화면 사용하지 않기" 버튼 → 확인 다이얼로그 → 이 provider를
// false로 바꾸면 main.dart가 그 탭을 네비게이션에서 뺀다. 설정 탭에는 꺼져있을
// 때만 "OO 화면 사용하기" 항목이 나타나 다시 켤 수 있다(두 UI가 동시에 노출되지
// 않게 하기 위한 규칙 - 이미 네비게이션에 있으면 설정에 "사용하기" 버튼이
// 필요 없고, 꺼놨으면 그 탭 자체가 없으니 "사용하지 않기" 버튼을 보여줄 화면이
// 없음 - 서로 배타적).
//
// SharedPreferences로 영속화 - 기본값은 둘 다 true(기존 동작 그대로 유지).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/schedule_notification_service.dart';

const _kScheduleTabEnabledKey = 'schedule_tab_enabled';
const _kConditionTabEnabledKey = 'condition_tab_enabled';

class TabEnabledNotifier extends StateNotifier<bool> {
  final String _prefsKey;
  TabEnabledNotifier(this._prefsKey) : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // ⭐ 2026-09-14 (출시전 교차 검토 X-09) - 손상된 값(bool이 아닌 자료형)이 남아 있어도 탭 초기화가 깨지지 않게 기본값으로
    final raw = prefs.get(_prefsKey);
    state = raw is bool ? raw : true;
    // ⭐ 2026-09-14 (출시전 감사 #5) - 일정관리 탭 설정은 Native에도 맞춰 둠(재부팅·알림 수신 때 확인)
    if (_prefsKey == _kScheduleTabEnabledKey) {
      await ScheduleNotificationService.syncTabEnabledToNative(state);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final previous = state;
    if (_prefsKey == _kScheduleTabEnabledKey) {
      final synced = await ScheduleNotificationService.syncTabEnabledToNative(enabled);
      if (!synced) throw StateError('일정관리 탭 Native 동기화 실패');
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setBool(_prefsKey, enabled);
    if (!saved) {
      if (_prefsKey == _kScheduleTabEnabledKey) {
        await ScheduleNotificationService.syncTabEnabledToNative(previous);
      }
      throw StateError('탭 설정 저장 실패: $_prefsKey');
    }
    state = enabled;
  }
}

final scheduleTabEnabledProvider =
    StateNotifierProvider<TabEnabledNotifier, bool>((ref) => TabEnabledNotifier(_kScheduleTabEnabledKey));

final conditionTabEnabledProvider =
    StateNotifierProvider<TabEnabledNotifier, bool>((ref) => TabEnabledNotifier(_kConditionTabEnabledKey));
