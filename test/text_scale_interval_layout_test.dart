import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/layout_limits.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/widgets/app_text_scale.dart';
import 'package:shiftbell/widgets/calendar_header_actions.dart';
import 'package:shiftbell/widgets/team_assignment_grid.dart';

void main() {
  setUpAll(() async {
    if (Platform.isWindows) {
      final bytes = await File('C:/Windows/Fonts/malgun.ttf').readAsBytes();
      await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  for (final locale in ['ko', 'en']) {
    testWidgets('fractional header and 40-position chips $locale', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [320.0, 360.0, 500.0, 501.0, 752.0]) {
        tester.view.physicalSize = Size(width, 840);
        for (var step = 0; step <= 30; step++) {
          final scale = 1 + step / 100;
          await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(360, 780),
            builder: (context, _) {
              ScreenUtil.configure(data: appContentMediaQuery(MediaQueryData.fromView(View.of(context))),
                  designSize: const Size(360, 780));
              return MaterialApp(
                locale: Locale(locale),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: AppTextScale(child: child!),
                ),
                home: Scaffold(body: SingleChildScrollView(child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    SizedBox(height: 40, child: CalendarTitleActionsRow(
                      title: Text(locale == 'ko' ? '2026년 10월' : 'September 2026',
                          key: const ValueKey('header-month'), style: const TextStyle(fontSize: 24)),
                      actions: CalendarHeaderActions(onToday: () {}, onAllShifts: () {},
                        onFriends: () {}, onOneTap: () {}, isKorean: locale == 'ko', editorial: true))),
                    TeamAssignmentGrid(
                      pattern: List.generate(40, (i) => locale == 'ko' ? '야간집중근무' : 'Late Night Shift'),
                      teamAtSlot: (i) => i < 6 ? '$i' : null,
                      isMine: (i) => i == 2, onTapSlot: (_) {},
                    ),
                  ]),
                ))),
              );
            },
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$locale width=$width scale=$scale');
          final month = tester.getRect(find.byKey(const ValueKey('header-month')));
          final alarm = tester.getRect(find.byKey(const ValueKey('one-tap-open')));
          expect(month.center.dy, closeTo(alarm.center.dy, .01));
          expect(month.right, lessThan(alarm.left));
          for (final button in find.byType(TextButton).evaluate()) {
            final rect = tester.getRect(find.byElementPredicate((e) => identical(e, button)));
            expect(rect.center.dy, closeTo(alarm.center.dy, .01));
            expect(rect.right, lessThanOrEqualTo(width - 12 + .01));
          }
          for (final element in find.byType(TeamAssignmentChip).evaluate()) {
            final rect = tester.getRect(find.byElementPredicate((e) => identical(e, element)));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width + .01));
          }
        }
      }
    });
  }
}
