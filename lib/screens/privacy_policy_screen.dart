// lib/screens/privacy_policy_screen.dart
//
// ⭐ 2026-09-07 - 개인정보처리방침 화면 전면 재작성(사용자 요청). 예전엔 설정 탭에서
// AlertDialog 하나에 문단 전체를 그냥 텍스트로 욱여넣었고(내용도 "개인정보를 전혀
// 수집하지 않는다"는 오래된 문구 그대로라, 그사이 생긴 일정공유(Firestore)/광고
// (Google AdMob) 기능과 안 맞았음 - 실제로는 예외가 두 가지 있는데 그걸 숨기는
// 꼴이었음), 이번에 help_screen.dart와 같은 "섹션 카드" 레이아웃(파스텔 배경 +
// 흰색 둥근 카드 + 강조색 섹션 제목)으로 다시 만들고, 내용도 실제 코드 기준으로
// 다시 검증해서 씀:
// - 기본 원칙: 기기 로컬 저장(그대로 유지 - 실제로 맞는 내용).
// - 예외 1: 일정공유(friend_sync_service.dart) - Firestore에 스케줄 저장, 공유
//   중지 시 즉시 삭제됨(stopSharing() 확인). 업데이트 확인(update_service.dart)도
//   Firestore를 읽지만 개인정보 전송은 없음 - 같은 섹션에서 같이 설명.
// - 예외 2: 광고(banner_ad_slot.dart, google_mobile_ads) - 예전 문구엔 아예
//   없었음(누락이었던 항목).
// - 권한 3종에 "정확한 알람"이 빠져있던 것도 추가(permission_intro_screen.dart
//   기준 3종 전부).
//
// 문의처는 티스토리 + 카카오톡 오픈채팅("교대시계 앱" 검색) 두 가지(사용자 요청).
//
// 콘텐츠(제목/본문)는 help_screen.dart와 동일하게 전부 l10n(app_ko.arb/app_en.arb의
// privacy* 키)에 있음 - 문구만 고치고 싶으면 이 파일이 아니라 그 키들을 고치면 됨.
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/app_colors.dart';

class _PrivacySection {
  final IconData icon;
  final String Function(AppLocalizations l10n) title;
  final String Function(AppLocalizations l10n) body;
  const _PrivacySection({required this.icon, required this.title, required this.body});
}

final List<_PrivacySection> _privacySections = [
  _PrivacySection(
    icon: Icons.smartphone_outlined,
    title: (l10n) => l10n.privacyNoCollectionTitle,
    body: (l10n) => l10n.privacyNoCollectionBody,
  ),
  _PrivacySection(
    icon: Icons.cloud_outlined,
    title: (l10n) => l10n.privacyFirebaseTitle,
    body: (l10n) => l10n.privacyFirebaseBody,
  ),
  _PrivacySection(
    icon: Icons.campaign_outlined,
    title: (l10n) => l10n.privacyAdsTitle,
    body: (l10n) => l10n.privacyAdsBody,
  ),
  _PrivacySection(
    icon: Icons.shield_outlined,
    title: (l10n) => l10n.privacyPermissionsTitle,
    body: (l10n) => l10n.privacyPermissionsBody,
  ),
  _PrivacySection(
    icon: Icons.delete_outline,
    title: (l10n) => l10n.privacyDataRetentionTitle,
    body: (l10n) => l10n.privacyDataRetentionBody,
  ),
  _PrivacySection(
    icon: Icons.child_care_outlined,
    title: (l10n) => l10n.privacyChildrenTitle,
    body: (l10n) => l10n.privacyChildrenBody,
  ),
  _PrivacySection(
    icon: Icons.mail_outline,
    title: (l10n) => l10n.privacyContactTitle,
    body: (l10n) => l10n.privacyContactBody,
  ),
];

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: kAppBackgroundPastel,
      appBar: AppBar(
        title: Text(l10n.settingsPrivacyPolicy),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 28.h),
          children: [
            // 인트로 카드 - 아이콘 + 한 줄 요약.
            Container(
              padding: EdgeInsets.all(18.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.privacy_tip_outlined, size: 22.sp, color: kAppMainAccent),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      l10n.privacyIntro,
                      style: TextStyle(fontSize: 13.5.sp, color: Colors.black87, height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
            for (final section in _privacySections) ...[
              SizedBox(height: 18.h),
              Row(
                children: [
                  Icon(section.icon, size: 18.sp, color: kAppMainAccent),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      section.title(l10n),
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: kAppMainAccent,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Text(
                  section.body(l10n),
                  style: TextStyle(fontSize: 13.5.sp, color: Colors.black87, height: 1.6),
                ),
              ),
            ],
            SizedBox(height: 20.h),
            Center(
              child: Text(
                l10n.privacyEffectiveDate,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5.sp, color: Colors.grey.shade600, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
