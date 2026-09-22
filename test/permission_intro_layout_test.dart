// 2026-09-22 - 권한 안내 첫 화면이 작은 화면·큰 글자에서 넘쳐 "허용" 버튼이 잘리던 문제의 회귀 테스트.
// 설명 영역은 스크롤, 버튼 두 개는 항상 화면 안(하단 고정)이어야 한다.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/permission_intro_screen.dart';

void main() {
  const sizes = [Size(320, 568), Size(360, 640), Size(411, 891)];
  const scales = [1.0, 1.5, 2.0];
  const locales = [Locale('ko'), Locale('en')];

  for (final size in sizes) {
    for (final scale in scales) {
      for (final locale in locales) {
        testWidgets('${size.width.toInt()}x${size.height.toInt()} 글자 x$scale ${locale.languageCode}: 넘치지 않고 버튼이 보인다',
            (tester) async {
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
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const PermissionIntroScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final screen = Offset.zero & size;
          for (final button in [find.byType(ElevatedButton), find.byType(TextButton)]) {
            expect(button, findsOneWidget);
            final rect = tester.getRect(button);
            expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight - const Offset(1, 1)), isTrue,
                reason: '버튼이 화면 밖으로 밀려남: $rect');
          }
        });
      }
    }
  }
}
