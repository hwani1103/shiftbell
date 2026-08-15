import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n_extensions.dart';

class PermissionIntroScreen extends StatefulWidget {
  const PermissionIntroScreen({super.key});

  @override
  State<PermissionIntroScreen> createState() => _PermissionIntroScreenState();
}

class _PermissionIntroScreenState extends State<PermissionIntroScreen> with WidgetsBindingObserver {
  bool _isNavigating = false; // 중복 navigate 방지

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
    // 앱이 포그라운드로 돌아올 때 권한 확인
    if (state == AppLifecycleState.resumed && !_isNavigating) {
      _checkPermissionsAndNavigate();
    }
  }

  Future<void> _checkPermissionsAndNavigate() async {
    if (_isNavigating) return; // 이미 이동 중이면 무시

    final permissions = await PermissionService().checkPermissions();
    final allGranted = permissions['notification']! && permissions['overlay']! && permissions['exactAlarm']!;

    if (allGranted && mounted) {
      _navigateToOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 40.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Text(
                context.l10n.permissionGetStarted,
                style: TextStyle(
                  fontSize: 28.sp,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                context.l10n.permissionIntro,
                style: TextStyle(
                  fontSize: 16.sp,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 48.h),

              // 필수 권한 목록
              _buildPermissionItem(
                context: context,
                icon: Icons.notifications_active,
                iconColor: colorScheme.tertiary,
                title: context.l10n.permissionNotification,
                description: context.l10n.permissionNotificationDesc,
                required: true,
              ),
              SizedBox(height: 24.h),
              _buildPermissionItem(
                context: context,
                icon: Icons.phone_android,
                iconColor: Colors.green,
                title: context.l10n.permissionOverlay,
                description: context.l10n.permissionOverlayDesc,
                required: true,
              ),
              SizedBox(height: 24.h),
              _buildPermissionItem(
                context: context,
                icon: Icons.alarm_on,
                iconColor: Colors.orange,
                title: context.l10n.permissionExactAlarm,
                description: context.l10n.permissionExactAlarmDesc,
                required: true,
              ),

              const Spacer(),

              // 하단 버튼
              SizedBox(
                width: double.infinity,
                height: 56.h,
                child: ElevatedButton(
                  onPressed: _requestPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: Text(
                    context.l10n.permissionAllow,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              SizedBox(
                width: double.infinity,
                height: 56.h,
                child: TextButton(
                  onPressed: _skipPermissions,
                  child: Text(
                    context.l10n.commonNotNow,
                    style: TextStyle(
                      fontSize: 16.sp,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required bool required,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 56.w,
          height: 56.w,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Icon(
            icon,
            size: 32.sp,
            color: iconColor,
          ),
        ),
        SizedBox(width: 16.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (required) ...[
                    SizedBox(width: 6.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(
                        context.l10n.permissionRequired,
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ] else ...[
                    SizedBox(width: 6.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(
                        context.l10n.permissionRecommended,
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 4.h),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13.sp,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _requestPermissions() async {
    // 권한 요청
    final allGranted = await PermissionService().requestAllPermissions();

    if (!mounted) return;

    // 권한 상태 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_requested', true);

    if (allGranted) {
      // 모두 허용 → 온보딩으로
      _navigateToOnboarding();
    } else {
      // 일부 거부 → 경고 다이얼로그 표시
      _showPermissionWarning();
    }
  }

  Future<void> _skipPermissions() async {
    // 나중에 하기 → 경고 다이얼로그 표시
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_requested', true);

    if (!mounted) return;
    _showPermissionWarning();
  }

  void _showPermissionWarning() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colorScheme.tertiary, size: 28.sp),
            SizedBox(width: 8.w),
            Flexible(
              child: Text(
                context.l10n.permissionSomeDenied,
                style: TextStyle(fontSize: 16.sp),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.permissionSomeDeniedDesc,
              style: TextStyle(fontSize: 14.sp, height: 1.5),
            ),
            SizedBox(height: 16.h),
            Text(
              context.l10n.permissionCanAllowLater,
              style: TextStyle(
                fontSize: 13.sp,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await PermissionService().openSettings();
            },
            child: Text(context.l10n.commonGoToSettings),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToOnboarding();
            },
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
            ),
            child: Text(context.l10n.commonContinue),
          ),
        ],
      ),
    );
  }

  void _navigateToOnboarding() {
    if (_isNavigating) return; // 중복 방지
    _isNavigating = true;
    Navigator.of(context).pushReplacementNamed('/onboarding');
  }
}
