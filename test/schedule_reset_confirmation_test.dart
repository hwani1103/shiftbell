import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/settings_tab.dart';

void main() {
  for (final language in ['ko', 'en']) {
    for (final scale in [1.0, 1.3]) {
      testWidgets(
          'Existing reset dialog $language/$scale remains readable and cancellable at 360dp',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 2496);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        bool? result;
        late AppLocalizations labels;
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(360, 800),
            builder: (_, __) => MaterialApp(
                locale: Locale(language),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate
                ],
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: Builder(builder: (context) {
                  labels = AppLocalizations.of(context);
                  return Scaffold(
                      body: TextButton(
                          onPressed: () async {
                            result = await showDialog<bool>(
                                context: context,
                                builder: buildScheduleResetConfirmation);
                          },
                          child: const Text('open')));
                }))));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(labels.settingsResetScheduleConfirm), findsOneWidget);
        expect(find.text(labels.commonReset).hitTestable(), findsOneWidget);
        expect(find.text(labels.commonCancel).hitTestable(), findsOneWidget);
        await tester.tap(find.text(labels.commonCancel));
        await tester.pumpAndSettle();
        expect(result, false);
        expect(find.byType(AlertDialog), findsNothing);
      });
    }
  }
}
