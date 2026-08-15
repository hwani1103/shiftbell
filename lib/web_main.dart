// lib/web_main.dart
//
// ⭐ 트랙1(웹/PWA) 전용 entry point - 진짜 앱(lib/main.dart)과 완전히 분리된 별도의 아주
// 가벼운 Flutter Web 앱. `flutter build web -t lib/web_main.dart`로 따로 빌드함. 진짜
// 앱의 main.dart는 sqflite(DB)/MethodChannel(네이티브 알람)에 강하게 의존하는데, 그건
// 전부 웹에서 동작 안 하거나 의미가 없어서(웹 방문자는 자기 스케줄이 없음 - 남의 스케줄을
// "보기만" 하러 옴) 아예 안 씀.
//
// ⭐ 친구공유 v1(Firestore) - 링크의 code는 이제 Firestore 문서 ID(ownerId)만 담고
// 있어서, 이 페이지를 열 때마다(또는 새로고침할 때마다) 그 시점 최신 스케줄을 다시
// fetch함 - 예전 SB1: 포맷(스케줄 전체를 링크에 그대로 박제)과 달리 진짜 "실시간에
// 가까운" 링크가 됨 (친구공유_v1_스펙.md 참고).
// ⭐ PWA 재실행 버그 수정: 홈 화면에 저장한 뒤 아이콘으로 재실행하면 manifest.json의
// start_url(코드 없는 루트)로 열려서 code 파라미터가 없음 - 마지막으로 성공 조회한
// ownerId를 localStorage에 저장해두고, URL에 code가 없을 때 그걸로 폴백함.
//
// ⭐ 링크 형태 예시: https://<배포도메인>/#/?code=SB2:3f9a1c2e-...
// (해시 라우팅이라 정적 호스팅 어디에 올려도 새로고침 시 404가 안 남)
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/friend_schedule.dart';
import 'services/friend_share_service.dart';
import 'services/friend_sync_service.dart';
import 'services/firebase_bootstrap.dart';
import 'screens/friend_calendar_view.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/l10n_extensions.dart';

const _kLastOwnerIdStorageKey = 'shiftbell_last_owner_id';

void main() async {
  // ⭐ FriendCalendarView가 이제 table_calendar를 locale: 'ko_KR'로 쓰기 때문에
  // (진짜 앱의 calendar_tab.dart와 동일) 날짜 심볼 데이터를 미리 초기화해야 함 -
  // 안 하면 intl이 LocaleDataException을 던짐. main.dart와 동일한 초기화 패턴.
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR', null);
  await initializeDateFormatting('en_US', null);
  // ⭐ 이 웹뷰어는 Firestore에서 남의 스케줄을 읽기만 함 - DB/MethodChannel 없이도
  // Firebase만 초기화하면 됨. 플레이스홀더 상태면 조용히 실패하고 아래 라우터가
  // "동기화 실패" 화면을 보여줌 (firebase_bootstrap.dart 참고).
  await initFirebase();
  runApp(const ShiftBellWebViewApp());
}

class ShiftBellWebViewApp extends StatelessWidget {
  const ShiftBellWebViewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 780),
      minTextAdapt: true,
      builder: (context, child) {
        return MaterialApp(
          onGenerateTitle: (context) => '${context.l10n.appTitle} - ${context.l10n.friendShareTitle}',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
          home: const _WebViewRouter(),
        );
      },
    );
  }
}

// ⭐ 브라우저 주소창의 code 파라미터(없으면 localStorage 폴백)를 ownerId로 풀어서
// Firestore에서 최신 스케줄을 fetch함.
class _WebViewRouter extends StatefulWidget {
  const _WebViewRouter();

  @override
  State<_WebViewRouter> createState() => _WebViewRouterState();
}

class _WebViewRouterState extends State<_WebViewRouter> {
  late final Future<_LoadResult> _future = _load();

  String? _extractCode() {
    final uri = Uri.base;
    // ⭐ 일반 쿼리(?code=...)와 해시 라우팅(#/?code=...) 둘 다 지원.
    if (uri.queryParameters.containsKey('code')) {
      return uri.queryParameters['code'];
    }
    final fragment = uri.fragment; // 예: "/?code=SB2:xxxx"
    if (fragment.contains('code=')) {
      final fragUri = Uri.tryParse(fragment.startsWith('/') ? fragment : '/$fragment');
      return fragUri?.queryParameters['code'];
    }
    return null;
  }

  Future<_LoadResult> _load() async {
    final code = _extractCode();
    var ownerId = code != null ? FriendShareService.decodeOwnerId(code) : null;

    if (ownerId == null) {
      // ⭐ 홈 화면 아이콘으로 재실행 등, URL에 code가 아예 없을 때만 폴백.
      try {
        ownerId = html.window.localStorage[_kLastOwnerIdStorageKey];
      } catch (_) {
        // localStorage 접근 자체가 막힌 브라우저 설정 등 - 그냥 폴백 없이 진행.
      }
      if (ownerId == null) return _LoadResult.invalidLink(context.l10n.friendLinkMissingCode);
    }

    final data = await FriendSyncService.instance.fetchByOwnerId(ownerId);
    if (data == null) {
      return _LoadResult.invalidLink(context.l10n.friendLoadFailedDetailed);
    }

    try {
      html.window.localStorage[_kLastOwnerIdStorageKey] = ownerId;
    } catch (_) {}

    return _LoadResult.success(data);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LoadResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final result = snapshot.data;
        if (result == null || result.data == null) {
          return _InvalidLinkPage(reason: result?.reason ?? context.l10n.friendUnknownError);
        }
        return FriendCalendarView(
          friendName: result.data!.ownerName,
          data: result.data!,
          showInstallPrompt: true,
          onInstallTap: openPlayStore,
        );
      },
    );
  }
}

class _LoadResult {
  final FriendScheduleData? data;
  final String? reason;
  const _LoadResult.success(FriendScheduleData this.data) : reason = null;
  const _LoadResult.invalidLink(String this.reason) : data = null;
}

class _InvalidLinkPage extends StatelessWidget {
  final String reason;
  const _InvalidLinkPage({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_off, size: 48.sp, color: Colors.grey),
              SizedBox(height: 16.h),
              Text(context.l10n.friendCouldNotLoad, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 8.h),
              Text(reason, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ⭐ "앱 설치하고 실시간으로 보기" 버튼에서 쓸 스토어 링크. 실제 배포 후 이
// 값만 실제 Play Store URL로 바꾸면 됨 (funnel 3단계 - 웹→앱 설치 유도).
const String kPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.hwani1103.shiftbell';

Future<void> openPlayStore() async {
  final uri = Uri.parse(kPlayStoreUrl);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
