import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/platform_channel.dart';
import 'app_analytics.dart';
import 'firebase_bootstrap.dart' show analytics;

/// Bounded delayed observations; identifiers, log payload and alarm times stay local.
class OperationsAnalytics {
  OperationsAnalytics._();
  static const cursorKey = 'analytics_ops_seen_tokens';
  static const dailyKey = 'analytics_ops_snapshot_day';
  static bool _running = false;
  static const _observedEvents = <String>{
    AnalyticsEvent.alarmScheduleOk,
    AnalyticsEvent.alarmScheduleFailed,
    AnalyticsEvent.alarmFired,
    AnalyticsEvent.alarmRefreshCompleted,
    AnalyticsEvent.alarmRefreshFailed,
    AnalyticsEvent.deviceBootSeen,
  };
  static Future<void> report(
      {DateTime? now,
      Future<Map<dynamic, dynamic>?> Function()? snapshot}) async {
    if (kIsWeb || _running || appFlavor == 'dev') return;
    if (analytics == null && AppAnalytics.debugSink == null) return;
    _running = true;
    try {
      final data = await (snapshot ??
          () => kAlarmChannel
              .invokeMapMethod<dynamic, dynamic>('operationsSnapshot'))();
      if (data == null) return;
      final prefs = await SharedPreferences.getInstance();
      final at = now ?? DateTime.now();
      final day = at.year.toString() +
          '-' +
          at.month.toString() +
          '-' +
          at.day.toString();
      final rawBrand =
          (data['manufacturer'] ?? 'unknown').toString().trim().toLowerCase();
      const brands = {
        'samsung',
        'xiaomi',
        'vivo',
        'oppo',
        'realme',
        'motorola',
        'google',
        'infinix',
        'honor',
        'huawei',
        'oneplus',
        'tecno',
        'nothing'
      };
      final brand = brands.contains(rawBrand) ? rawBrand : 'other';
      final params = <String, Object>{'manufacturer': brand};
      final observations =
          (data['observations'] as List? ?? []).whereType<Map>().toList();
      final tokens =
          observations.map((r) => r['token']).whereType<String>().toSet();
      final previous = prefs.getStringList(cursorKey)?.toSet();
      if (previous != null) {
        final sent = <String, int>{};
        for (final row in observations) {
          final name = row['event'];
          final token = row['token'];
          final stamp = row['atMs'];
          if (name is! String ||
              token is! String ||
              stamp is! int ||
              previous.contains(token) ||
              !_observedEvents.contains(name) ||
              stamp <
                  at
                      .subtract(const Duration(hours: 72))
                      .millisecondsSinceEpoch ||
              stamp > at.millisecondsSinceEpoch ||
              (sent[name] ?? 0) >= 40) continue;
          AppAnalytics.track(name, params: params);
          sent[name] = (sent[name] ?? 0) + 1;
        }
      }
      // Establish a baseline on first use; skip overflow rather than replay it.
      await prefs.setStringList(cursorKey, tokens.take(1000).toList());
      if (prefs.getString(dailyKey) != day) {
        final states = data['permissions'] as Map? ?? {};
        final values = [
          'notification',
          'exactAlarm',
          'overlay',
          'fullScreen',
          'alarmChannel'
        ].map((key) => states[key]).toList();
        final status = values.contains('denied')
            ? AnalyticsEvent.opsDailyRestricted
            : values.every((v) => v == 'granted' || v == 'notApplicable')
                ? AnalyticsEvent.opsDailyReady
                : AnalyticsEvent.opsDailyUnknown;
        AppAnalytics.track(status, params: params);
        if (data['battery'] == 'restricted')
          AppAnalytics.track(AnalyticsEvent.opsBatteryRestricted,
              params: params);
        final denied = {
          'exactAlarm': AnalyticsEvent.opsExactDenied,
          'notification': AnalyticsEvent.opsNotificationBlocked,
          'alarmChannel': AnalyticsEvent.opsChannelBlocked,
          'fullScreen': AnalyticsEvent.opsFullscreenDenied
        };
        for (final entry in denied.entries) {
          if (states[entry.key] == 'denied')
            AppAnalytics.track(entry.value, params: params);
        }
        await prefs.setString(dailyKey, day);
      }
    } catch (e) {
      debugPrint('Operations observations unavailable: ' + e.toString());
    } finally {
      _running = false;
    }
  }
}
