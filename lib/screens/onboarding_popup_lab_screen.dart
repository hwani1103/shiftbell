// lib/screens/onboarding_popup_lab_screen.dart
//
// ⭐ 2026-09-05 - "웰컴 팝업 / 근무 배정 방법 팝업" 확인용 임시 개발 탭(사용자
// 요청 - "테스트 탭 하나 만들어서 위아래로 보이게, 크기는 동일하게"). 실제
// 다이얼로그를 반복해서 띄우면 "평생 1회" SharedPreferences 플래그가 소모돼서
// 확인이 끝나면 다시 안 보이게 되므로, 여기서는 OnboardingInfoPreviewCard로
// 카드만(플래그 안 건드림) 나란히 렌더링함 - 실제 온보딩/달력탭 진입 흐름은
// 전혀 안 거침.
//
// ⭐ 2026-09-06(사용자 요청) - update_service.dart의 "업데이트 안내"/"업데이트
// 후 첫 1회 안내" 두 팝업도 같은 방식(카드 미리보기, 실제 트리거/플래그 전혀
// 안 건드림)으로 추가함 - 문구는 l10n(app_ko.arb)에 저장된 실제 값 그대로.
//
// ⭐ 확인 끝나면 main.dart의 _tabs/BottomNavigationBar에서 이 탭 항목만 빼면
// 됨(이 파일 자체는 남겨둬도 무해 - calendar_theme_lab_screen.dart 등 다른 lab
// 화면들과 동일한 선례).
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/onboarding_info_popups.dart';

class OnboardingPopupLabScreen extends StatelessWidget {
  const OnboardingPopupLabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAppBackgroundPastel,
      appBar: AppBar(
        title: const Text('온보딩 팝업 미리보기 (임시)'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Text(
              '① 웰컴 팝업 (앱 최초 설치 시 온보딩 첫 화면)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            const OnboardingInfoPreviewCard.welcome(),
            const SizedBox(height: 32),
            const Text(
              '② 근무 배정 방법 팝업 (불규칙 온보딩 후 첫 달력 진입 시)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            const OnboardingInfoPreviewCard.shiftAssignTutorial(),
            const SizedBox(height: 32),
            const Text(
              '③ 업데이트 안내 팝업 (새 버전이 있을 때, 버전당 1회)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            const OnboardingInfoPreviewCard.updateAvailable(),
            const SizedBox(height: 32),
            const Text(
              '④ 업데이트 후 첫 실행 안내 팝업 (이번 버전 기준, 최초 1회)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            const OnboardingInfoPreviewCard.releaseNote(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
