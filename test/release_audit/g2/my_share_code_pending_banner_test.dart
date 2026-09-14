// T13 G2 테스트 - 공유 화면 대기 상태 안내·재시도 (G2-02 연결 4a8f67e, #24 "실패/대기를 사실대로 표시")
// Firebase 미초기화 호스트: 공유 중(active)이어도 ownerId를 못 받아 연결 실패 카드가 함께 보이는 상태까지만 재현 가능.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/my_share_code_screen.dart';
import 'package:shiftbell/services/firebase_bootstrap.dart';
import 'package:shiftbell/services/friend_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../g0/g0_support.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('ko'));

  // FriendSyncService는 싱글톤이고 직렬 큐 꼬리(_serialTail)가 처음 만들어진 zone에 묶인다.
  // 첫 testWidgets의 FakeAsync zone에서 만들어지면 그 테스트가 끝난 뒤 큐 콜백이 영영 안 돌아
  // 다음 테스트의 재시도가 멈춤(테스트 하네스 한정 - 앱은 zone이 하나). 실제 zone에서 먼저 생성해 둔다.
  late Directory dir;
  setUpAll(() async {
    FriendSyncService.instance;
    // 재시도 버튼이 scheduleProvider를 읽으면 ScheduleNotifier가 DB를 연다 - 빈 임시 DB(ffi)로 근무표 없음 상태
    initFfi();
    dir = await Directory.systemTemp.createTemp('g2_share_screen_');
    await databaseFactory.setDatabasesPath(dir.path);
  });
  tearDownAll(() async {
    if (dir.existsSync()) await dir.delete(recursive: true).catchError((_) => dir);
  });
  setUp(() => firebaseReady = false);

  Future<void> pumpScreen(WidgetTester tester, Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(360, 780),
        builder: (context, child) => const MaterialApp(
          locale: Locale('ko'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: MyShareCodeScreen(),
        ),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  testWidgets('F-W01 off: 대기 안내 없음, 공유 시작 버튼', (tester) async {
    await pumpScreen(tester, {});
    expect(find.text(l10n.friendStartSharing), findsOneWidget);
    expect(find.text(l10n.friendStopPendingBanner), findsNothing);
    expect(find.text(l10n.friendSyncPendingBanner), findsNothing);
    expect(find.text(l10n.friendRetrySync), findsNothing);
  });

  testWidgets('F-W02 stop_pending: 중지 대기 안내 표시(삭제 완료로 표시 안 함), 재시도 후에도 대기면 토스트·안내 유지', (tester) async {
    await pumpScreen(tester, {
      'friend_share_intent': 'stop_pending', 'friend_share_enabled': false,
      'friend_share_generation': 2, 'friend_share_dirty': true,
    });
    expect(find.text(l10n.friendStopPendingBanner), findsOneWidget);
    expect(find.text(l10n.friendSyncPendingBanner), findsNothing);
    expect(find.text(l10n.friendStartSharing), findsOneWidget);

    await tester.ensureVisible(find.text(l10n.friendRetrySync));
    await tester.tap(find.text(l10n.friendRetrySync));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    // 재시도 뒤 상태 재조회·SnackBar 표시까지 실제 비동기를 흘려보냄(ScheduleNotifier의 DB 접근 포함)
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // SnackBar 내용은 기본 finder(skipOffstage)에서 빠져서 SnackBar 하위 Text를 직접 확인
    expect(find.byType(SnackBar), findsOneWidget);
    final snackTexts = tester
        .widgetList<Text>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Text), skipOffstage: false))
        .map((t) => t.data)
        .toList();
    expect(snackTexts, contains(l10n.friendSyncPendingToast));
    expect(find.text(l10n.friendStopPendingBanner), findsOneWidget);
    final state = await FriendSyncService.instance.getShareState();
    expect(state.intent, FriendShareIntent.stopPending);
    expect(state.generation, 2);
    // SnackBar 타이머 정리
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('F-W03 active+dirty: 반영 대기 안내 표시(연결 실패 카드와 함께)', (tester) async {
    await pumpScreen(tester, {
      'friend_share_intent': 'active', 'friend_share_enabled': true,
      'friend_share_generation': 1, 'friend_share_dirty': true, 'friend_share_my_name': '홍',
    });
    expect(find.text(l10n.friendSyncPendingBanner), findsOneWidget);
    expect(find.text(l10n.friendStopPendingBanner), findsNothing);
    expect(find.text(l10n.friendConnectionFailed), findsOneWidget);
    expect(find.text(l10n.friendStartSharing), findsNothing);
  });

  testWidgets('F-W04 active+반영 완료(dirty false): 대기 안내 없음', (tester) async {
    await pumpScreen(tester, {
      'friend_share_intent': 'active', 'friend_share_enabled': true,
      'friend_share_generation': 1, 'friend_share_dirty': false, 'friend_share_my_name': '홍',
    });
    expect(find.text(l10n.friendSyncPendingBanner), findsNothing);
    expect(find.text(l10n.friendRetrySync), findsNothing);
  });

  testWidgets('F-W05 legacy enabled만 있는 설치: active·dirty로 올라가 반영 대기 안내', (tester) async {
    await pumpScreen(tester, {'friend_share_enabled': true, 'friend_share_my_name': '홍'});
    expect(find.text(l10n.friendSyncPendingBanner), findsOneWidget);
  });
}
