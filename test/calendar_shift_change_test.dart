import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/theme/calendar_layout_contract.dart';
import 'package:shiftbell/theme/calendar_reading_palette.dart';
import 'package:shiftbell/widgets/calendar_shift_change.dart';
import 'package:shiftbell/widgets/contract_calendar_cell.dart';
import 'package:shiftbell/widgets/detail_calendar_cell.dart';
import 'package:shiftbell/widgets/global_concept_calendar_cell.dart';
import 'package:shiftbell/widgets/shift_chip_label.dart';
import 'package:shiftbell/widgets/wide_calendar_cell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.isWindows) {
      final bytes = await File('C:/Windows/Fonts/malgun.ttf').readAsBytes();
      await (FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });

  test(
      'first rest only gets rest color, other names use deterministic next colors',
      () {
    for (final theme in CalendarThemeId.values) {
      for (final names in [
        ['주간', '휴무', '연휴', '야간', '휴가', '패턴외'],
        ['Day', 'Off', 'Leave', 'Night', 'Vacation', 'Extra'],
      ]) {
        final colors = effectiveShiftColors(names, theme, null);
        final rest = theme == CalendarThemeId.periwinkle
            ? kPeriwinkleRestColor
            : kMainRestColor;
        expect(colors[names[1]], rest);
        expect(colors.values.where((c) => c == rest), hasLength(1));
        expect(colors.values.toSet(), hasLength(names.length));
        expect(colors, effectiveShiftColors(names, theme, null));
        expect(colors[names.last], isNotNull,
            reason: 'Inactive names use shiftTypes, not pattern');
      }
    }
  });
  test('editor preserves existing colors and adds seven distinct theme defaults', () {
    final old = [...ShiftSchedule.shiftPalette, ShiftSchedule.offColor];
    final options = editableShiftColors(old);
    expect(options.take(old.length), old);
    expect(options.toSet(), hasLength(options.length));
    expect(options.length, old.length + 7);
    expect(options, hasLength(40));
    final names = ['휴무', ...List.generate(20, (i) => '근무$i')];
    final defaults = {for (final theme in CalendarThemeId.values)
      ...assignShiftColorsForTheme(names, theme).values};
    final candidates = defaults.difference(old.toSet());
    for (final color in kAdditionalEditorShiftColors) {
      expect(candidates, contains(color));
    }
    final report = {'previousOptions':old.length,'themeDefaults':defaults.length,
      'missingDefaultCandidates':candidates.length,'added':kAdditionalEditorShiftColors.length,
      'totalOptions':options.length,
      'addedHex':kAdditionalEditorShiftColors.map((c) => c.toARGB32().toRadixString(16)).toList()};
    File('artifacts/shift_change_2026_10_16/palette_audit.txt')
      ..parent.createSync(recursive:true)..writeAsStringSync(report.toString());
  });
  test(
      'main cached automatic rest repeats are repaired without changing custom hues',
      () {
    final saved = {
      '주간': kMainLightPalette.first.toARGB32(),
      '휴무': kMainRestColor.toARGB32(),
      '휴가': kMainRestColor.toARGB32(),
      '야간': kMainLightPalette[1].toARGB32()
    };
    final result = mainCalendarShiftColors(saved.keys.toList(), saved, null);
    expect(result['주간']!.toARGB32(), saved['주간']);
    expect(result['야간']!.toARGB32(), saved['야간']);
    expect(result.values.toSet(), hasLength(4));
    final explicit = mainCalendarShiftColors(
        saved.keys.toList(), saved, {'휴가': Colors.pink.toARGB32()});
    expect(explicit['휴가']!.toARGB32(), Colors.pink.toARGB32());
  });
  test(
      'palette exhaustion remains deterministic rather than claiming unlimited uniqueness',
      () {
    final names = List.generate(12, (i) => '근무$i');
    final colors = assignShiftColorsForTheme(names, CalendarThemeId.mainWhite);
    expect(colors[names.first], colors[names.last]);
  });
  test(
      'changed periwinkle dates split runs, unchanged neighbouring dates still join',
      () {
    final day = DateTime(2026, 10, 7);
    bool changed(DateTime d) => d.day == 7;
    expect(
        calendarShiftRun(day, DateTime.sunday, (_) => 'Night',
            separatesDay: changed),
        (index: 0, length: 1));
    expect(
        calendarShiftRun(DateTime(2026, 10, 8), DateTime.sunday, (_) => 'Night',
            separatesDay: changed),
        (index: 0, length: 3));
  });
  test('only three excluded themes and actual pattern changes opt in', () {
    expect(
        CalendarThemeId.values
            .where((t) => !CalendarShiftChangeScope.supports(t)),
        [
          CalendarThemeId.initialBadge,
          CalendarThemeId.underline,
          CalendarThemeId.editorial
        ]);
    expect(CalendarShiftChangeScope.isChanged('주간', '야간'), isTrue);
    for (final pair in [
      ('', '야간'),
      ('미설정', '야간'),
      ('주간', '미설정'),
      ('주간', '주간')
    ]) {
      expect(CalendarShiftChangeScope.isChanged(pair.$1, pair.$2), isFalse);
    }
  });

  testWidgets(
      'split glyph pixels equal their corresponding complete original/current renders',
      (tester) async {
    const label = '야간야간야간';
    const key = ValueKey('capture');
    Future<Uint8List> draw(Color bg, Color fg, Color? original,
        Color? originalInk, String name) async {
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                      width: 120,
                      height: 36,
                      child: CalendarShiftChangeScope(
                          originalColor: original,
                          originalInk: originalInk,
                          child: CalendarShiftChange(
                              background: bg,
                              foreground: fg,
                              builder: (b, f) => ColoredBox(
                                  color: b,
                                  child: ShiftChipLabel(
                                      label: label,
                                      color: f,
                                      proportions: ShiftChipProportions
                                          .calendarReview)))))))));
      await tester.pump();
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      return (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final file = File('artifacts/shift_change_2026_10_16/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png.buffer.asUint8List());
        image.dispose();
        return data;
      }))!;
    }

    for (final invert in [false, true]) {
      final oldBg = invert ? Colors.white : Colors.black,
          oldFg = invert ? Colors.black : Colors.white;
      final bg = oldFg, fg = oldBg;
      final old = await draw(oldBg, oldFg, null, null, 'original-$invert');
      final current = await draw(bg, fg, null, null, 'current-$invert');
      final split = await draw(bg, fg, oldBg, oldFg, 'split-$invert');
      var oldInkPixels = 0;
      for (var y = 0; y < 36; y++)
        for (var x = 0; x < 120; x++) {
          final offset = (y * 120 + x) * 4;
          final expected = x < 24 ? old : current;
          for (var c = 0; c < 4; c++)
            expect(split[offset + c], expected[offset + c],
                reason: '$invert $x/$y/$c');
          if (x < 24 && old[offset] != (invert ? 255 : 0)) oldInkPixels++;
        }
      expect(oldInkPixels, greaterThan(0),
          reason:
              'The original area must contain glyph pixels, not only a background');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('two white-ink shifts keep the same ink on both sides', (tester) async {
    await tester.pumpWidget(MaterialApp(home:Center(child:SizedBox(width:80,height:28,
      child:CalendarShiftChangeScope(originalColor:const Color(0xFF4DCB51),
        originalInk:Colors.white,child:CalendarShiftChange(background:Colors.black,
          foreground:Colors.white,builder:(bg,fg)=>ColoredBox(color:bg,
            child:ShiftChipLabel(label:'야간',color:fg))))))));
    final labels=tester.widgetList<ShiftChipLabel>(find.byType(ShiftChipLabel));
    expect(labels,hasLength(2));
    expect(labels.every((label)=>label.color==Colors.white),isTrue);
  });

  testWidgets(
      'shared renderers keep chip geometry for changed and unchanged names',
      (tester) async {
    final palette = CalendarReadingPalette(AppUiPalette.blue, dark: false);
    for (final theme in CalendarThemeId.values) {
      Widget cell() {
        final profile = CalendarLayoutProfile.forTheme(theme);
        final detail = CalendarDetailProfile.forTheme(theme);
        if (profile != null)
          return ContractCalendarCell(
              profile: profile,
              palette: palette,
              day: 7,
              shift: '야간',
              shiftColor: Colors.white,
              shiftTextColor: Colors.black,
              memos: const [],
              isToday: false,
              isOutside: false,
              isRed: false,
              flushTop: false);
        if (detail != null)
          return DetailCalendarCell(
              profile: detail,
              palette: palette,
              day: 7,
              shift: '야간',
              shiftColor: Colors.white,
              shiftTextColor: Colors.black,
              memos: const [],
              today: false,
              outside: false,
              red: false,
              selected: false);
        if (theme == CalendarThemeId.periwinkle ||
            theme == CalendarThemeId.softMosaic)
          return GlobalConceptCalendarCell(
              theme: theme,
              date: DateTime(2026, 10, 7),
              shift: 'Night',
              shiftColor: Colors.white,
              shiftTextColor: Colors.black,
              memos: const [],
              today: false,
              outside: false,
              red: false,
              selected: false);
        return WideCalendarCell(
            theme: theme,
            day: 7,
            shift: 'Night',
            shiftColor: Colors.white,
            shiftTextColor: Colors.black,
            memos: const [],
            isToday: false,
            isOutside: false,
            isRed: false);
      }

      final supported = CalendarShiftChangeScope.supports(theme);
      for (final changed in [false, true]) {
        await tester.pumpWidget(MaterialApp(
            home: Center(
                child: SizedBox(
                    width: 64,
                    height: 130,
                    child: CalendarShiftChangeScope(
                        originalColor:
                            changed && supported ? Colors.black : null,
                        originalInk: changed && supported ? Colors.white : null,
                        child: cell())))));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: theme.name);
        expect(find.descendant(of: find.byType(CalendarShiftChange), matching: find.byType(IgnorePointer)),
            changed && supported ? findsWidgets : findsNothing);
      }
    }
  });
}
