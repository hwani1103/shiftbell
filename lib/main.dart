import 'services/friend_sync_service.dart';
import 'services/restore_coordinator.dart';
import 'screens/restore_interrupted_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants/platform_channel.dart';
import 'constants/layout_limits.dart';
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
import 'screens/schedule_management_tab.dart';
import 'screens/condition_tab.dart';
import 'screens/permission_intro_screen.dart';
import 'widgets/permission_warning_banner.dart';
import 'widgets/banner_ad_slot.dart';
import 'services/ad_service.dart';
import 'services/backup_watcher.dart';
import 'services/schedule_notification_service.dart';
import 'services/widget_refresh_service.dart';
import 'services/backup_storage_service.dart';
import 'models/backup_payload.dart';
import 'screens/restore_backup_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shift_schedule.dart';
import 'providers/alarm_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/calendar_theme_provider.dart';
import 'providers/condition_provider.dart';
import 'providers/sleep_record_provider.dart';
import 'providers/sleep_condition_provider.dart';
import 'models/calendar_theme.dart';
import 'theme/app_theme.dart';
import 'services/firebase_bootstrap.dart';
import 'services/memo_category_classifier.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/l10n_extensions.dart';
import 'utils/schedule_focus_request.dart';
import 'providers/tab_visibility_provider.dart';
import 'screens/startup_gate.dart';
import 'services/app_analytics.dart';

// ⭐ 2026-09-04 - MainScreen 바텀 네비게이션에서 "달력탭"을 가리키는 인덱스.
// 탭 순서(다음알람/일정관리/달력/컨디션/설정)가 바뀔 때마다 이 값 하나만
// 맞추면 됨 - 이 파일 안(뒤로가기 이동/_goToCalendar/범위 밖 폴백)과
// restore_backup_screen.dart/permission_intro_screen.dart/onboarding_screen.dart의
// MainScreen(initialIndex:) 호출부, Kotlin CalendarWidgetProvider.kt의 openTab
// 값이 전부 이 숫자를 그대로 써야 함(Kotlin 쪽은 언어가 달라 상수 공유가 안 되니
// 직접 값(2)을 맞춰뒀음 - 여길 바꾸면 거기도 같이 바꿀 것).
const int kCalendarTabIndex = 2;

// ⭐ 2026-09-12 - "일정관리" 탭 인덱스. 위 kCalendarTabIndex와 같은 이유로
// 탭 순서(다음알람(0)/일정관리(1)/달력(2)/...)가 바뀌면 이 값도 같이 맞출 것.
// 일정 알림(ScheduleNotificationReceiver.kt)을 탭했을 때 이 탭으로 이동시키는
// 용도(openDateSchedule 핸들러 참고) - kOpenConditionTabSentinel과 달리 이
// 탭은 로케일과 무관하게 항상 _tabs에 존재해서 센티널이 필요 없음.
const int kScheduleManagementTabIndex = 1;

// ⭐ 2026-09-07 - 수면 위젯(SleepWidgetProvider.kt) 탭(수면/기상 버튼 이외
// 영역) → 컨디션 탭으로 바로 열기 위한 Native→Dart 요청 센티널. 컨디션 탭은
// 한국어 로케일에서만 _tabs에 실제로 존재해서(_showConditionTab) 그 인덱스를
// Kotlin이 고정 숫자로 알 수 없다 - 그래서 실제 인덱스 대신 이 음수 값을
// 보내고, Dart(_MyAppState의 openTab 핸들러)가 런타임에 진짜 인덱스로
// 변환한다(MainActivity.kt의 handleOpenTabIntent가 음수도 그대로 전달하도록
// 이미 고쳐둠). 인덱스 값(0/2)과 안 겹치게 음수로 둠.
const int kOpenConditionTabSentinel = -2;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⭐ 릴리즈 빌드는 기본적으로 위젯 빌드 중 에러가 나면 그냥 빈 회색 박스만
  // 보여주고 원인을 숨김 (디버그 빌드의 "빨간 에러 화면"과 다름). 그래서
  // "가끔 화면이 백지로 보인다" 같은 문제의 실제 원인을 릴리즈에서는 알 수가
  // 없었음 - 릴리즈에서도 어떤 에러인지 최소한 화면에 보이게 함.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // ⭐ 2026-09-14 (G0, 출시전_코드감사_검토결과_v4 V4) - 릴리스에서는 예외 원문/스택(내부
    // 경로나 데이터 일부가 섞일 수 있음)을 화면에 보이지 않음. 원문은 FlutterError 로그로만
    // 남음. 아래의 상세 표시는 디버그/프로필 빌드에서만 유지.
    if (kReleaseMode) return const _ReleaseErrorPlaceholder();

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

  // ⭐ 2026-09-14 (G0, 출시전_코드감사_검토결과_v4 V4) - 초기화를 runApp() 전에 무방비로
  // await하지 않고 StartupGate 안에서 실행함. 필수 초기화가 실패하면 시작 실패 화면 +
  // 다시 시도, 성공하면 기존과 똑같이 ProviderScope(달력 테마 override) + MyApp을 그림.
  runApp(
    StartupGate<CalendarThemeId>(
      initialize: _initializeApp,
      builder: (initialCalendarTheme) => ProviderScope(
        overrides: [
          calendarThemeProvider.overrideWith(
              (ref) => CalendarThemeNotifier.withInitial(initialCalendarTheme)),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

// ⭐ 2026-09-14 (G0, V4) - 앱 시작 초기화. 필수 단계는 실패하면 예외를 그대로 던지고
// (StartupGate가 시작 실패 화면으로 처리), 선택 단계는 실패/지연돼도 앱을 시작함.
// 다시 시도 시 이 함수 전체가 다시 불리므로 각 단계는 여러 번 불려도 안전해야 함.
Future<CalendarThemeId> _initializeApp() async {
  // ── 필수 ──
  // ⭐ 영어 현지화: 이제 기기 로케일에 따라 ko_KR 또는 en_US 포맷터를 쓸 수 있어야
  // 하므로, 둘 다 미리 초기화해둠(하나만 초기화된 상태에서 다른 로케일 포맷터를
  // 쓰면 intl이 LocaleDataException을 던짐).
  await initializeDateFormatting('ko_KR', null);
  await initializeDateFormatting('en_US', null);
  // DB 열기 + 마이그레이션(#1/#8 - 실패를 삼키지 않음). 실패 후 다시 부르면 새로 시도함.
  await DatabaseService.instance.database;
  await AlarmService().initialize();

  // ── 선택 (없어도 알람/달력 핵심 기능은 동작) ──
  // ⭐ Phase 4 - 메모/일정 카테고리 자동분류 모델(~2.2MB JSON) 미리 로드.
  // await 안 함 - 첫 프레임을 이걸로 막을 이유가 없고, 실제 분류 시점(일정
  // 생성 저장)에서 안 끝났으면 그쪽에서 ensureLoaded()를 다시 await해서
  // 안전하게 기다림 (memo_category_classifier.dart 참고).
  unawaited(MemoCategoryClassifier.instance.ensureLoaded().then<void>(
        (_) {},
        onError: (Object e) =>
            debugPrint('⚠️ 카테고리 분류 모델 미리 로드 실패 - 분류 시점에 다시 시도: $e'),
      ));
  // ⭐ 2026-09-01 - "일정 생성 직후 잠깐 기본 폰트로 보였다가 1초 뒤에 주아체로
  // 바뀐다"는 피드백. schedule_management_tab.dart의 _ScheduleRow가 매번
  // GoogleFonts.jua()를 직접 부르는데, google_fonts 패키지는 처음 쓰는 폰트를
  // 그 시점에 비동기로 다운로드/캐싱하고 그동안 시스템 기본 폰트로 잠깐
  // 대체 표시함(FOUT) - 위 MemoCategoryClassifier와 같은 패턴으로 앱 시작
  // 시점에 미리 한 번 받아둬서, 실제로 일정 카드를 그릴 때는 이미 캐시돼
  // 있게 함(마찬가지로 첫 프레임을 막지 않도록 await 안 함).
  // ⭐ 2026-09-14 (G0, V4) - 오프라인 등으로 받기에 실패하면 처리 안 된 비동기 오류가
  // 되던 것을 로그로만 남김(표시는 기본 폰트로 계속됨).
  unawaited(GoogleFonts.pendingFonts([GoogleFonts.jua()]).then<void>(
    (_) {},
    onError: (Object e) => debugPrint('⚠️ 폰트 미리 받기 실패 - 기본 폰트로 표시될 수 있음: $e'),
  ));
  // ⭐ 친구공유(Firestore) 초기화 - firebase_options.dart가 아직 플레이스홀더면
  // 조용히 실패하고 친구공유 기능만 비활성화됨 (firebase_bootstrap.dart 참고).
  // 다시 시도로 이 함수가 또 불려도 이미 성공했으면 중복 초기화하지 않음.
  if (!firebaseReady) await _optionalStartupStep('Firebase', initFirebase);

  // ⭐ 광고 SDK 초기화 + 배너가 차지할 높이를 첫 프레임 전에 미리 확정해둠.
  // 화면을 그리는 중에 높이를 구하면 "높이 모르는 프레임 → 아는 프레임"으로 한 번
  // 튀는데, 그 튐을 막는 게 이 슬롯의 목적이라 여기서 미리 함.
  // 실패해도 예외를 던지지 않고 fallback 높이로 넘어감 (ad_service.dart 참고).
  await _optionalStartupStep('AdMob', AdService.warmUp);

  // ⭐ 앱 시작 전에 달력 테마 미리 로드 (깜빡임 방지) - 예전엔 "다크모드
  // on/off"를 미리 읽었는데, 이제는 9개 달력 테마 중 뭐가 선택돼 있는지를
  // 미리 읽음. 앱 전체 밝기는 항상 라이트 고정이고, 이 값은 오직 (1) 달력
  // 탭 자체가 어떤 테마로 그려질지 (2) 시스템 상태표시줄 아이콘 밝기에만 씀.
  // (실패하면 내부에서 기본 테마로 대체함 - calendar_theme_provider.dart)
  return CalendarThemeNotifier.loadInitial();
}

// ⭐ 2026-09-14 (G0, V4) - 없어도 앱 핵심(알람/달력)이 동작하는 초기화 단계. 예외는 로그만
// 남기고, 너무 오래 걸리면 기다리지 않고 앱을 시작함(그 Future는 뒤에서 계속 진행 - Dart는
// Future를 취소할 수 없음). 10초는 측정값이 아니라 "첫 화면을 무한정 막지 않는다"는 상한값.
Future<void> _optionalStartupStep(
  String name,
  Future<void> Function() step, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    await step().timeout(timeout);
  } on TimeoutException {
    debugPrint('⚠️ 시작 초기화 지연($name) - 기다리지 않고 앱 시작');
  } catch (e) {
    debugPrint('⚠️ 시작 초기화 실패($name) - 이 기능 없이 앱 시작: $e');
  }
}

// ⭐ 2026-09-14 (G0, V4) - 릴리스 빌드의 위젯 빌드 오류 자리 표시. 원문 없이 아이콘만.
class _ReleaseErrorPlaceholder extends StatelessWidget {
  const _ReleaseErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFFFAFAFA),
        child: Center(
          child: Icon(Icons.error_outline, size: 28, color: Color(0xFF9E9E9E)),
        ),
      ),
    );
  }
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

    // ⭐ 2026-09-11(사용자 신고 - "자동백업이 안 되고 있는 것 같다") - 지금까지는
    // 자동 백업이 AppLifecycleState.paused(앱이 백그라운드로 "나갈 때") 한
    // 지점에서만 fire-and-forget으로 돌았음. 문제는 그 시점 이후 프로세스가
    // 계속 살아있는다는 보장이 없다는 것 - Android가 onStop 직후 앱을 곧바로
    // 캐시/정지시키면(특히 배터리 최적화가 공격적인 제조사 기기, 이 저장소
    // 문서에 이미 여러 번 등장하는 삼성 포함), exportAll()이 모든 테이블을
    // 조회하고 JSON 인코딩하고 MediaStore에 파일로 쓰는 그 비동기 작업 도중에
    // 프로세스가 멈춰서 백업이 조용히 끝까지 못 도는 경우가 생길 수 있음(특히
    // alarm_history/alarm_creation_log는 규칙상 영구 보존이라 오래 쓸수록 행 수가
    // 계속 늘어나 export가 점점 느려짐 - History permanence rule 참고). "나갈
    // 때"만 믿지 않고, 앱이 정상적으로 켜져서 포그라운드에 살아있는(=중간에
    // 안 죽을) 이 시점에도 한 번 더 시도해서 신뢰도를 높인다. backupNow()는
    // data_version이 그대로면 즉시 반환하는 가벼운 함수라(백업_watcher.dart
    // 참고) 매 콜드 스타트마다 불러도 비용이 거의 없음.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(BackupWatcher.instance.backupNow());
    });
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

      // ⭐ 2026-09-11(사용자 신고 - "자동백업이 실제로 안 되고 있다") - 콜드
      // 스타트(initState)뿐 아니라 재개(resumed)될 때마다도 기회를 한 번 더 줌.
      // paused 트리거는 "이제 막 배경으로 나가는" 시점이라 그 직후 OS가 프로세스를
      // 정지시키면 exportAll()~파일쓰기 도중에 끊길 위험이 있는데(main.dart의
      // initState 주석 참고), resumed는 반대로 "방금 포그라운드로 돌아와서 확실히
      // 살아있는" 시점이라 그 위험이 없음. backupNow()는 data_version이 그대로면
      // 즉시 반환하는 가벼운 함수라 앱을 여닫을 때마다 불러도 비용이 거의 없음.
      unawaited(BackupWatcher.instance.backupNow());
    } else if (state == AppLifecycleState.paused) {
      // ⭐ 사용자 데이터 백업("A번 요구사항") 자동 트리거(Layer 3) - 앱이
      // 백그라운드로 전환되는 시점에만, 그것도 마지막 백업 이후 실제로 데이터가
      // 바뀌었을 때만 조용히 백업함(BackupWatcher.backupNow 참고 - PRAGMA
      // data_version으로 가볍게 확인). 알람/근무패턴 로직과 완전히 독립된
      // read-only 판단 + 별개의 파일 쓰기라 기존 로직에 전혀 영향 없음 -
      // await 없이 fire-and-forget(백그라운드 전환을 지연시키지 않음).
      unawaited(BackupWatcher.instance.backupNow());
    }
  }

  // 6.5인치 기준 최대 너비 (Fold 7 펼친 상태 대응)
  static const double maxContentWidth = kAppMaxContentWidth;

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
              value: isCalendarThemeDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
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
                    color: Colors.grey.shade200, // 넓은 화면에서 양옆 배경색 - 항상 라이트
                    child: Center(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: maxContentWidth),
                        child: Container(
                          color: Colors.white, // 컨텐츠 영역 배경 - 항상 라이트
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                home: const InitialRouter(),
                routes: {
                  '/permission_intro': (context) =>
                      const PermissionIntroScreen(),
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
  final int initialIndex; // ⭐ 초기 탭 인덱스 받기
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
class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  late int _currentIndex; // ⭐ nullable 제거
  static const platform = kAlarmChannel;

  late List<Widget> _tabs;

  // ⭐ 2026-09-03 - "컨디션 탭은 아직 한국어 전용(문구/문장 생성 로직까지
  // 전부 한국어)이라, 영어 사용자에게는 아예 안 보이게 해달라"는 요청.
  // Localizations.localeOf(context)는 initState()에서 못 씀(InheritedWidget
  // 구독이라 아직 안전하지 않음 - Flutter가 assert로 막음) - 그래서 탭 목록
  // 구성 자체를 initState에서 didChangeDependencies로 옮김(로케일이 확정된
  // 뒤 딱 한 번만 실행되도록 _tabsInitialized로 가드).
  bool _tabsInitialized = false;
  bool _showConditionTab = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ⭐ 초기 탭 설정 (InitialRouter에서 결정한 값)
    _currentIndex = widget.initialIndex;

    // ⭐ 탭 목록 구성/컨디션 Provider 프리웜은 로케일이 필요해서
    // didChangeDependencies()로 옮김(아래 _setupTabsAndPrewarm 참고).

    // ⭐ _scheduleGuardWakeup()이 triggerGuardCheck를 호출해서 Native 갱신 판단/실행까지 함
    // (예전엔 여기서 AlarmRefreshService도 따로 호출해서 Native와 중복 실행되는 문제가 있었음)
    _scheduleGuardWakeup();

    // ⭐ Method Call Handler 등록
    platform.setMethodCallHandler(_handleMethod);
    // ⭐ 2026-09-13 - 등록 직후 콜드스타트 유실 방지용 pull 확인(위
    // _checkPendingScheduleOpenOnStartup 주석 참고).
    _checkPendingScheduleOpenOnStartup();

    // ⭐ 2026-09-14 (출시전 수정 T10 연결, G2-01) - 친구공유 dirty/stop_pending 재시도.
    // 근무표가 처음 로드된 뒤(없음 포함) 앱 시작 1회 onAppStarted - 앱 시작을 막지 않고 오류는 로그만.
    // Firebase 초기화가 지연돼 아직 준비 전이면 서비스가 pending으로 두고 다음 재개 때 다시 시도함.
    ref.listenManual<AsyncValue<ShiftSchedule?>>(scheduleProvider,
        (previous, next) {
      if (_friendSyncStartNotified || next.isLoading) return;
      _friendSyncStartNotified = true;
      _runFriendSync('onAppStarted',
          FriendSyncService.instance.onAppStarted(next.valueOrNull));
    }, fireImmediately: true);

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
      // 알람 사용량(끄기/연장/무응답)은 앱을 열 때 새로 쌓인 이력만 이벤트로 보낸다 - AlarmUsageAnalytics 참고
      AlarmUsageAnalytics.reportNew();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tabsInitialized) return; // ⭐ 최초 1회만 - 기존 late final 캐시 의도 유지
    _tabsInitialized = true;
    _setupTabsAndPrewarm();
  }

  // ⭐ 2026-09-03 - "컨디션 탭은 영어 버전에서 아예 안 보이게 해달라"는 요청
  // (컨디션 매니저 UI/문구 생성 로직 전체가 아직 한국어 전용이라, 어설프게
  // 반쯤 번역된 화면을 보여주는 것보다 나은 선택이라고 판단 - 사용자도 동의).
  // Native(Kotlin)에서 openTab으로 보내는 인덱스는 0(다음알람)/kCalendarTabIndex(달력)
  // 뿐이고, 온보딩/백업 화면의 MainScreen(initialIndex:) 호출도 전부 그 둘만 써서
  // 컨디션 탭을 빼도 그 경로들은 전혀 영향받지 않음.
  void _setupTabsAndPrewarm() {
    _showConditionTab = Localizations.localeOf(context).languageCode == 'ko';

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
    // 바텀 네비게이션 4번째 탭으로 승격했었으나(다음알람(0)/달력(1)/일정공유(2)/설정(3)),
    // 2026-08-25 - 그 자리를 "일정관리"(신규, Structured 스타일 레이아웃 실험,
    // schedule_management_tab.dart)가 대신 차지하도록 교체함. 일정공유는 다시
    // 설정 탭의 진입점(ListTile)으로 옮김(settings_tab.dart 참고) - 탭에서
    // 눌렀을 때와 동일한 FriendListScreen을 그대로 push함.
    // ⭐ 2026-09-04 - "달력을 가운데(탭 순서상 중앙)로" 요청으로 순서를
    // 다음알람(0)/일정관리(1)/달력(2)/컨디션(3, ko만)/설정(4 또는 en은 3)으로
    // 재배치함 - 달력 인덱스가 1→2로 바뀌어서 이 파일 안의 "달력탭"을 가리키던
    // 모든 곳(PopScope의 canPop/뒤로가기 이동, _goToCalendar, 범위 밖 폴백)과
    // MainScreen(initialIndex:) 호출부(restore_backup_screen.dart/
    // permission_intro_screen.dart/onboarding_screen.dart), Kotlin
    // CalendarWidgetProvider.kt의 openTab 값도 전부 같이 2로 맞춰 갱신함.
    // 다음알람(0)은 그대로라 AlarmGuardReceiver.kt/NotificationHelper.kt가
    // 보내는 openTab=0은 영향 없음.
    _tabs = [
      const NextAlarmTab(),
      // ⭐ 2026-09-13 - "OO 화면 사용하지 않기" 버튼을 이 탭 자신의 스크롤
      // 콘텐츠 맨 아래로 옮기면서(사용자 요청) main.dart가 더 이상 이 버튼을
      // 고정 위치에 그리지 않음 - 대신 그 자리에서 쓰던 콜백을 그대로
      // 생성자로 내려줌(아래 build()의 옛 DisableTabButton 자리 주석 참고).
      ScheduleManagementTab(
        onDisabled: () => setState(() => _currentIndex = kCalendarTabIndex),
        onConfirmed: ScheduleNotificationService.cancelAllForTabDisable,
      ),
      Consumer(
        builder: (context, ref, _) {
          final isDark = ref.watch(calendarThemeProvider).isDark;
          return Theme(
            data: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
            child: CalendarTab(),
          );
        },
      ),
      // ⭐ 2026-08-31 - 컨디션 매니저 1차 버전(컨디션매니저_설계.md 참고).
      // "일정관리 옆에 독립 탭으로" 요청대로 여기(달력 다음, 설정 이전)에
      // 끼워 넣음.
      // ⭐ 2026-09-13 - 예전엔 "영어 로케일이면 이 탭 자체를 목록에서 뺌"이라고
      // 여기서 배열 길이 자체를 바꿨는데(_showConditionTab), 그러면 사용자가
      // 탭을 껐다 켰다 하는 기능(scheduleTabEnabledProvider/
      // conditionTabEnabledProvider)까지 더해질 때 이 배열의 길이/인덱스가
      // 두 가지 서로 다른 이유로 흔들려서 kScheduleManagementTabIndex/
      // kCalendarTabIndex 같은 고정 상수들이 깨지기 쉬워짐. _tabs 배열
      // 자체는 이제 로케일/사용자 설정과 무관하게 항상 고정 5칸으로 유지하고,
      // "실제로 보여줄지"는 build()의 _visibleTabIndices가 네비게이션 레벨
      // 에서만 필터링함(이 위젯은 만들어지긴 하지만 그 탭으로 이동하지 않는
      // 한 실제로 build되지 않음 - 이 화면이 IndexedStack이 아니라
      // `_tabs[_currentIndex]` 하나만 트리에 올리는 구조이기 때문).
      ConditionTab(
        onDisabled: () => setState(() => _currentIndex = kCalendarTabIndex),
        onConfirmed: WidgetRefreshService.refresh,
      ),
      // ⭐ 2026-09-01 후속13 - "컨디션 팁 실험실" 임시 개발용 탭(후속8에서 추가,
      // 컨디션 매니저 추천 로직 리팩토링 전 검토용)은 검토 끝나서 삭제함
      // (condition_tip_lab_screen.dart 파일 자체도 삭제).
      SettingsTab(onSwipeToCalendar: () => _goToCalendar()),
      // ⭐ 2026-08-25 - 아이콘 색상이 최종 확정되어(2번 변형: 인디고·오로라
      // 그라데이션·코랄) 임시 아이콘 픽커 탭 제거함. ui_theme_lab_screen.dart
      // 파일 자체는 나중에 다시 후보를 검토할 일이 생기면 재사용할 수 있어
      // 지우지 않고 남겨둠 - 필요하면 이 자리에 다시 추가하면 됨.
      // ⭐ 2026-09-05 - 웰컴/근무배정 팝업 확인용 임시 lab 탭(사용자 요청)은
      // 2026-09-07 확인 끝나서 제거, 2026-09-12에 "테스트알림" 탭으로 잠깐
      // 다시 추가했다가 배포 전 최종 점검을 마치고 이번에 완전히 제거함
      // (onboarding_popup_lab_screen.dart 파일 자체도 삭제 - 다른 lab 화면들과
      // 달리 이번 배포 직전 점검 전용 1회성 도구라 재사용 계획이 없음).
      // ⭐ 2026-09-22 - "일정관리 디자인 실험실"(dev_lab/) 탭은 근무시간 표기
      // 방식(반투명 영역 고정)과 헤더 그라데이션 색상을 확정하고 실제
      // ScheduleManagementTab에 반영한 뒤 완전히 삭제함(dev_lab/ 폴더 자체도
      // 삭제 - 재사용 계획 없음).
    ];

    // ⭐ _tabs가 이제 항상 고정 5칸이라(위 주석 참고) 사실상 트리거될 일은
    // 없지만, 혹시 모를 범위 밖 값에 대한 안전망으로 그대로 남겨둠.
    if (_currentIndex >= _tabs.length) _currentIndex = kCalendarTabIndex;

    // ⭐ 2026-09-01 후속14 - "컨디션 탭에 처음 들어가면 카드들이 텅 비어있다가
    // 뒤늦게 나타난다"는 피드백. 원인: 이 화면이 IndexedStack이 아니라
    // `_tabs[_currentIndex]` 하나만 트리에 올리는 구조라(위 주석 참고), 컨디션
    // 탭은 사용자가 실제로 그 탭에 들어가기 전까진 위젯 자체가 아예 안 만들어짐
    // - 그 탭 전용 Provider들(scheduleProvider 외엔 다른 탭이 안 건드리는
    // conditionShiftTimeProvider/sleepRecordProvider, 그리고 FutureProvider인
    // recentOvertimeMinutesProvider/healthTipsListProvider - 후자는 Firestore
    // 네트워크 호출까지 있어 더 오래 걸림)가 그제서야 처음 생성되면서 DB
    // 읽기/네트워크 요청이 "그 순간부터" 시작됨. 위젯을 실제로 안 띄우고도
    // Provider 로딩만 미리 시작시킬 수 있어서(ref.read - watch와 달리 위젯을
    // 구독시키지 않고 그냥 한 번 읽어서 생성만 트리거함), 앱 시작 시점에
    // 컨디션 탭이 실제로 쓰는 최상위 Provider들을 미리 한 번 읽어서 로딩을
    // 앞당김. 사용자가 다른 탭을 보는 동안 백그라운드에서 미리 끝나 있을
    // 가능성이 높아짐(첫 진입 시 완전히 안 보인다는 보장은 아니지만 체감
    // 지연은 크게 줄어듦).
    // ⭐ 2026-09-03 - 영어 로케일(탭 자체가 안 보임)이면 이 프리웜도 그냥
    // 낭비(불필요한 DB 읽기 + Firestore 네트워크 호출)라 같이 건너뜀.
    if (_showConditionTab) {
      // ⭐ 2026-09-15 - 점수·건강 Tip 삭제 후: "오늘의 컨디션"이 쓰는 입력(판정·수면 기록·미니 달력)만 미리 로딩
      // (recoveryBriefingProvider 자체는 1분 시계를 쓰는 autoDispose라 화면이 볼 때만 만든다)
      ref.read(todayConditionResultProvider);
      ref.read(sleepRecordProvider);
      ref.read(recentSleepDaySlotsProvider);
    }
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
      AlarmUsageAnalytics.reportNew();
      // ⭐ 2026-09-14 (T10 연결, G2-01) - 재개될 때마다 친구공유 대기 작업(dirty/stop_pending) 재시도
      _runFriendSync(
          'onAppResumed',
          FriendSyncService.instance
              .onAppResumed(ref.read(scheduleProvider).valueOrNull));
    }
  }

  bool _friendSyncStartNotified = false;

  // 친구공유는 선택 기능 - 실패가 앱 흐름을 막거나 처리되지 않은 비동기 오류가 되지 않게 로그만 남김
  void _runFriendSync(String label, Future<void> work) {
    unawaited(work.then<void>(
      (_) {},
      onError: (Object e) => debugPrint('⚠️ 친구공유 $label 재시도 실패(무시): $e'),
    ));
  }

  // ⭐ 6번 기능: 달력탭으로 이동
  void _goToCalendar() {
    setState(() => _currentIndex = kCalendarTabIndex);
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

  // ⭐ 2026-09-13 - openDateSchedule(push)과 consumePendingScheduleOpen(pull,
  // 아래 initState 참고)이 공유하는 실제 적용 로직 - 일정관리 탭으로 전환 +
  // schedule_focus_request.dart에 요청을 채워서, 그 탭이 마운트/재빌드될 때
  // 날짜/시간축을 그 일정 위치로 맞추게 함.
  void _applyOpenDateSchedule(Map? args) {
    if (args != null) {
      final date = args['date'] as String?;
      final startMinutes = args['startMinutes'] as int?;
      print('🔔 일정 알림 탭 → 일정관리 탭 이동: date=$date startMinutes=$startMinutes');
      if (date != null && startMinutes != null) {
        pendingScheduleFocusRequest.value =
            ScheduleFocusRequest(date: date, startMinutes: startMinutes);
      }
    }
    if (mounted) {
      setState(() => _currentIndex = kScheduleManagementTabIndex);
    }
  }

  // ⭐ 2026-09-13(사용자 신고 - "일정 알림 누르면 그냥 달력탭으로 와버림") -
  // MainActivity.kt의 handleOpenDateScheduleIntent가 콜드 스타트 시 이
  // setMethodCallHandler 등록보다 먼저 invokeMethod("openDateSchedule")를
  // 보내버리면(그 시점엔 이 핸들러가 아직 없어 메시지가 그냥 유실됨) 요청
  // 자체가 사라져서 InitialRouter의 기본값(달력 탭)에 그대로 머무르는 문제가
  // 있었음. 핸들러 등록 직후 "혹시 그 사이에 못 받은 요청 있어?"라고 Native에
  // 직접 되물어(pull) 타이밍과 무관하게 항상 처리되게 함 - 대기 중인 요청이
  // 없으면 그냥 null이 오고 아무 일도 안 일어남(기존 동작에 영향 없음).
  Future<void> _checkPendingScheduleOpenOnStartup() async {
    try {
      final result = await platform.invokeMethod('consumePendingScheduleOpen');
      if (result is Map) {
        print('🔔 콜드스타트 유실 방지 - 대기 중이던 일정 알림 요청을 뒤늦게 적용');
        _applyOpenDateSchedule(result);
      }
    } catch (e) {
      print('❌ consumePendingScheduleOpen 확인 실패: $e');
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
          if (tabIndex == kOpenConditionTabSentinel) {
            // ⭐ 2026-09-07 - 컨디션 탭은 항상 "달력 바로 다음"에 위치함.
            // ⭐ 2026-09-13 - 영어 로케일이거나(_showConditionTab) 사용자가 설정에서
            // 꺼놨으면(conditionTabEnabledProvider) 그 탭 자체가 네비게이션에
            // 없으니 다음알람 탭(0)으로 안전하게 대체.
            final conditionVisible =
                _showConditionTab && ref.read(conditionTabEnabledProvider);
            _currentIndex = conditionVisible ? kCalendarTabIndex + 1 : 0;
          } else {
            _currentIndex = tabIndex;
          }
        });
      }
    } else if (call.method == 'openDateSchedule') {
      // ⭐ 2026-09-12 - 일정 알림(ScheduleNotificationReceiver.kt)을 탭했을 때
      // ScheduleNotificationReceiver.kt가 MainActivity에 심어둔 extras를
      // handleOpenDateScheduleIntent(Kotlin)가 여기로 그대로 전달함(즉시 push
      // 경로 - 앱이 이미 떠 있는 warm start에서 정상 동작).
      final args = call.arguments;
      _applyOpenDateSchedule(args is Map ? args : null);
      // ⭐ 2026-09-13 - Native에게 "받았다"고 알려서 콜드스타트 유실 대비용
      // pending 값을 지우게 함(_checkPendingScheduleOpenOnStartup 주석 참고) -
      // 안 지우면 다음 번 무관한 콜드 스타트 때 이 오래된 요청이 잘못 재사용될 수 있음.
      platform.invokeMethod('clearPendingScheduleOpen');
    }
  }

  // ⭐ 2026-09-13 - 네비게이션에 실제로 보여줄 탭들의 실제 인덱스 목록(항상
  // kScheduleManagementTabIndex(1) < kCalendarTabIndex(2) < 3(컨디션) < 4(설정)
  // 순서 유지, 0(다음알람)/kCalendarTabIndex(달력)/4(설정)는 끌 수 없어 항상
  // 포함됨). _tabs 배열 자체는 항상 고정 5칸이고(위 _setupTabsAndPrewarm
  // 주석 참고), 여기서만 "실제로 네비게이션에 노출할지"를 결정함 - 로케일
  // 조건(_showConditionTab)과 사용자가 설정/각 탭에서 끈 값
  // (scheduleTabEnabledProvider/conditionTabEnabledProvider) 둘 다 여기서
  // 합쳐진다.
  List<int> get _visibleTabIndices {
    final scheduleVisible = ref.watch(scheduleTabEnabledProvider);
    final conditionVisible =
        _showConditionTab && ref.watch(conditionTabEnabledProvider);
    return [
      0,
      if (scheduleVisible) kScheduleManagementTabIndex,
      kCalendarTabIndex,
      if (conditionVisible) 3,
      4,
    ];
  }

  BottomNavigationBarItem _navItemFor(int index, BuildContext context) {
    switch (index) {
      case 0:
        return BottomNavigationBarItem(
            icon: const Icon(Icons.alarm), label: context.l10n.navNextAlarm);
      case 1:
        return BottomNavigationBarItem(
            icon: const Icon(Icons.event_note_outlined),
            label: context.l10n.navScheduleManagement);
      case 2:
        return BottomNavigationBarItem(
            icon: const Icon(Icons.calendar_month),
            label: context.l10n.navCalendar);
      case 3:
        return const BottomNavigationBarItem(
            icon: Icon(Icons.self_improvement), label: '수면·회복');
      case 4:
        return BottomNavigationBarItem(
            icon: const Icon(Icons.settings), label: context.l10n.navSettings);
      default:
        return BottomNavigationBarItem(
            icon: const Icon(Icons.settings), label: context.l10n.navSettings);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleTabIndices = _visibleTabIndices;
    // ⭐ 방금 이 탭이 꺼졌는데(다른 경로로, 혹은 아직 반영 전 프레임에) 지금
    // 하필 그 탭을 보고 있었다면 안전한 탭(달력)으로 옮김 - DisableTabButton의
    // onDisabled가 이미 즉시 처리하지만, 이건 그 경로를 놓쳤을 때의 안전망.
    if (!visibleTabIndices.contains(_currentIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_visibleTabIndices.contains(_currentIndex)) {
          setState(() => _currentIndex = kCalendarTabIndex);
        }
      });
    }
    return PopScope(
      canPop: _currentIndex == kCalendarTabIndex, // 달력탭이면 앱 종료 허용
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != kCalendarTabIndex) {
          // 달력탭이 아니면 달력탭으로 이동
          setState(() => _currentIndex = kCalendarTabIndex);
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
            // ⭐ 2026-08-25 - 일정관리 탭뿐 아니라 달력 탭에서도 항상 자리를
            // 차지하도록 확장 - "일정관리도 광고를 고정으로 보여주자" 요청.
            // 2026-09-01 후속14 - 컨디션 탭(index 3)도 동일하게 추가(사용자 요청 -
            // "달력/일정관리와 똑같은 위치·로직으로"). 다른 탭에선 여전히 높이 0.
            // ⭐ 2026-09-04 - 탭 순서를 다음알람/일정관리/달력/컨디션/설정으로
            // 바꾸면서 일정관리·달력의 인덱스가 서로 맞바뀌었을 뿐(1,2 두 값은
            // 그대로) 이 조건식 자체는 안 바뀜 - kCalendarTabIndex(=2)와 일정관리
            // 인덱스(=1)를 그대로 씀.
            // ⭐ 2026-09-03 - 영어 로케일이면 컨디션 탭이 빠져서 index 3이
            // 설정 탭 자리가 됨 - 그 상태에서 index 3을 그대로 광고 대상에
            // 넣으면 설정 탭에도 광고가 뜨는 버그가 생겨서 _showConditionTab을
            // 반영해 조건을 분기함.
            // ⭐ 2026-09-13(2차) - "OO 화면 사용하지 않기" 버튼을 여기(광고
            // 바로 위, 항상 고정 위치)에서 각 탭 자신의 스크롤 콘텐츠 맨
            // 아래로 옮김(사용자 요청 - "진짜 필요할 때만 누르는 버튼이니
            // 스크롤을 끝까지 내려야 보이게"). 콜백(onDisabled/onConfirmed -
            // 일정 알림 일괄 취소/수면 위젯 즉시 갱신 등, 탭 숨김의 우회
            // 경로를 막는 로직)은 그대로 두고 ScheduleManagementTab/
            // ConditionTab 생성자로 내려보냄(_setupTabsAndPrewarm 참고) -
            // 동작 자체는 안 바뀌고 버튼이 그려지는 위치만 바뀜.
            Offstage(
              offstage: _currentIndex != 1 &&
                  _currentIndex != kCalendarTabIndex &&
                  !(_showConditionTab && _currentIndex == 3),
              child: const BannerAdSlot(),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          // ⭐ 2026-09-13 - BottomNavigationBar의 currentIndex/items는 실제
          // _tabs 인덱스가 아니라 "보이는 탭들 중 몇 번째인지"를 써야 함(예:
          // 일정관리를 껐으면 [0, 2, 3, 4] 중 _currentIndex(=2, 달력)의
          // 위치는 1) - 안 그러면 숨긴 탭 자리만큼 나머지 항목들이 밀려
          // 보인다. indexOf가 -1이면(과도기 프레임에서 _currentIndex가 막
          // 숨겨진 탭을 가리키는 순간, 위 build() 시작의 안전망이 다음
          // 프레임에 고쳐주기 전) 0으로 방어.
          currentIndex: () {
            final idx = visibleTabIndices.indexOf(_currentIndex);
            return idx < 0 ? 0 : idx;
          }(),
          onTap: (visibleIndex) {
            final tab = visibleTabIndices[visibleIndex];
            if (tab != _currentIndex && tab < kAnalyticsTabNames.length) {
              AppAnalytics.track(AnalyticsEvent.tabSelected,
                  params: {'tab': kAnalyticsTabNames[tab]});
            }
            setState(() => _currentIndex = tab);
          },
          items: [for (final i in visibleTabIndices) _navItemFor(i, context)],
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
                leading:
                    Icon(Icons.access_time, color: Colors.blue, size: 24.sp),
                title: Text(_formatDateTime(selectedDateTime),
                    style: TextStyle(fontSize: 16.sp)),
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
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
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

    // ⭐ 2026-09-14 (출시전 감사 G4 #19) - 중단된 백업 복원 작업이 남아 있으면, 데이터를 고칠 수 있는 화면보다 먼저
    // "이어서 복원 / 지금 데이터로 계속"을 묻는다(자동 이어하기가 그 사이 변경을 몰래 덮어쓰지 않게).
    await RestoreCoordinator.instance.consumeInterruptedFlag();
    if (await RestoreCoordinator.instance.hasPendingJob()) {
      if (mounted) {
        Navigator.of(context)
            .pushReplacement(_instantRoute(const RestoreInterruptedScreen()));
      }
      return;
    }

    // 1. 권한 요청 여부 확인
    final prefs = await SharedPreferences.getInstance();
    final permissionsRequested =
        prefs.getBool('permissions_requested') ?? false;

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
        Navigator.of(context)
            .pushReplacement(_instantRoute(const PermissionIntroScreen()));
      }
    } else if (schedule == null) {
      // ⭐ 사용자 데이터 백업("A번 요구사항") - 스케줄이 아직 없다는 건 신규
      // 설치(또는 초기화 직후)라는 뜻인데, 재설치라면 이 기기에 예전 백업
      // 파일이 남아있을 수 있음(MediaStore는 앱을 지워도 파일이 안 지워짐 -
      // backup_storage_service.dart 참고). 곧장 OnboardingScreen으로 보내기
      // 전에 그 백업이 있는지만 가볍게 확인 - 있으면 복구 여부를 먼저 물어봄
      // (RestoreBackupScreen), 없으면(대부분의 진짜 신규 설치) 기존과 동일하게
      // 바로 OnboardingScreen.
      final backupJson = await BackupStorageService.instance.read();
      BackupPayload? payload;
      if (backupJson != null) {
        try {
          payload = BackupPayload.decode(backupJson);
        } catch (e) {
          payload = null; // 손상된 백업 파일 - 조용히 무시하고 신규 설치처럼 진행
        }
      }
      if (!mounted) return;
      if (payload != null) {
        Navigator.of(context).pushReplacement(
            _instantRoute(RestoreBackupScreen(payload: payload)));
      } else {
        Navigator.of(context)
            .pushReplacement(_instantRoute(const OnboardingScreen()));
      }
    } else {
      // ⭐ 홈 화면: 항상 달력탭으로 시작
      if (mounted) {
        Navigator.of(context).pushReplacement(
          _instantRoute(MainScreen(initialIndex: kCalendarTabIndex)), // 달력탭 고정
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
