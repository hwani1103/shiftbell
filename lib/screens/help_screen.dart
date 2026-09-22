// lib/screens/help_screen.dart
//
// ⭐ 2026-09-03 - 설정 탭 "도움말"을 4항목짜리 AlertDialog에서 전면 재작성.
// 앱의 모든 주요 기능을 목차(섹션 → 항목)로 정리한 사용설명서 화면 - 전부
// 스크롤 한 화면에 나열하면 너무 길어지므로, 이 화면에서는 "목차"만 보여주고
// 항목을 탭하면 [HelpDetailScreen]으로 넘어가 그 항목 내용만 상세히 읽게 함.
// 검색으로 항목 제목을 바로 필터링할 수도 있음.
//
// 콘텐츠(제목/본문) 자체는 전부 l10n(app_ko.arb/app_en.arb의 help* 키)에 있고,
// 이 파일은 그 키들을 섹션/항목 구조로 묶어서 화면에 뿌리는 역할만 함 - 새
// 항목을 추가하려면 ARB에 title/body 키 한 쌍을 추가하고 [_helpSections]에
// [HelpTopic] 한 줄만 추가하면 됨.
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/app_colors.dart';

typedef HelpTextOf = String Function(AppLocalizations l10n);

class HelpTopic {
  final HelpTextOf titleKey;
  final HelpTextOf bodyKey;
  // 2026-09-22 - 한국어에서만 동작하는 기능(일정 아이콘 자동분류)의 항목은 영어에서 숨김.
  final bool koreanOnly;
  const HelpTopic({
    required this.titleKey,
    required this.bodyKey,
    this.koreanOnly = false,
  });
}

class HelpSection {
  final IconData icon;
  final HelpTextOf titleKey;
  final List<HelpTopic> topics;
  // ⭐ 2026-09-22(영어화 P0-2) - 수면·회복 탭 자체가 한국어 로케일에서만 존재해서
  // (main.dart _showConditionTab) 그 탭을 설명하는 "수면·회복"/"수면 기록" 두
  // 섹션도 영어에서는 통째로 숨김(build()의 isKorean 필터 참고) - 쓸 수도 없는
  // 기능의 도움말만 남아 있으면 혼란스러움.
  final bool koreanOnly;
  const HelpSection({
    required this.icon,
    required this.titleKey,
    required this.topics,
    this.koreanOnly = false,
  });
}

// ⭐ 순서 = 사용자가 앱을 처음 접했을 때 흐름(시작하기 → 근무 관리 → 알람 →
// 달력/위젯 → 일정관리 → 컨디션 → 수면 → 친구공유 → 백업 → 문제해결)을 그대로 따름.
final List<HelpSection> _helpSections = [
  HelpSection(
    icon: Icons.rocket_launch_outlined,
    titleKey: (l10n) => l10n.helpStartSectionTitle,
    topics: [
      HelpTopic(
        titleKey: (l10n) => l10n.helpStartOnboardingTitle,
        bodyKey: (l10n) => l10n.helpStartOnboardingBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpStartScheduleTypesTitle,
        bodyKey: (l10n) => l10n.helpStartScheduleTypesBody,
      ),
    ],
  ),
  HelpSection(
    icon: Icons.badge_outlined,
    titleKey: (l10n) => l10n.helpShiftSectionTitle,
    topics: [
      HelpTopic(
        titleKey: (l10n) => l10n.helpShiftIrregularAssignTitle,
        bodyKey: (l10n) => l10n.helpShiftIrregularAssignBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpShiftChangeShiftTitle,
        bodyKey: (l10n) => l10n.helpShiftChangeShiftBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpShiftShiftColorsTitle,
        bodyKey: (l10n) => l10n.helpShiftShiftColorsBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpShiftAllShiftsTitle,
        bodyKey: (l10n) => l10n.helpShiftAllShiftsBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpShiftTeamChangeTitle,
        bodyKey: (l10n) => l10n.helpShiftTeamChangeBody,
      ),
    ],
  ),
  HelpSection(
    icon: Icons.alarm_outlined,
    titleKey: (l10n) => l10n.helpAlarmSectionTitle,
    topics: [
      HelpTopic(
        titleKey: (l10n) => l10n.helpAlarmTemplatesTitle,
        bodyKey: (l10n) => l10n.helpAlarmTemplatesBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpAlarmSoundVolumeTitle,
        bodyKey: (l10n) => l10n.helpAlarmSoundVolumeBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpAlarmAlarmNotRingingTitle,
        bodyKey: (l10n) => l10n.helpAlarmAlarmNotRingingBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpAlarmAlarmHistoryTitle,
        bodyKey: (l10n) => l10n.helpAlarmAlarmHistoryBody,
      ),
      // ⭐ 2026-09-04 - 전체_코드_점검_리포트_2026-09-04.md의 H2(알람 갱신
      // 트랜잭션 중 OS 알람 호출) 항목은 코드 수정은 보류하기로 했지만, 사용자가
      // 알아두면 스스로 대처 가능한 내용이라 도움말에만 추가.
    ],
  ),
  HelpSection(
    icon: Icons.calendar_month_outlined,
    titleKey: (l10n) => l10n.helpCalendarSectionTitle,
    topics: [
      HelpTopic(
        titleKey: (l10n) => l10n.helpCalendarThemesTitle,
        bodyKey: (l10n) => l10n.helpCalendarThemesBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpCalendarOtTitle,
        bodyKey: (l10n) => l10n.helpCalendarOtBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpCalendarWorkHoursPayTitle,
        bodyKey: (l10n) => l10n.helpCalendarWorkHoursPayBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpCalendarHomeWidgetTitle,
        bodyKey: (l10n) => l10n.helpCalendarHomeWidgetBody,
      ),
    ],
  ),
  HelpSection(
    icon: Icons.checklist_outlined,
    titleKey: (l10n) => l10n.helpScheduleTabSectionTitle,
    topics: [
      HelpTopic(
        titleKey: (l10n) => l10n.helpScheduleTabWhatIsItTitle,
        bodyKey: (l10n) => l10n.helpScheduleTabWhatIsItBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpScheduleTabCreateEditTitle,
        bodyKey: (l10n) => l10n.helpScheduleTabCreateEditBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpScheduleTabAutoCategoryTitle,
        bodyKey: (l10n) => l10n.helpScheduleTabAutoCategoryBody,
        // 자동분류 모델이 한국어 전용 - 영어에서는 분류 없이 기본 도형 아이콘만 순서대로 붙음
        koreanOnly: true,
      ),
    ],
  ),
  HelpSection(
    icon: Icons.self_improvement_outlined,
    titleKey: (l10n) => l10n.helpConditionSectionTitle,
    koreanOnly: true,
    topics: [
      HelpTopic(
        titleKey: (l10n) => l10n.helpConditionWhatIsItTitle,
        bodyKey: (l10n) => l10n.helpConditionWhatIsItBody,
      ),
      // ⭐ 2026-09-04 v2 - 컨디션 판정 로직 개편(evidence 6종 판정 반영)에 맞춰
      // 근거자료 12개 전체를 도움말 한곳에서 볼 수 있게 신설(사용자 요청).
      HelpTopic(
        titleKey: (l10n) => l10n.helpConditionEvidenceListTitle,
        bodyKey: (l10n) => l10n.helpConditionEvidenceListBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpConditionSetupNeededTitle,
        bodyKey: (l10n) => l10n.helpConditionSetupNeededBody,
      ),
    ],
  ),
  HelpSection(
    icon: Icons.bedtime_outlined,
    titleKey: (l10n) => l10n.helpSleepSectionTitle,
    koreanOnly: true,
    topics: [
      HelpTopic(
        titleKey: (l10n) => l10n.helpSleepWidgetTitle,
        bodyKey: (l10n) => l10n.helpSleepWidgetBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpSleepAutoDetectTitle,
        bodyKey: (l10n) => l10n.helpSleepAutoDetectBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpSleepMiniCalendarTitle,
        bodyKey: (l10n) => l10n.helpSleepMiniCalendarBody,
      ),
    ],
  ),
  HelpSection(
    icon: Icons.group_outlined,
    titleKey: (l10n) => l10n.helpFriendSectionTitle,
    topics: [
      HelpTopic(
        titleKey: (l10n) => l10n.helpFriendWhatIsItTitle,
        bodyKey: (l10n) => l10n.helpFriendWhatIsItBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpFriendShareCodeTitle,
        bodyKey: (l10n) => l10n.helpFriendShareCodeBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpFriendViewFriendTitle,
        bodyKey: (l10n) => l10n.helpFriendViewFriendBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpFriendReinstallNoteTitle,
        bodyKey: (l10n) => l10n.helpFriendReinstallNoteBody,
      ),
    ],
  ),
  HelpSection(
    icon: Icons.backup_outlined,
    titleKey: (l10n) => l10n.helpBackupSectionTitle,
    topics: [
      HelpTopic(
        titleKey: (l10n) => l10n.helpBackupDataStorageTitle,
        bodyKey: (l10n) => l10n.helpBackupDataStorageBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpBackupAutoBackupTitle,
        bodyKey: (l10n) => l10n.helpBackupAutoBackupBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpBackupRestoreTitle,
        bodyKey: (l10n) => l10n.helpBackupRestoreBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpBackupRestoreManualTitle,
        bodyKey: (l10n) => l10n.helpBackupRestoreManualBody,
      ),
      // ⭐ 2026-09-04 - 전체_코드_점검_리포트_2026-09-04.md M10(복구 부분실패
      // 격리 없음) 항목은 코드 수정은 보류하기로 했지만, 예방 차원에서 사용자가
      // 알아두면 도움되는 내용이라 도움말에만 추가.
      HelpTopic(
        titleKey: (l10n) => l10n.helpBackupRestoreOldBackupFailTitle,
        bodyKey: (l10n) => l10n.helpBackupRestoreOldBackupFailBody,
      ),
    ],
  ),
  HelpSection(
    icon: Icons.help_outline,
    titleKey: (l10n) => l10n.helpTroubleshootSectionTitle,
    topics: [
      HelpTopic(
        titleKey: (l10n) => l10n.helpTroubleshootAlarmIssueTitle,
        bodyKey: (l10n) => l10n.helpTroubleshootAlarmIssueBody,
      ),
      // ⭐ 2026-09-13 - 강제 종료 시 알람이 취소되는 OS 동작 + 그 이후 "다시
      // 실행하기 전에 시각이 지난 알람은 복원 안 됨"이라는 타이밍 리스크를
      // 정확히 안내(실기기/에뮬레이터 양쪽에서 실측 확인된 내용 - 세션 기록
      // 참고). 코드 수정은 검토 후 보류함(AlarmRefreshUtil의 "오늘 이미
      // 갱신됨" 중복 방지 로직을 건드리는 변경이라, 과거 이 영역에서 반복됐던
      // 사고 이력을 고려해 위험도 대비 이득이 낮다고 판단) - 안내로 대체.
      HelpTopic(
        titleKey: (l10n) => l10n.helpTroubleshootForceStopTitle,
        bodyKey: (l10n) => l10n.helpTroubleshootForceStopBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpTroubleshootWidgetIssueTitle,
        bodyKey: (l10n) => l10n.helpTroubleshootWidgetIssueBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpTroubleshootBackupFileMissingTitle,
        bodyKey: (l10n) => l10n.helpTroubleshootBackupFileMissingBody,
      ),
      HelpTopic(
        titleKey: (l10n) => l10n.helpTroubleshootFriendDisconnectedTitle,
        bodyKey: (l10n) => l10n.helpTroubleshootFriendDisconnectedBody,
      ),
    ],
  ),
];

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _query.trim().toLowerCase();

    // ⭐ 2026-09-22(영어화 P0-2) - koreanOnly 섹션(수면·회복/수면 기록)은 한국어
    // 로케일이 아니면 목차 자체에서 뺌 - 그 탭이 영어에는 없으므로.
    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    final availableSections = isKorean
        ? _helpSections
        : _helpSections
            .where((s) => !s.koreanOnly)
            .map((s) => HelpSection(
                  icon: s.icon,
                  titleKey: s.titleKey,
                  topics: s.topics.where((t) => !t.koreanOnly).toList(),
                ))
            .toList();

    // 검색어가 있으면 섹션별로 제목이 매치하는 항목만 남기고, 매치가 하나도
    // 없는 섹션은 통째로 숨긴다.
    final visibleSections = query.isEmpty
        ? availableSections
        : availableSections
            .map((s) {
              final matched = s.topics
                  .where((t) => t.titleKey(l10n).toLowerCase().contains(query))
                  .toList();
              return HelpSection(icon: s.icon, titleKey: s.titleKey, topics: matched);
            })
            .where((s) => s.topics.isNotEmpty)
            .toList();

    return Scaffold(
      backgroundColor: kAppBackgroundPastel,
      appBar: AppBar(
        title: Text(l10n.settingsHelp),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: l10n.helpSearchHint,
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _query = '';
                          }),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16.w),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: visibleSections.isEmpty
                  ? Center(
                      child: Text(
                        l10n.helpEmptySearchResult,
                        style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(bottom: 24.h),
                      itemCount: visibleSections.length,
                      itemBuilder: (context, i) => _SectionBlock(section: visibleSections[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  final HelpSection section;
  const _SectionBlock({required this.section});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20.w, 20.h, 16.w, 8.h),
          child: Row(
            children: [
              Icon(section.icon, size: 18.sp, color: kAppMainAccent),
              SizedBox(width: 8.w),
              Text(
                section.titleKey(l10n),
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  color: kAppMainAccent,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Column(
            children: [
              for (var i = 0; i < section.topics.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 16.w, endIndent: 16.w, color: Colors.grey.shade200),
                _TopicTile(topic: section.topics[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TopicTile extends StatelessWidget {
  final HelpTopic topic;
  const _TopicTile({required this.topic});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => HelpDetailScreen(topic: topic)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
          children: [
            Expanded(
              child: Text(
                topic.titleKey(l10n),
                style: TextStyle(fontSize: 14.5.sp, color: Colors.black87, height: 1.3),
              ),
            ),
            SizedBox(width: 8.w),
            Icon(Icons.chevron_right, size: 20.sp, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

/// 항목 하나의 상세 내용만 보여주는 화면 - 목차 화면에서 항목을 탭하면 옴.
class HelpDetailScreen extends StatelessWidget {
  final HelpTopic topic;
  const HelpDetailScreen({super.key, required this.topic});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: kAppBackgroundPastel,
      appBar: AppBar(
        title: Text(
          topic.titleKey(l10n),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.w),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                topic.titleKey(l10n),
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: Colors.black87),
              ),
              SizedBox(height: 14.h),
              Text(
                topic.bodyKey(l10n),
                style: TextStyle(fontSize: 14.5.sp, color: Colors.black87, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
