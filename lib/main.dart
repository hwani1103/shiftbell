import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/alarm_service.dart';
import 'services/permission_service.dart';
import 'services/database_service.dart';
import 'services/alarm_refresh_service.dart';
import 'services/update_service.dart';
import 'screens/next_alarm_tab.dart';
import 'screens/calendar_tab.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_tab.dart';
import 'screens/permission_intro_screen.dart';
import 'widgets/permission_warning_banner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shift_schedule.dart';
import 'providers/alarm_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⭐ 런치 스크린 유지 시간 (0.3초)
  await Future.delayed(const Duration(milliseconds: 300));

  await initializeDateFormatting('ko_KR', null);
  await DatabaseService.instance.database;
  await AlarmService().initialize();

  // ⭐ 10일 이상 지난 알람 이력 자동 삭제
  await DatabaseService.instance.deleteOldAlarmHistory();

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.hwani1103.shiftbell/alarm');
  
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
    print('📱 앱 포그라운드 진입 - 갱신 체크');
    AlarmRefreshService.instance.refreshIfNeeded();
    
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
        return MaterialApp(
          title: '교대종',
          theme: ThemeData.light().copyWith(
            primaryColor: Colors.blue,
          ),
          // 모든 화면에 최대 너비 제한 적용
          builder: (context, child) {
            return Container(
              color: Colors.grey.shade200,  // 넓은 화면에서 양옆 배경색
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxContentWidth),
                  child: Container(
                    color: Colors.white,  // 컨텐츠 영역 배경
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
            '/home': (context) => const MainScreen(),
          },
        );
      },
    );
  }
}

class MainScreen extends ConsumerStatefulWidget {  // ⭐ ConsumerStatefulWidget으로 변경
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();  // ⭐ ConsumerState로 변경
}

class _MainScreenState extends ConsumerState<MainScreen> {  // ⭐ ConsumerState로 변경
  int? _currentIndex;  // ⭐ null = 로딩 중
  static const platform = MethodChannel('com.hwani1103.shiftbell/alarm');

  late final List<Widget> _tabs;

  // main.dart - _MainScreenState
@override
void initState() {
  super.initState();

  // ⭐ 탭 생성 (callback 전달)
  _tabs = [
    NextAlarmTab(onSwipeToCalendar: () => _goToCalendar()),
    CalendarTab(),
    SettingsTab(onSwipeToCalendar: () => _goToCalendar()),
  ];

  _checkRefreshOnStart();
  _scheduleGuardWakeup();

  // ⭐ Method Call Handler 등록
  platform.setMethodCallHandler(_handleMethod);

  // ⭐ 5번 기능: 초기 탭 즉시 결정 (버벅임 제거)
  _determineInitialTab();

  // ⭐ 업데이트 체크 (2초 후 - UI 로딩 완료 후)
  Future.delayed(const Duration(seconds: 2), () {
    if (mounted) {
      UpdateService.checkForUpdate(context);
    }
  });
}

Future<void> _determineInitialTab() async {
  try {
    // DB에서 직접 알람 읽기 (Provider 없이)
    final db = await DatabaseService.instance.database;
    final now = DateTime.now();
    final result = await db.query(
      'alarms',
      where: 'date > ?',
      whereArgs: [now.toIso8601String()],
      limit: 1,
    );

    final hasFutureAlarm = result.isNotEmpty;

    if (mounted) {
      setState(() {
        _currentIndex = hasFutureAlarm ? 0 : 1;  // 0: 다음알람, 1: 달력
      });
      print('✅ 초기 탭 결정: ${hasFutureAlarm ? "다음알람탭" : "달력탭"}');
    }

    // Provider 갱신은 별도로 (UI 블로킹 방지)
    final container = ProviderScope.containerOf(context);
    container.read(alarmNotifierProvider.notifier).refresh();
  } catch (e) {
    print('❌ 초기 탭 결정 실패: $e');
    if (mounted) {
      setState(() => _currentIndex = 1);  // 에러 시 달력탭
    }
  }
}

  // ⭐ 6번 기능: 달력탭으로 이동
  void _goToCalendar() {
    setState(() => _currentIndex = 1);
  }

  Future<void> _checkRefreshOnStart() async {
    print('🚀 앱 시작 - 갱신 체크');
    await AlarmRefreshService.instance.refreshIfNeeded();
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
    print('🔄 알람 갱신 요청 - 전체 갱신 시작');

    try {
      // ⭐ 1. AlarmRefreshService 호출 (10일치 재생성)
      await AlarmRefreshService.instance.refreshIfNeeded();
      print('✅ AlarmRefreshService 완료 (10일치 재생성)');

      // ⭐ 2. AlarmNotifier 갱신 (UI 업데이트)
      if (mounted) {
        final container = ProviderScope.containerOf(context);
        await container.read(alarmNotifierProvider.notifier).refresh();
        print('✅ AlarmNotifier 새로고침 완료');
      }

    } catch (e) {
      print('❌ 갱신 실패: $e');
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
    // ⭐ 로딩 중이면 빈 화면 표시 (버벅임 방지)
    if (_currentIndex == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: Colors.indigo),
        ),
      );
    }

    return PopScope(
      canPop: _currentIndex == 1,  // 달력탭이면 앱 종료 허용
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 1) {
          // 달력탭이 아니면 달력탭으로 이동
          setState(() => _currentIndex = 1);
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            // 탭 화면
            _tabs[_currentIndex!],
            // ⭐ 권한 경고 배너 (하단에 오버레이)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: const PermissionWarningBanner(),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex!,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.alarm), label: '다음알람'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: '달력'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
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
    // 스플래시 제거 - 바로 다음 화면으로

    if (!mounted) return;

    // 1. 권한 요청 여부 확인
    final prefs = await SharedPreferences.getInstance();
    final permissionsRequested = prefs.getBool('permissions_requested') ?? false;

    // 2. 스케줄 존재 여부 확인
    final schedule = await DatabaseService.instance.getShiftSchedule();

    // 3. 다음 화면 결정
    String nextRoute;

    if (!permissionsRequested) {
      nextRoute = '/permission_intro';
    } else if (schedule == null) {
      nextRoute = '/onboarding';
    } else {
      nextRoute = '/home';
    }

    if (mounted) {
      Navigator.of(context).pushReplacementNamed(nextRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 런치 스크린과 동일한 빈 흰색 화면 (깜빡임 방지)
    return const Scaffold(
      backgroundColor: Colors.white,
    );
  }
}