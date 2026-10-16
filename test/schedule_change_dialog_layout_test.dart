import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/theme/app_theme.dart';
import 'package:shiftbell/widgets/schedule_change_dialog.dart';

void main() {
  for (final scenario in [
    (const Size(400, 850), 1.0, 0.0),
    (const Size(360, 480), 2.0, 0.0),
    (const Size(800, 600), 2.0, 200.0),
  ]) {
    testWidgets('mixed language schedule dialog opens and saves at $scenario',
        (tester) async {
      tester.view.physicalSize = scenario.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ScheduleChangeSelection? selection;
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(360, 780),
        builder: (_, __) => MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('ko'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scenario.$2),
                viewInsets: EdgeInsets.only(bottom: scenario.$3)),
            child: child!,
          ),
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                      child: const Text('open'),
                      onPressed: () async {
                        selection = await showDialog<ScheduleChangeSelection>(
                          context: context,
                          builder: (_) => ScheduleChangeDialog(
                            pattern: const [
                              '주간',
                              'Early',
                              'Früh',
                              'Manhã',
                              'सुबह'
                            ],
                            date: DateTime(2026, 10, 15),
                          ),
                        );
                      },
                    ),
                  )),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final slot = find.byKey(const ValueKey('schedule-slot-2'));
      await tester.ensureVisible(slot);
      await tester.tap(slot);
      await tester.pumpAndSettle();
      final save = find.text('저장');
      expect(save, findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(selection?.index, 2);
      expect(find.byType(ScheduleChangeDialog), findsNothing);
    });
  }
}
