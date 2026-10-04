import '../widgets/soft_info_dialog.dart';
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

  // ⭐ 이번 릴리즈 전용 "업데이트 후 첫 실행" 안내 문구.
  // 아래 _showUpdateDialog(업데이트 하기 "전" 구버전에서 뜨는 안내)와 달리, 이건
  // 이번 버전 코드에 직접 박아넣는 문구라 "이번 업데이트에 뭐가 바뀌었는지" 구체적으로
  // 쓸 수 있음 - 업데이트 완료 후 첫 실행 시 한 번만 뜸.
  // 다음 버전엔 이 내용을 다시 쓰고 싶지 않으면 _releaseNoteVersion을 빈 문자열로
  // 두면 됨 → 그러면 이 다이얼로그는 그냥 안 뜨고, 위의 "새 버전이 있어요" 안내만
  // 평소처럼 동작함.
  // ⭐ 2026-09-21(사용자 결정) - 1.0.23은 "이번 업데이트는 꼭 확인해주세요" 안내를 띄우지 않음(불필요).
  // 빈 문자열이면 checkAndShowReleaseNote가 즉시 반환하고 "새 버전이 있어요" 안내만 동작함. 다음에 릴리즈 노트를
  // 다시 쓰려면 이 값을 그 버전 문자열로 바꾸고 l10n의 updateReleaseNoteTitle/Body를 새로 쓸 것.
  // 앱 버전과 별개인 이번 공지 전용 ID. 이 값을 본 기기에는 다시 표시하지 않는다.
  // 신규 설치는 온보딩 완료 시 markOnboardingBaselineVersion()이 같은 값을 기록해
  // 업데이트 사용자가 아닌데 공지를 보는 일을 막는다.
  static const String _releaseNoteVersion =
      '2026-09-schedule-sleep-recovery-release';
  static const String _releaseNoteSeenKey = 'release_note_seen_version';

  // ⭐ 2026-08-20 "기존 유저인데도 업데이트 후 안내가 안 뜬다" 버그 수정 - 예전엔
  // "기존 유저가 업데이트하고 나서만 보여줘야 함(신규 설치 유저는 제외)" 판별을
  // _notifiedVersionKey(아래 checkForUpdate가 "새 버전이 있어요" 다이얼로그를 실제로
  // 보여줬을 때만 채워짐)로 했었음 - 그런데 그 자체가 버그가 있던 값이라(위
  // checkForUpdate 주석 참고), 업데이트를 놓친 적 없는(항상 스토어에서 직접 최신으로
  // 유지하는) "성실한" 사용자는 애초에 그 다이얼로그를 볼 일이 영영 없어서
  // _notifiedVersionKey가 평생 0으로 남고, 그래서 "신규 설치 유저"로 영구 오판되어
  // 릴리즈 노트를 한 번도 못 보는 문제가 있었음.
  //
  // 새 방식: 온보딩을 마치는 "그 순간"(markOnboardingBaselineVersion() 참고)에만
  // _lastSeenAppVersionKey를 그때 버전으로 미리 채워둠 - 이게 "이 사용자는 방금
  // 이 버전으로 막 시작했다"는 확실한 신호. 그래서 여기서 이 값이 비어있다는 건
  // (a) 이 기능이 생기기 "전"부터 써오던 기존 유저이거나 (b) 온보딩 이후 최소 한 번은
  // 이 함수를 통과한 적 있는 유저 둘 중 하나 - 어느 쪽이든 "신규 설치 첫 실행"은
  // 아니므로 안내를 보여줘도 안전함(뒤이어 항상 현재 버전으로 값을 채워두므로, 순수
  // 신규 설치는 온보딩 시점에 이미 채워져 있어 아래 "같으면 스킵" 조건에 걸림).
  static const String _lastSeenAppVersionKey =
      'release_note_last_seen_app_version';

  /// 온보딩을 막 끝낸 신규 설치 유저 전용 - "나는 이 버전으로 막 시작했다"는 기준선을
  /// 남겨서, 이후 checkAndShowReleaseNote가 이 사용자에게 "업데이트 후 첫 실행" 안내를
  /// (아직 겪지도 않은 예전 버전과의 차이를) 잘못 보여주지 않게 함.
  static Future<void> markOnboardingBaselineVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSeenAppVersionKey, _releaseNoteVersion);
    } catch (e) {
      debugPrint('릴리즈 노트 기준선 기록 실패: $e');
    }
  }

  /// 업데이트 후 첫 실행 안내 (버전당 1번만, _releaseNoteVersion이 비어있으면 스킵).
  static Future<void> checkAndShowReleaseNote(BuildContext context) async {
    if (_releaseNoteVersion.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final lastSeenVersion = prefs.getString(_lastSeenAppVersionKey);
      if (lastSeenVersion == _releaseNoteVersion) return; // 이미 이 버전 기준선/안내를 지남

      // ⭐ 먼저 기록해서, 다이얼로그 표시 중 문제가 생겨도 다음 실행 때 또 뜨지 않게 함
      await prefs.setString(_lastSeenAppVersionKey, _releaseNoteVersion);

      // 위 클래스 주석 참고 - lastSeenVersion이 null이어도(=이 기능이 생기기 전부터
      // 쓰던 기존 유저) 신규 설치와 구분 없이 그냥 보여줌. 이중 방어로 아래
      // _releaseNoteSeenKey(예전 메커니즘의 잔재)도 같이 체크해서, 혹시 예전 로직으로
      // 이미 이 버전 안내를 본 적 있다면 중복으로 또 띄우지 않음.
      if (prefs.getString(_releaseNoteSeenKey) == _releaseNoteVersion) return;
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

    await showSoftInfoDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        scrollable: true,
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
              textAlign: TextAlign.start,
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
                  style:
                      TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
