import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/friend_schedule.dart';
import 'package:shiftbell/widgets/friend_web_calendar.dart';
import 'package:shiftbell/constants/layout_limits.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting();
    final bytes = await File('C:/Windows/Fonts/malgun.ttf').readAsBytes();
    await (FontLoader('CalendarTest')
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  });
  final schedule = FriendScheduleData(
    ownerName: '친구 이름이 아주 길어도 제목이 화면 밖으로 나가지 않아요',
    isRegular: true,
    pattern: ['주간근무', '야간근무', '휴무'],
    todayIndex: 0,
    startDate: DateTime(2026, 9, 1),
    shiftColors: const {
      '주간근무': 0xFF476DCD,
      '야간근무': 0xFF6C7025,
      '휴무': 0xFFF45151
    },
    assignedDates: const {},
    updatedAt: DateTime(2026, 9, 30, 6),
  );

  testWidgets('vertical drag over shared calendar reaches the footer', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 698);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate],
      theme: ThemeData(fontFamily: 'CalendarTest'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!),
      home: FriendWebCalendar(friendName: schedule.ownerName, data: schedule,
        initialDay: DateTime(2026, 10, 3), showInstallPrompt: true, showPwaAddressBarHint: true,
        showQuickInstallButton: true, onQuickInstallTap: () {}, onInstallTap: () {}),
    ));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.descendant(
      of: find.byKey(const ValueKey('friend-web-scroll')),
      matching: find.byType(Scrollable)).first).position;
    expect(scroll.maxScrollExtent, greaterThan(0));
    await tester.drag(find.byKey(const ValueKey('friend-web-grid')), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(scroll.pixels, greaterThan(0), reason: 'Calendar must not swallow vertical scrolling');
    expect(tester.getRect(find.byKey(const ValueKey('friend-web-app-banner'))).bottom,
      lessThanOrEqualTo(698));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long shared shift name stays visible on one line',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const longName = 'Afternoon Shift';
    final longSchedule = FriendScheduleData(
      ownerName: 'Test',
      isRegular: true,
      pattern: [longName],
      todayIndex: 0,
      startDate: DateTime(2026, 10, 1),
      shiftColors: const {'Afternoon Shift': 0xFF90CAF9},
      assignedDates: const {},
      updatedAt: DateTime(2026, 10, 1),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: FriendWebCalendar(
        friendName: longSchedule.ownerName,
        data: longSchedule,
        initialDay: DateTime(2026, 10, 1),
        showInstallPrompt: false,
        showPwaAddressBarHint: false,
        showQuickInstallButton: false,
        onQuickInstallTap: () {},
        onInstallTap: () {},
      ),
    ));
    await tester.pumpAndSettle();
    final labelFinder = find.byKey(const ValueKey('friend-shift-2026-10-01'));
    final label = tester.widget<Text>(labelFinder);
    expect(label.data, longName);
    expect(label.maxLines, 1);
    expect(label.softWrap, false);
    expect(label.overflow, isNot(TextOverflow.ellipsis));
    expect(
        tester
            .widget<FittedBox>(find
                .ancestor(of: labelFinder, matching: find.byType(FittedBox))
                .first)
            .fit,
        BoxFit.scaleDown);
    final band = tester
        .getRect(find.byKey(const ValueKey('friend-shift-band-2026-10-01')));
    final labelRect = tester.getRect(labelFinder);
    expect(labelRect.left, greaterThanOrEqualTo(band.left));
    expect(labelRect.right, lessThanOrEqualTo(band.right));
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(411.43, 780),
    const Size(411.43, 850),
    const Size(320, 568),
    const Size(360, 698), // Ultra cover, Chrome controls visible.
    const Size(752, 653), // Ultra inner, tab strip and taskbar visible.
    const Size(475, 605), // Fold8 cover, Chrome controls visible.
    const Size(932, 520), // Fold8 inner, tab strip and taskbar visible.
    const Size(475, 751), // Fold8 native cover.
    const Size(933, 530), // Fold8-like wide browser (not a device validation).
    const Size(780, 360)
  ]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      for (final banner in ['none', 'install', 'browser', 'app']) {
        testWidgets('$size scale=$scale banner=$banner', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var taps = 0;
          await tester.pumpWidget(MaterialApp(
            locale: const Locale('ko'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            theme: ThemeData(fontFamily: 'CalendarTest', useMaterial3: true),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: FriendWebCalendar(
                friendName: schedule.ownerName,
                data: schedule,
                initialDay: DateTime(2026, 9, 30),
                showInstallPrompt: banner != 'app',
                showPwaAddressBarHint: banner != 'browser',
                showQuickInstallButton: banner == 'install',
                onQuickInstallTap: () => taps++,
                onInstallTap: () => taps++),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final day in ['2026-09-24', '2026-09-30', '2026-10-05']) {
            Finder key(String prefix) =>
                find.byKey(ValueKey('$prefix-$day')).first;
            final cell = tester.getRect(key('friend-cell'));
            final badge = tester.getRect(key('friend-shift-band'));
            final date = tester.getRect(key('friend-date'));
            expect(date.bottom, lessThanOrEqualTo(cell.bottom + .1));
            expect(date.top, greaterThanOrEqualTo(badge.bottom));
            expect(date.center.dy,
                closeTo((badge.bottom + cell.bottom - 2) / 2, .2),
                reason: 'Date must stay centered in the body below the shift');
            expect(date.left, greaterThanOrEqualTo(cell.left));
            expect(date.right, lessThanOrEqualTo(cell.right));
            final label = tester.widget<Text>(key('friend-date'));
            if (size.width > 500) {
              expect(label.textScaler, TextScaler.noScaling);
              expect(label.style!.fontSize, 14);
            }
            final context = tester.element(key('friend-date'));
            final painter = TextPainter(
              text: TextSpan(
                  text: label.data,
                  style: DefaultTextStyle.of(context).style.merge(label.style)),
              textDirection: TextDirection.ltr,
              textScaler: label.textScaler ?? MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout();
            expect(date.width, greaterThanOrEqualTo(painter.width - .1),
                reason: 'Both digits must fit without horizontal clipping');
            painter.dispose();
            final effective =
                MediaQuery.textScalerOf(context).scale(label.style!.fontSize!);
            expect(effective,
                lessThanOrEqualTo(label.style!.fontSize! * 1.3 + .01));
            final holiday = find.byKey(ValueKey('friend-holiday-$day'));
            if (holiday.evaluate().isNotEmpty) {
              expect(tester.widget<Text>(holiday.first).maxLines, 1);
              final rect = tester.getRect(holiday.first);
              expect(rect.top, greaterThanOrEqualTo(badge.bottom));
              if (AppLayout(size).isShortCover ||
                  (size.width > 500 && size.aspectRatio >= 1.25)) {
                expect(rect.left, greaterThanOrEqualTo(date.right));
                expect(rect.center.dy, closeTo(date.center.dy, .2));
              } else {
                expect(rect.bottom, lessThanOrEqualTo(date.top + .1));
              }
            }
          }
          if (banner == 'install') {
            await tester.ensureVisible(find.text('바로가기 추가'));
            await tester.tap(find.text('바로가기 추가'));
            expect(taps, 1);
          }
          if (banner == 'app') {
            expect(find.byKey(const ValueKey('friend-web-app-banner')),
                findsNothing);
            expect(find.byKey(const ValueKey('friend-web-pwa-banner')),
                findsNothing);
          } else {
            await tester.ensureVisible(
                find.byKey(const ValueKey('friend-web-app-banner')));
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
