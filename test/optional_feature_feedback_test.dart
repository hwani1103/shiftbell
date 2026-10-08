import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/widgets/onboarding_info_popups.dart';
import 'package:shiftbell/widgets/nav_icon_emphasis.dart';

void main() {
  for (final schedule in [true, false]) {
    testWidgets(
        '${schedule ? 'schedule' : 'sleep'} tutorial stays once after reopening',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      Future<void>? pending;
      await tester.pumpWidget(MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () {
                        pending = schedule
                            ? maybeShowScheduleTabTutorial(context)
                            : maybeShowConditionTabTutorial(context);
                      },
                      child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(kInfoPopupDelay);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      // Closing the real tutorial preserves its permanent shown preference.
      // Use the button's user-facing label rather than reaching into popup state.
      final close = find.text('확인했어요');
      if (close.evaluate().isNotEmpty) {
        await tester.tap(close.last);
      } else {
        Navigator.of(tester.element(find.byType(Dialog))).pop();
      }
      await tester.pumpAndSettle();
      await pending;
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await pending;
      expect(find.byType(Dialog), findsNothing);
      expect(
          (await SharedPreferences.getInstance()).getBool(schedule
              ? 'schedule_tab_tutorial_shown'
              : 'condition_tab_tutorial_shown'),
          isTrue);
    });
  }
  testWidgets('navigation emphasis grows then returns without changing layout',
      (tester) async {
    Widget app(int sequence) => MaterialApp(
        home: Scaffold(
            body: NavIconEmphasis(
                icon: Icons.event_note_outlined, sequence: sequence)));
    await tester.pumpWidget(app(0));
    final initialSize = tester.getSize(find.byType(NavIconEmphasis));
    await tester.pumpWidget(app(1));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
        tester
            .widget<ScaleTransition>(find.descendant(
                of: find.byType(NavIconEmphasis),
                matching: find.byType(ScaleTransition)))
            .scale
            .value,
        greaterThan(1));
    expect(tester.getSize(find.byType(NavIconEmphasis)), initialSize);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ScaleTransition>(find.descendant(
                of: find.byType(NavIconEmphasis),
                matching: find.byType(ScaleTransition)))
            .scale
            .value,
        1);
  });
}
