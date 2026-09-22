import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/services/update_service.dart';

Widget _testApp(GlobalKey<NavigatorState> navigatorKey) {
  return ScreenUtilInit(
    designSize: const Size(360, 800),
    builder: (_, __) => MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('ko'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SizedBox()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('이번 업데이트 노트는 기존 사용자에게 정확히 한 번만 표시된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_testApp(navigatorKey));
    await tester.pumpAndSettle();

    final first =
        UpdateService.checkAndShowReleaseNote(navigatorKey.currentContext!);
    await tester.pumpAndSettle();
    expect(find.text('교대시계 업데이트 노트'), findsOneWidget);

    await tester.ensureVisible(find.text('확인했어요'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인했어요'));
    await tester.pumpAndSettle();
    await first;

    await UpdateService.checkAndShowReleaseNote(navigatorKey.currentContext!);
    await tester.pumpAndSettle();
    expect(find.text('교대시계 업데이트 노트'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getString('release_note_seen_version');
    final lastSeen = prefs.getString('release_note_last_seen_app_version');
    expect(seen, isNotEmpty);
    expect(lastSeen, seen);
  });

  testWidgets('신규 설치 온보딩 기준을 기록하면 업데이트 노트를 표시하지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await UpdateService.markOnboardingBaselineVersion();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_testApp(navigatorKey));
    await tester.pumpAndSettle();

    await UpdateService.checkAndShowReleaseNote(navigatorKey.currentContext!);
    await tester.pumpAndSettle();
    expect(find.text('교대시계 업데이트 노트'), findsNothing);
  });
}
