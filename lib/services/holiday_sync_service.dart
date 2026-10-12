// App-only holiday overrides. The web viewer uses the bundled holiday list.
// Each installation draws its first check date from a 7-day window, then
// checks again 14 days after a successful read. This spreads reads over time;
// it does not enforce a global daily quota.

import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/platform_channel.dart';
import '../utils/holiday_util.dart';
import 'firebase_bootstrap.dart';
import 'widget_refresh_service.dart';

class HolidaySyncService {
  HolidaySyncService._();
  static final HolidaySyncService instance = HolidaySyncService._();

  static const cachePrefKey = 'holiday_overrides_json';
  // New key resets the old dev-only 30-day schedule when this policy ships.
  static const nextCheckPrefKey = 'holiday_next_check_v2_at_ms';
  static const _oldNextCheckPrefKey = 'holiday_next_check_at_ms';
  static const docPath = 'app_config/holidays_kr';
  static const firstCheckWindow = Duration(days: 7);
  static const checkInterval = Duration(days: 14);
  static const retryInterval = Duration(days: 1);

  bool _checkInProgress = false;
  bool get _koreanLanguage => WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ko';

  /// Show the last verified result while offline or before the first check.
  Future<void> loadCached() async {
    if (!_koreanLanguage) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_koreanLanguage) return;
      final raw = prefs.getString(cachePrefKey);
      if (raw == null) return;
      HolidayOverrides.current =
          HolidayOverrides.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      await _applyToNative(HolidayOverrides.current);
    } catch (e) {
      debugPrint('공휴일 캐시 읽기 실패(기본 목록 사용): $e');
    }
  }

  /// No read on every launch: first check is spread over 7 days; after a
  /// successful read the next one is 14 days later. Failures retry in 1-2 days.
  Future<void> refreshIfDue() async {
    if (kIsWeb || !firebaseReady || _checkInProgress ||
        !_koreanLanguage) return;
    _checkInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_koreanLanguage) return;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final dueMs = prefs.getInt(nextCheckPrefKey);
      if (dueMs == null) {
        await prefs.setInt(
          nextCheckPrefKey,
          nowMs + Random().nextInt(firstCheckWindow.inMilliseconds),
        );
        await prefs.remove(_oldNextCheckPrefKey);
        return;
      }
      if (nowMs < dueMs) return;

      try {
        if (!_koreanLanguage) return;
        // A server read is required here: an offline SDK cache must not mark
        // this installation as checked for another 14 days.
        final doc = await FirebaseFirestore.instance
            .doc(docPath)
            .get(const GetOptions(source: Source.server));
        if (!_koreanLanguage) return;
        await apply(HolidayOverrides.fromJson(doc.data()));
        await prefs.setInt(
          nextCheckPrefKey,
          DateTime.now().millisecondsSinceEpoch + checkInterval.inMilliseconds,
        );
      } catch (e) {
        if (!_koreanLanguage) return;
        await prefs.setInt(
          nextCheckPrefKey,
          DateTime.now().millisecondsSinceEpoch + retryInterval.inMilliseconds +
              Random().nextInt(retryInterval.inMilliseconds),
        );
        debugPrint('공휴일 조회 실패(1~2일 뒤 재시도): $e');
      }
    } catch (e) {
      debugPrint('공휴일 확인 일정 처리 실패: $e');
    } finally {
      _checkInProgress = false;
    }
  }

  Future<void> apply(HolidayOverrides overrides) async {
    if (!_koreanLanguage) return;
    final prefs = await SharedPreferences.getInstance();
    if (!_koreanLanguage) return;
    if (!await prefs.setString(cachePrefKey, jsonEncode(overrides.toJson()))) {
      throw StateError('Holiday override cache could not be saved');
    }
    HolidayOverrides.current = overrides;
    await _applyToNative(overrides);
  }

  Future<void> _applyToNative(HolidayOverrides overrides) async {
    if (!_koreanLanguage) return;
    try {
      await kAlarmChannel.invokeMethod('setHolidayOverrides', {
        'add': overrides.add.keys.toList(),
        'remove': overrides.remove.toList(),
      });
      await WidgetRefreshService.refresh();
    } catch (e) {
      debugPrint('위젯 공휴일 반영 실패: $e');
    }
  }
}
