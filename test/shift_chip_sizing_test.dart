import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/widgets/shift_chip_label.dart';

void main() {
  testWidgets(
      'short names use maximum; longer names shrink without truncation or wrapping',
      (tester) async {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final name in [
        'D',
        '주간',
        '특별연장근무',
        'Afternoon Shift',
        'Nachtschicht',
        'रात्रि ड्यूटी'
      ]) {
        double? previous;
        for (final width in [40.0, 64.0, 100.0]) {
          await tester.pumpWidget(MaterialApp(
              home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                      body: Center(
                          child: SizedBox(
                              width: width,
                              height: 24,
                              child: ShiftChipLabel(
                                  label: name, size: AppChipSize.regular)))))));
          await tester.pump();
          final text = tester.widget<Text>(find.text(name));
          final paragraph =
              tester.renderObject<RenderParagraph>(find.text(name));
          expect(text.maxLines, 1);
          expect(text.textScaler, TextScaler.noScaling);
          expect(paragraph.didExceedMaxLines, isFalse);
          final glyphs = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: name.length));
          expect(glyphs, isNotEmpty);
          for (final box in glyphs) {
            expect(box.right - box.left, lessThanOrEqualTo(width + .5));
          }
          expect(text.style!.fontSize, lessThanOrEqualTo(16));
          if (previous != null)
            expect(text.style!.fontSize, greaterThanOrEqualTo(previous!));
          previous = text.style!.fontSize;
          expect(tester.takeException(), isNull);
        }
      }
    }
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 100, height: 24, child: ShiftChipLabel(label: 'D')))));
    await tester.pump();
    expect(tester.widget<Text>(find.text('D')).style!.fontSize, 16);
  });
  testWidgets(
      'roster measurement cache preserves layout when text and space change',
      (t) async {
    final cache = ShiftChipFitCache();
    for (final width in [44.0, 28.0, 70.0, 44.0]) {
      for (final label in ['주간', '특별연장근무', 'Afternoon Shift']) {
        final sizes = <double>[];
        for (final cached in [false, true]) {
          Widget child = Center(
              child: SizedBox(
                  width: width,
                  height: 28,
                  child: ShiftChipLabel(label: label, fontScale: 1.08)));
          if (cached)
            child = ShiftChipFitCacheScope(cache: cache, child: child);
          await t.pumpWidget(MaterialApp(home: Scaffold(body: child)));
          await t.pump();
          sizes.add(t.widget<Text>(find.text(label)).style!.fontSize!);
          expect(
              t
                  .renderObject<RenderParagraph>(find.text(label))
                  .didExceedMaxLines,
              isFalse);
        }
        expect(sizes[1], sizes[0]);
      }
    }
    cache.clear();
    expect(t.takeException(), isNull);
  });
}
