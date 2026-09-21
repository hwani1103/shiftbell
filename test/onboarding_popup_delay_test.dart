// test/onboarding_popup_delay_test.dart
//
// ⭐ 2026-09-22(사용자 요청) - 최초 1회 안내 팝업 4종이 화면이 그려진 바로 그 프레임에 뜨던 것을
// [kInfoPopupDelay]만큼 늦춘 것의 회귀 테스트. 함께 고친 순서 문제도 고정한다: 플래그(이미 봤다는
// 기록)를 팝업을 실제로 띄우기 직전에 세워야, 지연 중에 사용자가 탭을 옮겨 화면이 사라진 경우
// "본 적 없는데 봤다고 기록"되어 영영 안 뜨는 일이 없다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/widgets/onboarding_info_popups.dart';

const _kScheduleKey = 'schedule_tab_tutorial_shown';
// 팝업 제목은 wordSafeSpans로 그려지는 Text.rich라 문자열 검색이 안 맞는다 - Dialog 유무로 판단.
final _popup = find.byType(Dialog);

Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox.expand());
    }),
  ));
  return ctx;
}

void main() {
  test('지연 시간은 "아주 약간"의 범위(0.4~1초)', () {
    expect(kInfoPopupDelay, greaterThanOrEqualTo(const Duration(milliseconds: 400)));
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
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.expand())));
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
}
