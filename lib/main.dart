import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants/platform_channel.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/alarm_service.dart';
import 'services/permission_service.dart';
import 'services/database_service.dart';
import 'services/update_service.dart';
import 'screens/next_alarm_tab.dart';
import 'screens/calendar_tab.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_tab.dart';
import 'screens/friend_list_screen.dart';
import 'screens/permission_intro_screen.dart';
import 'screens/ui_theme_lab_screen.dart'; // ⭐ 2026-08-25 - 아이콘 색상 후보 재검토용으로 임시 재활성화
import 'widgets/permission_warning_banner.dart';
import 'widgets/banner_ad_slot.dart';
import 'services/ad_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shift_schedule.dart';
import 'providers/alarm_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/calendar_theme_provider.dart';
import 'models/calendar_theme.dart';
import 'theme/app_theme.dart';
import 'services/firebase_bootstrap.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/l10n_extensions.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⭐ 릴리즈 빌드는 기본적으로 위젯 빌드 중 에러가 나면 그냥 빈 회색 박스만
  // 보여주고 원인을 숨김 (디버그 빌드의 "빨간 에러 화면"과 다름). 그래서
  // "가끔 화면이 백지로 보인다" 같은 문제의 실제 원인을 릴리즈에서는 알 수가
  // 없었음 - 릴리즈에서도 어떤 에러인지 최소한 화면에 보이게 함.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // ⭐ context에 "어느 위젯을 빌드하다가" 났는지가 요약돼 있어서, 메시지만으로
    // 재현 상황을 특정하기 어려운 버그(예: 특정 화면에서만 5초 이내에 재현) 리포트 시
    // 훨씬 빨리 원인 파일/위젯을 좁힐 수 있음.
    final contextSummary = details.context?.toDescription() ?? '';

    // ⭐ 스택 트레이스에서 이 앱 코드(package:shiftbell/...)에 해당하는 줄만 몇 개
    // 뽑아서 보여줌 - "Null check operator..." 같은 메시지만으로는 어느 파일/몇
    // 번째 줄인지 알 수 없어서 원인 특정이 안 됐는데, 이게 있으면 바로 짚을 수 있음.
    final appFrames = (details.stack?.toString().split('\n') ?? [])
        .where((line) => line.contains('package:shiftbell/'))
        .take(3)
        .join('\n');

    return Container(
      color: Colors.red.shade50,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Text(
          '⚠️ 화면 표시 오류\n${details.exceptionAsString()}'
          '${contextSummary.isNotEmpty ? '\n($contextSummary)' : ''}'
          '${appFrames.isNotEmpty ? '\n\n$appFrames' : ''}',
          style: const TextStyle(color: Colors.red, fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ),
    );
  };

  // ⭐ 런치 스크린 유지 시간 (0.3초)
  await Future.delayed(const Duration(milliseconds: 300));

  // ⭐ 영어 현지화: 이제 기기 로케일에 따라 ko_KR 또는 en_US 포맷터를 쓸 수 있어야
  // 하므로, 둘 다 미리 초기화해둠(하나만 초기화된 상태에서 다른 로케일 포맷터를
  // 쓰면 intl이 LocaleDataException을 던짐).
  await initializeDateFormatting('ko_KR', null);
  await initializeDateFormatting('en_US', null);
  await DatabaseService.instance.database;
  await AlarmService().initialize();
  // ⭐ 친구공유(Firestore) 초기화 - firebase_options.dart가 아직 플레이스홀더면
  // 조용히 실패하고 친구공유 기능만 비활성화됨 (firebase_bootstrap.dart 참고).
  await initFirebase();

  // ⭐ 앱 시작 전에 달력 테마 미리 로드 (깜빡임 방지) - 예전엔 "다크모드
  // on/off"를 미리 읽었는데, 이제는 9개 달력 테마 중 뭐가 선택돼 있는지를
  // 미리 읽음. 앱 전체 밝기는 항상 라이트 고정이고, 이 값은 오직 (1) 달력
  // 탭 자체가 어떤 테마로 그려질지 (2) 시스템 상태표시줄 아이콘 밝기에만 씀.
  // ⭐ 광고 SDK 초기화 + 배너가 차지할 높이를 첫 프레임 전에 미리 확정해둠.
  // 화면을 그리는 중에 높이를 구하면 "높이 모르는 프레임 → 아는 프레임"으로 한 번
  // 튀는데, 그 튐을 막는 게 이 슬롯의 목적이라 여기서 미리 함.
  // 실패해도 예외를 던지지 않고 fallback 높이로 넘어감 (ad_service.dart 참고).
  await AdService.warmUp();

  final initialCalendarTheme = await CalendarThemeNotifier.loadInitial();

  runApp(
    ProviderScope(
      overrides: [
        calendarThemeProvider.overrideWith((ref) => CalendarThemeNotifier.withInitial(initialCalendarTheme)),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static const platform = kAlarmChannel;

  @override
  void initState() {
    super.initState();

    // ⭐ 앱 라이프사이클 감지
    WidgetsBinding.instance.addObserver(this);

    // ⭐ MethodChannel handler는 MainScreen에서 등록 (중복 방지)
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ⭐ 앱이 포그라운드로 돌아올 때마다 체크
  // main.dart - _MyAppState
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);

  if (state == AppLifecycleState.resumed) {
    // ⭐ Native MainActivity.onResume()이 이미 자체적으로 AlarmGuardReceiver.triggerCheck()를
    // 호출해서 갱신 필요 여부를 판단/실행함 (Dart에서 또 트리거하면 중복이라 제거함).
    // 여기서는 화면에 보여줄 데이터만 새로고침하면 됨.
    print('📱 앱 포그라운드 진입 - UI 새로고침');

    // ⭐ 추가: AlarmNotifier도 강제 갱신
    if (mounted) {
      try {
        final container = ProviderScope.containerOf(context);
        container.read(alarmNotifierProvider.notifier).refresh();
        print('✅ AlarmNotifier 강제 갱신 완료');
      } catch (e) {
        print('❌ AlarmNotifier 갱신 실패: $e');
      }
    }
  }
}

  // 6.5인치 기준 최대 너비 (Fold 7 펼친 상태 대응)
  static const double maxContentWidth = 500.0;

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 780),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        // ⭐ MaterialApp만 Consumer로 감싸기 (MyApp rebuild 방지)
        return Consumer(
          builder: (context, ref, _) {
            // ⭐ "다크모드"라는 전역 개념은 없앰 - 앱 자체는 항상 라이트로
            // 고정(theme만 지정, darkTheme/themeMode 없음). 유일하게 선택된
            // 달력 테마(9개 중 하나)가 다크(메인·다크)일 때만, 시스템
            // 상태표시줄(시계/배터리/알림) 아이콘을 밝게 바꿔줌 - 그 외
            // 앱 UI는 전부 라이트 그대로.
            final isCalendarThemeDark = ref.watch(calendarThemeProvider).isDark;

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: isCalendarThemeDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
              child: MaterialApp(
                onGenerateTitle: (context) => context.l10n.appTitle,
                // ⭐ 영어 현지화 인프라 - flutter_localizations(SDK) + 이 앱의
                // AppLocalizations(lib/l10n/app_ko.arb, app_en.arb에서 생성).
                // 기본은 기기 로케일을 그대로 따름(localeResolutionCallback 없음
                // → Flutter가 supportedLocales 중 기기 로케일과 가장 잘 맞는 걸
                // 자동 선택하고, 지원 안 하는 로케일이면 첫 번째=ko로 폴백).
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.lightTheme,
                // 모든 화면에 최대 너비 제한 적용
                // ⭐ 2026-08-24 - 컨텐츠 영역 배경을 단색(Colors.white)에서 앱
                // 톤에 맞춘 은은한 그라데이션으로 바꿈("배경이 단색이라 딱딱하다"는
                // 피드백). 여기 한 곳만 바꾸면 앱 전체 배경이 다 같이 바뀜 -
                // AppTheme.lightTheme의 scaffoldBackgroundColor를 투명으로 해뒀기
                // 때문에(app_theme.dart 참고) 각 화면의 Scaffold가 이 그라데이션을
                // 가리지 않고 그대로 비쳐 보임. 달력 탭만 예외 - CalendarTab이
                // 자기 Scaffold에 Colors.white를 직접 불투명하게 고정해뒀으므로
                // (calendar_tab.dart 참고) 이 그라데이션의 영향을 안 받음.
                // ⭐ 2026-08-24 - 그라데이션 시도(kAppBackgroundGradientTop/Bottom,
                // app_colors.dart에 값은 남겨둠)를 보류하고 흰색 고정으로 되돌림 -
                // InitialRouter(로딩 게이트)가 네이티브 스플래시와 맞추려고 항상
                // 불투명 흰색인데, 그 뒤에 그라데이션이 깔려 있으면 다음 화면으로
                // 넘어가는 순간 "가려져 있던 그라데이션이 드러나는" 깜빡임이
                // 생김 - 전환 애니메이션을 없애도(main.dart의 _instantRoute)
                // 여전히 보인다는 피드백을 받아서, 아예 같은 흰색으로 통일해
                // 이 깜빡임의 근본 원인 자체를 없앰.
                builder: (context, child) {
                  return Container(
                    color: Colors.grey.shade200,  // 넓은 화면에서 양옆 배경색 - 항상 라이트
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: maxContentWidth),
                        child: Container(
                          color: Colors.white,  // 컨텐츠 영역 배경 - 항상 라이트
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                home: const InitialRouter(),
                routes: {
                  '/permission_intro': (context) => const PermissionIntroScreen(),
                  '/onboarding': (context) => const OnboardingScreen(),
                  // '/home' 경로는 제거 - InitialRouter에서 직접 MainScreen 생성
                },
              ),
            );
          },
        );
      },
    );
  }
}

class MainScreen extends ConsumerStatefulWidget {
  final int initialIndex;  // ⭐ 초기 탭 인덱스 받기
  const MainScreen({super.key, required this.initialIndex});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

// ⭐ 2026-08-20 "업데이트 있다는 안내가 안 뜬다" 신고로 발견 - 예전엔
// UpdateService.checkForUpdate()가 MainScreen.initState()에서 딱 한 번만(즉 콜드
// 스타트 1회) 불렸음. 근데 대부분의 사용자는 앱을 아예 껐다 켜기보다 "최근 앱"에서
// 다시 열거나(백그라운드→포그라운드 재개) 화면만 켜서 보는 식으로 하루 종일 씀 -
// initState는 프로세스가 살아있는 동안 재실행되지 않으므로, 콜드 스타트 시점에 아직
// Play가 새 버전을 인지 못 했으면(배포 직후 전파 지연은 흔함) 그날 다시는 체크할
// 기회가 없었음. WidgetsBindingObserver로 "앱이 포그라운드로 돌아올 때"마다 다시
// 체크하도록 함 - UpdateService.checkForUpdate() 자체가 이미 "이 버전은 이미
// 안내했다" 여부를 버전코드로 dedupe하므로 스팸 다이얼로그 걱정은 없고, 추가로
// update_service.dart에 쿨다운을 둬서 Play Core 호출 자체도 너무 잦지 않게 함.
class _MainScreenState extends ConsumerState<MainScreen> with WidgetsBindingObserver {
  late int _currentIndex;  // ⭐ nullable 제거
  static const platform = kAlarmChannel;

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ⭐ 초기 탭 설정 (InitialRouter에서 결정한 값)
    _currentIndex = widget.initialIndex;

    // ⭐ 탭 생성 (callback 전달) - "달력테마" 탭은 제거함. 테마 실험은 다
    // 끝났고 실제 선택 UI가 설정 탭 안으로 들어갔으니(테마 캐러셀 화면),
    // 메인 탭 구성이 원래대로 3개로 되돌아옴.
    //
    // ⭐ CalendarTab만 Consumer+Theme로 한 겹 감쌈 - CalendarTab 내부의
    // Theme.of(context) 호출들(_buildDateCell/_buildMonthlyOvertimeCard 등,
    // this.context를 그대로 씀)이 선택된 달력 테마가 다크(메인·다크)일 때
    // 실제로 다크 배색을 받게 하려면, CalendarTab "자기 자신"보다 위쪽
    // 트리에서 Theme를 덮어써야 함 - CalendarTab의 build() 안에서 return값만
    // Theme로 감싸면 this.context 기준 조회는 여전히 그 감싼 지점보다 위를
    // 보게 되어 아무 효과가 없음(BuildContext는 위치 기반 조회라 이렇게
    // 바깥에서 감싸는 게 유일하게 확실한 방법).
    // ⭐ "일정공유(구 친구공유)"를 설정 탭 안에 묻혀있던 항목에서 메인
    // 바텀 네비게이션 4번째 탭으로 승격 - 다음알람(0)/달력(1)/일정공유(2)/설정(3).
    // Native(Kotlin)에서 openTab으로 보내는 인덱스는 0(다음알람)/1(달력)뿐이라
    // 이 순서 변경의 영향을 안 받음(AlarmGuardReceiver.kt/NotificationHelper.kt
    // /CalendarWidgetProvider.kt 확인함).
    _tabs = [
      NextAlarmTab(onSwipeToCalendar: () => _goToCalendar()),
      Consumer(
        builder: (context, ref, _) {
          final isDark = ref.watch(calendarThemeProvider).isDark;
          return Theme(
            data: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
            child: CalendarTab(),
          );
        },
      ),
      FriendListScreen(onSwipeToCalendar: () => _goToCalendar()),
      SettingsTab(onSwipeToCalendar: () => _goToCalendar()),
      // ⭐ 2026-08-25 - 아이콘 색상 후보를 다시 검토하기 위해 임시로 재활성화.
      // 나머지(잠금화면/오버레이/다음알람탭/메인 컬러 테마)는 이미 확정 반영
      // 완료된 상태 - 이 탭은 이제 순수하게 "실제 적응형 아이콘 렌더링과
      // 100% 동일한 아이콘 색상 후보 갤러리" 역할만 함(ui_theme_lab_screen.dart
      // 참고). 최종 색상이 정해지면 다시 주석 처리할 것.
      const UiThemeLabScreen(),
    ];

    // ⭐ _scheduleGuardWakeup()이 triggerGuardCheck를 호출해서 Native 갱신 판단/실행까지 함
    // (예전엔 여기서 AlarmRefreshService도 따로 호출해서 Native와 중복 실행되는 문제가 있었음)
    _scheduleGuardWakeup();

    // ⭐ Method Call Handler 등록
    platform.setMethodCallHandler(_handleMethod);

    // ⭐ Provider 사전 로드 (첫 탭 전환 시 버벅임 방지)
    Future.microtask(() {
      final container = ProviderScope.containerOf(context);
      // 알람 Provider 갱신
      container.read(alarmNotifierProvider.notifier).refresh();
      // 스케줄 Provider 사전 로드 (CalendarTab, SettingsTab 첫 진입 시 loading 방지)
      container.read(scheduleProvider);
    });

    // ⭐ 업데이트 체크 (2초 후 - UI 로딩 완료 후)
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      // 이번 업데이트로 막 올라온 사용자에게 한 번만 보여주는 안내가 있으면 먼저 표시
      await UpdateService.checkAndShowReleaseNote(context);
      if (!mounted) return;
      UpdateService.checkForUpdate(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ⭐ 클래스 선언부 주석 참고 - 앱을 백그라운드에서 포그라운드로 복귀할 때마다
  // 업데이트 여부를 다시 체크함(콜드 스타트 1회로는 배포 직후 전파 지연 구간을
  // 영영 놓칠 수 있어서). 릴리즈 노트는 여기서 다시 안 부름 - 그건 "버전당 1회"
  // 정책이라 이미 봤으면 checkAndShowReleaseNote 내부에서 알아서 스킵하지만,
  // 굳이 앱을 복귀할 때마다 또 체크할 필요는 없어서 콜드 스타트 경로에만 남겨둠.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      UpdateService.checkForUpdate(context);
    }
  }

  // ⭐ 6번 기능: 달력탭으로 이동
  void _goToCalendar() {
    setState(() => _currentIndex = 1);
  }

  Future<void> _scheduleGuardWakeup() async {
    try {
      // ⭐ triggerGuardCheck()가 내부에서 scheduleNextWakeup()도 호출함
      // scheduleGuardWakeup()은 자정만 예약해서 20분전 예약을 덮어쓰는 버그 → 제거
      print('🔍 AlarmGuardReceiver 트리거');
      await platform.invokeMethod('triggerGuardCheck');
      print('✅ AlarmGuardReceiver 완료 (20분 전 예약 포함)');
    } catch (e) {
      print('❌ 감시 예약 실패: $e');
    }
  }

  // ⭐ Native에서 호출하는 메서드 처리 (통합 버전)
Future<void> _handleMethod(MethodCall call) async {
  print('📞 Method Call 수신: ${call.method}');

  if (call.method == 'refreshAlarms') {
    // ⭐ Native가 이미 갱신(AlarmRefreshEngine)을 끝내고 나서 UI만 새로고침해달라고
    // 보내는 신호임. 여기서 다시 갱신을 트리거하면 Native가 방금 한 일을 Dart가
    // 또 반복하는 꼴이라 삭제/재등록 경쟁 상태가 생김 - 그래서 UI 갱신만 함.
    print('🔄 Native 갱신 완료 신호 수신 - UI만 새로고침');

    try {
      if (mounted) {
        final container = ProviderScope.containerOf(context);
        await container.read(alarmNotifierProvider.notifier).refresh();
        print('✅ AlarmNotifier 새로고침 완료');
      }
    } catch (e) {
      print('❌ UI 새로고침 실패: $e');
    }

  } else if (call.method == 'openTab') {
    final tabIndex = call.arguments as int;
    print('📱 탭 이동 요청: $tabIndex');
    if (mounted) {
      setState(() {
        _currentIndex = tabIndex;
      });
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 1,  // 달력탭이면 앱 종료 허용
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 1) {
          // 달력탭이 아니면 달력탭으로 이동
          setState(() => _currentIndex = 1);
        }
      },
      child: Scaffold(
        // ⭐ 2026-08-24 - AppTheme.lightTheme.scaffoldBackgroundColor(현재 흰색)와
        // 같은 값을 여기 인스턴스에도 직접 명시함(hot reload에도 안전하게 -
        // onboarding_screen.dart의 같은 패턴 참고).
        backgroundColor: Colors.white,
        // ⭐ 2026-08-24 추가 - 배너 광고 자리(BannerAdSlot)를 탭 화면 바깥,
        // BottomNavigationBar 바로 위에 둠. Column으로 감싸서 "탭 컨텐츠(Expanded)
        // + 광고 슬롯" 순서로 쌓았고, 광고 슬롯은 Offstage로 감싸 달력 탭(index 1)일
        // 때만 자리를 차지하게 함.
        //
        // 왜 _tabs[_currentIndex]처럼 탭 안에 안 넣고 여기 두는가: 이 화면은
        // IndexedStack이 아니라 `_tabs[_currentIndex]` 하나만 트리에 올리는 구조라,
        // 탭을 옮기면 이전 탭 위젯이 통째로 dispose됨. 광고를 달력 탭 위젯 안에
        // 넣으면 달력 탭을 떠났다 돌아올 때마다 BannerAd와 그 안드로이드 플랫폼
        // 뷰가 매번 새로 생성돼서 (1) 탭 전환마다 버벅이고 (2) 광고가 매번 새로
        // 요청됨. Offstage는 자식을 계속 mount된 채로 유지하면서(=BannerAd/플랫폼
        // 뷰가 살아있음) 화면에서 크기·렌더링만 뺀다 - 그래서 탭을 몇 번을 오가도
        // 광고는 앱 시작 시 딱 한 번만 로드되고, 달력 탭으로 돌아오면 다시
        // "짠" 나타나기만 함(재생성 없음).
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  // 탭 화면
                  _tabs[_currentIndex],
                  // ⭐ 권한 경고 배너 (하단에 오버레이)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: const PermissionWarningBanner(),
                  ),
                ],
              ),
            ),
            // 달력 탭(index 1)에서만 자리를 차지함 - 다른 탭에선 높이 0.
            Offstage(
              offstage: _currentIndex != 1,
              child: const BannerAdSlot(),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: [
            BottomNavigationBarItem(icon: const Icon(Icons.alarm), label: context.l10n.navNextAlarm),
            BottomNavigationBarItem(icon: const Icon(Icons.calendar_month), label: context.l10n.navCalendar),
            BottomNavigationBarItem(icon: const Icon(Icons.people_outline), label: context.l10n.navFriendShare),
            BottomNavigationBarItem(icon: const Icon(Icons.settings), label: context.l10n.navSettings),
            // ⭐ 임시 재활성화(위 _tabs 주석 참고) - l10n 없이 직접 문자열.
            const BottomNavigationBarItem(icon: Icon(Icons.palette_outlined), label: '아이콘'),
          ],
        ),
      ),
    );
  }
}

// ... (AlarmTestScreen은 그대로 유지)

class AlarmTestScreen extends StatefulWidget {
  const AlarmTestScreen({super.key});

  @override
  State<AlarmTestScreen> createState() => _AlarmTestScreenState();
}

class _AlarmTestScreenState extends State<AlarmTestScreen> {
  DateTime selectedDateTime = DateTime.now().add(const Duration(minutes: 1));
  String selectedSoundType = 'loud';
  bool permissionsGranted = false;
  bool overlayPermissionGranted = false;

  final soundTypes = {
    'loud': '🔊 시끄러운 알람',
    'soft': '🔉 조용한 알람',
    'vibrate': '📳 진동만',
    'silent': '🔕 무음',
  };

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final permissions = await PermissionService().checkPermissions();
    final overlayPermission = await AlarmService().checkOverlayPermission();

    setState(() {
      permissionsGranted = permissions['notification']!;
      overlayPermissionGranted = overlayPermission;
    });
  }

  Future<void> _requestPermissions() async {
    final granted = await PermissionService().requestAllPermissions();

    await Future.delayed(const Duration(milliseconds: 500));
    final overlayPermission = await AlarmService().checkOverlayPermission();

    setState(() {
      permissionsGranted = granted;
      overlayPermissionGranted = overlayPermission;
    });

    if (granted && overlayPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 모든 권한 허용 완료')),
      );
    } else if (granted && !overlayPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ "다른 앱 위에 표시" 권한이 필요합니다'),
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('⚠️ 권한이 필요합니다'),
          action: SnackBarAction(
            label: '설정',
            onPressed: () => PermissionService().openSettings(),
          ),
        ),
      );
    }
  }

  Future<void> _requestOverlayPermission() async {
    await AlarmService().requestOverlayPermission();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⏳ 권한 설정 후 뒤로가기를 눌러주세요'),
        duration: Duration(seconds: 5),
      ),
    );

    await Future.delayed(const Duration(seconds: 3));
    _checkPermissions();
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDateTime),
    );

    if (time == null) return;

    setState(() {
      selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _scheduleAlarm() async {
    if (!permissionsGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 먼저 권한을 허용해주세요')),
      );
      return;
    }

    try {
      await AlarmService().scheduleAlarm(
        id: 1,
        dateTime: selectedDateTime,
        label: '테스트 알람',
        soundType: selectedSoundType,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 알람 등록 완료!\n${_formatDateTime(selectedDateTime)}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 알람 등록 실패: $e')),
      );
    }
  }

  Future<void> _scheduleTestAlarm() async {
    if (!permissionsGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 먼저 권한을 허용해주세요')),
      );
      return;
    }

    await AlarmService().scheduleTestAlarm(
      label: '5초 테스트',
      soundType: selectedSoundType,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(overlayPermissionGranted
          ? '🧪 5초 후 작은 팝업창이 뜹니다!'
          : '🧪 5초 후 전체 화면이 뜹니다!\n(Overlay 권한 없음)'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _cancelAlarm() async {
    await AlarmService().cancelAlarm(1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🗑️ 알람 취소됨')),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}월 ${dt.day}일 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔔 교대종 알람 테스트'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: permissionsGranted && overlayPermissionGranted
                  ? Colors.green.shade50
                  : Colors.orange.shade50,
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Column(
                  children: [
                    Icon(
                      permissionsGranted && overlayPermissionGranted
                          ? Icons.check_circle
                          : Icons.warning,
                      color: permissionsGranted && overlayPermissionGranted
                          ? Colors.green
                          : Colors.orange,
                      size: 48.sp,
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      permissionsGranted && overlayPermissionGranted
                          ? '모든 권한 허용됨'
                          : '권한 필요',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      '알림: ${permissionsGranted ? "✅" : "❌"}\n'
                      '다른 앱 위 표시: ${overlayPermissionGranted ? "✅" : "❌"}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14.sp),
                    ),
                    if (!permissionsGranted || !overlayPermissionGranted) ...[
                      SizedBox(height: 12.h),
                      ElevatedButton(
                        onPressed: _requestPermissions,
                        child: const Text('기본 권한 요청'),
                      ),
                      if (!overlayPermissionGranted) ...[
                        SizedBox(height: 8.h),
                        OutlinedButton.icon(
                          onPressed: _requestOverlayPermission,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('다른 앱 위에 표시 권한'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          '💡 작은 팝업창을 보려면 필수!',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            SizedBox(height: 24.h),

            Text(
              '알람 시간',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8.h),
            Card(
              child: ListTile(
                leading: Icon(Icons.access_time, color: Colors.blue, size: 24.sp),
                title: Text(_formatDateTime(selectedDateTime), style: TextStyle(fontSize: 16.sp)),
                subtitle: Text('탭하여 시간 변경', style: TextStyle(fontSize: 14.sp)),
                trailing: Icon(Icons.arrow_forward_ios, size: 16.sp),
                onTap: _selectDateTime,
              ),
            ),

            SizedBox(height: 24.h),

            Text(
              '알람 타입',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8.h),
            ...soundTypes.entries.map((entry) {
              final isSelected = selectedSoundType == entry.key;
              return Card(
                color: isSelected ? Colors.blue.shade50 : null,
                child: ListTile(
                  leading: Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.blue : Colors.grey,
                    size: 24.sp,
                  ),
                  title: Text(entry.value, style: TextStyle(fontSize: 16.sp)),
                  onTap: () {
                    setState(() {
                      selectedSoundType = entry.key;
                    });
                  },
                ),
              );
            }).toList(),

            SizedBox(height: 32.h),

            ElevatedButton.icon(
              onPressed: _scheduleAlarm,
              icon: const Icon(Icons.alarm_add),
              label: const Text('알람 등록'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.all(16.h),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),

            SizedBox(height: 12.h),

            OutlinedButton.icon(
              onPressed: _scheduleTestAlarm,
              icon: const Icon(Icons.science),
              label: const Text('5초 후 테스트'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.all(16.h),
              ),
            ),

            SizedBox(height: 12.h),

            TextButton.icon(
              onPressed: _cancelAlarm,
              icon: const Icon(Icons.cancel),
              label: const Text('알람 취소'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.all(16.h),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 런치 스크린 이후 즉시 라우팅 (스플래시 화면 제거)
class InitialRouter extends StatefulWidget {
  const InitialRouter({super.key});

  @override
  State<InitialRouter> createState() => _InitialRouterState();
}

class _InitialRouterState extends State<InitialRouter> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    if (!mounted) return;

    // 1. 권한 요청 여부 확인
    final prefs = await SharedPreferences.getInstance();
    final permissionsRequested = prefs.getBool('permissions_requested') ?? false;

    // 2. 스케줄 존재 여부 확인
    final schedule = await DatabaseService.instance.getShiftSchedule();

    // 3. 다음 화면 결정
    // ⭐ 2026-08-24 - 기본 MaterialPageRoute 전환(pushReplacementNamed 포함, 내부적으로
    // 같은 애니메이션을 씀) 대신 즉시 전환(_instantRoute, 지속시간 0)을 씀.
    // 이 화면(InitialRouter)은 "권한/스케줄 확인하는 동안 잠깐 뜨는 순수 로딩
    // 게이트"라 애니메이션이 있는 화면 전환이 필요 없음 - 오히려 역효과가
    // 있었음: 이 화면은 네이티브 스플래시와 맞추려고 일부러 불투명 흰색인데,
    // 그 뒤에는 항상 앱의 그라데이션 배경이 깔려 있음(main.dart의
    // MaterialApp.builder, 다음 화면들은 Scaffold가 투명이라 그게 비쳐 보임).
    // 애니메이션이 있는 전환 중에는 두 화면이 겹쳐서 페이드되는데, 그 과정에서
    // "가려져 있던 그라데이션이 애니메이션 중간에 갑자기 드러나는" 것처럼
    // 보여서 "흰색이었다가 갑자기 확 바뀐다"는 어색한 깜빡임으로 느껴졌음.
    // 지속시간 0으로 즉시 전환하면 중간 프레임이 아예 없어서 이 깜빡임 자체가
    // 생길 수가 없음.
    if (!permissionsRequested) {
      if (mounted) {
        Navigator.of(context).pushReplacement(_instantRoute(const PermissionIntroScreen()));
      }
    } else if (schedule == null) {
      if (mounted) {
        Navigator.of(context).pushReplacement(_instantRoute(const OnboardingScreen()));
      }
    } else {
      // ⭐ 홈 화면: 항상 달력탭으로 시작
      if (mounted) {
        Navigator.of(context).pushReplacement(
          _instantRoute(MainScreen(initialIndex: 1)),  // 달력탭 고정
        );
      }
    }
  }

  // ⭐ 애니메이션 없이 즉시 전환하는 라우트. InitialRouter는 순수 로딩 게이트라
  // 화면 전환 애니메이션이 필요 없고, 오히려 그 애니메이션 중간 프레임에서
  // "가려져 있던 배경이 갑자기 드러나는" 어색한 깜빡임이 생겼음(위 _navigate()
  // 주석 참고) - transitionDuration을 0으로 줘서 중간 프레임 자체를 없앰.
  Route<void> _instantRoute(Widget page) {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 런치 스크린과 동일한 빈 흰색 화면 (깜빡임 방지)
    return const Scaffold(
      backgroundColor: Colors.white,
    );
  }
}
