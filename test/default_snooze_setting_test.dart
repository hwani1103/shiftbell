import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/services/snooze_settings_service.dart';
import 'package:shiftbell/widgets/default_snooze_setting.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(kAlarmChannel, null));
  Widget app(Locale locale) => MaterialApp(locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: const Scaffold(body: SingleChildScrollView(child: DefaultSnoozeSetting())));

  testWidgets('selection waits for confirmed save and survives failure without claiming success', (tester) async {
    var saved = 10;
    var writes = 0;
    Completer<int>? pending;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'getDefaultSnoozeMinutes') return saved;
      writes++;
      pending = Completer<int>();
      saved = await pending!.future;
      return saved;
    });
    await tester.pumpWidget(app(const Locale('ko')));
    await tester.pumpAndSettle();
    ChoiceChip chip(int n) => tester.widget(find.byKey(ValueKey('default-snooze-$n')));
    expect(chip(10).selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('default-snooze-15')));
    await tester.pump();
    expect(chip(10).selected, isTrue);
    expect(chip(5).onSelected, isNull);
    pending!.completeError(PlatformException(code: 'SAVE_FAILED'));
    await tester.pumpAndSettle();
    expect(chip(10).selected, isTrue);
    expect(chip(15).selected, isFalse);
    await tester.tap(find.byKey(const ValueKey('default-snooze-15')));
    await tester.pump();
    pending!.complete(15);
    await tester.pumpAndSettle();
    expect(chip(15).selected, isTrue);
    expect(writes, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(const Locale('ko')));
    await tester.pumpAndSettle();
    expect(chip(15).selected, isTrue);
  });
  test('unsupported defaults are rejected before reaching native', () async {
    var calls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(kAlarmChannel, (_) async { calls++; return 5; });
    for (final value in [0, 20, 25, 30, 35]) {
      await expectLater(SnoozeSettingsService.save(value), throwsArgumentError);
    }
    expect(calls, 0);
  });
  for (final locale in [const Locale('ko'),const Locale('en'),const Locale('de'),const Locale('pt','BR'),const Locale('hi')]) {
    testWidgets('$locale three choices fit at width280 and textScale2', (tester) async {
      tester.view.physicalSize = const Size(280, 800); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(kAlarmChannel, (_) async => 5);
      await tester.pumpWidget(app(locale));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  }
}
