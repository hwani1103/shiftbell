// lib/services/update_service.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/l10n_extensions.dart';

class UpdateService {
  static const String _notifiedVersionKey = 'notified_update_version';
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.hwani1103.shiftbell';

  // Play가 이 기기에 제공하는 버전만 안내한다. 단계적 배포 대상이 아니거나
  // Play 반영 전이면 UPDATE_AVAILABLE이 아니므로 Firestore로 앞서 알리지 않는다.
  // 콜드 스타트와 포그라운드 복귀에 호출되지만 Play 조회는 6시간 간격으로 제한한다.
  static const String _lastCheckedAtKey = 'play_update_last_checked_at';
  static const Duration _checkCooldown = Duration(hours: 6);
  static bool _checkInProgress = false;

  // 업데이트 내용은 Play 스토어에서 안내한다. 앱은 새 버전 설치만 안내한다.

  /// 업데이트 체크 (버전당 1번만 알림). 콜드 스타트 + 앱 포그라운드 복귀마다 호출됨 -
  /// 클래스 상단 _checkCooldown 주석 참고.
  ///
  /// ⭐ 핵심 요구사항(반드시 지켜야 함):
  /// 1. 새 버전이 있으면 기존 유저에게 "딱 1번"만 안내 - 사용자가 "나중에"로 명시적으로
  ///    닫으면, 그 버전에 대해서는 다시는 안 뜸(아래 notifiedVersion 저장). 더 새로운
  ///    버전이 나오면 그때는 다시 뜸(버전별로 독립적으로 관리됨).
  /// 2. Play 조회가 실패해도 앱 사용엔 영향 없음.
  static Future<void> checkForUpdate(BuildContext context) async {
    if (_checkInProgress) return;
    _checkInProgress = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      final lastCheckedMs = prefs.getInt(_lastCheckedAtKey);
      if (lastCheckedMs != null) {
        final elapsed = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(lastCheckedMs));
        if (elapsed < _checkCooldown) return;
      }
      final info = await InAppUpdate.checkForUpdate();
      await prefs.setInt(
          _lastCheckedAtKey, DateTime.now().millisecondsSinceEpoch);
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
      final latestVersionCode = info.availableVersionCode;
      if (latestVersionCode == null || latestVersionCode <= 0) return;

      // 이미 이 버전에 대해 알림했는지 체크 (위에서 얻은 prefs 재사용)
      final notifiedVersion = prefs.getInt(_notifiedVersionKey) ?? 0;
      if (latestVersionCode <= notifiedVersion) return; // 이 버전은 이미 안내함(요구사항 1)

      if (context.mounted) {
        final result = await _showUpdateDialog(context);

        // ⭐ 버튼을 명확히 눌렀을 때만 저장 (백버튼/바깥터치 dismiss 제외)
        // result: null = 백버튼/바깥터치, false = "나중에"(의도적으로 닫음), true = "업데이트"
        if (result != null) {
          await prefs.setInt(_notifiedVersionKey, latestVersionCode);

          if (result) {
            await _openPlayStore();
          }
        }
        // result가 null이면 저장하지 않음 → 다음 실행 시 다시 표시(실수로 뒤로가기 눌렀을
        // 가능성을 배려 - "의도적으로" 닫은 경우만 다시 안 뜨게 하는 게 목표라, 명시적
        // 버튼(나중에/업데이트) 클릭만 "의도적"으로 취급함)
      }
    } catch (e) {
      debugPrint('Play 업데이트 확인 실패: $e');
    } finally {
      _checkInProgress = false;
    }
  }

  /// 업데이트 안내 다이얼로그
  /// 반환값: null = dismiss(백버튼/바깥터치), false = "나중에", true = "업데이트"
  static Future<bool?> _showUpdateDialog(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;

    return await showDialog<bool?>(
      context: context,
      barrierDismissible: true, // 바깥 터치로 닫기 가능 (null 반환)
      builder: (context) => AlertDialog(
        // ⭐ 2026-09-22 - 큰 글자·작은 화면에서 세로로 넘치지 않게 스크롤 허용(출시 직후 기존 사용자 전원이 보는 대화상자)
        scrollable: true,
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        contentPadding: EdgeInsets.all(24.w),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 타이틀 - 영어·큰 글자에서 가로로 넘치지 않게 Flexible(짧으면 지금처럼 가운데)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.celebration,
                  size: 24.sp,
                  color: colorScheme.primary,
                ),
                SizedBox(width: 8.w),
                Flexible(
                  child: Text(
                    context.l10n.updateNewVersionAvailable,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
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
