// lib/services/update_service.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String _notifiedVersionKey = 'notified_update_version';
  static const String _playStoreUrl = 'https://play.google.com/store/apps/details?id=com.hwani1103.shiftbell';

  /// 업데이트 체크 (버전당 1번만 알림)
  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      final info = await InAppUpdate.checkForUpdate();

      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        final availableVersion = info.availableVersionCode ?? 0;

        // 이미 이 버전에 대해 알림했는지 체크
        final prefs = await SharedPreferences.getInstance();
        final notifiedVersion = prefs.getInt(_notifiedVersionKey) ?? 0;

        if (availableVersion > notifiedVersion) {
          // 새 버전 알림 표시
          if (context.mounted) {
            final shouldUpdate = await _showUpdateDialog(context);

            // 알림한 버전 저장 (다시 안 보이게)
            await prefs.setInt(_notifiedVersionKey, availableVersion);

            if (shouldUpdate) {
              await _openPlayStore();
            }
          }
        }
      }
    } catch (e) {
      // 업데이트 체크 실패해도 앱 사용에는 문제 없음
      debugPrint('업데이트 체크 실패: $e');
    }
  }

  /// 업데이트 안내 다이얼로그
  static Future<bool> _showUpdateDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Container(
          padding: EdgeInsets.all(24.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.indigo.shade50,
                Colors.white,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 아이콘
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.system_update,
                  size: 40.sp,
                  color: Colors.indigo.shade700,
                ),
              ),
              SizedBox(height: 20.h),

              // 타이틀
              Text(
                '새 버전이 있어요!',
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade800,
                ),
              ),
              SizedBox(height: 12.h),

              // 설명
              Text(
                '더 나은 사용을 위해\n업데이트를 권장드려요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 8.h),

              // 안내 문구
              Text(
                '(저장된 정보는 그대로 유지됩니다.)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.grey.shade500,
                ),
              ),
              SizedBox(height: 24.h),

              // 버튼들
              Row(
                children: [
                  // 나중에 버튼
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                      ),
                      child: Text(
                        '나중에',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),

                  // 업데이트 버튼
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade600,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                      ),
                      child: Text(
                        '업데이트',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ) ?? false;
  }

  /// Play Store 열기
  static Future<void> _openPlayStore() async {
    final uri = Uri.parse(_playStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
