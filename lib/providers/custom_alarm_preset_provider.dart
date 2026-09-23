// lib/providers/custom_alarm_preset_provider.dart
//
// ⭐ 2026-09-23 (1.0.24 B) - 달력 상단 커스텀 알람 5칸 상태(SharedPreferences 'custom_alarm_presets').
// 백업 복원으로 설정이 바뀌면 앱이 재시작되므로(app_restart.dart) 별도 무효화 없이 새로 읽힌다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_alarm_preset.dart';

class CustomAlarmPresetsNotifier extends StateNotifier<List<CustomAlarmPreset>> {
  CustomAlarmPresetsNotifier()
      : super(List<CustomAlarmPreset>.filled(kCustomAlarmPresetCount, CustomAlarmPreset.empty)) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = CustomAlarmPreset.decodeList(prefs.getString(kCustomAlarmPresetsPrefKey));
  }

  /// 5칸 전체를 한 번에 저장(편집 시트의 "저장").
  Future<void> saveAll(List<CustomAlarmPreset> presets) async {
    final normalized = CustomAlarmPreset.decodeList(CustomAlarmPreset.encodeList(presets));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kCustomAlarmPresetsPrefKey, CustomAlarmPreset.encodeList(normalized));
    if (mounted) state = normalized;
  }
}

final customAlarmPresetsProvider =
    StateNotifierProvider<CustomAlarmPresetsNotifier, List<CustomAlarmPreset>>(
        (ref) => CustomAlarmPresetsNotifier());
