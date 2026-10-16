import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/all_shifts_view.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/widgets/all_shifts_timeline_metrics.dart';
import 'package:shiftbell/widgets/app_shift_chip.dart';
import 'package:shiftbell/widgets/shift_chip_label.dart';
import 'package:shiftbell/widgets/shift_label_layout.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('RosterPhaseTest')
          ..addFont(Future.value(ByteData.sublistView(
              File('C:/Windows/Fonts/malgun.ttf').readAsBytesSync()))))
        .load();
  });
  for (final names in [
    const ['주간', '야간'],
    const ['주간', '특별연장근무']
  ]) {
    testWidgets('two bounded sizes and larger labels: $names', (t) async {
      t.view.physicalSize = const Size(411.43, 891.43);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await t.pumpWidget(ScreenUtilInit(
          designSize: const Size(360, 780),
          builder: (_, __) => MaterialApp(
              theme: ThemeData(fontFamily: 'RosterPhaseTest'),
              locale: const Locale('ko'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: Scaffold(
                  body: RepaintBoundary(
                      key: boundary,
                      child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.w),
                          child: MonthShiftTable(
                              year: 2026,
                              month: 10,
                              lastDay: 31,
                              teams: const ['A', 'B', 'C', 'D'],
                              myTeam: 'C',
                              teamOffsets: const {
                                'A': 0,
                                'B': 1,
                                'C': 0,
                                'D': 1
                              },
                              baseDate: DateTime(2026, 10, 1),
                              pattern: names,
                              shiftColorMap: {
                                for (final name in names) name: Colors.indigo
                              },
                              isViewingCurrentRealMonth: false,
                              onPrevMonth: () {},
                              onNextMonth: () {})))))));
      await t.pumpAndSettle();
      final tableContext = t.element(find.byType(MonthShiftTable));
      final style = TextStyle(
          fontSize: 13.sp,
          height: 1.15,
          fontWeight: FontWeight.w600,
          leadingDistribution: TextLeadingDistribution.even);
      final original = ShiftCellMetrics.forNames(
          const ['가나'], style, MediaQuery.textScalerOf(tableContext),
          minWidth: 40.w, minHeight: 36.h);
      final chips = find.byType(AppShiftChip);
      final first = t.getRect(chips.first);
      final stride = t.getRect(chips.at(1)).left - first.left;
      final expanded = names.last == '특별연장근무';
      final preferred = original.width *
          (expanded ? 1 : AllShiftsTimelineMetrics.compactScale);
      final viewport =
          t.getRect(find.byKey(const ValueKey('roster-timeline-days-1')));
      expect(
          stride,
          closeTo(
              AllShiftsTimelineMetrics.fittedColumnWidth(
                  viewport.width, preferred),
              .001));
      expect(first.width, lessThanOrEqualTo(preferred));
      if (!expanded) {
        for (final pair in [(1, 8), (16, 23)]) {
          final rect = t
              .getRect(find.byKey(ValueKey('roster-timeline-days-${pair.$1}')));
          final lastDate = t.getRect(find.text('${pair.$2}'));
          expect(rect.width / stride, closeTo(8, .001));
          expect(lastDate.right, lessThanOrEqualTo(rect.right));
        }
      }
      expect(
          first.height,
          closeTo(
              original.height *
                      (expanded ? 1 : AllShiftsTimelineMetrics.compactScale) -
                  2 * 1.3.w,
              .001));
      for (final name in names) {
        final label =
            find.descendant(of: chips, matching: find.text(name)).first;
        final actual = t.widget<Text>(label).style!.fontSize!;
        final oldAvailable = Size(
            original.width - 2 * (1.3.w + 3 + AppShiftChip.denseBorderWidth),
            original.height - 2 * (1.3.w + 3 + AppShiftChip.denseBorderWidth));
        final before = ShiftChipLabel.fit(t.element(label), name,
            density: AppChipSize.compact, available: oldAvailable);
        expect(actual, greaterThan(before.style.fontSize!),
            reason: 'Both size phases enlarge labels');
        expect(
            t.renderObject<RenderParagraph>(label).didExceedMaxLines, isFalse);
      }
      final narrow = AllShiftsTimelineMetrics.measure(
          tableContext, const ['iiii'], style, TextScaler.noScaling);
      final wide = AllShiftsTimelineMetrics.measure(
          tableContext, const ['WWWW'], style, TextScaler.noScaling);
      expect(narrow.large, isFalse);
      expect(wide.large, isTrue,
          reason: 'Same character count, different measured widths');
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final capture = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final data = await capture.toByteData(format: ui.ImageByteFormat.png);
        await Directory('artifacts/roster_swipe_2026_10_16/renders')
            .create(recursive: true);
        await File('artifacts/roster_swipe_2026_10_16/renders/phase-' +
                (expanded ? 'expanded' : 'compact') +
                '.png')
            .writeAsBytes(data!.buffer.asUint8List());
        capture.dispose();
      });
    });
  }
}
