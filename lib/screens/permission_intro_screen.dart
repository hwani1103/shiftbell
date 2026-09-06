import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n_extensions.dart';
import '../main.dart'; // ⭐ MainScreen import(onboarding_screen.dart와 동일 패턴)
import '../models/backup_payload.dart';
import '../services/backup_storage_service.dart';
import '../services/database_service.dart';
import 'restore_backup_screen.dart';

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
              // ⭐ 2026-09-01 - 백업 불러오기 진입점은 온보딩 화면(근무명 지정
              // 단계, "다음" 버튼 위)으로 옮김 - 여기 있으면 권한 허용 전에
              // 눈에 안 띄게 묻혀서, 실제로 근무 데이터를 입력하려는 시점에
              // 더 자연스럽게 물어보는 게 낫다는 판단. onboarding_screen.dart
              // _buildShiftTypeCreation() 참고.
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

  // ⭐ 2026-09-01 - "백업 복구했는데 온보딩 어디에도 그 화면이 안 나온다" 버그
  // 수정. 원인: 사용자 데이터 백업("A번 요구사항")의 복구 확인 화면
  // (RestoreBackupScreen)은 main.dart의 InitialRouter._navigate()에만 연결해
  // 뒀었는데, 실제 "권한 안내 화면을 막 통과한" 순간은 이 함수(당시
  // _navigateToOnboarding)가 그 InitialRouter를 다시 거치지 않고 곧장
  // `/onboarding`으로 직행했음(named route). 그래서 진짜 신규 설치 흐름에서는
  // 백업 확인 로직이 있으나 마나였음 - 이 함수가 그 "권한 화면 다음" 분기의
  // 진짜 트리거였다.
  //
  // 이 참에 반대 방향 버그도 같이 고침: RestoreBackupScreen에서 복구를 마친
  // 뒤 OS 권한을 다시 받게 하려고 이 화면으로 돌아오는데(restore_backup_screen.dart),
  // 그 경우 스케줄이 이미 채워져 있으므로 여기서 다시 온보딩으로 보내면 안 되고
  // 곧장 MainScreen으로 가야 함 - InitialRouter의 3단 분기(권한→스케줄 유무→
  // 백업 유무)와 동일한 판단을 여기서도 그대로 반복함.
  Future<void> _navigateToOnboarding() async {
    if (_isNavigating) return; // 중복 방지
    _isNavigating = true;

    final schedule = await DatabaseService.instance.getShiftSchedule();

    if (schedule != null) {
      // 이미 스케줄이 있음 - 방금 백업을 복구하고 돌아온 경우. 온보딩 마법사를
      // 다시 태울 이유가 없으므로 곧장 메인 화면으로.
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainScreen(initialIndex: kCalendarTabIndex)), // 달력탭
      );
      return;
    }

    // 스케줄이 없음 - 진짜 신규 설치(또는 초기화 직후). 온보딩으로 보내기 전에
    // 이 기기에 예전 백업이 남아있는지 마지막으로 확인 - MediaStore는 앱을
    // 지워도 파일이 안 지워지므로(backup_storage_service.dart 참고).
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
        MaterialPageRoute(builder: (context) => RestoreBackupScreen(payload: payload!)),
      );
    } else {
      Navigator.of(context).pushReplacementNamed('/onboarding');
    }
  }
}
