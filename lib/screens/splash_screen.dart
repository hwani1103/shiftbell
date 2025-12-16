import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // 페이드인 애니메이션
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _animationController.forward();
    _navigateToNextScreen();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _navigateToNextScreen() async {
    // 0.8초 대기
    await Future.delayed(const Duration(milliseconds: 800));

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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.indigo.shade800,
              Colors.indigo.shade600,
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 교대근무 시계 아이콘 (3개 시계 조합)
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // 배경 원 (부드러운 그림자)
                    Container(
                      width: 140.w,
                      height: 140.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),

                    // 중앙 메인 시계
                    Icon(
                      Icons.schedule,
                      size: 90.sp,
                      color: Colors.white,
                    ),

                    // 우측 상단 알람 아이콘 (교대 느낌)
                    Positioned(
                      right: 8.w,
                      top: 8.h,
                      child: Container(
                        padding: EdgeInsets.all(6.w),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade400,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.notifications_active,
                          size: 24.sp,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 32.h),

                // 앱 타이틀
                Text(
                  '교대시계',
                  style: TextStyle(
                    fontSize: 36.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),

                SizedBox(height: 16.h),

                // 구분선
                Container(
                  width: 60.w,
                  height: 3.h,
                  decoration: BoxDecoration(
                    color: Colors.amber.shade400,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),

                SizedBox(height: 16.h),

                // 설명 텍스트
                Text(
                  '교대 스케줄 확인 및 자동 알람 생성',
                  style: TextStyle(
                    fontSize: 15.sp,
                    color: Colors.white.withOpacity(0.9),
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
