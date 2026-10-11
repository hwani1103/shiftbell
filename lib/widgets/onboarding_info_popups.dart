// First-use guidance: irregular shift assignment, sleep/recovery and schedules.
// Each popup appears once, after the screen settles. Resetting a schedule does
// not reset these preferences. The onboarding welcome popup was removed on
// 2026-10-09; its old backup preference remains readable for compatibility.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_button.dart';
import 'soft_info_dialog.dart';
import 'word_safe_spans.dart';
import '../l10n/l10n_extensions.dart';

const _kShiftAssignTutorialShownKey = 'shift_assign_tutorial_shown';

const _kConditionTabTutorialShownKey = 'condition_tab_tutorial_shown';
// ⭐ 2026-09-13 추가(사용자 요청) - 일정관리 탭 최초 진입 안내(컨디션 탭과
// 동일한 디자인/원칙).
const _kScheduleTabTutorialShownKey = 'schedule_tab_tutorial_shown';

/// 화면이 자리를 잡은 뒤 팝업이 뜨기까지의 여유. 너무 짧으면 여전히 갑작스럽고, 1초를
/// 넘기면 "왜 안 뜨지?" 하고 다른 곳을 누르기 시작해서 그 사이 손이 팝업에 닿을 수 있다.
const Duration kInfoPopupDelay = Duration(milliseconds: 700);

/// 세 안내 팝업이 공통으로 쓰는 "평생 1회" 표시 절차.
///
/// ⚠️ 플래그(shownKey)는 **팝업을 실제로 띄우기 직전**에 세운다. 예전엔 맨 처음에 세웠는데,
/// 지연이 생기면 그 사이 사용자가 탭을 옮기거나(위젯이 dispose되어 context가 죽음) 다른 화면이
/// 위에 올라오는 경우 "본 적도 없는데 봤다고 기록"되어 영영 안 뜬다. 건너뛴 경우엔 플래그를
/// 그대로 두므로 다음에 그 화면에 들어올 때 다시 시도된다.
Future<void> _showInfoPopupOnce(
  BuildContext context, {
  required String shownKey,
  required _PopupContent Function(BuildContext) content,
  bool Function()? canShow,
  bool koreanOnly = false,
}) async {
  if (koreanOnly && !context.usesKoreanFeatures) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(shownKey) ?? false) return;

  await Future<void>.delayed(kInfoPopupDelay);

  if (!context.mounted) return; // 기다리는 사이 탭을 옮겨 화면이 사라짐
  if (koreanOnly && !context.usesKoreanFeatures) return;
  if (ModalRoute.of(context)?.isCurrent == false)
    return; // 다른 화면/대화상자가 이미 위에 있음

  if ((prefs.getBool(shownKey) ?? false) || canShow?.call() == false) return;
  await prefs.setBool(shownKey, true);
  if (!context.mounted) return;
  await showSoftInfoDialog(
    context: context,
    barrierDismissible: false,
    // ⭐ 2026-09-22(영어화) - content(dialogContext)로 바뀌어서 각 _PopupContent가
    // context.l10n으로 로케일에 맞는 문구를 직접 고름(아래 WelcomePopupContent 등 참고).
    builder: (dialogContext) => koreanOnly && !dialogContext.usesKoreanFeatures
        ? AlertDialog(actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(dialogContext.l10n.commonClose),
            )
          ])
        : Dialog(
            backgroundColor: Colors.transparent,
            child: _InfoPopupCard(
              content: content(dialogContext),
              onConfirm: () => Navigator.of(dialogContext).pop(),
            ),
          ),
  );
}

/// 달력 탭(calendar_tab.dart)이 스케줄 로드 후 부르는 함수 - 불규칙 스케줄이고
/// 아직 안 봤을 때만 뜸.
Future<void> maybeShowShiftAssignTutorial(BuildContext context,
    {required bool isRegular}) async {
  if (isRegular) return;
  await _showInfoPopupOnce(
    context,
    shownKey: _kShiftAssignTutorialShownKey,
    content: ShiftAssignTutorialContent.new,
  );
}

/// 컨디션 탭(condition_tab.dart) `_ConditionBodyState`가 최초 build 시 부르는
/// 함수 - 이미 봤으면 아무 것도 안 함. setupNeeded 여부와 무관하게 항상 뜸(설정이
/// 안 돼 있으면 그 자체가 이 안내의 1번 내용이므로).
Future<void> maybeShowConditionTabTutorial(BuildContext context,
        {bool Function()? canShow}) =>
    _showInfoPopupOnce(
      context,
      shownKey: _kConditionTabTutorialShownKey,
      canShow: canShow,
      koreanOnly: true,
      content: ConditionTabTutorialContent.new,
    );

/// 일정관리 탭(schedule_management_tab.dart)이 최초 build 시 부르는 함수 -
/// 이미 봤으면 아무 것도 안 함. 컨디션 탭의 maybeShowConditionTabTutorial과
/// 완전히 동일한 패턴(같은 카드/버튼 디자인, 평생 1회).
Future<void> maybeShowScheduleTabTutorial(BuildContext context,
        {bool Function()? canShow}) =>
    _showInfoPopupOnce(
      context,
      shownKey: _kScheduleTabTutorialShownKey,
      canShow: canShow,
      koreanOnly: true,
      content: ScheduleTabTutorialContent.new,
    );

/// 공용 카드 - 두 팝업이 항상 같은 크기/톤으로 보이게 함(제목 아이콘 + 제목 +
/// 본문 + 버튼 1개, 최소 높이를 통일해서 본문 길이가 달라도 비슷한 크기로 보임).
class _InfoPopupCard extends StatelessWidget {
  final _PopupContent content;
  final VoidCallback onConfirm;
  const _InfoPopupCard({required this.content, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    // ⭐ 2026-09-12(사용자 신고 - "컨디션 탭 최초진입 팝업, 스크롤이 없어서
    // 버튼이 팝업 밑으로 내려가버렸다") - 근본 원인 수정. 예전(2026-09-05)
    // 주석은 "실제 Dialog에서는 높이 제한이 되니 문제 없다"고 가정했는데,
    // 이 카드를 감싼 바깥 Dialog는 maxHeight를 안 정해주는 평범한 Dialog라
    // 본문이 화면보다 길어지면(컨디션탭 튜토리얼처럼 5단계짜리 긴 본문)
    // 그 가정이 깨짐 - SingleChildScrollView가 본문 Text 하나만 감싸고
    // 있었는데, 그 자체를 제한할 부모 높이가 없어서 스크롤이 전혀 동작 안
    // 하고 Column 전체가 화면 아래로 그냥 넘쳐버렸음(버튼이 화면 밖으로).
    // 고친 방법: 바깥 ConstrainedBox에 화면 기준 maxHeight를 주고, 스크롤
    // 대상을 본문 Text 하나가 아니라 "이모지+제목+본문" 전체로 넓힌 뒤
    // Flexible로 감싸서 - 화면이 부족하면 이 부분만 줄어들며 스크롤되고,
    // 버튼은 항상 그 아래 고정된 자리에서 보이게 함(AlertDialog의 content/
    // actions 분리와 같은 원리).
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return ConstrainedBox(
      constraints:
          BoxConstraints(minHeight: 320, maxWidth: 340, maxHeight: maxHeight),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 24,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(content.emoji, style: const TextStyle(fontSize: 40)),
                    const SizedBox(height: 14),
                    // ⭐ 2026-09-15 - 한국어가 "감사합\n니다"처럼 단어 중간에서 끊기지 않게 wordSafeSpans(명시 \n은 유지)
                    Text.rich(
                      TextSpan(
                        children: wordSafeSpans(
                          content.title,
                          const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text.rich(
                      TextSpan(
                        children: wordSafeSpans(
                          content.body,
                          TextStyle(
                              fontSize: 14.5,
                              height: 1.55,
                              color: Colors.black.withOpacity(0.75)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                  onPressed: onConfirm, child: Text(content.buttonLabel)),
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
  const _PopupContent({
    required this.emoji,
    required this.title,
    required this.body,
    required this.buttonLabel,
  });
}

class ShiftAssignTutorialContent extends _PopupContent {
  ShiftAssignTutorialContent(BuildContext context)
      : super(
          emoji: '📅',
          title: context.l10n.onboardingShiftAssignPopupTitle,
          body: context.l10n.onboardingShiftAssignPopupBody,
          buttonLabel: context.l10n.commonGotIt,
        );
}

// A short introduction; detailed controls are explained on the tab itself.
class ConditionTabTutorialContent extends _PopupContent {
  ConditionTabTutorialContent(BuildContext context)
      : super(
          emoji: '🌙',
          title: context.koOnly.onboardingConditionTabPopupTitle,
          body: context.koOnly.onboardingConditionTabPopupBody,
          buttonLabel: context.l10n.commonGotIt,
        );
}

// ⭐ 2026-09-13 추가(사용자 요청) - 일정관리 탭에 처음 들어왔을 때, 세로
// 시간축에서 일정을 만드는 방법과 지속시간/알림 옵션을 한 번에 설명하는 안내.
class ScheduleTabTutorialContent extends _PopupContent {
  ScheduleTabTutorialContent(BuildContext context)
      : super(
          emoji: '🗓️',
          title: context.koOnly.onboardingScheduleTabPopupTitle,
          body: context.koOnly.onboardingScheduleTabPopupBody,
          buttonLabel: context.l10n.commonGotIt,
        );
}
