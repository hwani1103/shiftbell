import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/permission_service.dart';

class PermissionWarningBanner extends StatefulWidget {
  const PermissionWarningBanner({super.key});

  @override
  State<PermissionWarningBanner> createState() => _PermissionWarningBannerState();
}

class _PermissionWarningBannerState extends State<PermissionWarningBanner> {
  bool _showBanner = false;
  List<String> _missingPermissions = [];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final permissions = await PermissionService().checkPermissions();

    final missing = <String>[];
    if (!permissions['notification']!) missing.add('알림');
    if (!permissions['exactAlarm']!) missing.add('정확한 알람');
    if (!permissions['overlay']!) missing.add('화면 위 표시');

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

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border(
          bottom: BorderSide(
            color: Colors.orange.shade200,
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange.shade700,
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
                    color: Colors.orange.shade900,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _missingPermissions.join(', '),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          TextButton(
            onPressed: () async {
              await PermissionService().openSettings();
              // 설정에서 돌아왔을 때 재확인
              Future.delayed(const Duration(milliseconds: 500), () {
                _checkPermissions();
              });
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
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
