// lib/services/update_service.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/l10n_extensions.dart';
import 'firebase_bootstrap.dart';

class UpdateService {
  static const String _notifiedVersionKey = 'notified_update_version';
  static const String _playStoreUrl = 'https://play.google.com/store/apps/details?id=com.hwani1103.shiftbell';

  // ⭐ 2026-08-20 "업데이트가 있다는 안내가 안 뜬다" 버그 재설계 - 원래는 Google Play
  // In-App Update API(패키지 in_app_update)로 "새 버전이 있는지"를 물어봤는데, 이 API는
  // Play가 그 기기에 새 버전을 실제로 "전파"해야만 응답이 오는 구조라(배포 직후 몇 시간~
  // 하루 지연 흔함 + 단계적 배포 비율에 걸리면 그 비율 밖 기기는 영영 응답 안 옴) 앱
  // 코드로는 못 고치는 근본 한계가 있었음. 그래서 "새 버전이 있는지" 판단 자체를 Play가
  // 아니라 우리가 직접 통제하는 Firestore 문서(app_config/android)로 옮김 - 이 문서 값을
  // 개발자가 배포 직후 바로 갱신하면, 전파 지연 없이 즉시 전 사용자에게 반영됨. 실제
  // "업데이트하기" 액션은 여전히 Play 스토어로 보냄(_openPlayStore) - 판단만 우리 손으로
  // 옮긴 것.
  static const String _appConfigDocPath = 'app_config/android';

  // ⭐ 콜드 스타트뿐 아니라 앱이 포그라운드로 복귀할 때마다도 불림(main.dart의
  // didChangeAppLifecycleState 참고). Firestore 문서 읽기 자체는 가볍지만(캐시도 됨)
  // 탭 전환하듯 앱을 들락날락하는 사용자가 매번 읽기 호출을 타는 건 낭비라, 마지막 체크
  // 이후 이 시간 안이면 그냥 건너뜀 - "버전당 1번만 알림"이라는 정책과는 별개로,
  // 순수하게 "체크 자체"를 너무 자주 하지 않기 위한 쿨다운.
  static const String _lastCheckedAtKey = 'update_check_last_checked_at';
  static const Duration _checkCooldown = Duration(minutes: 30);

  // ⭐ 이번 릴리즈 전용 "업데이트 후 첫 실행" 안내 문구.
  // 아래 _showUpdateDialog(업데이트 하기 "전" 구버전에서 뜨는 안내)와 달리, 이건
  // 이번 버전 코드에 직접 박아넣는 문구라 "이번 업데이트에 뭐가 바뀌었는지" 구체적으로
  // 쓸 수 있음 - 업데이트 완료 후 첫 실행 시 한 번만 뜸.
  // 다음 버전엔 이 내용을 다시 쓰고 싶지 않으면 _releaseNoteVersion을 빈 문자열로
  // 두면 됨 → 그러면 이 다이얼로그는 그냥 안 뜨고, 위의 "새 버전이 있어요" 안내만
  // 평소처럼 동작함.
  static const String _releaseNoteVersion = '1.0.19';
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
  static const String _lastSeenAppVersionKey = 'release_note_last_seen_app_version';

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
      if (lastSeenVersion == _releaseNoteVersion) return;  // 이미 이 버전 기준선/안내를 지남

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

  /// 업데이트 체크 (버전당 1번만 알림). 콜드 스타트 + 앱 포그라운드 복귀마다 호출됨 -
  /// 클래스 상단 _checkCooldown 주석 참고.
  ///
  /// ⭐ 핵심 요구사항(반드시 지켜야 함):
  /// 1. 새 버전이 있으면 기존 유저에게 "딱 1번"만 안내 - 사용자가 "나중에"로 명시적으로
  ///    닫으면, 그 버전에 대해서는 다시는 안 뜸(아래 notifiedVersion 저장). 더 새로운
  ///    버전이 나오면 그때는 다시 뜸(버전별로 독립적으로 관리됨).
  /// 2. Firestore 조회 자체가 실패해도(오프라인, Firebase 미설정 등) 앱 사용엔 영향 없음.
  static Future<void> checkForUpdate(BuildContext context) async {
    if (!firebaseReady) return;  // 친구공유와 동일한 방어 - Firebase 미설정 시 조용히 스킵

    try {
      final prefs = await SharedPreferences.getInstance();

      final lastCheckedMs = prefs.getInt(_lastCheckedAtKey);
      if (lastCheckedMs != null) {
        final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastCheckedMs));
        if (elapsed < _checkCooldown) return;
      }
      await prefs.setInt(_lastCheckedAtKey, DateTime.now().millisecondsSinceEpoch);

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      if (currentVersionCode == 0) return;  // 버전 정보를 못 읽으면 비교 자체가 무의미 - 스킵

      final doc = await FirebaseFirestore.instance.doc(_appConfigDocPath).get();
      final data = doc.data();
      if (data == null) return;  // 문서가 아직 없음(개발자가 아직 안 만듦) - 조용히 스킵

      // ⭐ 강제 업데이트(하위 호환이 깨지는 등 반드시 최신이어야 하는 경우) - 지금은
      // 문서에 이 필드를 안 넣어두면 0으로 취급돼 자동으로 비활성 상태. 필요할 때
      // Firebase 콘솔에서 minSupportedVersionCode 필드만 채우면 바로 작동함.
      final minSupportedVersionCode = (data['minSupportedVersionCode'] as num?)?.toInt() ?? 0;
      if (minSupportedVersionCode > 0 && currentVersionCode < minSupportedVersionCode) {
        if (context.mounted) await _showForceUpdateDialog(context);
        return;  // 강제 업데이트 안내를 띄웠으면 아래 소프트 안내는 겹쳐서 안 띄움
      }

      final latestVersionCode = (data['latestVersionCode'] as num?)?.toInt() ?? 0;
      if (latestVersionCode <= currentVersionCode) return;  // 이미 최신 - 안내 불필요

      // 이미 이 버전에 대해 알림했는지 체크 (위에서 얻은 prefs 재사용)
      final notifiedVersion = prefs.getInt(_notifiedVersionKey) ?? 0;
      if (latestVersionCode <= notifiedVersion) return;  // 이 버전은 이미 안내함(요구사항 1)

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
      // 업데이트 체크 실패해도 앱 사용에는 문제 없음
      debugPrint('업데이트 체크 실패: $e');
    }
  }

  /// 강제 업데이트 안내 - minSupportedVersionCode 미만일 때만 뜸(기본은 비활성).
  /// 뒤로가기/바깥터치로 닫을 수 없음 - 반드시 업데이트해야 계속 쓸 수 있는 상황 전용.
  static Future<void> _showForceUpdateDialog(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
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
                  Icon(Icons.system_update_alt, size: 24.sp, color: colorScheme.error),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      context.l10n.updateForceUpdateTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18.h),
              Text(
                context.l10n.updateForceUpdateBody,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurfaceVariant, height: 1.5),
              ),
              SizedBox(height: 24.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await _openPlayStore();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                  ),
                  child: Text(
                    context.l10n.commonUpdate,
                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
