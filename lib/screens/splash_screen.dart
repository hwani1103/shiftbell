import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNextScreen();
  }

  Future<void> _navigateToNextScreen() async {
    // 1초 대기
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    // 1. 권한 요청 여부 확인
    final prefs = await SharedPreferences.getInstance();
    final permissionsRequested = prefs.getBool('permissions_requested') ?? false;

    // 2. 스케줄 존재 여부 확인
    final schedule = await DatabaseService.instance.getShiftSchedule();

    // 3. 다음 화면 결정
    String nextRoute;

    if (!permissionsRequested) {
      // 권한 미요청 → 권한 안내 화면
      nextRoute = '/permission_intro';
    } else if (schedule == null) {
      // 권한 요청됨 + 스케줄 없음 → 온보딩
      nextRoute = '/onboarding';
    } else {
      // 권한 요청됨 + 스케줄 있음 → 메인 화면
      nextRoute = '/home';
    }

    if (mounted) {
      Navigator.of(context).pushReplacementNamed(nextRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade700,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 앱 아이콘 또는 로고
            Icon(
              Icons.access_time,
              size: 100.sp,
              color: Colors.white,
            ),
            SizedBox(height: 24.h),
            Text(
              '교대시계',
              style: TextStyle(
                fontSize: 32.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'ShiftBell',
              style: TextStyle(
                fontSize: 16.sp,
                color: Colors.white70,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
