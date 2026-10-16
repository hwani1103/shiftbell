import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/alarm.dart';
import 'package:shiftbell/providers/alarm_provider.dart';
import 'package:shiftbell/providers/app_ui_theme_preview_provider.dart';
import 'package:shiftbell/screens/next_alarm_tab.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';
import 'package:shiftbell/widgets/app_ui_components.dart';

class _Alarms extends StateNotifier<AsyncValue<List<Alarm>>>
    implements AlarmNotifier {
  _Alarms(List<Alarm> alarms) : super(AsyncData(alarms));
  @override
  Future<void> refresh() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  void empty() => state = const AsyncData([]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('CAPTURE_NEXT_ALARM');
  setUpAll(() async {
    if (capture && Platform.isWindows) {
      for (final entry in [
        ('NextAlarmTest', 'C:/Windows/Fonts/malgun.ttf'),
        (
          'MaterialIcons',
          'C:/tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
        )
      ]) {
        await (FontLoader(entry.$1)
              ..addFont(Future.value(
                  ByteData.sublistView(File(entry.$2).readAsBytesSync()))))
            .load();
      }
    }
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'getPlatformSdkInt') return 36;
      if (call.method == 'permissionSnapshot') {
        return {
          'notification': 'granted',
          'overlay': 'granted',
          'exactAlarm': 'granted',
          'fullScreen': 'granted',
          'alarmChannel': 'granted',
          'sdk': 36,
        };
      }
      return null;
    });
  });

  Future<void> snapshot(WidgetTester t, GlobalKey key, String name) async {
    if (!capture) return;
    await t.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      const directory = String.fromEnvironment('NEXT_ALARM_CAPTURE_DIR',
          defaultValue: 'artifacts/calendar_ot_2026_10_16');
      final file = File('$directory/next_alarm_$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final theme in AppUiTimeTheme.values) {
    test('${theme.name} next-alarm roles retain readable contrast', () {
      final p = theme.palette;
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
      }

      for (final pair in [
        (p.text, p.surface),
        (p.secondaryText, p.surface),
        (p.secondaryText, p.background),
        (p.primary, p.surface),
        (p.primary, p.soft),
        (p.onPrimary, p.primary),
        (p.selectionOutline, p.surface),
        (p.danger, p.dangerSurface),
        (p.onDanger, p.danger),
        (p.text, p.soft),
      ]) {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
    });
    testWidgets(
        '${theme.name} tab and list inherit saved palette; outer theme stays intact',
        (t) async {
      SharedPreferences.setMockInitialValues(
          {'app_ui_preview_theme': theme.name});
      t.view.physicalSize = const Size(411.43, 891.43);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final alarms = _Alarms([
        Alarm(
            id: 1,
            time: '09:30',
            date: now.add(const Duration(minutes: 20)),
            type: 'fixed',
            alarmTypeId: 1,
            shiftType: '주간'),
        Alarm(
            id: 2,
            time: '10:30',
            date: now.add(const Duration(hours: 5)),
            type: 'custom',
            alarmTypeId: 2),
        Alarm(
            id: 3,
            time: '11:30',
            date: now.add(const Duration(hours: 6)),
            type: 'custom',
            alarmTypeId: 3),
      ]);
      final container = ProviderContainer(
          overrides: [alarmNotifierProvider.overrideWith((ref) => alarms)]);
      addTearDown(container.dispose);
      await container.read(appUiThemePreviewProvider.future);
      final key = GlobalKey();
      await t.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: ScreenUtilInit(
              designSize: const Size(360, 780),
              builder: (_, __) => MaterialApp(
                    theme:
                        ThemeData(fontFamily: capture ? 'NextAlarmTest' : null),
                    locale: const Locale('ko'),
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    builder: (_, child) =>
                        RepaintBoundary(key: key, child: child!),
                    home: Scaffold(
                        body: const NextAlarmTab(),
                        bottomNavigationBar: const SizedBox(height: 64)),
                  ))));
      await t.pumpAndSettle();
      final p = theme.palette;
      expect(t.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          p.background);
      expect(
          Theme.of(t.element(find.byType(NextAlarmTab)))
              .extension<AppUiPalette>(),
          isNull);
      final l = AppLocalizations.of(t.element(find.byType(NextAlarmTab)));
      expect(t.widget<Text>(find.text(l.alarmUpNext)).style!.color,
          p.secondaryText);
      expect(t.widget<Text>(find.text(l.alarmUntil)).style!.color,
          p.secondaryText);
      expect(find.byType(AppUiButton), findsNWidgets(2));
      expect(t.takeException(), isNull);
      expect(
          find.descendant(
              of: find.byType(NextAlarmTab), matching: find.byType(Scrollable)),
          findsNothing);
      final tabBounds = t.getRect(find.byType(NextAlarmTab));
      final dismissBounds = t.getRect(find.ancestor(
          of: find.text(l.alarmTurnOffThis),
          matching: find.byType(AppUiButton)));
      expect(tabBounds.bottom - dismissBounds.bottom, inInclusiveRange(4, 20));
      for (final button in find.byType(AppUiButton).evaluate()) {
        final rect = t.getRect(find.byWidget(button.widget));
        expect(rect.bottom, lessThanOrEqualTo(tabBounds.bottom));
        final control = t.widget<FilledButton>(find.descendant(
            of: find.byWidget(button.widget),
            matching: find.byType(FilledButton)));
        final action = button.widget as AppUiButton;
        expect(action.emphasized, isTrue);
        expect(control.style!.backgroundColor!.resolve({}),
            action.action == AppUiAction.danger ? p.danger : p.primary);
      }
      final beforeDrag = t.getTopLeft(find.text(l.alarmTurnOffThis));
      await t.drag(find.byType(NextAlarmTab), const Offset(0, -100));
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.text(l.alarmTurnOffThis)), beforeDrag);
      await snapshot(t, key, '${theme.name}_tab');
      await t.ensureVisible(find.text(l.alarmViewAllRegistered));
      await t.tap(find.text(l.alarmViewAllRegistered));
      await t.pumpAndSettle();
      Color? sheetColor() => (t
              .widget<Container>(
                  find.byKey(const ValueKey('next-alarm-list-surface')))
              .decoration as BoxDecoration)
          .color;
      expect(sheetColor(), p.surface);
      expect(t.widget<Text>(find.text(l.alarmRegistered)).style!.color, p.text);
      expect(find.text(l.alarmVibration), findsWidgets);
      expect(find.text(l.alarmSilent), findsWidgets);
      expect(t.takeException(), isNull);
      await snapshot(t, key, '${theme.name}_list');
      final controller = container.read(appUiThemePreviewProvider.notifier);
      final changed = theme == AppUiTimeTheme.night
          ? AppUiTimeTheme.daytime
          : AppUiTimeTheme.night;
      await controller.select(changed);
      await t.pumpAndSettle();
      expect(sheetColor(), changed.palette.surface);
      expect(t.widget<Text>(find.text(l.alarmRegistered)).style!.color,
          changed.palette.text);
      await controller.select(theme);
      await t.pumpAndSettle();
      Navigator.of(t.element(find.text(l.alarmRegistered))).pop();
      await t.pumpAndSettle();
      alarms.empty();
      await t.pumpAndSettle();
      expect(find.text(l.alarmNoneUpcoming), findsOneWidget);
      expect(t.widget<Text>(find.text(l.alarmNoneUpcoming)).style!.color,
          p.secondaryText);
      expect(t.takeException(), isNull);
      await snapshot(t, key, '${theme.name}_empty');
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
