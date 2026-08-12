// lib/web_main.dart
//
// ⭐ 트랙1(웹/PWA) 전용 entry point - 진짜 앱(lib/main.dart)과 완전히 분리된
// 별도의 아주 가벼운 Flutter Web 앱. `flutter build web -t lib/web_main.dart`로
// 따로 빌드함. 진짜 앱의 main.dart는 sqflite(DB)/MethodChannel(네이티브 알람)에
// 강하게 의존하는데, 그건 전부 웹에서 동작 안 하거나 의미가 없어서(웹 방문자는
// 자기 스케줄이 없음 - 남의 스케줄을 "보기만" 하러 옴) 아예 안 씀.
//
// ⭐ 서버/Firebase 없이 동작하는 이유: 공유 코드 자체(FriendShareService로
// base64 인코딩된 JSON)를 URL의 쿼리 파라미터(?code=...)에 통째로 실어서
// 전달함. 이 웹 페이지는 그 URL을 열자마자 code를 그대로 디코딩해서 보여주는
// 것뿐이라 백엔드가 필요 없음 - 정적 파일(build/web 폴더)만 아무 호스팅에
// 올려두면 끝. (나중에 Firebase Firestore를 붙이면 code 대신 문서 ID를 받아서
// "실시간 최신 데이터"를 보여주는 것으로 업그레이드 가능 - 그때도 이 화면의
// UI는 그대로 두고 데이터 가져오는 부분만 바꾸면 됨.)
//
// ⭐ 링크 형태 예시: https://<배포도메인>/#/?code=SB1:eyJvd25lck5hbWUiOi...
// (해시 라우팅이라 정적 호스팅 어디에 올려도 새로고침 시 404가 안 남)
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/friend_share_service.dart';
import 'screens/friend_calendar_view.dart';

void main() async {
  // ⭐ FriendCalendarView가 이제 table_calendar를 locale: 'ko_KR'로 쓰기 때문에
  // (진짜 앱의 calendar_tab.dart와 동일) 날짜 심볼 데이터를 미리 초기화해야 함 -
  // 안 하면 intl이 LocaleDataException을 던짐. main.dart와 동일한 초기화 패턴.
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR', null);
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
          title: '교대시계 - 공유 달력 보기',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
          home: const _WebViewRouter(),
        );
      },
    );
  }
}

// ⭐ 브라우저 주소창의 code 파라미터를 읽어서 분기함.
class _WebViewRouter extends StatelessWidget {
  const _WebViewRouter();

  String? _extractCode() {
    final uri = Uri.base;
    // ⭐ 일반 쿼리(?code=...)와 해시 라우팅(#/?code=...) 둘 다 지원.
    if (uri.queryParameters.containsKey('code')) {
      return uri.queryParameters['code'];
    }
    final fragment = uri.fragment; // 예: "/?code=SB1:xxxx"
    if (fragment.contains('code=')) {
      final fragUri = Uri.tryParse(fragment.startsWith('/') ? fragment : '/$fragment');
      return fragUri?.queryParameters['code'];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final code = _extractCode();
    if (code == null || code.isEmpty) {
      return const _InvalidLinkPage(reason: '링크에 공유 코드가 없어요.');
    }

    final data = FriendShareService.decode(code);
    if (data == null) {
      return const _InvalidLinkPage(reason: '공유 코드를 읽을 수 없어요. 링크가 손상됐거나 오래됐을 수 있어요.');
    }

    return FriendCalendarView(
      friendName: data.ownerName,
      data: data,
      showInstallPrompt: true,
      onInstallTap: openPlayStore,
    );
  }
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
              Text('유효하지 않은 링크입니다', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
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
