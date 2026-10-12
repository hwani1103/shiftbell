import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/alarm.dart';
import 'package:shiftbell/widgets/alarm_time_editor.dart';
import 'package:shiftbell/widgets/tappable_number_picker.dart';
import 'package:shiftbell/constants/platform_channel.dart';

void main() {
  setUpAll(() async {
    final bytes = await File(Platform.isWindows
            ? 'C:/Windows/Fonts/segoeui.ttf'
            : 'test/fixtures/layout_fonts/Quicksand-Bold.ttf')
        .readAsBytes();
    await (FontLoader('TimeEditorTest')
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  });
  Widget app(bool use24, Widget home, {double textScale = 1}) => ScreenUtilInit(
      designSize: const Size(360, 780),
      builder: (context, _) => MaterialApp(
          theme: ThemeData(fontFamily: 'TimeEditorTest'),
          locale: const Locale('en', 'US'),
          supportedLocales: const [Locale('en', 'US')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  alwaysUse24HourFormat: use24,
                  textScaler: TextScaler.linear(textScale)),
              child: child!),
          home: home));

  for (final use24 in [false, true]) {
    testWidgets(
        '${use24 ? 24 : 12}-hour editor preserves all 24 hours and day offsets',
        (tester) async {
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final offset in [-1, 0, 1]) {
        for (var hour = 0; hour < 24; hour++) {
          TimeOfDay? saved;
          int? savedOffset;
          await tester.pumpWidget(app(
              use24,
              Builder(
                  builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => AlarmTimePicker(
                                  shiftName: 'Night duty',
                                  initialTime:
                                      TimeOfDay(hour: hour, minute: 37),
                                  initialDayOffset: offset,
                                  onTimeSelected: (time, dayOffset) {
                                    saved = time;
                                    savedOffset = dayOffset;
                                  })),
                          child: const Text('Open'))))));
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final picker = tester.widget<TappableNumberPicker>(
              find.byKey(ValueKey('alarm-hour-${use24 ? 24 : 12}')));
          expect(
              picker.value, use24 ? hour : (hour % 12 == 0 ? 12 : hour % 12));
          expect(picker.minValue, use24 ? 0 : 1);
          expect(picker.maxValue, use24 ? 23 : 12);
          expect(find.text('AM'), use24 ? findsNothing : findsOneWidget);
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          expect(saved, TimeOfDay(hour: hour, minute: 37));
          expect(savedOffset, offset);
          // Exercise the actual DB serialization/decoder, not formatted AM/PM text.
          final stored = Alarm(
              time: '${saved!.hour.toString().padLeft(2, '0')}:37',
              date: DateTime(
                  2026, 12, 15 + savedOffset!, saved!.hour, saved!.minute),
              type: 'fixed',
              alarmTypeId: 1,
              dayOffset: savedOffset!);
          final restored = Alarm.fromMap(stored.toMap());
          expect(restored.date!.hour, hour);
          expect(restored.date!.minute, 37);
          expect(restored.dayOffset, offset);
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
  testWidgets('changing system format while editing preserves canonical time',
      (tester) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<AlarmTimePickerState>();
    final editor = AlarmTimePicker(
        key: key,
        shiftName: 'Night',
        initialTime: const TimeOfDay(hour: 13, minute: 5),
        onTimeSelected: (_, __) {});
    await tester.pumpWidget(app(false, Scaffold(body: editor)));
    final state = key.currentState;
    expect(
        tester
            .widget<TappableNumberPicker>(
                find.byKey(const ValueKey('alarm-hour-12')))
            .value,
        1);
    await tester.pumpWidget(app(true, Scaffold(body: editor)));
    expect(key.currentState, same(state));
    expect(
        tester
            .widget<TappableNumberPicker>(
                find.byKey(const ValueKey('alarm-hour-24')))
            .value,
        13);
    tester
        .widget<TappableNumberPicker>(
            find.byKey(const ValueKey('alarm-hour-24')))
        .onChanged(0);
    await tester.pump();
    await tester.pumpWidget(app(false, Scaffold(body: editor)));
    expect(
        tester
            .widget<TappableNumberPicker>(
                find.byKey(const ValueKey('alarm-hour-12')))
            .value,
        12);
    expect(tester.takeException(), isNull);
  });
  testWidgets('resume reads Android format when Flutter settings are stale',
      (tester) async {
    var nativeUse24 = false;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'getUse24HourFormat') return nativeUse24;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));
    TimeOfDay? saved;
    await tester.pumpWidget(app(false, Scaffold(body: AlarmTimePicker(
      shiftName: 'Night duty',
      initialTime: const TimeOfDay(hour: 23, minute: 37),
      onTimeSelected: (time, _) => saved = time,
    ))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('alarm-hour-12')), findsOneWidget);
    nativeUse24 = true;
    tester.state<AlarmTimePickerState>(find.byType(AlarmTimePicker))
        .didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.widget<TappableNumberPicker>(
        find.byKey(const ValueKey('alarm-hour-24'))).value, 23);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(saved, const TimeOfDay(hour: 23, minute: 37));
  });
  testWidgets('tapping across noon and midnight converts exactly once',
      (tester) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final c in [
      (false, 11, '12', 12),
      (false, 23, '12', 0),
      (false, 12, '11', 11),
      (false, 0, '11', 23),
      (true, 23, '00', 0),
      (true, 0, '23', 23)
    ]) {
      TimeOfDay? saved;
      await tester.pumpWidget(app(
          c.$1,
          Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => AlarmTimePicker(
                              shiftName: 'Night',
                              initialTime: TimeOfDay(hour: c.$2, minute: 15),
                              onTimeSelected: (time, _) {
                                saved = time;
                              })),
                      child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find
          .descendant(
              of: find.byKey(ValueKey('alarm-hour-${c.$1 ? 24 : 12}')),
              matching: find.text(c.$3))
          .first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(saved, TimeOfDay(hour: c.$4, minute: 15));
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('both time formats fit phone and fold windows at larger text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(411, 891),
      const Size(360, 840),
      const Size(752, 834.67),
      const Size(834.67, 752),
      const Size(475.43, 751.24),
      const Size(704, 932.57),
      const Size(932.57, 704)
    ]) {
      tester.view.physicalSize = size;
      for (final use24 in [true, false]) {
        for (final scale in [1.0, 1.3]) {
          await tester.pumpWidget(app(
              use24,
              Scaffold(
                  body: AlarmTimePicker(
                      shiftName: 'Night duty',
                      initialTime: const TimeOfDay(hour: 23, minute: 59),
                      onTimeSelected: (_, __) {})),
              textScale: scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '$size use24=$use24 scale=$scale');
        }
      }
    }
  });
}
