import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionIntroScreen extends StatelessWidget {
  const PermissionIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 40.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Text(
                '교대시계 시작하기',
                style: TextStyle(
                  fontSize: 28.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                '알람이 정확하게 울리려면\n아래 권한이 필요해요',
                style: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 48.h),

              // 필수 권한 목록
              _buildPermissionItem(
                icon: Icons.notifications_active,
                iconColor: Colors.orange,
                title: '알림',
                description: '사전 알림 & 스누즈 안내',
                required: true,
              ),
              SizedBox(height: 24.h),
              _buildPermissionItem(
                icon: Icons.alarm,
                iconColor: Colors.blue,
                title: '정확한 알람',
                description: '정확한 시간에 알람 울림',
                required: true,
              ),
              SizedBox(height: 24.h),
              _buildPermissionItem(
                icon: Icons.phone_android,
                iconColor: Colors.green,
                title: '화면 위 표시',
                description: '화면 해제 시 알람 팝업',
                required: true,
              ),
              SizedBox(height: 32.h),

              // 구분선
              Divider(color: Colors.grey.shade300, thickness: 1),
              SizedBox(height: 24.h),

              // 선택 권한
              _buildPermissionItem(
                icon: Icons.battery_charging_full,
                iconColor: Colors.purple,
                title: '배터리 최적화 제외',
                description: '안정적인 백그라운드 작동',
                required: false,
              ),

              const Spacer(),

              // 하단 버튼
              SizedBox(
                width: double.infinity,
                height: 56.h,
                child: ElevatedButton(
                  onPressed: () => _requestPermissions(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: Text(
                    '권한 허용하기',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              SizedBox(
                width: double.infinity,
                height: 56.h,
                child: TextButton(
                  onPressed: () => _skipPermissions(context),
                  child: Text(
                    '나중에 하기',
                    style: TextStyle(
                      fontSize: 16.sp,
                      color: Colors.grey.shade600,
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
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required bool required,
  }) {
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
                      color: Colors.black87,
                    ),
                  ),
                  if (required) ...[
                    SizedBox(width: 6.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(
                        '필수',
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ] else ...[
                    SizedBox(width: 6.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(
                        '권장',
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
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
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _requestPermissions(BuildContext context) async {
    // 권한 요청
    final allGranted = await PermissionService().requestAllPermissions();

    if (!context.mounted) return;

    // 권한 상태 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_requested', true);

    if (allGranted) {
      // 모두 허용 → 온보딩으로
      _navigateToOnboarding(context);
    } else {
      // 일부 거부 → 경고 다이얼로그 표시
      _showPermissionWarning(context);
    }
  }

  Future<void> _skipPermissions(BuildContext context) async {
    // 나중에 하기 → 경고 다이얼로그 표시
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_requested', true);

    if (!context.mounted) return;
    _showPermissionWarning(context);
  }

  void _showPermissionWarning(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28.sp),
            SizedBox(width: 8.w),
            Text('일부 권한이 거부되었어요'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '앱을 계속 사용할 수 있지만\n알람이 정확히 울리지 않을 수 있어요.',
              style: TextStyle(fontSize: 14.sp, height: 1.5),
            ),
            SizedBox(height: 16.h),
            Text(
              '설정에서 언제든지 권한을 허용할 수 있어요.',
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.grey.shade600,
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
            child: const Text('설정으로 이동'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToOnboarding(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade600,
            ),
            child: const Text('계속 진행하기'),
          ),
        ],
      ),
    );
  }

  void _navigateToOnboarding(BuildContext context) {
    Navigator.of(context).pushReplacementNamed('/onboarding');
  }
}
