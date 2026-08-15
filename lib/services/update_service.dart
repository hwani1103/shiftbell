// lib/services/update_service.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/l10n_extensions.dart';

class UpdateService {
  static const String _notifiedVersionKey = 'notified_update_version';
  static const String _playStoreUrl = 'https://play.google.com/store/apps/details?id=com.hwani1103.shiftbell';

  // ⭐ 이번 릴리즈 전용 "업데이트 후 첫 실행" 안내 문구.
  // 아래 _showUpdateDialog(업데이트 하기 "전" 구버전에서 뜨는 안내)와 달리, 이건
  // 이번 버전 코드에 직접 박아넣는 문구라 "이번 업데이트에 뭐가 바뀌었는지" 구체적으로
  // 쓸 수 있음 - 업데이트 완료 후 첫 실행 시 한 번만 뜸.
  // 다음 버전엔 이 내용을 다시 쓰고 싶지 않으면 _releaseNoteVersion을 빈 문자열로
  // 두면 됨 → 그러면 이 다이얼로그는 그냥 안 뜨고, 위의 "새 버전이 있어요" 안내만
  // 평소처럼 동작함.
  static const String _releaseNoteVersion = '1.0.16';
  static const String _releaseNoteSeenKey = 'release_note_seen_version';

  /// 업데이트 후 첫 실행 안내 (버전당 1번만, _releaseNoteVersion이 비어있으면 스킵).
  ///
  /// ⭐ "기존 유저가 업데이트하고 나서"만 보여줘야 함(신규 설치 유저는 제외) - 판별
  /// 기준으로 _notifiedVersionKey(아래 checkForUpdate가 씀)를 재사용함. 이 키는
  /// "Play Store에 지금 깔린 것보다 최신 버전이 있다"는 인앱 업데이트 안내를 실제로
  /// 본 적이 있을 때만 채워짐 - 방금 Play Store에서 최신 버전을 새로 설치한 사람은
  /// 이미 최신이라 이 안내 자체를 볼 일이 없어서 항상 비어있음(0). 즉 "예전 버전을
  /// 실제로 써본 적 있다"는 신뢰할 만한 증거로 재사용 가능함. (참고: 이 값은
  /// checkForUpdate가 checkAndShowReleaseNote보다 먼저 호출된 "구버전 시절의 실행"에서
  /// 이미 기록돼 있으므로, 방금 업데이트를 마치고 처음 켠 시점엔 이미 존재함)
  static Future<void> checkAndShowReleaseNote(BuildContext context) async {
    if (_releaseNoteVersion.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final everNotifiedOfUpdate = (prefs.getInt(_notifiedVersionKey) ?? 0) > 0;
      if (!everNotifiedOfUpdate) return;  // 신규 설치 유저로 추정 - 스킵

      final seenVersion = prefs.getString(_releaseNoteSeenKey);
      if (seenVersion == _releaseNoteVersion) return;

      // ⭐ 먼저 기록해서, 다이얼로그 표시 중 문제가 생겨도 다음 실행 때 또 뜨지 않게 함
      await prefs.setString(_releaseNoteSeenKey, _releaseNoteVersion);

      if (context.mounted) {
        await _showReleaseNoteDialog(context);
      }
    } catch (e) {
      debugPrint('릴리즈 노트 표시 실패: $e');
    }
  }

  static Future<void> _showReleaseNoteDialog(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        contentPadding: EdgeInsets.all(24.w),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_active_rounded,
                  size: 24.sp,
                  color: colorScheme.primary,
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    context.l10n.updateReleaseNoteTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 18.h),
            Text(
              context.l10n.updateReleaseNoteBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            SizedBox(height: 24.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
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
                  context.l10n.commonGotIt,
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            final result = await _showUpdateDialog(context);

            // ⭐ 버튼을 명확히 눌렀을 때만 저장 (백버튼/바깥터치 dismiss 제외)
            // result: null = 백버튼/바깥터치, false = "나중에", true = "업데이트"
            if (result != null) {
              await prefs.setInt(_notifiedVersionKey, availableVersion);

              if (result) {
                await _openPlayStore();
              }
            }
            // result가 null이면 저장하지 않음 → 다음 실행 시 다시 표시
          }
        }
      }
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
                  context.l10n.updateNewVersionAvailable,
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
              context.l10n.updateRecommendMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            SizedBox(height: 8.h),

            // 안내 문구
            Text(
              context.l10n.updateDataPreservedHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.sp,
                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
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
                      context.l10n.commonLater,
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
                      context.l10n.commonUpdate,
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
