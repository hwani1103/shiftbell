// test/onboarding_popup_delay_test.dart
//
// ⭐ 2026-09-22(사용자 요청) - 최초 1회 안내 팝업 4종이 화면이 그려진 바로 그 프레임에 뜨던 것을
// [kInfoPopupDelay]만큼 늦춘 것의 회귀 테스트. 함께 고친 순서 문제도 고정한다: 플래그(이미 봤다는
// 기록)를 팝업을 실제로 띄우기 직전에 세워야, 지연 중에 사용자가 탭을 옮겨 화면이 사라진 경우
// "본 적 없는데 봤다고 기록"되어 영영 안 뜨는 일이 없다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/widgets/app_button.dart';
import 'package:shiftbell/widgets/onboarding_info_popups.dart';

const _kScheduleKey = 'schedule_tab_tutorial_shown';
// 팝업 제목은 wordSafeSpans로 그려지는 Text.rich라 문자열 검색이 안 맞는다 - Dialog 유무로 판단.
final _popup = find.byType(Dialog);

// ⭐ 2026-09-22(영어화) - 팝업 내용이 l10n(context.l10n)을 쓰도록 바뀌어서, 이 테스트의
// MaterialApp도 AppLocalizations delegate가 있어야 함(없으면 AppLocalizations.of(context)가
// null → context.l10n에서 null-check 에러). locale을 'ko'로 고정해서 아래 "확인했어요" 문자열
// 검색 등 기존 한국어 기준 단언은 그대로 유지.
Widget _wrap(Widget child, {Locale locale = const Locale('ko')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(_wrap(Builder(builder: (c) {
    ctx = c;
    return const Scaffold(body: SizedBox.expand());
  })));
  return ctx;
}

void main() {
  test('지연 시간은 "아주 약간"의 범위(0.4~1초)', () {
    expect(kInfoPopupDelay,
        greaterThanOrEqualTo(const Duration(milliseconds: 400)));
    expect(kInfoPopupDelay, lessThanOrEqualTo(const Duration(seconds: 1)));
  });

  testWidgets('팝업은 화면이 뜬 직후가 아니라 지연 뒤에 나타난다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ctx = await _pumpHost(tester);

    final done = maybeShowScheduleTabTutorial(ctx);
    await tester.pump(); // prefs 읽기 완료
    expect(_popup, findsNothing, reason: '화면과 같은 프레임에 바로 뜨면 안 됨');

    await tester.pump(kInfoPopupDelay - const Duration(milliseconds: 100));
    expect(_popup, findsNothing, reason: '지연이 끝나기 전에는 아직 안 떠야 함');

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400)); // 다이얼로그 전환 애니메이션
    expect(_popup, findsOneWidget);

    await tester.tap(find.text('확인했어요'));
    await tester.pumpAndSettle();
    await done;

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_kScheduleKey), true, reason: '실제로 띄운 뒤에는 "봤다"고 기록');
  });

  testWidgets('지연 중에 화면이 사라지면 팝업을 띄우지 않고 "봤다"고도 기록하지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ctx = await _pumpHost(tester);

    maybeShowScheduleTabTutorial(ctx);
    await tester.pump();

    // 지연 도중 사용자가 다른 탭으로 옮겨 이 화면(위젯)이 dispose된 상황
    await tester.pumpWidget(_wrap(const Scaffold(body: SizedBox.expand())));
    await tester.pump(kInfoPopupDelay + const Duration(seconds: 1));

    expect(_popup, findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_kScheduleKey) ?? false, false,
        reason: '못 본 팝업을 봤다고 기록하면 다음에 그 화면에 들어와도 영영 안 뜬다');
  });

  testWidgets('이미 본 팝업은 지연도 없이 아무 것도 하지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({_kScheduleKey: true});
    final ctx = await _pumpHost(tester);

    await maybeShowScheduleTabTutorial(ctx);
    await tester.pump(kInfoPopupDelay + const Duration(seconds: 1));
    expect(_popup, findsNothing);
  });

  testWidgets('규칙적 근무면 근무 배정 안내는 뜨지 않는다(기존 동작 유지)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ctx = await _pumpHost(tester);

    await maybeShowShiftAssignTutorial(ctx, isRegular: true);
    await tester.pump(kInfoPopupDelay + const Duration(seconds: 1));
    expect(_popup, findsNothing);
  });

  testWidgets('네 가지 웰컴 안내는 각각 처음 한 번만 표시된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ctx = await _pumpHost(tester);

    final popups = <Future<void> Function()>[
      () => maybeShowWelcomePopup(ctx),
      () => maybeShowShiftAssignTutorial(ctx, isRegular: false),
      () => maybeShowConditionTabTutorial(ctx),
      () => maybeShowScheduleTabTutorial(ctx),
    ];

    for (final show in popups) {
      final first = show();
      await tester.pump(kInfoPopupDelay + const Duration(milliseconds: 500));
      expect(_popup, findsOneWidget);
      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();
      await first;

      await show();
      await tester.pump(kInfoPopupDelay + const Duration(milliseconds: 500));
      expect(_popup, findsNothing);
    }

    final prefs = await SharedPreferences.getInstance();
    for (final key in const [
      'welcome_popup_shown',
      'shift_assign_tutorial_shown',
      'condition_tab_tutorial_shown',
      'schedule_tab_tutorial_shown',
    ]) {
      expect(prefs.getBool(key), isTrue,
          reason: '$key should be recorded once');
    }
  });

  // ⭐ 2026-09-22(영어화 P0) - 웰컴/근무배정/일정관리 탭 안내가 영어 로케일에서도 깨지지 않고
  // 실제 영어 문구(l10n)로 뜨는지 확인. 웰컴 팝업 본문은 수면·회복 탭이 영어에 없으므로 그
  // 기능을 언급하면 안 됨(onboarding_info_popups.dart WelcomePopupContent 참고).
  testWidgets('영어 로케일에서는 웰컴 팝업이 영어 문구로 뜨고 수면·회복 탭을 언급하지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late BuildContext ctx;
    await tester.pumpWidget(_wrap(
      Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox.expand());
      }),
      locale: const Locale('en'),
    ));

    maybeShowWelcomePopup(ctx);
    await tester.pump();
    await tester.pump(kInfoPopupDelay + const Duration(milliseconds: 500));

    expect(_popup, findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.textContaining('Sleep'), findsNothing);
  });
}
