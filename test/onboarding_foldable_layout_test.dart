import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/onboarding_screen.dart';
import 'package:shiftbell/constants/layout_limits.dart';
import 'package:shiftbell/widgets/app_content_frame.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(337, 817),
    const Size(674, 817),
    // Galaxy Fold8 cover (1248x1972) and inner (1848x2448) aspect ratios.
    const Size(400, 632),
    const Size(662, 876),
    const Size(360, 840),
    const Size(806, 895),
    const Size(752, 834.67),
    const Size(834.67, 752),
  ]) {
    for (final locale in [
      const Locale('ko'),
      const Locale('en'),
      const Locale('de'),
      const Locale('pt'),
      const Locale('hi'),
    ]) {
      testWidgets(
          '온보딩 패턴 단계 ${size.width}x${size.height} ${locale.languageCode}: 스크롤되고 버튼이 보인다',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            child: ScreenUtilInit(
              designSize: const Size(360, 780),
              minTextAdapt: true,
              builder: (context, _) {
                ScreenUtil.configure(
                  data: appContentMediaQuery(
                      MediaQueryData.fromView(View.of(context))),
                  designSize: const Size(360, 780),
                  minTextAdapt: true,
                  splitScreenMode: true,
                );
                return MaterialApp(
                  locale: locale,
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(double.parse(
                              const String.fromEnvironment('LAYOUT_TEXT_SCALE',
                                  defaultValue: '1.0')))),
                      child: AppContentFrame(child: child!)),
                  home: const OnboardingScreen(),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(Dialog), findsNothing,
            reason: 'Fresh onboarding must start without a welcome popup');
        final l =
            AppLocalizations.of(tester.element(find.byType(OnboardingScreen)));
        expect(find.text(l.onboardingShortNamesHint), findsOneWidget);
        final nextText = l.commonNext;
        await tester.tap(find.text(nextText));
        await tester.pumpAndSettle();

        expect(find.text('2 / 4'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsWidgets);
        final next = tester.getRect(find.text(nextText));
        expect(next.bottom <= size.height, isTrue,
            reason: '패턴 단계의 다음 버튼이 화면 아래로 밀림: $next');
        for (final shift in [
          l.shiftDay,
          l.shiftNight,
          l.shiftMorning,
          l.shiftAfternoon,
        ]) {
          await tester.ensureVisible(find.text(shift));
          await tester.tap(find.text(shift));
          await tester.pumpAndSettle();
          final preview =
              find.byKey(const ValueKey('onboarding-pattern-preview'));
          final previewBox = tester.getRect(preview);
          final added =
              find.descendant(of: preview, matching: find.text(shift));
          final addedBox = tester.getRect(added);
          expect(addedBox.top, greaterThanOrEqualTo(previewBox.top));
          expect(addedBox.bottom, lessThanOrEqualTo(previewBox.bottom));
          expect(added.hitTestable(), findsOneWidget,
              reason: 'The added shift must be visible without scrolling');
          expect(previewBox.bottom, lessThan(next.top));
        }
        await tester.tap(find.text(nextText));
        await tester.pumpAndSettle();
        expect(find.text('3 / 4'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(l.shiftDay));
        await tester.pump();
        await tester.tap(find.text(nextText));
        await tester.pumpAndSettle();
        expect(find.text('4 / 4'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final label = find.text(l.shiftAfternoon);
        await tester.ensureVisible(label);
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(
          paragraph.getBoxesForSelection(TextSelection(
            baseOffset: 0,
            extentOffset: l.shiftAfternoon.length,
          )),
          hasLength(1),
          reason:
              'A shift name must not strand its last letter on a second line',
        );
      });
    }
  }
}
