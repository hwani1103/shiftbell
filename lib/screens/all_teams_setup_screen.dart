import '../widgets/settings_appearance.dart';
import '../widgets/team_assignment_grid.dart';
import '../widgets/semantics_table_boundary.dart';
import '../widgets/adaptive_layout.dart';
// Initial roster creation: names, my team, then all remaining positions.
import '../models/team_rule.dart';
import '../models/team_schedule_config.dart';
import '../services/database_service.dart';
import '../widgets/team_rule_card.dart';
import '../widgets/shift_editor_dialog.dart';
import 'team_rule_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/shift_schedule.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shift_chip.dart';
import '../widgets/app_second_button.dart';
import '../widgets/app_button.dart';

/// Stable identity used by selection and assignments even when names change.
class _RosterEntry {
  final TextEditingController controller;
  _RosterEntry(String name) : controller = TextEditingController(text: name);
  String get name => controller.text.trim().toUpperCase();
  void dispose() => controller.dispose();
}

class AllTeamsSetupScreen extends StatefulWidget {
  final List<String> pattern;
  final List<String>? shiftTypes;
  final DateTime? referenceDate;
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
    this.shiftTypes,
    this.referenceDate,
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

  // All roster entries participate; the remaining teams need only a position.
  Iterable<_RosterEntry> get _otherEntries =>
      _rosterEntries.where((e) => !identical(e, _myTeamEntry));
  final List<_RosterEntry> _retiredEntries = [];
  bool _saving = false;
  bool _individual = false;
  late DateTime _referenceDate;
  final Map<_RosterEntry, TeamRule> _rules = {};

  // 4단계: 근무 배정(조 → 패턴 슬롯 0-based index)
  final Map<_RosterEntry, int> _assignments = {};
  _RosterEntry? _pickedEntry; // 지금 "집어든" 조(탭-탭 배치용)

  @override
  void initState() {
    super.initState();
    final today = widget.referenceDate ?? DateTime.now();
    _referenceDate = DateTime(today.year, today.month, today.day);
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
    for (final e in [..._rosterEntries, ..._retiredEntries]) {
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
    final names = _rosterEntries.map((e) => e.name).toList();
    return !_saving &&
        _myTeamEntry != null &&
        names.length >= 2 &&
        names.every((n) => n.characters.length == 1) &&
        names.toSet().length == names.length &&
        (_individual
            ? _otherEntries.every(_rules.containsKey)
            : _rosterEntries.every((e) => _assignments.containsKey(e)) &&
                _assignments.values.toSet().length == _rosterEntries.length);
  }

  // ───────────────────────── 1단계: 로스터 편집 ─────────────────────────
  // Names are edited separately and committed only after validation.
  Future<void> _openRosterEditor() async {
    // Edit a draft. Dismissing the sheet must not leak invalid/duplicate names
    // into the assignment map, whose persisted keys are the final team names.
    final originals = {for (final e in _rosterEntries) _RosterEntry(e.name): e};
    final draft = originals.keys.toList();
    final removedDrafts = <_RosterEntry>[];
    final completed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (_) => _RosterEditorSheet(
        entries: draft,
        onRemoveCascade: removedDrafts.add,
      ),
    );
    if (!mounted) {
      for (final e in [...draft, ...removedDrafts]) {
        e.dispose();
      }
      return;
    }
    // Keep controllers alive until the sheet's closing animation unmounts its
    // TextFields. They are disposed with this page, never during a remove tap.
    _retiredEntries.addAll([...draft, ...removedDrafts]);
    if (completed != true) return;
    setState(() {
      final next = <_RosterEntry>[];
      for (final e in draft) {
        final original = originals[e];
        if (original != null) {
          original.controller.text = e.name;
          next.add(original);
        } else {
          next.add(_RosterEntry(e.name));
        }
      }
      for (final e in _rosterEntries.where((e) => !next.contains(e))) {
        _cascadeCleanupAfterRosterRemoval(e);
      }
      _rosterEntries = next;
    });
  }

  void _cascadeCleanupAfterRosterRemoval(_RosterEntry entry) {
    if (identical(_myTeamEntry, entry)) _myTeamEntry = null;
    _retiredEntries.add(entry);
    _assignments.remove(entry);
    _rules.remove(entry);
    if (identical(_pickedEntry, entry)) _pickedEntry = null;
  }

  // ───────────────────────── 2단계: 내 조 선택 ─────────────────────────

  void _selectMyTeam(_RosterEntry entry) {
    if (identical(_myTeamEntry, entry)) return;
    setState(() {
      // The previous identity returns to the unassigned tray automatically.
      if (_myTeamEntry != null) _assignments.remove(_myTeamEntry);
      _rules.remove(entry);
      _myTeamEntry = entry;
      _assignments.remove(entry);
      _rules.remove(entry); // 혹시 다른 조로 이미 배정돼 있었다면 해제
      _assignments[entry] = widget.myTodayIndex;
      if (identical(_pickedEntry, entry)) _pickedEntry = null;
    });
  }

  // ───────────────────────── 3단계: 근무 배정 ─────────────────────────

  void _pickForAssignment(_RosterEntry entry) {
    setState(
        () => _pickedEntry = identical(_pickedEntry, entry) ? null : entry);
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
    if (!_canSave) return;
    setState(() => _saving = true);
    final included = _rosterEntries;
    final teamNames = included.map((e) => e.name).toList();
    final offsets = <String, int>{
      for (final e in included)
        e.name: _offsetFor((identical(e, _myTeamEntry)
                ? widget.myTodayIndex
                : (_assignments[e] ?? 0)) +
            1),
    };
    final config = TeamScheduleConfig(
        names: teamNames,
        offsets: offsets,
        myTeam: _myTeamEntry!.name,
        individual: _individual,
        rules: {
          for (final e in included)
            e.name: identical(e, _myTeamEntry)
                ? TeamRule.cycle(
                    widget.pattern, _referenceDate, widget.myTodayIndex)
                : _individual
                    ? _rules[e]!
                    : TeamRule.cycle(
                        widget.pattern, _referenceDate, _assignments[e]!),
        }).materialize(widget.pattern);
    try {
      final accepted = await _review(config);
      if (!mounted) return;
      if (!accepted) {
        setState(() => _saving = false);
        return;
      }
      await DatabaseService.instance.saveTeamScheduleConfig(config);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      debugPrint('Team schedule save failed: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.settingsScheduleChangeFailedWithError(
              context.localizedErrorDetail(error)))));
    }
  }

  Future<void> _editRule(_RosterEntry entry) async {
    final rule = await Navigator.push<TeamRule>(
        context,
        MaterialPageRoute(
            builder: (_) => TeamRuleEditorScreen(
                team: entry.name,
                basePattern: widget.pattern,
                shiftTypes:
                    widget.shiftTypes ?? widget.pattern.toSet().toList(),
                date: _referenceDate,
                initial: _rules[entry])));
    if (rule != null && mounted) setState(() => _rules[entry] = rule);
  }

  Future<bool> _review(TeamScheduleConfig config) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) => ShiftEditorDialog(
                  title: Text(context.l10n.teamRuleReview),
                  content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(context.l10n.teamRuleReviewHint,
                            style: const TextStyle(height: 1.5)),
                        const SizedBox(height: 16),
                        SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SemanticsTableBoundary(
                                child: DataTable(
                              columnSpacing: 16,
                              horizontalMargin: 8,
                              columns: [
                                const DataColumn(label: Text('')),
                                for (final name in config.names)
                                  DataColumn(label: Text(name))
                              ],
                              rows: [
                                for (var day = 0; day < 14; day++)
                                  _previewRow(config, day)
                              ],
                            ))),
                      ]),
                  actions: [
                    AppSecondButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(context.l10n.commonCancel)),
                    AppSecondButton(
                        key: const ValueKey('team-review-save'),
                        variant: AppSecondButtonVariant.success,
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(context.l10n.commonSave)),
                  ])) ??
      false;

  DataRow _previewRow(TeamScheduleConfig config, int day) {
    final date = DateTime(
        _referenceDate.year, _referenceDate.month, _referenceDate.day + day);
    return DataRow(cells: [
      DataCell(Text('${date.month}/${date.day}')),
      for (final name in config.names)
        DataCell(Text(config.rules[name]!.shiftOn(date)))
    ]);
  }

  Widget _sectionLabel(String text, {required Color color}) => Text(
        text,
        style: TextStyle(
            fontSize: 16.sp, fontWeight: FontWeight.w600, color: color),
      );

  @override
  Widget build(BuildContext context) =>
      SettingsAppearance(builder: _buildStyled);

  Widget _buildStyled(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // ⭐ 2026-09-05(3차) - 여기도 저장 로직과 같은 이유로 Set 순서 대신 로스터
    // 순서를 따름(트레이 칩이 탭한 순서대로 뒤섞여 보이지 않게).
    final unassignedOtherEntries = _rosterEntries
        .where((e) => _otherEntries.contains(e) && !_assignments.containsKey(e))
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(context.l10n.statusFullTeamScheduleTitle),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: AdaptiveFormBody(
          child: SafeArea(
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
                          child: _sectionLabel(
                              context.l10n.allTeamsSetupRosterLabel,
                              color: kAppMainAccent),
                        ),
                        // ⭐ 2026-09-05(3차) - 눈에 잘 띄게 제대로 된 버튼으로
                        // (요청: "초록색이나 뭐 좀 눈에 보이게"). 초록(success)은
                        // 이 앱에서 "저장/확인처럼 긍정적으로 완료하는 액션"
                        // 톤으로 이미 쓰이고 있어서(app_second_button.dart) 그대로
                        // 재사용 - 조 이름을 확정 짓는 이 버튼과 잘 맞음.
                        AppSecondButton(
                          variant: AppSecondButtonVariant.neutral,
                          compact: true,
                          onPressed: _saving ? null : _openRosterEditor,
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
                        style: TextStyle(
                            fontSize: 12.5.sp,
                            color: colorScheme.onSurfaceVariant)),
                    SizedBox(height: 10.h),
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: [
                        for (final e in _rosterEntries)
                          AppShiftChip(label: e.name)
                      ],
                    ),

                    // ── 2단계: 내 조 ──
                    SizedBox(height: 28.h),
                    _sectionLabel(context.l10n.allTeamsSetupMyTeamLabel,
                        color: kAppMainAccent),
                    SizedBox(height: 4.h),
                    Text(context.l10n.allTeamsSetupMyTeamPickHint,
                        style: TextStyle(
                            fontSize: 13.sp,
                            color: colorScheme.onSurfaceVariant)),
                    SizedBox(height: 10.h),
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: [
                        for (final e in _rosterEntries)
                          AppShiftChip(
                            label: e.name,
                            selected: identical(e, _myTeamEntry),
                            onTap: _saving ? null : () => _selectMyTeam(e),
                          ),
                      ],
                    ),

                    // Choose the method next to the content it changes.
                    if (_myTeamEntry != null) ...[
                      SizedBox(height: 28.h),
                      _sectionLabel(context.l10n.teamSetupModeTitle,
                          color: kAppMainAccent),
                      SizedBox(height: 12.h),
                      for (final individual in [false, true])
                        Padding(
                          padding: EdgeInsets.only(bottom: 10.h),
                          child: Material(
                            color: _individual == individual
                                ? kAppSurface
                                : Colors.white,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14.r),
                              side: BorderSide(
                                color: _individual == individual
                                    ? kAppMainAccent
                                    : colorScheme.outlineVariant,
                                width: _individual == individual ? 1.5 : 1,
                              ),
                            ),
                            child: ListTile(
                              key: ValueKey(
                                  'team-mode-${individual ? 'individual' : 'shared'}'),
                              selected: _individual == individual,
                              selectedColor: colorScheme.onSurface,
                              selectedTileColor: Colors.transparent,
                              tileColor: Colors.transparent,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14.w, vertical: 6.h),
                              title: Text(individual
                                  ? context.l10n.teamSetupIndividual
                                  : context.l10n.teamSetupShared),
                              subtitle: Text(
                                  individual
                                      ? context.l10n.teamSetupIndividualHint
                                      : context.l10n.teamSetupSharedHint,
                                  style: const TextStyle(height: 1.4)),
                              trailing: Icon(
                                  _individual == individual
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: kAppMainAccent),
                              onTap: _saving
                                  ? null
                                  : () =>
                                      setState(() => _individual = individual),
                            ),
                          ),
                        ),
                    ],

                    // ── 4단계: 근무 배정 ──
                    if (_myTeamEntry != null && _individual == false) ...[
                      SizedBox(height: 28.h),
                      _sectionLabel(
                          context.l10n.allTeamsSetupAssignSectionLabel,
                          color: kAppMainAccent),
                      SizedBox(height: 4.h),
                      Text(context.l10n.allTeamsSetupAssignHint,
                          style: TextStyle(
                              fontSize: 13.sp,
                              color: colorScheme.onSurfaceVariant)),
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
                      Text(
                          context.l10n
                              .statusPatternDayCycle(widget.pattern.length),
                          style: TextStyle(
                              fontSize: 13.5.sp,
                              fontWeight: FontWeight.w700,
                              color: kAppChipBorder)),
                      SizedBox(height: 6.h),
                      TeamAssignmentGrid(
                        pattern: widget.pattern,
                        teamAtSlot: (index) => _entryAtSlot(index)?.name,
                        isMine: (index) =>
                            _myTeamEntry != null &&
                            identical(_entryAtSlot(index), _myTeamEntry),
                        onTapSlot: _tapSlot,
                      ),
                    ],
                    if (_myTeamEntry != null && _individual == true) ...[
                      const SizedBox(height: 24),
                      Text(context.l10n.teamRuleTitle,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: kAppMainAccent)),
                      const SizedBox(height: 6),
                      Text(context.l10n.teamRuleOverlapHint,
                          style: const TextStyle(height: 1.5)),
                      const SizedBox(height: 12),
                      TeamRuleCard(
                          team: _myTeamEntry!.name,
                          isMine: true,
                          locked: true,
                          date: _referenceDate,
                          rule: TeamRule.cycle(widget.pattern, _referenceDate,
                              widget.myTodayIndex)),
                      for (final entry in _otherEntries)
                        TeamRuleCard(
                            key: ValueKey('team-setup-rule-${entry.name}'),
                            team: entry.name,
                            date: _referenceDate,
                            rule: _rules[entry],
                            onTap: _saving ? null : () => _editRule(entry)),
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
                    child: AppButton(
                      onPressed: _canSave ? _save : null,
                      child: Text(context.l10n.commonSave),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      )),
    );
  }
}

/// Edits draft entries; true means validated completion, dismissal means cancel.
class _RosterEditorSheet extends StatefulWidget {
  final List<_RosterEntry> entries;
  final ValueChanged<_RosterEntry> onRemoveCascade;

  const _RosterEditorSheet(
      {required this.entries, required this.onRemoveCascade});

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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
      // Parent disposes this controller after the editor has unmounted.
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
    Navigator.pop(context, true);
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
              key: ObjectKey(entry),
              controller: entry.controller,
              maxLength: 1,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.sp),
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
              child: Icon(Icons.close,
                  size: 15.sp, color: const Color(0xFFD64545)),
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
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.sp),
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
  Widget build(BuildContext context) =>
      SettingsAppearance(builder: _buildStyled);

  Widget _buildStyled(BuildContext context) {
    return Padding(
      // ⭐ 키보드가 뜨면 그만큼 시트를 밀어올림.
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                    color: kAppChipBorder),
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
                child: AppButton(
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
