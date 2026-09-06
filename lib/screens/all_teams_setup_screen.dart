// lib/screens/all_teams_setup_screen.dart
//
// ⭐ 2026-09-05 - 전체 교대조 근무표 설정/편집 화면. 예전 `AllTeamsSetupDialog`
// (all_teams_setup_dialog.dart, 삭제됨)의 3페이지 마법사를 없애고 한 화면으로
// 합침(왜 합쳤는지는 아래 2차 재설계 이력 참고).
//
// ⭐ 2026-09-05 (2차 재설계, 사용자 피드백 반영) - 초판("내 조 이름 입력 + 다른
// 조 칩 추가/삭제 + 칩마다 오늘 근무 인라인 그리드")이 "간소화된 듯하면서도
// 별로"라는 피드백을 받아 아래 5단계 흐름으로 다시 설계함(한 화면 안에서
// 위→아래로 이어지는 섹션일 뿐, 페이지 넘김은 여전히 없음):
//   1. 조 이름(로스터) - 가장 흔한 A/B/C/D를 기본값으로 미리 채워두고 표시만
//      함. "편집" 버튼을 누르면 그제서야 각 이름을 고치거나(텍스트필드로 바로
//      수정) 조를 추가/삭제할 수 있음.
//   2. 내 조 - 로스터 중 하나를 "고르기만" 함(단일 선택).
//   3. 다른 조 - 로스터에서 내 조를 뺀 나머지 중, 실제로 이 근무표에 쓸 조를
//      "고르기만" 함(다중 토글) - 로스터가 4개(A~D)여도 3조만 쓰는 곳이면
//      D를 안 고르면 됨(로스터 자체를 지울 필요 없음).
//   4. 근무 배정 - 내 근무 패턴을 그대로 펼쳐두고(각 자리가 며칠째 무슨
//      근무인지 다 보임), 2·3단계에서 고른 조들을 그 자리에 배정함. 내 조는
//      schedule.todayIndex 기반으로 자동 배정되어 잠김(다시 안 물어봄) - 다른
//      조만 탭-탭으로 배정(조 칩을 먼저 탭해 "집어들고" → 빈 자리를 탭해
//      놓음). 중복 배정(한 조가 두 자리, 한 자리에 두 조) 불가능하게 설계.
//   5. 저장 시 위 배정을 기존과 동일한 오프셋 계산식으로 변환해 SharedPreferences에
//      기록 - all_shifts_view.dart가 매번 이 값으로 전체근무표를 그림.
//
// 로스터 항목은 문자열이 아니라 `_RosterEntry`(TextEditingController 보유)로
// 관리함 - 내 조/다른 조 선택/배정을 전부 이 객체 자체(식별자)로 추적해서,
// 편집 중 이름을 바꿔도 그 아래 선택·배정이 끊기지 않고 그대로 따라감(문자열
// 키였다면 이름이 바뀔 때마다 선택 상태를 일일이 옮겨줘야 했음).
//
// ⭐ 2026-09-05(3차, 사용자 피드백) - "조 이름 편집은 팝업에서, 메인 취소/저장
// 버튼이 안 보이는 곳에서 하자"는 요청으로 로스터 편집만 모달 바텀시트
// (_RosterEditorSheet)로 뺌 - 2차에서 "인라인 편집만 쓴다"고 했던 원칙에서
// 이 한 곳만 예외. 다만 이전에 겪은 `_dependents.isEmpty` 버그(탭 한 번이
// 그리드 위치 배정 + 메인 화면 저장까지 같은 프레임에 겹치며 생긴 경합)와는
// 발생 조건 자체가 다름 - 여기는 이 시트 하나만 독립적으로 열고 닫힐 뿐,
// 닫히는 동작이 곧바로 메인 화면의 또 다른 pop(저장 등)과 겹치지 않음.
// 2·3·4단계(내 조/다른 조 선택, 근무 배정)는 여전히 라우트 전환 없는 인라인
// UI 그대로 - 원래 버그가 실제로 나던 지점(배정 그리드+저장)은 그대로 안전함.
//
// ⭐ 취소/저장 버튼은 AppButton(메인 그라데이션 버튼)이 아니라 취소와 같은
// AppSecondButton 모양에 색만 다르게(variant: primary) - schedule_management_tab.dart의
// 일정생성 시트가 이미 "생성 버튼도 AppButton 말고 AppSecondButton(primary)"로
// 확정해둔 것과 동일한 원칙(요청: "메인버튼 저거 말고").

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shift_schedule.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shift_chip.dart';
import '../widgets/app_second_button.dart';

/// 로스터(1단계 "조 이름") 항목 하나 - 위 클래스 docstring 참고.
class _RosterEntry {
  final TextEditingController controller;
  _RosterEntry(String name) : controller = TextEditingController(text: name);
  String get name => controller.text.trim().toUpperCase();
  void dispose() => controller.dispose();
}

class AllTeamsSetupScreen extends StatefulWidget {
  final List<String> pattern;
  // ⭐ 2026-09-05 - 이름을 todayIndex → myTodayIndex로 명확화(버그 수정 겸함).
  // 호출부(all_shifts_view.dart)가 schedule.startDate 기준 경과일을 반영해
  // "진짜 오늘"의 패턴 인덱스로 미리 보정해서 넘겨준다는 걸 이름으로 드러냄 -
  // schedule.todayIndex를 여기서 직접 쓰면 안 됨(그건 startDate 시점의
  // 인덱스일 뿐이라 시간이 지날수록 오늘과 어긋남).
  final int myTodayIndex;

  // ⭐ 편집 진입 시 프리필용(신규 작성이면 전부 기본값으로 옴).
  final List<String> existingTeamNames;
  final Map<String, int> existingTeamOffsets;
  final String existingMyTeam;

  const AllTeamsSetupScreen({
    super.key,
    required this.pattern,
    required this.myTodayIndex,
    this.existingTeamNames = const [],
    this.existingTeamOffsets = const {},
    this.existingMyTeam = '',
  });

  @override
  State<AllTeamsSetupScreen> createState() => _AllTeamsSetupScreenState();
}

class _AllTeamsSetupScreenState extends State<AllTeamsSetupScreen> {
  // ⭐ 이전 버전과 동일한 고정 기준일 - 오프셋 저장 포맷을 그대로 유지해야
  // 기존 데이터/다른 코드와 호환됨.
  static final DateTime _baseDate = DateTime(2024, 1, 1);
  late final int _daysFromBase;

  // 1단계: 조 이름(로스터)
  late List<_RosterEntry> _rosterEntries;

  // 2단계: 내 조(단일 선택)
  _RosterEntry? _myTeamEntry;

  // 3단계: 다른 조(다중 토글, 로스터에서 내 조를 뺀 나머지 중)
  final Set<_RosterEntry> _selectedOtherEntries = {};

  // 4단계: 근무 배정(조 → 패턴 슬롯 0-based index)
  final Map<_RosterEntry, int> _assignments = {};
  _RosterEntry? _pickedEntry; // 지금 "집어든" 조(탭-탭 배치용)

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _daysFromBase = julianDayNumber(today.year, today.month, today.day) -
        julianDayNumber(_baseDate.year, _baseDate.month, _baseDate.day);

    // ⭐ 가장 흔한 A/B/C/D를 기본 제공(요청) - 기존 값이 있으면(편집 진입)
    // 그걸 그대로 씀.
    final names = widget.existingTeamNames.isNotEmpty
        ? widget.existingTeamNames
        : const ['A', 'B', 'C', 'D'];
    _rosterEntries = names.map((n) => _RosterEntry(n)).toList();

    if (widget.existingMyTeam.isNotEmpty) {
      for (final e in _rosterEntries) {
        if (e.name == widget.existingMyTeam) {
          _myTeamEntry = e;
          break;
        }
      }
    }

    for (final e in _rosterEntries) {
      if (identical(e, _myTeamEntry)) continue;
      final offset = widget.existingTeamOffsets[e.name];
      if (offset == null) continue;
      _selectedOtherEntries.add(e);
      if (widget.pattern.isEmpty) continue;
      final len = widget.pattern.length;
      final pos = ((offset + _daysFromBase) % len + len) % len;
      _assignments[e] = pos;
    }
    if (_myTeamEntry != null) {
      _assignments[_myTeamEntry!] = widget.myTodayIndex;
    }
  }

  @override
  void dispose() {
    for (final e in _rosterEntries) {
      e.dispose();
    }
    super.dispose();
  }

  int _offsetFor(int selectedIndex) {
    final len = widget.pattern.length;
    return ((selectedIndex - 1 - _daysFromBase) % len + len) % len;
  }

  _RosterEntry? _entryAtSlot(int index) {
    for (final e in _assignments.entries) {
      if (e.value == index) return e.key;
    }
    return null;
  }

  bool get _canSave {
    if (_myTeamEntry == null) return false;
    if (_selectedOtherEntries.isEmpty) return false;
    return _selectedOtherEntries.every((e) => _assignments.containsKey(e));
  }

  // ───────────────────────── 1단계: 로스터 편집 ─────────────────────────
  // ⭐ 2026-09-05(3차) - "편집은 팝업에서, 메인 취소/저장 버튼이 안 보이는
  // 곳에서" 요청으로 이 화면 안 인라인 편집 대신 모달 바텀시트(_RosterEditorSheet)로
  // 뺌. 시트가 로스터를 직접(참조 공유) 편집하고, 삭제 시의 뒷정리(내 조/다른
  // 조 선택·배정 해제)만 이 콜백으로 위임함 - 시트는 자기 화면 갱신만 책임지고,
  // 이 화면의 나머지 상태(2~4단계)는 시트가 닫힌 뒤 한 번에 반영됨.
  Future<void> _openRosterEditor() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (_) => _RosterEditorSheet(
        entries: _rosterEntries,
        onRemoveCascade: _cascadeCleanupAfterRosterRemoval,
      ),
    );
    if (!mounted) return;
    setState(() {}); // 시트에서 바뀐 이름/추가/삭제를 이 화면에 반영
  }

  void _cascadeCleanupAfterRosterRemoval(_RosterEntry entry) {
    if (identical(_myTeamEntry, entry)) _myTeamEntry = null;
    _selectedOtherEntries.remove(entry);
    _assignments.remove(entry);
    if (identical(_pickedEntry, entry)) _pickedEntry = null;
  }

  // ───────────────────────── 2단계: 내 조 선택 ─────────────────────────

  void _selectMyTeam(_RosterEntry entry) {
    if (identical(_myTeamEntry, entry)) return;
    setState(() {
      // ⭐ 이전 내 조는 자동 배정을 잃음 - 계속 근무표에 쓰려면 3단계에서
      // "다른 조"로 다시 골라야 함(자동 승격하지 않음 - 단순함 우선).
      if (_myTeamEntry != null) _assignments.remove(_myTeamEntry);
      _myTeamEntry = entry;
      _selectedOtherEntries.remove(entry);
      _assignments.remove(entry); // 혹시 다른 조로 이미 배정돼 있었다면 해제
      _assignments[entry] = widget.myTodayIndex;
      if (identical(_pickedEntry, entry)) _pickedEntry = null;
    });
  }

  // ───────────────────────── 3단계: 다른 조 선택 ─────────────────────────

  void _toggleOtherTeam(_RosterEntry entry) {
    setState(() {
      if (_selectedOtherEntries.contains(entry)) {
        _selectedOtherEntries.remove(entry);
        _assignments.remove(entry);
        if (identical(_pickedEntry, entry)) _pickedEntry = null;
      } else {
        _selectedOtherEntries.add(entry);
      }
    });
  }

  // ───────────────────────── 4단계: 근무 배정(탭-탭) ─────────────────────────

  void _pickForAssignment(_RosterEntry entry) {
    setState(() => _pickedEntry = identical(_pickedEntry, entry) ? null : entry);
  }

  void _tapSlot(int index) {
    final occupant = _entryAtSlot(index);
    if (occupant != null) {
      if (identical(occupant, _myTeamEntry)) return; // 잠김 - 내 조는 안 건드림
      setState(() => _assignments.remove(occupant));
      return;
    }
    if (_pickedEntry == null) return;
    setState(() {
      _assignments[_pickedEntry!] = index;
      _pickedEntry = null;
    });
  }

  Future<void> _save() async {
    // ⭐ 2026-09-05(3차) - 버그 수정. _selectedOtherEntries는 Set이라 사용자가
    // 3단계에서 탭한 순서 그대로 저장돼서(예: B→D→A 순으로 탭하면 그 순서로
    // 저장됨), 실제 전체근무표 표에 "C A B D"처럼 로스터 순서와 무관하게
    // 뒤섞여 나오는 원인이었음. 저장 순서는 항상 로스터(1단계) 순서를 그대로
    // 따라야 하므로, Set을 그대로 쓰지 않고 _rosterEntries를 훑으며 "포함되는
    // 것만" 순서대로 골라냄 - 결과가 항상 로스터 순서(예: A B C D)로 고정됨.
    final included = _rosterEntries
        .where((e) => identical(e, _myTeamEntry) || _selectedOtherEntries.contains(e))
        .toList();
    final teamNames = included.map((e) => e.name).toList();
    final offsets = <String, String>{
      for (final e in included)
        e.name: _offsetFor(
                (identical(e, _myTeamEntry) ? widget.myTodayIndex : _assignments[e]!) + 1)
            .toString(),
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('all_teams_names', teamNames);
    await prefs.setString('all_teams_my_team', _myTeamEntry!.name);
    await prefs.setString('all_teams_offsets', jsonEncode(offsets));

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Widget _sectionLabel(String text, {required Color color}) => Text(
        text,
        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: color),
      );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // ⭐ 2026-09-05(3차) - 여기도 저장 로직과 같은 이유로 Set 순서 대신 로스터
    // 순서를 따름(트레이 칩이 탭한 순서대로 뒤섞여 보이지 않게).
    final unassignedOtherEntries = _rosterEntries
        .where((e) => _selectedOtherEntries.contains(e) && !_assignments.containsKey(e))
        .toList();

    return Scaffold(
      backgroundColor: kAppBackgroundPastel,
      appBar: AppBar(
        title: Text(context.l10n.statusFullTeamScheduleTitle),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 1단계: 조 이름 ──
                    Row(
                      children: [
                        Expanded(
                          child: _sectionLabel(context.l10n.allTeamsSetupRosterLabel, color: kAppMainAccent),
                        ),
                        // ⭐ 2026-09-05(3차) - 눈에 잘 띄게 제대로 된 버튼으로
                        // (요청: "초록색이나 뭐 좀 눈에 보이게"). 초록(success)은
                        // 이 앱에서 "저장/확인처럼 긍정적으로 완료하는 액션"
                        // 톤으로 이미 쓰이고 있어서(app_second_button.dart) 그대로
                        // 재사용 - 조 이름을 확정 짓는 이 버튼과 잘 맞음.
                        AppSecondButton(
                          variant: AppSecondButtonVariant.success,
                          compact: true,
                          onPressed: _openRosterEditor,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_outlined, size: 14.sp),
                              SizedBox(width: 4.w),
                              Text(context.l10n.commonEdit),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Text(context.l10n.allTeamsSetupRosterHint,
                        style: TextStyle(fontSize: 12.5.sp, color: colorScheme.onSurfaceVariant)),
                    SizedBox(height: 10.h),
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: [for (final e in _rosterEntries) AppShiftChip(label: e.name)],
                    ),

                    // ── 2단계: 내 조 ──
                    SizedBox(height: 28.h),
                    _sectionLabel(context.l10n.allTeamsSetupMyTeamLabel, color: kAppMainAccent),
                    SizedBox(height: 4.h),
                    Text(context.l10n.allTeamsSetupMyTeamPickHint,
                        style: TextStyle(fontSize: 13.sp, color: colorScheme.onSurfaceVariant)),
                    SizedBox(height: 10.h),
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: [
                        for (final e in _rosterEntries)
                          AppShiftChip(
                            label: e.name,
                            selected: identical(e, _myTeamEntry),
                            onTap: () => _selectMyTeam(e),
                          ),
                      ],
                    ),

                    // ── 3단계: 다른 조 ──
                    SizedBox(height: 28.h),
                    _sectionLabel(context.l10n.allTeamsSetupOtherTeamsLabel, color: kAppMainAccent),
                    SizedBox(height: 4.h),
                    if (_myTeamEntry == null)
                      Text(context.l10n.allTeamsSetupPickMyTeamFirstHint,
                          style: TextStyle(fontSize: 12.5.sp, color: colorScheme.onSurfaceVariant))
                    else ...[
                      Text(context.l10n.allTeamsSetupOtherTeamsHint,
                          style: TextStyle(fontSize: 13.sp, color: colorScheme.onSurfaceVariant)),
                      SizedBox(height: 10.h),
                      Wrap(
                        spacing: 8.w,
                        runSpacing: 8.h,
                        children: [
                          for (final e in _rosterEntries)
                            if (!identical(e, _myTeamEntry))
                              AppShiftChip(
                                label: e.name,
                                selected: _selectedOtherEntries.contains(e),
                                onTap: () => _toggleOtherTeam(e),
                              ),
                        ],
                      ),
                      if (_selectedOtherEntries.isEmpty) ...[
                        SizedBox(height: 8.h),
                        Text(context.l10n.allTeamsSetupMinOtherTeamHint,
                            style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant)),
                      ],
                    ],

                    // ── 4단계: 근무 배정 ──
                    if (_myTeamEntry != null) ...[
                      SizedBox(height: 28.h),
                      _sectionLabel(context.l10n.allTeamsSetupAssignSectionLabel, color: kAppMainAccent),
                      SizedBox(height: 4.h),
                      Text(context.l10n.allTeamsSetupAssignHint,
                          style: TextStyle(fontSize: 13.sp, color: colorScheme.onSurfaceVariant)),
                      if (unassignedOtherEntries.isNotEmpty) ...[
                        SizedBox(height: 10.h),
                        Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: [
                            for (final e in unassignedOtherEntries)
                              AppShiftChip(
                                label: e.name,
                                selected: identical(e, _pickedEntry),
                                onTap: () => _pickForAssignment(e),
                              ),
                          ],
                        ),
                      ],
                      SizedBox(height: 16.h),
                      // ⭐ 2026-09-05(3차) - "안내문구처럼 보이지 말고 아래 카드의
                      // 제목처럼" 요청 - 다른 캡션들과 같은 옅은 톤 대신 진하게,
                      // 그리드와 붙여서(간격 6.h) 그 카드의 타이틀처럼 보이게 함.
                      Text(context.l10n.statusPatternDayCycle(widget.pattern.length),
                          style: TextStyle(fontSize: 13.5.sp, fontWeight: FontWeight.w700, color: kAppChipBorder)),
                      SizedBox(height: 6.h),
                      _AssignmentGrid(
                        pattern: widget.pattern,
                        entryAtSlot: _entryAtSlot,
                        isMine: (e) => identical(e, _myTeamEntry),
                        onTapSlot: _tapSlot,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
              child: Row(
                children: [
                  Expanded(
                    child: AppSecondButton(
                      variant: AppSecondButtonVariant.neutral,
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.commonCancel),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: AppSecondButton(
                      variant: AppSecondButtonVariant.primary,
                      onPressed: _canSave ? _save : null,
                      child: Text(context.l10n.commonSave),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 4단계 배정 그리드 - 온보딩의 _buildPatternGrid와 같은 6열 레이아웃.
/// ⭐ 2026-09-05(3차) - 칸 안 배치를 다시 잡음(요청: "1 주간 D 이렇게 들어가는
/// 칩 안에서의 배치를 좀 잘해봐") - 순번(1)은 예전처럼 가운데 줄 하나로 안
/// 뺏고 달력 날짜 숫자처럼 카드 좌상단 모서리에 작게 붙이고, 근무명(주간)을
/// 칸 정중앙에 가장 크게 둬서 시각적 주인공으로 삼음. 조 배지(D)는 그 아래
/// 알약 모양으로 확실히 분리해서 "이 자리는 D 소속"이 한눈에 들어오게 함.
/// 내 조 자리는 잠금 아이콘 + 강조색으로 "탭해도 안 바뀜"을 표시.
class _AssignmentGrid extends StatelessWidget {
  final List<String> pattern;
  final _RosterEntry? Function(int index) entryAtSlot;
  final bool Function(_RosterEntry entry) isMine;
  final ValueChanged<int> onTapSlot;

  const _AssignmentGrid({
    required this.pattern,
    required this.entryAtSlot,
    required this.isMine,
    required this.onTapSlot,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          crossAxisSpacing: 6.w,
          mainAxisSpacing: 6.h,
          childAspectRatio: 0.82,
        ),
        itemCount: pattern.length,
        itemBuilder: (context, index) {
          final occupant = entryAtSlot(index);
          final mine = occupant != null && isMine(occupant);
          final Color borderColor;
          final Color fillColor;
          final Color badgeColor;
          if (mine) {
            // ⭐ 2026-09-05(4차) - 잠금 아이콘 대신 "살짝 비활성" 느낌만(요청:
            // "자물쇠는 좀 별로, 그냥 살짝 비활성느낌이면 충분"). 다른 조가
            // 배정된 칸(생동감 있는 강조색)과 확실히 구분되도록 채도를 확
            // 낮춘 회색 톤 + 전체를 살짝 옅게(Opacity)만 줌 - 별도 아이콘 없이
            // "이건 손댈 수 없는 자리"라는 게 톤 자체로 드러남.
            borderColor = colorScheme.outlineVariant;
            fillColor = colorScheme.surfaceVariant.withValues(alpha: 0.4);
            badgeColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
          } else if (occupant != null) {
            borderColor = kAppMainAccent.withValues(alpha: 0.6);
            fillColor = kAppSurface;
            badgeColor = kAppChipBorder;
          } else {
            borderColor = colorScheme.outlineVariant;
            fillColor = Colors.white;
            badgeColor = kAppChipBorder;
          }
          return InkWell(
            borderRadius: BorderRadius.circular(8.r),
            splashColor: kAppMainAccent.withValues(alpha: 0.25),
            highlightColor: kAppMainAccent.withValues(alpha: 0.15),
            onTap: () => onTapSlot(index),
            child: Opacity(
              opacity: mine ? 0.65 : 1.0,
              child: Container(
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: borderColor, width: occupant != null ? 2 : 1),
              ),
              padding: EdgeInsets.symmetric(vertical: 4.h),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ⭐ 순번 - 달력 날짜 숫자처럼 카드 좌상단 모서리에 작게.
                  Positioned(
                    top: 0,
                    left: 3.w,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(fontSize: 8.sp, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    ),
                  ),
                  // ⭐ 근무명 - 이 칸의 시각적 주인공. 조 배지가 있든 없든 항상
                  // 칸 정중앙에 오도록 Center 하나로 감쌈(배지 유무로 전체
                  // 블록의 높이가 달라져도 기준점이 안 흔들림).
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          pattern[index],
                          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: colorScheme.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (occupant != null) ...[
                          SizedBox(height: 4.h),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(20.r),
                            ),
                            child: Text(
                              occupant.name,
                              style: TextStyle(fontSize: 9.5.sp, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ⭐ 2026-09-05(3차) - "조 이름" 편집 전용 팝업(모달 바텀시트). 메인 화면의
/// 취소/저장 버튼과 완전히 분리된 화면에서 편집하게 하려는 요청으로 뺌 - 위
/// 파일 상단 docstring 참고.
///
/// [entries]는 부모(_AllTeamsSetupScreenState)의 _rosterEntries를 그대로
/// 참조로 받음(복사하지 않음) - 추가/이름변경은 이 위젯이 알아서 반영되고,
/// 부모는 시트가 닫힌 뒤 setState 한 번으로 최신 상태를 그대로 보여줌. 다만
/// 삭제는 부모 쪽 상태(내 조/다른 조 선택/배정)까지 정리해야 해서
/// [onRemoveCascade] 콜백으로 위임함.
class _RosterEditorSheet extends StatefulWidget {
  final List<_RosterEntry> entries;
  final ValueChanged<_RosterEntry> onRemoveCascade;

  const _RosterEditorSheet({required this.entries, required this.onRemoveCascade});

  @override
  State<_RosterEditorSheet> createState() => _RosterEditorSheetState();
}

class _RosterEditorSheetState extends State<_RosterEditorSheet> {
  final _addController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _add() {
    final trimmed = _addController.text.trim().toUpperCase();
    if (trimmed.isEmpty) return;
    if (trimmed.length != 1) {
      _showSnack(context.l10n.statusOneCharOnly);
      return;
    }
    if (widget.entries.any((e) => e.name == trimmed)) {
      _showSnack(context.l10n.allTeamsSetupDuplicateNameError);
      _addController.clear();
      return;
    }
    setState(() {
      widget.entries.add(_RosterEntry(trimmed));
      _addController.clear();
    });
  }

  void _remove(_RosterEntry entry) {
    setState(() {
      widget.entries.remove(entry);
      widget.onRemoveCascade(entry);
      entry.dispose();
    });
  }

  void _done() {
    final names = widget.entries.map((e) => e.name).toList();
    if (names.any((n) => n.length != 1)) {
      _showSnack(context.l10n.statusOneCharOnly);
      return;
    }
    if (names.toSet().length != names.length) {
      _showSnack(context.l10n.allTeamsSetupDuplicateNameError);
      return;
    }
    Navigator.pop(context);
  }

  // ⭐ 2026-09-05(4차) - 로스터 항목 하나를 세로로 늘어선 Row가 아니라, 이름
  // 입력칸+삭제(X)가 한 덩어리로 붙은 작은 알약(pill) 모양으로 바꿈. 이걸
  // Wrap에 넣으면 폭이 남는 만큼 가로로 이어 붙고 모자라면 자동으로 다음
  // 줄로 넘어가서, 조가 5개든 그 이상이든 세로 목록처럼 쌓이며 화면 아래로
  // 넘치는(overflow) 일이 없음(요청: "굳이 세로로 나열할 필요는 없을듯").
  Widget _entryPill(_RosterEntry entry) {
    return Container(
      padding: EdgeInsets.only(left: 12.w, right: 2.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FC),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26.w,
            child: TextField(
              controller: entry.controller,
              maxLength: 1,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp),
              decoration: const InputDecoration(
                counterText: '',
                isCollapsed: true,
                border: InputBorder.none,
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20.r),
            onTap: () => _remove(entry),
            child: Padding(
              padding: EdgeInsets.all(7.w),
              child: Icon(Icons.close, size: 15.sp, color: const Color(0xFFD64545)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addPill() {
    return Container(
      padding: EdgeInsets.only(left: 12.w, right: 2.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FC),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: kAppMainAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26.w,
            child: TextField(
              controller: _addController,
              maxLength: 1,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp),
              decoration: const InputDecoration(
                counterText: '',
                isCollapsed: true,
                border: InputBorder.none,
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20.r),
            onTap: _add,
            child: Padding(
              padding: EdgeInsets.all(7.w),
              child: Icon(Icons.add, size: 16.sp, color: kAppMainAccent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // ⭐ 키보드가 뜨면 그만큼 시트를 밀어올림.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        // ⭐ 위 Wrap 재설계로 웬만하면 다 들어가지만, 조가 아주 많거나 키보드가
        // 뜬 좁은 화면에서도 안전하도록 스크롤 가능하게 감쌈(요청: "bottom
        // overflow 해결").
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: kAppChipBorder.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                context.l10n.allTeamsSetupRosterLabel,
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800, color: kAppChipBorder),
              ),
              SizedBox(height: 16.h),
              Wrap(
                spacing: 10.w,
                runSpacing: 10.h,
                children: [
                  for (final e in widget.entries) _entryPill(e),
                  _addPill(),
                ],
              ),
              SizedBox(height: 20.h),
              SizedBox(
                width: double.infinity,
                child: AppSecondButton(
                  variant: AppSecondButtonVariant.success,
                  onPressed: _done,
                  child: Text(context.l10n.commonDone),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
