import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/services/app_analytics.dart';

/// 대시보드(admin_dashboard)가 보여 주는 이벤트 목록과 앱이 실제로 보내는 이벤트 목록이
/// 어긋나면(이름 변경·추가 후 한쪽만 고침) 대시보드에 "이름 없는 이벤트"가 뜨거나 항목이 비어 있게 된다.
Set<String> _dashboardCustomEvents() {
  final src = File('admin_dashboard/public/assets/js/labels.js').readAsStringSync();
  final re = RegExp(r"^\s+([a-z][a-z0-9_]*): \{[^\n]*group: '([^']+)'", multiLine: true);
  return {
    for (final m in re.allMatches(src))
      if (m.group(2) != 'system') m.group(1)!,
  };
}

Map<String, Object?> _row(int id, String type, DateTime ring) => {
      'id': id,
      'dismiss_type': type,
      'actual_ring_time': ring.toIso8601String(),
    };

void main() {
  group('이벤트 이름', () {
    test('GA4 규칙(소문자 시작·영문 소문자/숫자/밑줄·40자 이하, 예약 접두어 금지)', () {
      final valid = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
      for (final name in AnalyticsEvent.all) {
        expect(valid.hasMatch(name), isTrue, reason: name);
        expect(name.startsWith('firebase_') || name.startsWith('google_') || name.startsWith('ga_'), isFalse, reason: name);
      }
      expect(AnalyticsEvent.all.toSet().length, AnalyticsEvent.all.length, reason: '중복 이름');
    });

    test('앱 이벤트 목록 == 대시보드 labels.js의 사용자 이벤트 목록', () {
      expect(_dashboardCustomEvents(), AnalyticsEvent.all.toSet());
    });

    test('탭 이름은 main.dart의 5개 탭과 같은 순서', () {
      expect(kAnalyticsTabNames, ['next_alarm', 'schedule', 'calendar', 'sleep_recovery', 'settings']);
    });
  });

  group('AppAnalytics.track', () {
    tearDown(() => AppAnalytics.debugSink = null);

    test('이름과 분류 파라미터를 그대로 전달하고 예외를 던지지 않는다', () {
      final got = <String>[];
      AppAnalytics.debugSink = (name, params) => got.add('$name|${params ?? {}}');
      AppAnalytics.track(AnalyticsEvent.onboardingComplete, params: {'schedule_type': 'regular'});
      AppAnalytics.track(AnalyticsEvent.memoSaved);
      expect(got, ['onboarding_complete|{schedule_type: regular}', 'memo_saved|{}']);
    });

    test('싱크가 예외를 던져도 호출부로 새지 않는다', () async {
      AppAnalytics.debugSink = (_, __) => throw StateError('boom');
      expect(() => AppAnalytics.track(AnalyticsEvent.helpOpened), returnsNormally);
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('AlarmUsageAnalytics.reportNew', () {
    final now = DateTime(2026, 9, 22, 12);
    late List<String> sent;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      sent = [];
      AppAnalytics.debugSink = (name, _) => sent.add(name);
    });
    tearDown(() => AppAnalytics.debugSink = null);

    test('계측 첫 실행: 옛 이력은 보내지 않고 기준선(최대 id)만 저장', () async {
      await AlarmUsageAnalytics.reportNew(
        now: now,
        maxId: () async => 57,
        rowsSince: (_) async => fail('첫 실행에는 이력을 조회하지 않아야 함'),
      );
      expect(sent, isEmpty);
      expect((await SharedPreferences.getInstance()).getInt(AlarmUsageAnalytics.cursorKey), 57);
    });

    test('새 이력만 종류별로 매핑, ringing/removed·72시간보다 오래된 이력은 제외, 커서는 끝까지 전진', () async {
      SharedPreferences.setMockInitialValues({AlarmUsageAnalytics.cursorKey: 10});
      final rows = [
        _row(11, 'swiped', now.subtract(const Duration(hours: 5))),
        _row(12, 'snoozed', now.subtract(const Duration(hours: 4))),
        _row(13, 'timeout', now.subtract(const Duration(hours: 3))),
        _row(14, 'ringing', now.subtract(const Duration(hours: 2))),
        _row(15, 'removed', now.subtract(const Duration(hours: 2))),
        _row(16, 'swiped', now.subtract(const Duration(days: 30))), // 복원 등으로 들어온 옛 이력
      ];
      int? askedAfter;
      await AlarmUsageAnalytics.reportNew(
        now: now,
        maxId: () async => fail('기준선이 있으면 호출되지 않아야 함'),
        rowsSince: (after) async {
          askedAfter = after;
          return rows;
        },
      );
      expect(askedAfter, 10);
      expect(sent, [AnalyticsEvent.alarmDismissed, AnalyticsEvent.alarmSnoozed, AnalyticsEvent.alarmNoResponse]);
      expect((await SharedPreferences.getInstance()).getInt(AlarmUsageAnalytics.cursorKey), 16);
    });

    test('한꺼번에 몰려도 종류별 상한만 보내고, 나머지도 다시 보내지 않도록 커서는 전진', () async {
      SharedPreferences.setMockInitialValues({AlarmUsageAnalytics.cursorKey: 0});
      final rows = [
        for (var i = 1; i <= 100; i++) _row(i, 'swiped', now.subtract(const Duration(hours: 1))),
      ];
      await AlarmUsageAnalytics.reportNew(now: now, maxId: () async => 0, rowsSince: (_) async => rows);
      expect(sent.length, AlarmUsageAnalytics.maxPerType);
      expect((await SharedPreferences.getInstance()).getInt(AlarmUsageAnalytics.cursorKey), 100);
    });

    test('연속 호출 시 같은 이력을 두 번 보내지 않는다', () async {
      SharedPreferences.setMockInitialValues({AlarmUsageAnalytics.cursorKey: 0});
      final all = [_row(1, 'swiped', now.subtract(const Duration(hours: 1)))];
      Future<List<Map<String, Object?>>> since(int after) async => all.where((r) => (r['id'] as int) > after).toList();

      await AlarmUsageAnalytics.reportNew(now: now, maxId: () async => 0, rowsSince: since);
      await AlarmUsageAnalytics.reportNew(now: now, maxId: () async => 0, rowsSince: since);
      expect(sent, [AnalyticsEvent.alarmDismissed]);
    });

    test('조회가 실패해도 예외를 던지지 않고 커서를 건드리지 않는다', () async {
      SharedPreferences.setMockInitialValues({AlarmUsageAnalytics.cursorKey: 5});
      await AlarmUsageAnalytics.reportNew(
        now: now,
        maxId: () async => 0,
        rowsSince: (_) async => throw StateError('db closed'),
      );
      expect(sent, isEmpty);
      expect((await SharedPreferences.getInstance()).getInt(AlarmUsageAnalytics.cursorKey), 5);
    });
  });
}
