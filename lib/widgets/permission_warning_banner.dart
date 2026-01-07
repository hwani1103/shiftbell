import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/permission_service.dart';

class PermissionWarningBanner extends StatefulWidget {
  const PermissionWarningBanner({super.key});

  @override
  State<PermissionWarningBanner> createState() => _PermissionWarningBannerState();
}

class _PermissionWarningBannerState extends State<PermissionWarningBanner> with WidgetsBindingObserver {
  bool _showBanner = false;
  List<String> _missingPermissions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 다시 활성화되면 권한 재확인
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final permissions = await PermissionService().checkPermissions();

    final missing = <String>[];
    if (!permissions['notification']!) missing.add('알림');
    if (!permissions['overlay']!) missing.add('다른 앱 위에 표시');

    if (mounted) {
      setState(() {
        _missingPermissions = missing;
        _showBanner = missing.isNotEmpty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_showBanner) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.tertiary.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colorScheme.tertiary,
            size: 24.sp,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '필수 권한 미허용',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _missingPermissions.join(', '),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          TextButton(
            onPressed: () async {
              await PermissionService().openSettings();
            },
            style: TextButton.styleFrom(
              backgroundColor: colorScheme.tertiary,
              foregroundColor: colorScheme.onTertiary,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            child: Text(
              '설정',
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
