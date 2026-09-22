// lib/widgets/onboarding_info_popups.dart
//
// ⭐ 최초 1회만 보여주는 안내 팝업 4종(2026-09-05 2종으로 시작, 이후 탭 안내 2종 추가):
// 1) 웰컴 팝업 - 온보딩 첫 화면 진입 시(앱을 실제로 처음 설치했을 때만).
// 2) 근무 배정 방법 팝업 - 불규칙 온보딩을 마치고 메인 달력에 처음 왔을 때만
//    (규칙적 스케줄이면 안 뜸 - 패턴이 자동으로 배정되니 이 안내가 불필요).
// 3) 수면·회복 탭 안내 - 그 탭에 처음 들어갔을 때.
// 4) 일정관리 탭 안내 - 그 탭에 처음 들어갔을 때.
//
// ⭐ 2026-09-22(사용자 요청) - 네 팝업 모두 "화면이 그려진 바로 그 프레임"에 모달이 덮여서
// 갑작스럽게 느껴졌다. 홈 화면은 IndexedStack이 아니라 현재 탭 하나만 트리에 올리는
// 구조라(main.dart), 탭 안내는 사용자가 그 탭에 처음 들어가 첫 프레임이 그려진 직후에
// 바로 떴다. [kInfoPopupDelay]만큼 기다렸다가 띄운다 - 공용 [_showInfoPopupOnce] 참고.
//
// 둘 다 SharedPreferences 플래그로 "평생 1회"만 관리함(달력 탭 재진입/재실행은
// 물론, 설정 → 초기화를 해도 다시 안 뜸 - 초기화 로직(schedule_provider.dart의
// resetSchedule)이 이 플래그들을 전혀 안 건드리므로 자연히 유지됨).
//
// 내용은 서로 완전히 다른 주제(웰컴 인사말 vs 근무 배정 조작법)라 별도
// 위젯이지만, "같은 크기·같은 톤의 카드"로 보이도록 [_InfoPopupCard] 하나를
// 공유해서 씀.
//
// ⭐ 2026-09-12 - 한때 있던 미리보기 전용 lab 탭("테스트알림",
// onboarding_popup_lab_screen.dart)은 배포 전 최종 점검 후 제거함 - 이 파일엔
// 그 흔적(미리보기 전용 클래스들)이 없고, 실제 팝업 로직만 남아있음.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_button.dart';
import 'word_safe_spans.dart';
import '../l10n/l10n_extensions.dart';

const _kWelcomePopupShownKey = 'welcome_popup_shown';
const _kShiftAssignTutorialShownKey = 'shift_assign_tutorial_shown';
// ⭐ 2026-09-11 추가(사용자 요청) - 컨디션 탭 최초 진입 안내.
const _kConditionTabTutorialShownKey = 'condition_tab_tutorial_shown';
// ⭐ 2026-09-13 추가(사용자 요청) - 일정관리 탭 최초 진입 안내(컨디션 탭과
// 동일한 디자인/원칙).
const _kScheduleTabTutorialShownKey = 'schedule_tab_tutorial_shown';

/// 화면이 자리를 잡은 뒤 팝업이 뜨기까지의 여유. 너무 짧으면 여전히 갑작스럽고, 1초를
/// 넘기면 "왜 안 뜨지?" 하고 다른 곳을 누르기 시작해서 그 사이 손이 팝업에 닿을 수 있다.
const Duration kInfoPopupDelay = Duration(milliseconds: 700);

/// 네 안내 팝업이 공통으로 쓰는 "평생 1회" 표시 절차.
///
/// ⚠️ 플래그(shownKey)는 **팝업을 실제로 띄우기 직전**에 세운다. 예전엔 맨 처음에 세웠는데,
/// 지연이 생기면 그 사이 사용자가 탭을 옮기거나(위젯이 dispose되어 context가 죽음) 다른 화면이
/// 위에 올라오는 경우 "본 적도 없는데 봤다고 기록"되어 영영 안 뜬다. 건너뛴 경우엔 플래그를
/// 그대로 두므로 다음에 그 화면에 들어올 때 다시 시도된다.
Future<void> _showInfoPopupOnce(
  BuildContext context, {
  required String shownKey,
  required _PopupContent Function(BuildContext) content,
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(shownKey) ?? false) return;

  await Future<void>.delayed(kInfoPopupDelay);

  if (!context.mounted) return; // 기다리는 사이 탭을 옮겨 화면이 사라짐
  if (ModalRoute.of(context)?.isCurrent == false) return; // 다른 화면/대화상자가 이미 위에 있음

  await prefs.setBool(shownKey, true);
  if (!context.mounted) return;
  await showDialog(
    context: context,
    barrierDismissible: false,
    // ⭐ 2026-09-22(영어화) - content(dialogContext)로 바뀌어서 각 _PopupContent가
    // context.l10n으로 로케일에 맞는 문구를 직접 고름(아래 WelcomePopupContent 등 참고).
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      child: _InfoPopupCard(
        content: content(dialogContext),
        onConfirm: () => Navigator.of(dialogContext).pop(),
      ),
    ),
  );
}

/// 온보딩 첫 화면(_OnboardingScreenState)이 initState에서 부르는 함수 - 이미
/// 봤으면 아무 것도 안 함.
Future<void> maybeShowWelcomePopup(BuildContext context) => _showInfoPopupOnce(
      context,
      shownKey: _kWelcomePopupShownKey,
      content: WelcomePopupContent.new,
    );

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
Future<void> maybeShowConditionTabTutorial(BuildContext context) => _showInfoPopupOnce(
      context,
      shownKey: _kConditionTabTutorialShownKey,
      content: ConditionTabTutorialContent.new,
    );

/// 일정관리 탭(schedule_management_tab.dart)이 최초 build 시 부르는 함수 -
/// 이미 봤으면 아무 것도 안 함. 컨디션 탭의 maybeShowConditionTabTutorial과
/// 완전히 동일한 패턴(같은 카드/버튼 디자인, 평생 1회).
Future<void> maybeShowScheduleTabTutorial(BuildContext context) => _showInfoPopupOnce(
      context,
      shownKey: _kScheduleTabTutorialShownKey,
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

/// ⭐ 실제 다이얼로그 안(_InfoPopupCard)에서도 쓰고, lab 탭에서 "다이얼로그를
/// 안 띄우고 카드만" 미리보기할 때도 재사용하려고 StatelessWidget이 아니라
/// 데이터 객체 형태로 뺌 - WelcomePopupContent()/ShiftAssignTutorialContent()는
/// 그 데이터를 담은 값일 뿐, 자기 자신을 그리지 않음(_InfoPopupCard가 그림).
// ⭐ 2026-09-22(영어화) - 웰컴/근무배정/일정관리 탭 안내는 로케일과 무관하게 모든
// 사용자가 보는 팝업이라 l10n(app_ko.arb/app_en.arb의 onboarding*Popup* 키)으로
// 옮김. 컨디션 탭 안내(ConditionTabTutorialContent, 아래)만 그 탭 자체가 한국어
// 로케일에서만 존재해서(main.dart _showConditionTab) 그대로 한국어 하드코딩.
class WelcomePopupContent extends _PopupContent {
  WelcomePopupContent(BuildContext context)
      : super(
          emoji: '👋',
          title: context.l10n.onboardingWelcomePopupTitle,
          body: context.l10n.onboardingWelcomePopupBody,
          buttonLabel: context.l10n.onboardingWelcomePopupStartButton,
        );
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

// ⭐ 2026-09-11 추가(사용자 요청) - 컨디션 탭에 처음 들어왔을 때, "설정부터
// 해야 아무것도 안 보인다"는 진입장벽과 "수면 기록이 대체 어떻게 쌓이는
// 건지"를 한 번에 설명하는 안내. 근무시간 설정/수면 위젯 추가/자동·수동 기록
// 여러 가지를 다 다루다 보니 다른 팝업보다 본문이 길다 - _InfoPopupCard의
// SingleChildScrollView가 이미 넘치는 내용을 스크롤로 받아주므로 그대로 재사용.
// ⭐ 2026-09-18 - 컨디션 판정 로직 v3(개인 기준선) 재설계 + 근무별 평균 수면(P2#6)
// + 자동 기록 일괄 확인(P2#7) 반영해서 전면 갱신. "확인된 사실" 섹션 라벨이
// condition_tab.dart에서 "최근 근무·수면"으로 바뀐 것도 같이 맞춤(같은 화면인데
// 팝업 문구만 옛 이름으로 남아있으면 안 됨). 예전 본문의 "3."이 두 번 나오던
// 오타도 이번에 같이 정리함.
class ConditionTabTutorialContent extends _PopupContent {
  // ⭐ 이 탭 자체가 한국어 로케일에서만 존재해서(main.dart _showConditionTab) 이
  // 팝업도 항상 한국어 하드코딩 - context는 다른 세 팝업과 타입을 맞추기 위한
  // 파라미터일 뿐 안 씀(CLAUDE.md "수면·회복 탭" 문구는 l10n 미적용 방침과 일치).
  ConditionTabTutorialContent(BuildContext context)
      : super(
          emoji: '🌙',
          title: '수면·회복 탭, 이렇게 써보세요',
          body: '1. 근무시간 설정\n'
              '설정 → 근무시간 및 OT 설정에서, 사용 중인 근무명 중 하나 이상의 '
              '출퇴근 시각을 입력하면 "오늘의 컨디션"이 나와요. 수면 기록은 입력 전에도 남길 수 있어요.\n\n'
              '2. 오늘의 컨디션\n'
              '지금 시각을 기준으로 근무 사이 회복시간·퇴근 후 실제 수면 같은 "최근 근무·수면" 정보와, '
              '몇 시까지 잠자리에 들기·카페인 끊을 시각 같은 "추천 행동"을 보여드려요. 평소 근무량보다 '
              '이번 주가 유독 많을 때만 알려드리고, 기록이 부족하면 상태를 나쁘게 보지 않고 "판단 범위"에 적어둬요.\n\n'
              '3. 근무별 수면 패턴\n'
              '야간, 주간, 휴무일처럼 근무 유형별 평균 수면을 주 수면과 낮잠으로 나눠 보여줘요. '
              '유형마다 3일이 쌓이면 평균이 나오고, 그 전에는 준비 상황이 표시돼요.\n\n'
              '4. 수면 위젯\n'
              '홈 화면을 길게 눌러 위젯 추가 화면에서 "교대시계 수면" 위젯을 올려 두면, 앱을 열지 않고도 '
              '자기 전에 "수면", 일어난 뒤에 "기상" 버튼으로 바로 기록할 수 있어요.\n\n'
              '5. 자동 기록\n'
              '위젯을 안 눌러도, 정해진 수면 시간대에 폰을 오래 안 만지면 앱이 수면으로 추정해 기록해요. '
              '야간 출근 전에 잔 낮잠도 찾아요. 추정이라 틀릴 수 있어서 탭 위쪽에 확인 카드가 떠요. '
              '맞으면 "맞아요", 아니면 "기록하지 않기"를 눌러 주세요(거부한 시간대는 다음부터 덜 잡혀요). '
              '카드가 여러 개 쌓이면 "보이는 기록 모두 확인"으로 한 번에 처리할 수도 있어요.\n\n'
              '6. 수동 입력/수정\n'
              '아래 "최근 수면 기록" 달력의 빈 칸을 탭하면 직접 기록을 추가하거나, '
              '이미 있는 기록을 눌러 시각을 고치거나 지울 수 있어요.',
          buttonLabel: '확인했어요',
        );
}

// ⭐ 2026-09-13 추가(사용자 요청) - 일정관리 탭에 처음 들어왔을 때, 세로
// 시간축에서 일정을 만드는 방법과 지속시간/알림 옵션을 한 번에 설명하는 안내.
class ScheduleTabTutorialContent extends _PopupContent {
  ScheduleTabTutorialContent(BuildContext context)
      : super(
          emoji: '🗓️',
          title: context.l10n.onboardingScheduleTabPopupTitle,
          body: context.l10n.onboardingScheduleTabPopupBody,
          buttonLabel: context.l10n.commonGotIt,
        );
}

// ⭐ 2026-09-12 - 이 밑에 있던 미리보기 전용 코드(UpdateAvailableContent/
// ReleaseNoteContent/ForceUpdateContent/OnboardingInfoPreviewCard/_PreviewKind)는
// "테스트알림" 임시 lab 탭(onboarding_popup_lab_screen.dart) 전용이었음 - 그
// 탭을 배포 전 최종 점검 후 완전히 제거하면서 같이 정리함. 실제 팝업에 쓰이는
// WelcomePopupContent/ShiftAssignTutorialContent/ConditionTabTutorialContent와
// 그걸 띄우는 maybeShow* 함수들은 이 파일 위쪽에 그대로 남아있음(영향 없음).
