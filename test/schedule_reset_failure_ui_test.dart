import 'package:shiftbell/l10n/korean_only_copy.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/providers/schedule_provider.dart';
import 'package:shiftbell/screens/onboarding_screen.dart';
import 'package:shiftbell/screens/settings_tab.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ResetWithSharingFailure extends ScheduleNotifier {
  int resetCalls = 0;
  @override
  Future<bool> resetSchedule() async {
    resetCalls++;
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('reset_failure_ui_');
    await databaseFactory.setDatabasesPath(directory.path);
    DatabaseService.debugIsAndroidOverride = false;
    await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(
      isRegular: true, pattern: const ['주간', '휴무'], todayIndex: 0,
      startDate: DateTime(2026, 10, 4), shiftTypes: const ['주간', '휴무'],
    ));
    final bytes = await File('C:/Windows/Fonts/malgun.ttf').readAsBytes();
    await (FontLoader('ResetPreview')
      ..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
  });
  tearDownAll(() async {
    await (await DatabaseService.instance.database).close();
    DatabaseService.debugIsAndroidOverride = null;
    await directory.delete(recursive: true);
  });

  for (final language in ['ko', 'en']) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('Reset proceeds to onboarding with readable sharing warning $language/$scale', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'all_teams_names': ['A', 'B'],
          'welcome_popup_shown': true,
        });
        late _ResetWithSharingFailure notifier;
        await tester.runAsync(() async {
          notifier = _ResetWithSharingFailure();
          await notifier.refresh();
        });
        final captureKey = GlobalKey();
        late AppLocalizations labels;
        await tester.pumpWidget(ProviderScope(
          overrides: [scheduleProvider.overrideWith((ref) => notifier)],
          child: ScreenUtilInit(designSize: const Size(360, 800),
            builder: (_, __) => MaterialApp(
              theme: ThemeData(fontFamily: 'ResetPreview'),
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: captureKey, child: child!)),
              home: Builder(builder: (context) {
                labels = AppLocalizations.of(context);
                return const Scaffold(body: SettingsTab());
              }),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(labels.shiftResetSchedule));
        await tester.tap(find.text(labels.shiftResetSchedule));
        await tester.pumpAndSettle();
        await tester.tap(find.text(labels.commonReset));
        await tester.pumpAndSettle();
        expect(notifier.resetCalls, 1);
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.byType(SettingsTab), findsNothing);
        final message = find.text(KoreanOnlyCopy.forLocale('ko').settingsResetScheduleSharingFailed);
        expect(message, language == 'ko' ? findsOneWidget : findsNothing);
        if (language == 'ko') {
        final paragraph = tester.renderObject<RenderParagraph>(message);
        expect(paragraph.didExceedMaxLines, isFalse);
        final rect = tester.getRect(message);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(800));
        }
        expect(tester.takeException(), isNull);
        expect((await SharedPreferences.getInstance()).getStringList('all_teams_names'), isNull);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(message, language == 'ko' ? findsOneWidget : findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File('build/reset_failure_ui/$language-$scale.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
      });
    }
  }
}
