import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/widgets/sleep_edit_dialog.dart';

void main() {
  for (final language in ['ko', 'en', 'de']) {
    testWidgets('$language sleep editor preserves time and scopes UTC labels',
        (tester) async {
      final end = DateTime(2026, 1, 5, 12);
      final start = end.subtract(const Duration(hours: 8));
      SleepSlotEditResult? result;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: AppUiTheme.withPalette(ThemeData(), AppUiPalette.blue),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () async {
                        result = await showSleepSlotEditDialog(context,
                            initialStart: start,
                            initialEnd: end,
                            showDeleteButton: true);
                      },
                      child: const Text('open'),
                    ))),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final utc = find.byWidgetPredicate(
          (w) => w is Text && (w.data?.contains('UTC') ?? false));
      expect(utc, language == 'ko' ? findsNothing : findsNWidgets(2));
      final context = tester.element(find.byType(BottomSheet));
      final l = AppLocalizations.of(context)!;
      await tester.tap(find.text(l.sleepText063));
      await tester.pumpAndSettle();
      expect(result, isA<SleepSlotSaved>());
      final saved = result as SleepSlotSaved;
      expect(saved.start, start);
      expect(saved.end, end);
      expect(tester.takeException(), isNull);
    });
  }
}
