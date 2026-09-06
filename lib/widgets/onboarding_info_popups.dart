// lib/widgets/onboarding_info_popups.dart
//
// ⭐ 2026-09-05 - 최초 1회만 보여주는 안내 팝업 2종(사용자 요청):
// 1) 웰컴 팝업 - 온보딩 첫 화면 진입 시(앱을 실제로 처음 설치했을 때만).
// 2) 근무 배정 방법 팝업 - 불규칙 온보딩을 마치고 메인 달력에 처음 왔을 때만
//    (규칙적 스케줄이면 안 뜸 - 패턴이 자동으로 배정되니 이 안내가 불필요).
//
// 둘 다 SharedPreferences 플래그로 "평생 1회"만 관리함(달력 탭 재진입/재실행은
// 물론, 설정 → 초기화를 해도 다시 안 뜸 - 초기화 로직(schedule_provider.dart의
// resetSchedule)이 이 플래그들을 전혀 안 건드리므로 자연히 유지됨).
//
// 내용은 서로 완전히 다른 주제(웰컴 인사말 vs 근무 배정 조작법)라 별도
// 위젯이지만, "같은 크기·같은 톤의 카드"로 보이도록 [_InfoPopupCard] 하나를
// 공유해서 씀 - 사용자가 새로 만든 lab 탭(onboarding_popup_lab_screen.dart)에서
// 두 개를 나란히 비교해도 크기가 어긋나 보이지 않게 하려는 목적.
//
// ⭐ 2026-09-06(사용자 요청) - "업데이트 안내"/"업데이트 후 첫 1회 안내"
// 팝업(둘 다 실제 구현은 update_service.dart에 이미 있고 여기서 새로 만드는 게
// 아님)도 같은 lab 탭에서 같은 카드 스타일로 미리보기만 하고 싶다고 해서
// UpdateAvailableContent/ReleaseNoteContent를 추가함 - 문구는 l10n(app_ko.arb)에
// 저장된 실제 값을 그대로 옮김. update_service.dart의 실제 다이얼로그 로직/트리거
// 조건은 전혀 안 건드림(이 파일은 순수 미리보기 카드 전용).

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_button.dart';

const _kWelcomePopupShownKey = 'welcome_popup_shown';
const _kShiftAssignTutorialShownKey = 'shift_assign_tutorial_shown';

/// 온보딩 첫 화면(_OnboardingScreenState)이 initState에서 부르는 함수 - 이미
/// 봤으면 아무 것도 안 함.
Future<void> maybeShowWelcomePopup(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kWelcomePopupShownKey) ?? false) return;
  await prefs.setBool(_kWelcomePopupShownKey, true);
  if (!context.mounted) return;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: _InfoPopupCard(
        content: WelcomePopupContent(),
        onConfirm: () => Navigator.of(context).pop(),
      ),
    ),
  );
}

/// 달력 탭(calendar_tab.dart)이 스케줄 로드 후 부르는 함수 - 불규칙 스케줄이고
/// 아직 안 봤을 때만 뜸.
Future<void> maybeShowShiftAssignTutorial(BuildContext context, {required bool isRegular}) async {
  if (isRegular) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kShiftAssignTutorialShownKey) ?? false) return;
  await prefs.setBool(_kShiftAssignTutorialShownKey, true);
  if (!context.mounted) return;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: _InfoPopupCard(
        content: ShiftAssignTutorialContent(),
        onConfirm: () => Navigator.of(context).pop(),
      ),
    ),
  );
}

/// 공용 카드 - 두 팝업이 항상 같은 크기/톤으로 보이게 함(제목 아이콘 + 제목 +
/// 본문 + 버튼 1개, 최소 높이를 통일해서 본문 길이가 달라도 비슷한 크기로 보임).
class _InfoPopupCard extends StatelessWidget {
  final _PopupContent content;
  final VoidCallback onConfirm;
  // ⭐ 2026-09-06 - "업데이트 안내" 미리보기용. null이면(기존 두 팝업) 예전처럼
  // 버튼 1개(전체 너비)만 그림 - 실제 다이얼로그 로직과는 무관한 미리보기
  // 전용이라 onSecondaryConfirm도 그냥 시각적 버튼만 필요할 뿐 실제 동작은
  // 없어도 됨.
  final VoidCallback? onSecondaryConfirm;
  const _InfoPopupCard({required this.content, required this.onConfirm, this.onSecondaryConfirm});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 320, maxWidth: 340),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(content.emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 14),
            Text(
              content.title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.black87),
            ),
            const SizedBox(height: 14),
            // ⭐ 2026-09-05 버그 수정(사용자 신고 - "팝업확인 탭에 아무것도 안
            // 보임") - 여기 Expanded가 원인이었음. 실제 팝업(showDialog)에서는
            // Dialog가 높이를 제한해주니 문제가 없었는데, lab
            // 탭(onboarding_popup_lab_screen.dart)은 이 카드를
            // SingleChildScrollView 안에 그대로 두므로 그 Column의 높이가
            // 무제한(unbounded)이 됨 - Expanded는 부모 높이가 유한해야만
            // 동작해서 레이아웃 예외가 나 화면이 통째로 안 그려졌음. 이
            // 카드는 애초에 maxHeight 제약이 없어서(ConstrainedBox엔
            // minHeight만 있음) Expanded로 "남는 공간 채우기"를 할 이유가
            // 없었음 - 그냥 내용 높이만큼만 차지하게 두면 Dialog/lab 탭 양쪽
            // 다 안전함(SingleChildScrollView는 그대로 둬서, 아주 작은
            // 화면에서 Dialog에 담겼을 때 내용이 넘치면 스크롤은 여전히 됨).
            SingleChildScrollView(
              child: Text(
                content.body,
                style: TextStyle(fontSize: 14.5, height: 1.55, color: Colors.black.withOpacity(0.75)),
              ),
            ),
            const SizedBox(height: 20),
            if (content.secondaryButtonLabel == null)
              SizedBox(
                width: double.infinity,
                child: AppButton(onPressed: onConfirm, child: Text(content.buttonLabel)),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSecondaryConfirm,
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text(content.secondaryButtonLabel!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: AppButton(onPressed: onConfirm, child: Text(content.buttonLabel))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PopupContent {
  final String emoji;
  final String title;
  final String body;
  final String buttonLabel;
  final String? secondaryButtonLabel;
  const _PopupContent({
    required this.emoji,
    required this.title,
    required this.body,
    required this.buttonLabel,
    this.secondaryButtonLabel,
  });
}

/// ⭐ 실제 다이얼로그 안(_InfoPopupCard)에서도 쓰고, lab 탭에서 "다이얼로그를
/// 안 띄우고 카드만" 미리보기할 때도 재사용하려고 StatelessWidget이 아니라
/// 데이터 객체 형태로 뺌 - WelcomePopupContent()/ShiftAssignTutorialContent()는
/// 그 데이터를 담은 값일 뿐, 자기 자신을 그리지 않음(_InfoPopupCard가 그림).
class WelcomePopupContent extends _PopupContent {
  WelcomePopupContent()
      : super(
          emoji: '👋',
          title: '교대시계 앱을 설치해주셔서 \n감사합니다.',
          body: 
              '최초 1회 내 근무 스케줄을 설정하고 알람을 등록해두면, '
              '내 근무에 맞춰 정해진 시간에 시간에 자동으로 알람이 울려요.\n'
              '일정, 컨디션 관리, 친구 공유 등 다양한 기능도 구현되어 있습니다.\n\n'
              '많은 사용 부탁드립니다!',
          buttonLabel: '시작하기',
        );
}

class ShiftAssignTutorialContent extends _PopupContent {
  ShiftAssignTutorialContent()
      : super(
          emoji: '📅',
          title: '근무 배정, 이렇게 하면 돼요',
          body: '불규칙 근무는 정해진 패턴이 없어서, 날짜마다 직접 근무를 지정해줘야 해요.\n\n'
              '근무를 지정할 날짜를 길게 눌러 선택 모드로 들어간 뒤,'
              ' 원하는 날짜들을 이어서 탭하고 하단의 근무명을 탭하여 근무를 지정하세요.\n\n'
              '지정한 근무는 언제든 같은 방법으로 다시 바꿀 수 있어요.',
          buttonLabel: '확인했어요',
        );
}

// ⭐ 2026-09-06 - update_service.dart의 "새 버전이 있어요!" 다이얼로그
// (_showUpdateDialog)와 문구/버튼 구성을 그대로 옮긴 미리보기 전용 content.
// 실제 로직(Firestore 조회, 버전 비교, notifiedVersion 저장 등)은 여기서 전혀
// 안 건드림 - l10n 문구(app_ko.arb)만 그대로 가져와 카드로 보여줄 뿐.
class UpdateAvailableContent extends _PopupContent {
  UpdateAvailableContent()
      : super(
          emoji: '🎉',
          title: '새 버전이 있어요!',
          body: '더 나은 사용을 위해\n업데이트를 권장드려요.\n\n(저장된 정보는 그대로 유지됩니다)',
          buttonLabel: '업데이트',
          secondaryButtonLabel: '나중에',
        );
}

// ⭐ 2026-09-06 - update_service.dart의 "업데이트 후 첫 실행" 안내
// (_showReleaseNoteDialog)와 문구를 그대로 옮긴 미리보기 전용 content. 버전마다
// 바뀌는 문구(_releaseNoteVersion='1.0.19' 기준 현재 저장된 값)라 다음 버전엔
// 이 카드 문구도 같이 갱신해야 실제 화면과 계속 일치함.
class ReleaseNoteContent extends _PopupContent {
  ReleaseNoteContent()
      : super(
          emoji: '📢',
          title: '이번 업데이트는 꼭 확인해주세요',
          body: '사용자 편의 개선을 위해 달력 테마에서 지정한 근무명 색상 외에 기존의 근무명 색상 변경 기능 복원 - '
              '기본적으로 테마별 색상이 지정되고, 색상 변경시 변경된 색상으로 모든 테마에 고정됩니다. '
              '많은 사용 부탁드립니다 ^^',
          buttonLabel: '확인했어요',
        );
}

enum _PreviewKind { welcome, shiftAssignTutorial, updateAvailable, releaseNote }

/// lab 탭 전용 - 카드만 (다이얼로그 없이) 보여주고 싶을 때 씀. 팩토리로만
/// 만들 수 있게 해서(private 생성자) 실수로 다른 content 타입이 안 들어가게 함.
class OnboardingInfoPreviewCard extends StatelessWidget {
  const OnboardingInfoPreviewCard._(this._kind);
  final _PreviewKind _kind;

  const OnboardingInfoPreviewCard.welcome() : this._(_PreviewKind.welcome);
  const OnboardingInfoPreviewCard.shiftAssignTutorial() : this._(_PreviewKind.shiftAssignTutorial);
  const OnboardingInfoPreviewCard.updateAvailable() : this._(_PreviewKind.updateAvailable);
  const OnboardingInfoPreviewCard.releaseNote() : this._(_PreviewKind.releaseNote);

  @override
  Widget build(BuildContext context) {
    final _PopupContent content;
    switch (_kind) {
      case _PreviewKind.welcome:
        content = WelcomePopupContent();
      case _PreviewKind.shiftAssignTutorial:
        content = ShiftAssignTutorialContent();
      case _PreviewKind.updateAvailable:
        content = UpdateAvailableContent();
      case _PreviewKind.releaseNote:
        content = ReleaseNoteContent();
    }
    return _InfoPopupCard(
      content: content,
      onConfirm: () {},
      onSecondaryConfirm: () {},
    );
  }
}
