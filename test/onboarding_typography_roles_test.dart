import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/permission_intro_screen.dart';
import 'package:shiftbell/widgets/app_ui_components.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'onboarding_pattern_feedback_test.dart' show pumpOnboarding;

void main() {
  testWidgets(
      'step metadata uses the shared progress role and date entry is an enabled secondary action',
      (tester) async {
    final l = await pumpOnboarding(
        tester, const Locale('ko'), const Size(400, 800), 2, GlobalKey());
    expect(tester.widget<Text>(find.text('1 / 3')).style?.fontSize,
        AppFontSize.body);
    expect(tester.widget<Text>(find.text('1 / 3')).style?.fontWeight,
        FontWeight.w600);
    await tester.tap(find.text(l.onboardingNextPattern));
    await tester.pumpAndSettle();
    final entry = tester.widget<AppUiButton>(find.ancestor(
        of: find.text(l.onboardingIrregularChoiceTitle),
        matching: find.byType(AppUiButton)));
    expect(entry.action, AppUiAction.secondary);
    expect(entry.onPressed, isNotNull);
    final next = tester.widget<AppUiButton>(find.ancestor(
        of: find.text(l.onboardingNextAlarms),
        matching: find.byType(AppUiButton)));
    expect(next.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'indexed chips use the largest safe shared tier and preserve name size',
      (tester) async {
    for (final size in AppChipSize.values) {
      for (final width in [64.0, 90.0, 112.0]) {
        for (final name in ['D', '주간', 'LongerShift']) {
          for (final index in [1, 12, 40]) {
            await tester.pumpWidget(MaterialApp(
                home: Scaffold(
                    body: Center(
                        child: SizedBox(
                            width: width,
                            child: AppUiShiftChip(
                                name: name, index: index, size: size))))));
            await tester.pump();
            final chip = tester.getRect(find.byType(AppUiShiftChip));
            Rect bounds(String text) {
              final f = find.text(text);
              final p = tester.renderObject<RenderParagraph>(f);
              return p
                  .getBoxesForSelection(
                      TextSelection(baseOffset: 0, extentOffset: text.length))
                  .map((b) => b.toRect().shift(tester.getRect(f).topLeft))
                  .reduce((a, b) => a.expandToInclude(b));
            }

            expect(bounds(index.toString()).overlaps(bounds(name)), isFalse);
            final indexText = tester.widget<Text>(find.text(index.toString()));
            expect(
                indexText.style?.fontSize, lessThanOrEqualTo(AppFontSize.meta));
            expect(indexText.textScaler, TextScaler.noScaling);
            expect(tester.getRect(find.text(name)).center.dy,
                closeTo(chip.center.dy, .1));
            if (name == 'D' && width == 112) {
              expect(indexText.style?.fontSize, AppFontSize.meta);
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });
  testWidgets(
      'first permission frame waits for verified state without temporary cards',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final snapshot = Completer<Map<String, Object>>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'permissionSnapshot') return snapshot.future;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ProviderScope(child: PermissionIntroScreen())));
    await tester.pump();
    final l =
        AppLocalizations.of(tester.element(find.byType(PermissionIntroScreen)));
    expect(find.text(l.permissionGetStarted), findsNothing);
    expect(find.byKey(const ValueKey('permission-exactAlarm')), findsNothing);
    expect(find.text(l.onboardingShiftNameTitle), findsNothing);
    snapshot.complete({
      'notification': 'denied',
      'overlay': 'denied',
      'exactAlarm': 'granted',
      'fullScreen': 'notApplicable',
      'alarmChannel': 'granted',
      'sdk': 34
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('permission-exactAlarm')), findsNothing);
    expect(find.byKey(const ValueKey('permission-fullScreen')), findsNothing);
    expect(find.byKey(const ValueKey('permission-overlay')), findsOneWidget);
    expect(find.text(l.permissionGetStarted), findsOneWidget);
    expect(find.text(l.onboardingShiftNameTitle), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
