// lib/services/holiday_sync_service.dart
//
// ⭐ 2026-09-23 (1.0.24 D) - 공휴일 원격 갱신. 대체·임시공휴일이 갑자기 생겨도 앱 업데이트 없이 Firebase에서 고치면 반영된다.
//
// 흐름(Firestore 읽기를 최소로):
//  1. 앱 시작 → [loadCached]: 마지막으로 받은 변경분을 SharedPreferences에서 읽어 HolidayOverrides.current에 적용(네트워크 없음)
//  2. 업데이트 안내 확인(update_service.dart, 기기당 6시간에 최대 1번)이 이미 읽는 `app_config/android` 문서의
//     `holidaysVersion` 숫자만 비교 → 캐시 버전보다 클 때만 [syncIfNeeded]가 `app_config/holidays_kr`를 **1번** 읽음
//  3. 받은 값 저장 → 달력(Dart)에 즉시 적용 → 홈 위젯용 날짜 목록을 네이티브에 넘기고 위젯 갱신
// 보안 규칙: 기존 `match /app_config/{document}`(get만 허용, write 거부)로 충분 - 규칙 변경 없음.
// 운영 방법: docs/next_version/1.0.24_구현계획.md D절, 업데이트_가이드.md "공휴일".

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/platform_channel.dart';
import '../utils/holiday_util.dart';
import 'widget_refresh_service.dart';

class HolidaySyncService {
  HolidaySyncService._();
  static final HolidaySyncService instance = HolidaySyncService._();

  static const cachePrefKey = 'holiday_overrides_json';
  static const docPath = 'app_config/holidays_kr';

  /// 시작 시 캐시 적용. 실패해도 하드코딩 목록으로 계속 동작.
  Future<void> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cachePrefKey);
      if (raw == null) return;
      HolidayOverrides.current = HolidayOverrides.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('⚠️ 공휴일 캐시 읽기 실패(하드코딩 목록 사용): $e');
    }
  }

  /// [remoteVersion]은 `app_config/android.holidaysVersion`. 캐시보다 클 때만 문서를 읽어 적용.
  Future<void> syncIfNeeded(Object? remoteVersion) async {
    if (remoteVersion is! num) return;
    final version = remoteVersion.toInt();
    if (version <= HolidayOverrides.current.version) return;
    try {
      final doc = await FirebaseFirestore.instance.doc(docPath).get();
      final data = doc.data();
      if (data == null) return;
      final overrides = HolidayOverrides.fromJson(data);
      // 문서의 version이 안내 번호보다 낮으면(수정 도중) 이번엔 적용하지 않고 다음 확인 때 다시
      if (overrides.version < version) return;
      await apply(overrides);
    } catch (e) {
      debugPrint('⚠️ 공휴일 원격 갱신 실패(다음 확인 때 재시도): $e');
    }
  }

  /// 저장 + 달력 적용 + 위젯(네이티브) 반영.
  Future<void> apply(HolidayOverrides overrides) async {
    HolidayOverrides.current = overrides;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cachePrefKey, jsonEncode(overrides.toJson()));
    if (kIsWeb) return;
    try {
      await kAlarmChannel.invokeMethod('setHolidayOverrides', {
        'add': overrides.add.keys.toList(),
        'remove': overrides.remove.toList(),
      });
      await WidgetRefreshService.refresh();
    } catch (e) {
      debugPrint('⚠️ 위젯 공휴일 반영 실패: $e');
    }
  }

  /// 웹 뷰어용 - 캐시 없이 페이지를 열 때 1번 읽음.
  Future<void> loadForWeb() async {
    try {
      final doc = await FirebaseFirestore.instance.doc(docPath).get();
      HolidayOverrides.current = HolidayOverrides.fromJson(doc.data());
    } catch (e) {
      debugPrint('⚠️ 웹 공휴일 원격 값 읽기 실패(하드코딩 목록 사용): $e');
    }
  }
}
