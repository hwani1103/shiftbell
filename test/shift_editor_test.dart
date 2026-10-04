import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/layout_limits.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/widgets/shift_names_dialog.dart';
import 'package:shiftbell/widgets/shift_label_layout.dart';

void main() {
  test('Hangul wraps two characters without dropping long names', () {
    const style = TextStyle(fontSize: 13);
    for (final entry in {
      '주': '주',
      '주간': '주간',
      '주간근': '주간\n근',
      '주간근무': '주간\n근무',
      '주간근무추가': '주간근\n무추가'
    }.entries) {
      expect(wrapShiftLabel(entry.key, 40, style, TextScaler.noScaling),
          entry.value);
    }
    final english =
        wrapShiftLabel('Night Duty', 45, style, TextScaler.noScaling);
    expect(english, 'Night\nDuty');
    expect(
        wrapShiftLabel('WWWWWWWWWW', 45, style, TextScaler.noScaling)
            .replaceAll('\n', ''),
        'WWWWWWWWWW');
  });

  for (final locale in [const Locale('ko'), const Locale('en')]) {
    for (final size in [
      const Size(320, 568),
      const Size(806, 895),
      const Size(1280, 800)
    ]) {
      testWidgets(
          'edit all shifts, lock used, add/delete ${locale.languageCode} $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ShiftNameEdits? result;
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(360, 780),
            builder: (context, _) {
              ScreenUtil.configure(
                  data: appContentMediaQuery(
                      MediaQueryData.fromView(View.of(context))),
                  designSize: const Size(360, 780));
              return MaterialApp(
                locale: locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate
                ],
                home: Builder(
                    builder: (context) => Scaffold(
                        body: TextButton(
                            child: const Text('open'),
                            onPressed: () async {
                              result = await showDialog<ShiftNameEdits>(
                                  context: context,
                                  builder: (_) => const ShiftNamesDialog(
                                      names: ['Day', 'Leave', 'Unused'],
                                      used: {'Day', 'Leave'}));
                            }))),
              );
            }));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNWidgets(3));
        expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
        await tester.ensureVisible(find.byIcon(Icons.delete_outline));
        await tester.tap(find.byIcon(Icons.delete_outline));
        await tester.pumpAndSettle();
        final l = lookupAppLocalizations(locale);
        final add = find.text('${l.commonAdd} (2/13)');
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'Afternoon Shift');
        await tester.tap(find.text(l.commonSave));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(result!.deleted, {'Unused'});
        expect(result!.added, ['Afternoon Shift']);
      });
    }
  }
}
