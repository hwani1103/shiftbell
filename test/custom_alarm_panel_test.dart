import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/custom_alarm_preset.dart';
import 'package:shiftbell/providers/custom_alarm_preset_provider.dart';
import 'package:shiftbell/widgets/custom_alarm_preset_panel.dart';

void main() {
  testWidgets('one empty slot grows to five; deletion preserves other presets',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: SizedBox(
          width: 210,
          height: 40,
          child: CustomAlarmPresetPanel(selectedIndex: null,
            onSelect: (_) {}, onBack: () {}, onEdit: () {}, onDelete: () {}),
        ))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byKey(const ValueKey('one-tap-slot-1')), findsNothing);
    for (var count = 1; count <= 5; count++) {
      await container.read(customAlarmPresetsProvider.notifier).saveAll([
        for (var i = 0; i < 5; i++)
          i < count ? CustomAlarmPreset(time: '0$i:00') : CustomAlarmPreset.empty,
      ]);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add), count < 5 ? findsOneWidget : findsNothing);
      expect(find.byIcon(Icons.volume_up), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await container.read(customAlarmPresetsProvider.notifier).saveAll([
      const CustomAlarmPreset(time: '07:00'), CustomAlarmPreset.empty,
      const CustomAlarmPreset(time: '09:00'), CustomAlarmPreset.empty,
      CustomAlarmPreset.empty,
    ]);
    await tester.pumpAndSettle();
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    expect(find.byKey(const ValueKey('one-tap-slot-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('one-tap-slot-3')), findsNothing);
  });
}
