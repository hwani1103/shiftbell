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
      // ⭐⭐⭐ 테스트용: 항상 다이얼로그 표시 (다크모드 테스트) ⭐⭐⭐
      if (context.mounted) {
        await _showUpdateDialog(context);
      }
      return;
      // ⭐⭐⭐ 원래 코드 (테스트 후 복원 필요) ⭐⭐⭐
      // final info = await InAppUpdate.checkForUpdate();
      //
      // if (info.updateAvailability == UpdateAvailability.updateAvailable) {
      //   final availableVersion = info.availableVersionCode ?? 0;
      //
      //   // 이미 이 버전에 대해 알림했는지 체크
      //   final prefs = await SharedPreferences.getInstance();
      //   final notifiedVersion = prefs.getInt(_notifiedVersionKey) ?? 0;
      //
      //   if (availableVersion > notifiedVersion) {
      //     // 새 버전 알림 표시
      //     if (context.mounted) {
      //       final result = await _showUpdateDialog(context);
      //
      //       // ⭐ 버튼을 명확히 눌렀을 때만 저장 (백버튼/바깥터치 dismiss 제외)
      //       // result: null = 백버튼/바깥터치, false = "나중에", true = "업데이트"
      //       if (result != null) {
      //         await prefs.setInt(_notifiedVersionKey, availableVersion);
      //
      //         if (result) {
      //           await _openPlayStore();
      //         }
      //       }
      //       // result가 null이면 저장하지 않음 → 다음 실행 시 다시 표시
      //     }
      //   }
      // }
    } catch (e) {
      // 업데이트 체크 실패해도 앱 사용에는 문제 없음
      debugPrint('업데이트 체크 실패: $e');
    }
  }

  /// 업데이트 안내 다이얼로그
  /// 반환값: null = dismiss(백버튼/바깥터치), false = "나중에", true = "업데이트"
  static Future<bool?> _showUpdateDialog(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return await showDialog<bool?>(
      context: context,
      barrierDismissible: true,  // 바깥 터치로 닫기 가능 (null 반환)
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        contentPadding: EdgeInsets.all(24.w),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 타이틀
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.celebration,
                  size: 24.sp,
                  color: colorScheme.primary,
                ),
                SizedBox(width: 8.w),
                Text(
                  '새 버전이 있어요!',
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20.h),

            // 설명
            Text(
              '더 나은 사용을 위해\n업데이트를 권장드려요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            SizedBox(height: 8.h),

            // 안내 문구
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: isDark
                    ? colorScheme.primaryContainer.withOpacity(0.3)
                    : colorScheme.primaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                '저장된 정보는 그대로 유지됩니다',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: colorScheme.onSurfaceVariant,
                ),
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
                      side: BorderSide(color: colorScheme.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                    child: Text(
                      '나중에',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: colorScheme.onSurfaceVariant,
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
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
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
    );
  }

  /// Play Store 열기
  static Future<void> _openPlayStore() async {
    final uri = Uri.parse(_playStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
