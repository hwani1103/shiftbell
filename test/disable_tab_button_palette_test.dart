import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/providers/tab_visibility_provider.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';
import 'package:shiftbell/widgets/disable_tab_button.dart';

void main() {
  for (final theme in AppUiTimeTheme.values) {
    for (final label in ['수면·회복', '일정관리']) {
      testWidgets('${theme.name} $label hide label and icon remain readable',
          (t) async {
        var disabled = false;
        final p = theme.palette;
        await t.pumpWidget(ProviderScope(
            child: MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppUiTheme.withPalette(ThemeData(), p),
          home: Scaffold(
              body: SizedBox(
                  width: 264,
                  child: DisableTabButton(
                    tabLabel: label,
                    provider: conditionTabEnabledProvider,
                    onDisabled: () => disabled = true,
                  ))),
        )));
        await t.pumpAndSettle();
        final l = AppLocalizations.of(t.element(find.byType(DisableTabButton)));
        final text = find.text(l.disableTabButtonLabel(label));
        expect(text, findsOneWidget);
        final rich = find.descendant(of: text, matching: find.byType(RichText));
        final ink = t.widget<RichText>(rich).text.style!.color!;
        final button = t.widget<FilledButton>(find.byType(FilledButton));
        final background = button.style!.backgroundColor!.resolve({})!;
        final x = ink.computeLuminance(), y = background.computeLuminance();
        expect(((x > y ? x : y) + .05) / ((x > y ? y : x) + .05),
            greaterThanOrEqualTo(4.5));
        expect(
            IconTheme.of(t.element(find.byIcon(Icons.visibility_off_outlined)))
                .color,
            ink);
        expect(t.takeException(), isNull);
        await t.tap(text);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await t.tap(find.text(l.commonCancel));
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(disabled, isFalse);
        expect(t.takeException(), isNull);
      });
    }
  }
}
