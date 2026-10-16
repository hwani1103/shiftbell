import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/widgets/app_ui_components.dart';
import 'onboarding_pattern_feedback_test.dart' show pumpOnboarding;

void main() {
  testWidgets(
      'indexed chips keep name centred and index at top-left at every density',
      (tester) async {
    for (final size in AppChipSize.values) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 90,
                      child: AppUiShiftChip(
                          name: 'Day',
                          index: 12,
                          badge: 'Today',
                          size: size))))));
      await tester.pump();
      final chip = tester.getRect(find.byType(AppUiShiftChip));
      final name = tester.getRect(find.text('Day'));
      final index = tester.getRect(find.text('12'));
      expect(name.center.dy, closeTo(chip.center.dy, .1));
      expect(index.left, greaterThanOrEqualTo(chip.left + 12));
      expect(index.left, lessThan(chip.center.dx));
      expect(index.top, closeTo(chip.top + 2, .1));
      Rect glyphBounds(String text) {
        final finder = find.text(text);
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        return paragraph
            .getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: text.length))
            .map((box) => box.toRect().shift(tester.getRect(finder).topLeft))
            .reduce((a, b) => a.expandToInclude(b));
      }

      expect(glyphBounds('12').overlaps(glyphBounds('Day')), isFalse,
          reason: 'visible index and name must not overlap');
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('shared four-column choices and fixed four-column pattern card',
      (tester) async {
    final l = await pumpOnboarding(
        tester, const Locale('ko'), const Size(400, 632), 1, GlobalKey());
    for (var i = 0; i < 3; i++) {
      await tester.ensureVisible(find.text(l.onboardingAddShiftName));
      await tester.tap(find.text(l.onboardingAddShiftName));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Z$i');
      await tester.tap(find.text(l.commonAdd));
      await tester.pumpAndSettle();
    }
    final names = find.byKey(const ValueKey('onboarding-shift-names'));
    final nameChips =
        find.descendant(of: names, matching: find.byType(AppUiShiftChip));
    expect(tester.getRect(nameChips.at(0)).top,
        tester.getRect(nameChips.at(3)).top);
    expect(tester.getRect(nameChips.at(4)).top,
        greaterThan(tester.getRect(nameChips.at(0)).top));
    expect(tester.getRect(names).height, 86);
    final nameScroll = tester.state<ScrollableState>(
        find.descendant(of: names, matching: find.byType(Scrollable)));
    expect(nameScroll.position.maxScrollExtent, greaterThan(0));
    final firstChip = tester.getSize(nameChips.first);
    await tester.tap(find.text(l.onboardingNextPattern));
    await tester.pumpAndSettle();
    final choices = find.byKey(const ValueKey('onboarding-shift-choices'));
    final secondChip = tester.getSize(find
        .descendant(of: choices, matching: find.byType(AppUiShiftChip))
        .first);
    expect(secondChip, firstChip);
    final card = find.byKey(const ValueKey('onboarding-pattern-card'));
    final fixedHeight = tester.getSize(card).height;
    final day = find.descendant(of: choices, matching: find.text(l.shiftDay));
    for (var i = 0; i < 40; i++) {
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pumpAndSettle();
    }
    final preview = find.byKey(const ValueKey('onboarding-pattern-preview'));
    final scroll = tester.state<ScrollableState>(
        find.descendant(of: preview, matching: find.byType(Scrollable)));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(tester.getSize(card).height, fixedHeight);
    final a =
        tester.getRect(find.byKey(const ValueKey('onboarding-pattern-slot-0')));
    final f =
        tester.getRect(find.byKey(const ValueKey('onboarding-pattern-slot-3')));
    expect(a.top, f.top);
    await tester.ensureVisible(find.text(l.onboardingCompletePattern));
    await tester.tap(find.text(l.onboardingCompletePattern));
    await tester.pumpAndSettle();
    final slot = find.byKey(const ValueKey('onboarding-pattern-slot-0'));
    await tester.ensureVisible(slot);
    await tester.tap(slot);
    await tester.pumpAndSettle();
    expect(find.text(l.onboardingEditPattern), findsOneWidget);
    expect(tester.widget<AppUiShiftChip>(slot).selectionMode, isTrue);
    final material = tester.widget<Material>(
        find.descendant(of: slot, matching: find.byType(Material)));
    expect((material.shape! as RoundedRectangleBorder).side.color,
        AppUiPalette.blue.selectionOutline);
    await tester.tap(slot);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-pattern-slot-23')),
        findsOneWidget);
    await tester.ensureVisible(find.text(l.onboardingEditPattern));
    await tester.tap(find.text(l.onboardingEditPattern));
    await tester.pumpAndSettle();
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
