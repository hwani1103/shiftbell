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
// ⭐ 링크 형태 예시: https://<배포도메인>/?code=SB2:3f9a1c2e-...
// ⭐ 2026-08-16: 해시 라우팅(#/?code=...)에서 일반 경로/쿼리(?code=...)로 전환함.
// 카카오톡으로 링크를 공유했을 때(카톡 안에서 열면 되는데, 그 링크를 복사해서 일반
// 브라우저에서 열면 "공유 코드가 없어요" 에러가 나는 버그 리포트) - 메신저의 링크
// 미리보기/안전링크 처리 과정에서 URL의 "#" 뒤쪽(프래그먼트)이 브라우저 밖 어딘가에서
// 유실될 가능성이 있고(프래그먼트는 원래 서버에 전달되지 않는 순수 브라우저 전용
// 개념이라, 링크를 다루는 중간 단계에서 가장 잘리기 쉬운 부분), 실제로 카톡
// 안에서는 되고 일반 브라우저에서는 안 되는 비대칭 증상과도 맞아떨어짐. firebase.json의
// hosting rewrite가 이미 모든 경로를 index.html로 돌려주게 돼있어서("source": "**")
// 일반 경로로 바꿔도 새로고침 시 404 걱정 없음. 기존에 이미 뿌려진 구형(#/?code=...)
// 링크도 계속 동작하도록 _extractCode()의 프래그먼트 파싱은 그대로 남겨둠(폴백).
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
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

// ⭐ 카카오톡/인스타그램/라인/네이버 등 "인앱 브라우저"(메신저 안에 내장된 미니
// 웹뷰)는 주소창 자체가 없어서(또는 있어도 PWA 설치 아이콘을 지원 안 해서) 상단
// "작업 표시줄의 설치 버튼을 눌러주세요" 안내가 실제로 따라할 수 없는 조언이 됨
// - 사용자가 "PWA 설치 버튼이 안 보인다"고 느끼는 지점. User-Agent로 대표적인
// 인앱 브라우저를 감지해서 그 안내만 숨김(하단 "앱 설치"(Play스토어 이동) 버튼은
// 인앱 브라우저에서도 대부분 정상 동작해서 그대로 유지함).
bool _isLikelyInAppBrowser() {
  try {
    final ua = html.window.navigator.userAgent.toLowerCase();
    return ua.contains('kakaotalk') ||
        ua.contains('instagram') ||
        ua.contains('fban') || // Facebook 앱
        ua.contains('fbav') ||
        ua.contains('line/') ||
        ua.contains('naver');
  } catch (_) {
    return false;
  }
}

// ⭐ 2026-08-17 추가 - "카톡/네이버 등에서 링크를 누르면 그 안의 인앱
// 브라우저로 열려서, 정상적인 PWA 설치/즐겨찾기/주소 복사가 안 된다"는 문제의
// 실질적 해결책. 안드로이드의 intent:// 스킴을 이용해 "이 페이지, 진짜 브라우저로
// 다시 열어줘"라고 OS에 직접 요청함 - 은행/결제 사이트들이 카톡 인앱 브라우저를
// 피하려고 실제로 쓰는 방식과 동일. 인앱 브라우저가 이 요청 자체를 막지만
// 않으면(대부분 안 막음) 거의 즉시 진짜 브라우저로 넘어가고, 거기서부턴 정상
// 동작함.
//
// ⭐ 목적지를 크롬(com.android.chrome)으로 함. 처음엔 삼성 인터넷으로
// 시도했었는데(실사용 테스트에서 주소창 옆에 "설치" 버튼이 바로 보였음), "여러
// 제조사 기기에 걸쳐 실패 가능성이 가장 낮은 타겟이 뭐냐"를 다시 따져보면 -
// 크롬은 구글 모바일 서비스(Play 스토어)가 있는 사실상 모든 안드로이드
// 기기(제조사 무관)에 기본 탑재가 강제되는 반면, 삼성 인터넷은 삼성 기기에만
// 기본 탑재됨. 그래서 "하나의 브라우저로 일관되게" 유도한다는 목표엔 크롬이
// 더 안전한 선택. 대신 크롬은 주소창에 눈에 보이는 설치 버튼이 없는 대신
// beforeinstallprompt 이벤트를 지원하므로, 그걸 잡아서 우리 화면에 직접
// "바로가기 추가" 버튼을 띄우는 방식으로 보완함(아래 _listenForInstallPrompt
// 참고) - 그래서 굳이 "주소창을 보세요" 안내가 필요 없어짐.
// ⭐ 크롬이 없는 극히 드문 기기(중국 내수용 등 구글 서비스 자체가 없는 기기)에서는
// intent 해석이 실패하고 S.browser_fallback_url로 원래 주소를 그대로
// 폴백함(지금 인앱 브라우저 안에서 계속 보임 - 최소한 지금보다 나빠지진 않음).
// ⭐ iOS는 이 스킴 자체가 없어서(그리고 이 프로젝트의 네이티브 앱 자체가
// 안드로이드 전용이라) 안드로이드에서만 시도함 - iOS/이미 정상 브라우저인
// 경우는 그냥 지금 페이지를 그대로 계속 씀(아래 함수가 그 경우 즉시 리턴).
void _bounceToRealBrowserIfInAppBrowser() {
  if (!_isLikelyInAppBrowser()) return;
  try {
    final ua = html.window.navigator.userAgent.toLowerCase();
    if (!ua.contains('android')) return;
    final currentUrl = html.window.location.href;
    final withoutScheme = currentUrl.replaceFirst(RegExp(r'^https?://'), '');
    final intentUrl = 'intent://$withoutScheme#Intent;scheme=https;package=com.android.chrome;'
        'S.browser_fallback_url=${Uri.encodeComponent(currentUrl)};end';
    html.window.location.href = intentUrl;

    // ⭐ 크롬이 실제로 설치돼 있는지는 웹페이지 입장에서 직접 확인할 방법이
    // 없음(보안상 브라우저가 설치된 앱 목록을 안 알려줌) - 대신 "전환에 성공하면
    // 이 탭이 백그라운드로 내려가면서 visibilityState가 hidden이 된다"는
    // 사실로 간접 판단함. intent 발사 후 1.5초가 지나도 여전히 화면이 보이고
    // 있으면(=전환 실패, 크롬 미설치로 추정 - 매우 드문 케이스) 크롬 설치
    // 페이지(Play 스토어)로 안내함. 설치 후에는 원래 링크를 다시 열어야 함
    // (자동 재시도는 불가능 - 이 페이지 자체가 스토어로 넘어가며 사라지므로).
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (html.document.visibilityState == 'visible') {
        html.window.location.href = 'https://play.google.com/store/apps/details?id=com.android.chrome';
      }
    });
  } catch (_) {
    // ⭐ intent:// 자체를 막는 인앱 브라우저 등 - 조용히 무시하고 지금 페이지
    // 그대로 계속 진행(위 PWA 안내 배너가 수동 대안으로 남아있음).
  }
}

// ⭐ 2026-08-17 추가 - "주소창에서 설치 버튼을 찾아서 누르세요" 같은 안내
// 대신, 크롬이 표준으로 지원하는 beforeinstallprompt 이벤트를 우리가 직접
// 가로채서 화면에 우리 버튼("바로가기 추가")을 보여주고, 그 버튼을 누르면
// 브라우저의 진짜 설치 팝업을 바로 띄우는 방식. 이러면 사용자는 브라우저
// 메뉴/설정을 뒤질 필요 없이 화면에 보이는 버튼 하나만 누르면 됨.
// ValueNotifier로 들고 있는 이유: 이 이벤트가 페이지 로드 후 비동기로(브라우저가
// "설치할 만한 페이지인지" 판단한 뒤) 나중에 발생하기 때문에, 화면(위젯 트리)이
// 그 시점에 맞춰 다시 그려져야 버튼이 나타남.
final ValueNotifier<Object?> deferredInstallPrompt = ValueNotifier(null);

void _listenForInstallPrompt() {
  try {
    html.window.addEventListener('beforeinstallprompt', (event) {
      // ⭐ 기본 동작(크롬이 자체적으로 하단에 작은 배너를 띄우는 것)을 막고,
      // 우리가 원하는 타이밍(우리 버튼을 눌렀을 때)에만 띄우기 위해 이벤트
      // 자체를 저장해둠 - 딱 한 번만 쓸 수 있는 "티켓" 같은 객체라 나중에
      // js_util로 그 안의 prompt() 메서드를 직접 호출함.
      event.preventDefault();
      deferredInstallPrompt.value = event;
    });
    // ⭐ 이미 설치를 마치면(또는 사용자가 우리 버튼으로 설치를 완료하면) 버튼을
    // 다시 숨김 - 설치된 뒤에도 계속 "바로가기 추가" 버튼이 남아있으면 어색함.
    html.window.addEventListener('appinstalled', (event) {
      deferredInstallPrompt.value = null;
    });
  } catch (_) {
    // ⭐ beforeinstallprompt 자체를 지원 안 하는 브라우저(사파리 등) - 그냥
    // 버튼이 영영 안 뜨는 것으로 조용히 처리됨(하단 "앱 설치" 버튼은 별개로
    // 항상 남아있음).
  }
}

Future<void> triggerInstallPrompt() async {
  final event = deferredInstallPrompt.value;
  if (event == null) return;
  js_util.callMethod(event, 'prompt', const []);
  deferredInstallPrompt.value = null;
}

void main() async {
  // ⭐ Firebase 초기화 등 무거운 작업을 하기 전에 먼저 시도 - 튕겨나갈 거면
  // 그 작업들이 낭비이기도 하고, 최대한 빨리 진짜 브라우저로 넘어가는 게
  // 사용자 체감상 더 매끄러움.
  _bounceToRealBrowserIfInAppBrowser();
  _listenForInstallPrompt();

  // ⭐ FriendCalendarView가 이제 table_calendar를 locale: 'ko_KR'로 쓰기 때문에
  // (진짜 앱의 calendar_tab.dart와 동일) 날짜 심볼 데이터를 미리 초기화해야 함 -
  // 안 하면 intl이 LocaleDataException을 던짐. main.dart와 동일한 초기화 패턴.
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
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
      final fromFragment = fragUri?.queryParameters['code'];
      if (fromFragment != null) return fromFragment;
    }
    // ⭐ 최후 방어선: 위 두 정상 경로가 다 실패해도, 주소 표시줄 전체 문자열
    // 어딘가에 SB2:코드 패턴이 살아있으면 정규식으로 직접 뽑아냄 - 메신저를
    // 거치며 URL이 일부 손상되는 경우(my_share_code_screen.dart의 콜론(:)
    // 인코딩 문제로 실제 재현됨) 대비한 안전망. 지금은 콜론을 %3A로 인코딩해서
    // 근본 원인을 고쳤지만, 다른 메신저/브라우저 조합에서 또 다른 방식으로
    // 손상될 가능성까지 막기 위해 남겨둠.
    final full = Uri.decodeFull(uri.toString());
    final match = RegExp(r'(SB2:[^\s&"]+)').firstMatch(full);
    if (match != null) return match.group(1);
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
        // ⭐ deferredInstallPrompt는 페이지 로드 후 비동기로 값이 채워질 수
        // 있어서(브라우저가 판단하는 타이밍), ValueListenableBuilder로 감싸서
        // 그 값이 바뀔 때 "바로가기 추가" 버튼이 즉시 나타나게 함.
        return ValueListenableBuilder<Object?>(
          valueListenable: deferredInstallPrompt,
          builder: (context, promptEvent, _) {
            return FriendCalendarView(
              friendName: result.data!.ownerName,
              data: result.data!,
              showInstallPrompt: true,
              showPwaAddressBarHint: !_isLikelyInAppBrowser(),
              showQuickInstallButton: promptEvent != null,
              onQuickInstallTap: triggerInstallPrompt,
              onInstallTap: openPlayStore,
            );
          },
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
