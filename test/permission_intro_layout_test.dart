// 2026-09-22 - 권한 안내 첫 화면이 작은 화면·큰 글자에서 넘쳐 "허용" 버튼이 잘리던 문제의 회귀 테스트.
// 본문과 버튼을 스크롤해서 접근할 수 있고, 후속 경고 팝업도 진행 가능해야 한다.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/permission_intro_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const sizes = [
    Size(320, 568),
    Size(360, 640),
    Size(411, 891),
    Size(400, 632),
    Size(662, 876),
    Size(360, 840),
    Size(806, 895),
    Size(752, 834.67),
    Size(932.57, 704),
    Size(800, 1280),
    Size(1280, 800),
    Size(640, 320)
  ];
  const scales = [1.0, 2.0];
  const locales = [Locale('ko'), Locale('en')];

  for (final size in sizes) {
    for (final scale in scales) {
      for (final locale in locales) {
        testWidgets(
            '${size.width.toInt()}x${size.height.toInt()} 글자 x$scale ${locale.languageCode}: 넘치지 않고 버튼이 보인다',
            (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            ScreenUtilInit(
              designSize: const Size(360, 780),
              minTextAdapt: true,
              builder: (context, _) => MaterialApp(
                locale: locale,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const PermissionIntroScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final screen = Offset.zero & size;
          for (final button in [
            find.byType(ElevatedButton),
            find.byType(TextButton)
          ]) {
            expect(button, findsOneWidget);
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            final rect = tester.getRect(button);
            expect(
                screen.contains(rect.topLeft) &&
                    screen.contains(rect.bottomRight - const Offset(1, 1)),
                isTrue,
                reason: '버튼이 화면 밖으로 밀려남: $rect');
          }
          // The actual warning dialog was missing from the older layout matrix.
          await tester.tap(find.byType(TextButton));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          final l = lookupAppLocalizations(locale);
          final next = find.widgetWithText(TextButton, l.commonContinue);
          await tester.ensureVisible(next);
          expect(next.hitTestable(), findsOneWidget);
        });
      }
    }
  }
}
