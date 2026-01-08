import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'screens/calendar_tab.dart';
import 'screens/next_alarm_tab.dart';
import 'screens/settings_tab.dart';
import 'screens/permission_intro_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/database_service.dart';
import 'services/alarm_service.dart';
import 'services/alarm_refresh_helper.dart';
import 'services/alarm_refresh_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_pkg;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shift_schedule.dart';
import 'providers/alarm_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⭐ 앱 시작 시 알람 갱신 체크
  await AlarmRefreshService.instance.refreshIfNeeded();

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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      print('📱 앱 포그라운드 진입 - 갱신 체크');
      AlarmRefreshService.instance.refreshIfNeeded();

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
            final themeMode = ref.watch(themeProvider);
            final isDark = themeMode == ThemeMode.dark;

            return MaterialApp(
              title: '교대종',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              builder: (context, child) {
                return Container(
                  color: isDark ? Color(0xFF0A0A0A) : Colors.grey.shade200,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: maxContentWidth),
                      child: Container(
                        color: isDark ? Color(0xFF000000) : Colors.white,
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
              },
            );
          },
        );
      },
    );
  }
}

class MainScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  const MainScreen({super.key, required this.initialIndex});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  late int _currentIndex;
  static const platform = MethodChannel('com.hwani1103.shiftbell/alarm');

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex;

    _tabs = [
      NextAlarmTab(onSwipeToCalendar: _onSwipeToCalendar),
      CalendarTab(onSwipeToSettings: _onSwipeToSettings),
      SettingsTab(onSwipeToCalendar: _onSwipeToCalendar),
    ];

    platform.setMethodCallHandler(_handleMethod);
  }

  void _onSwipeToCalendar() {
    if (mounted) {
      setState(() {
        _currentIndex = 1;
      });
    }
  }

  void _onSwipeToSettings() {
    if (mounted) {
      setState(() {
        _currentIndex = 2;
      });
    }
  }

  Future<void> _handleMethod(MethodCall call) async {
    if (!mounted) return;

    if (call.method == 'switchToCalendarTab') {
      setState(() {
        _currentIndex = 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.alarm),
            label: '다음 알람',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: '달력',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}

class InitialRouter extends ConsumerStatefulWidget {
  const InitialRouter({super.key});

  @override
  ConsumerState<InitialRouter> createState() => _InitialRouterState();
}

class _InitialRouterState extends ConsumerState<InitialRouter> {
  @override
  void initState() {
    super.initState();
    _checkAndRoute();
  }

  Future<void> _checkAndRoute() async {
    await Future.delayed(const Duration(milliseconds: 50));

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;

    if (!onboardingComplete) {
      Navigator.of(context).pushReplacementNamed('/permission_intro');
      return;
    }

    final schedule = await ref.read(scheduleProvider.future);
    if (schedule == null) {
      Navigator.of(context).pushReplacementNamed('/onboarding');
      return;
    }

    final nextAlarm = await ref.read(nextAlarmProvider.future);
    final initialTab = (nextAlarm != null) ? 0 : 1;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => MainScreen(initialIndex: initialTab),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
