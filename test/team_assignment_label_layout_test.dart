import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/layout_limits.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/widgets/team_assignment_grid.dart';

void main() {
  for (final width in [320.0, 360.0, 480.0, 600.0, 806.0, 1000.0]) {
    for (final language in ['ko', 'en', 'de', 'pt', 'hi']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('default assignment names remain readable $width $language $scale', (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          late List<String> shifts;
          await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(360, 780),
            builder: (context, _) {
              ScreenUtil.configure(
                data: appContentMediaQuery(MediaQueryData.fromView(View.of(context))),
                designSize: const Size(360, 780),
              );
              return MaterialApp(
                locale: Locale(language),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(body: Builder(builder: (context) {
                  final l = AppLocalizations.of(context);
                  shifts = [l.shiftDay, l.shiftNight, l.shiftDayOff, l.shiftMorning, l.shiftAfternoon];
                  return SingleChildScrollView(child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: TeamAssignmentGrid(
                      pattern: shifts,
                      teamAtSlot: (_) => 'A',
                      isMine: (_) => false,
                      onTapSlot: (_) {},
                    ),
                  ));
                })),
              );
            },
          ));
          await tester.pumpAndSettle();
          for (final shift in shifts) {
            final text = find.text(shift);
            expect(text, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(text);
            expect(paragraph.didExceedMaxLines, isFalse, reason: '$shift at $width / $language / $scale');
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  for (final width in [320.0, 360.0, 806.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('long labels fit unchanged cell geometry $width $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var labels = List.generate(12, (i) => 'D$i');
        late StateSetter updateLabels;
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(360, 780),
          builder: (context, _) {
            ScreenUtil.configure(
              data: appContentMediaQuery(
                  MediaQueryData.fromView(View.of(context))),
              designSize: const Size(360, 780),
            );
            return MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: StatefulBuilder(builder: (context, setState) {
                      updateLabels = setState;
                      return TeamAssignmentGrid(
                        pattern: labels,
                        teamAtSlot: (i) => i < 4 ? 'ABCD'[i] : null,
                        isMine: (i) => i == 0,
                        selectedIndex: 1,
                        onTapSlot: (_) {},
                      );
                    }),
                  ),
                ),
              ),
            );
          },
        ));
        await tester.pumpAndSettle();
        final before = List.generate(12,
            (i) => tester.getRect(find.byKey(ValueKey('team-assign-slot-$i'))));
        final firstRow = before.where((rect) => rect.top == before.first.top);
        expect(firstRow.length, lessThanOrEqualTo(5));
        if (scale == 1) expect(firstRow.length, 5);
        updateLabels(() {
          labels = const [
            'Day',
            'Day Off',
            'Night Shift',
            'Bereitschaft',
            'iiiiiiiiiiii',
            'WWW WWW WWWW',
            '야간집중근무',
            'दोपहर',
            'Early',
            'Late',
            '휴무',
            'Leave',
          ];
        });
        await tester.pumpAndSettle();
        for (var i = 0; i < labels.length; i++) {
          final cell =
              tester.getRect(find.byKey(ValueKey('team-assign-slot-$i')));
          expect(cell, before[i], reason: 'Name must not change cell size');
          final finder = find.text(labels[i]);
          final text = tester.widget<Text>(finder);
          expect(text.maxLines, 1);
          expect(text.softWrap, isFalse);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          expect(paragraph.didExceedMaxLines, isFalse);
          final ink = tester.getRect(finder);
          expect(ink.left, greaterThanOrEqualTo(cell.left));
          expect(ink.right, lessThanOrEqualTo(cell.right + .01));
          expect(ink.top, greaterThanOrEqualTo(cell.top));
          expect(ink.bottom, lessThanOrEqualTo(cell.bottom + .01));
          final shortText = tester.widget<Text>(find.text('Day'));
          expect(text.style!.fontSize, shortText.style!.fontSize);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
