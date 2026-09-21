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
// 공유해서 씀.
//
// ⭐ 2026-09-12 - 한때 있던 미리보기 전용 lab 탭("테스트알림",
// onboarding_popup_lab_screen.dart)은 배포 전 최종 점검 후 제거함 - 이 파일엔
// 그 흔적(미리보기 전용 클래스들)이 없고, 실제 팝업 로직만 남아있음.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_button.dart';
import 'word_safe_spans.dart';

const _kWelcomePopupShownKey = 'welcome_popup_shown';
const _kShiftAssignTutorialShownKey = 'shift_assign_tutorial_shown';
// ⭐ 2026-09-11 추가(사용자 요청) - 컨디션 탭 최초 진입 안내.
const _kConditionTabTutorialShownKey = 'condition_tab_tutorial_shown';
// ⭐ 2026-09-13 추가(사용자 요청) - 일정관리 탭 최초 진입 안내(컨디션 탭과
// 동일한 디자인/원칙).
const _kScheduleTabTutorialShownKey = 'schedule_tab_tutorial_shown';

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
Future<void> maybeShowShiftAssignTutorial(BuildContext context,
    {required bool isRegular}) async {
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

/// 컨디션 탭(condition_tab.dart) `_ConditionBodyState`가 최초 build 시 부르는
/// 함수 - 이미 봤으면 아무 것도 안 함. setupNeeded 여부와 무관하게 항상 뜸(설정이
/// 안 돼 있으면 그 자체가 이 안내의 1번 내용이므로).
Future<void> maybeShowConditionTabTutorial(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kConditionTabTutorialShownKey) ?? false) return;
  await prefs.setBool(_kConditionTabTutorialShownKey, true);
  if (!context.mounted) return;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: _InfoPopupCard(
        content: ConditionTabTutorialContent(),
        onConfirm: () => Navigator.of(context).pop(),
      ),
    ),
  );
}

/// 일정관리 탭(schedule_management_tab.dart)이 최초 build 시 부르는 함수 -
/// 이미 봤으면 아무 것도 안 함. 컨디션 탭의 maybeShowConditionTabTutorial과
/// 완전히 동일한 패턴(같은 카드/버튼 디자인, 평생 1회).
Future<void> maybeShowScheduleTabTutorial(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kScheduleTabTutorialShownKey) ?? false) return;
  await prefs.setBool(_kScheduleTabTutorialShownKey, true);
  if (!context.mounted) return;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: _InfoPopupCard(
        content: ScheduleTabTutorialContent(),
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
class WelcomePopupContent extends _PopupContent {
  WelcomePopupContent()
      : super(
          emoji: '👋',
          title: '교대시계를 설치해 주셔서\n감사합니다',
          // ⭐ 2026-09-15 (사용자 요청) - 너무 간소화됐다는 피드백으로 기능 소개를 되살림. 문장 중간에 \n을 넣으면
          // 화면 폭에 따라 어색하게 끊겨서 문단 사이에만 줄바꿈하고, 줄바꿈은 _InfoPopupCard의 wordSafeSpans에 맡김.
          body: '처음 한 번만 근무표와 알람을 등록해 두면, '
              '내 근무에 맞춰 정해진 시간에 알람이 자동으로 울려요.\n\n'
              '📅  달력에서 날짜별 근무 한눈에 보기\n'
              '🗓️  일정 관리와 일정 알림\n'
              '🌙  수면·회복 관리\n'
              '👥  친구와 근무표 공유',
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
  ConditionTabTutorialContent()
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
              '3. 근무별 평균 수면\n'
              '야간 후/주간 후/휴무일처럼 근무 종류별로 평균 수면시간을 따로 모아 보여드려요 '
              '(그 종류로 기록이 3일 이상 쌓여야 나와요).\n\n'
              '4. 수면 위젯\n'
              '홈 화면을 길게 눌러 위젯 추가 화면에서 "교대시계 수면" 위젯을 올려두면, 앱을 열지 않고도 '
              '취침 전 "🌙 수면", 기상 후 "☀️ 기상" 버튼으로 바로 기록할 수 있어요.\n\n'
              '5. 자동 기록\n'
              '위젯을 안 눌러도, 정해진 수면 시간대에 폰을 오래 안 만지면 자동으로 '
              '추정해서 기록해요. 다만 추정이라 확실하지 않을 수 있어 확인이 필요하면 '
              '탭 상단에 확인 카드가 떠요 - 맞으면 "맞아요", 아니면 "기록하지 않기"를 '
              '눌러주세요(거부한 시간대는 다음부터는 자동으로 덜 잡히도록 학습돼요). 카드가 여러 개 쌓이면 '
              '"보이는 기록 모두 확인" 버튼으로 한 번에 처리할 수도 있어요.\n\n'
              '6. 수동 입력/수정\n'
              '아래 "최근 수면 기록" 달력의 빈 칸을 탭하면 직접 기록을 추가하거나, '
              '이미 있는 기록을 눌러 시각을 고치거나 지울 수 있어요.',
          buttonLabel: '확인했어요',
        );
}

// ⭐ 2026-09-13 추가(사용자 요청) - 일정관리 탭에 처음 들어왔을 때, 세로
// 시간축에서 일정을 만드는 방법과 지속시간/알림 옵션을 한 번에 설명하는 안내.
class ScheduleTabTutorialContent extends _PopupContent {
  ScheduleTabTutorialContent()
      : super(
          emoji: '🗓️',
          title: '일정관리 탭, 이렇게 써보세요',
          body: '1. 일정 만들기\n'
              '오른쪽 아래 시계 아이콘을 탭하면 시간축 위에서 시각을 고를 수 있는 '
              '모드로 바뀌어요. 원하는 시각에서 한 번 더 탭하면 그 시각으로 새 '
              '일정을 만들 수 있어요.\n\n'
              '2. 지속시간 설정\n'
              '기본은 "지속시간 없음"(특정 시각 하나)이에요. "+"나 5분/30분/1시간 '
              '버튼을 누르면 종료 시각이 있는 일정으로 바뀌어요.\n\n'
              '3. 일정에 맞춰 알림받기\n'
              '스위치를 켜면 정시 또는 5/10/30분 전에 가벼운 알림 1건을 받을 수 '
              '있어요. 기존 "알람"(잠금화면/벨소리)과는 별개로, 시스템 알림 '
              '설정을 그대로 따르는 알림이에요.\n\n'
              '4. 지난 시각 표시\n'
              '이미 지난 시각에 만든 일정은 느낌표(⚠) 아이콘으로 구분해서 '
              '보여드려요.',
          buttonLabel: '확인했어요',
        );
}

// ⭐ 2026-09-12 - 이 밑에 있던 미리보기 전용 코드(UpdateAvailableContent/
// ReleaseNoteContent/ForceUpdateContent/OnboardingInfoPreviewCard/_PreviewKind)는
// "테스트알림" 임시 lab 탭(onboarding_popup_lab_screen.dart) 전용이었음 - 그
// 탭을 배포 전 최종 점검 후 완전히 제거하면서 같이 정리함. 실제 팝업에 쓰이는
// WelcomePopupContent/ShiftAssignTutorialContent/ConditionTabTutorialContent와
// 그걸 띄우는 maybeShow* 함수들은 이 파일 위쪽에 그대로 남아있음(영향 없음).
