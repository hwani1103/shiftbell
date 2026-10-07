from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
def edit(path, fn):
 p=ROOT/path;s=p.read_text('utf-8');p.write_text(fn(s),'utf-8')

def guarded(s):
 s="import '../widgets/unavailable_feature.dart';\n"+s
 if "import '../l10n/l10n_extensions.dart';" not in s:
  s="import '../l10n/l10n_extensions.dart';\n"+s
 s=re.sub(r'(Widget build\(BuildContext context(?:, WidgetRef ref)?\) \{)',
  r'\1\n    if (!context.usesKoreanFeatures) return const UnavailableFeature();',s)
 # Independently mounted edit screens/sheets must also re-check on locale change.
 s=re.sub(r'(builder: \((\w+)(?:, setState)?\) \{)',
  r'\1\n          if (!\2.usesKoreanFeatures) return const UnavailableFeature();',s)
 s=re.sub(r'builder: \((\w+)\) => (AlertDialog|ShiftEditorDialog|Scaffold)',
  r'builder: (\1) => !\1.usesKoreanFeatures ? const UnavailableFeature() : \2',s)
 return s
for path in ['lib/screens/condition_tab.dart','lib/screens/schedule_management_tab.dart',
 'lib/screens/sleep_calendar_full_screen.dart','lib/screens/english_condition_tab.dart',
 'lib/widgets/custom_alarm_preset_panel.dart','lib/widgets/custom_alarm_widgets.dart',
 'lib/widgets/sleep_edit_dialog.dart','lib/screens/friend_list_screen.dart','lib/screens/my_share_code_screen.dart']:
 edit(path,guarded)
edit('lib/widgets/sleep_edit_dialog.dart',lambda s:s.replace('  var start = initialStart;',
 '  if (!context.usesKoreanFeatures) return null;\n  var start = initialStart;'))
edit('lib/widgets/custom_alarm_widgets.dart',lambda s:s.replace('  final original =',
 '  if (!context.usesKoreanFeatures) return;\n  final original =',1).replace('if (!context.mounted) return;',
 'if (!context.mounted || !context.usesKoreanFeatures) return;').replace('  final l10n = context.l10n;\n  final at =',
 '  if (!context.usesKoreanFeatures) throw StateError("One-tap UI outside Korean scope");\n  final l10n = context.l10n;\n  final at ='))
edit('lib/widgets/calendar_header_actions.dart',lambda s:s.replace('if (onOneTap != null)',
 'if (context.usesKoreanFeatures && onOneTap != null)'))
edit('lib/widgets/disable_tab_button.dart',lambda s:guarded(s).replace('  try {\n    await setEnabled();',
 '  if (!context.usesKoreanFeatures) return false;\n  try {\n    await setEnabled();').replace('if (context.mounted)',
 'if (context.mounted && context.usesKoreanFeatures)'))
edit('lib/utils/friend_open_util.dart',lambda s:s.replace('  // ⭐ 2026-09-15',
 '  if (!context.usesKoreanFeatures) return;\n  // ⭐ 2026-09-15',1).replace('if (!context.mounted) return;',
 'if (!context.mounted || !context.usesKoreanFeatures) return;'))
edit('lib/screens/friend_calendar_view.dart',lambda s:s.replace('this.showInstallPrompt = false,',
 'this.showInstallPrompt = false,\n    this.publicWebViewer = false,').replace('  final String friendName;',
 '  final bool publicWebViewer;\n  final String friendName;').replace('=> !context.usesKoreanFeatures',
 '=> !publicWebViewer && !context.usesKoreanFeatures'))
edit('lib/web_main.dart',lambda s:s.replace('return FriendCalendarView(', 'return FriendCalendarView(publicWebViewer: true,'))
edit('lib/models/calendar_theme.dart',lambda s:s.replace('    final l10n = context.l10n;',
 '    if (!context.usesKoreanFeatures && !kEnglishCalendarThemeIds.contains(this)) {\n      return kDefaultCalendarThemeId.label(context);\n    }\n    final l10n = context.l10n;',1))
edit('lib/screens/calendar_theme_lab_screen.dart',lambda s:s.replace('  static const _themeCount = 10;',
 '  int get _themeCount => context.availableCalendarThemes.length;').replace('itemBuilder: (context, index) => _buildThemeBody(index)',
 'itemBuilder: (context, index) => _buildThemeBody(index)').replace('  Widget _buildThemeBody(int index) {',
 '  Widget _buildThemeBody(int index) {\n    if (!context.usesKoreanFeatures && index >= kEnglishCalendarThemeIds.length) {\n      return _themeMainWhite();\n    }'))
for path in ['lib/screens/calendar_tab.dart','lib/utils/apply_schedule_change.dart']:
 edit(path,lambda s:s.replace("skippedSlots.isEmpty ? ''", "(skippedSlots.isEmpty || !context.usesKoreanFeatures) ? ''")
  .replace("alarmOutcome.skippedSlots.isEmpty ? ''", "(alarmOutcome.skippedSlots.isEmpty || !context.usesKoreanFeatures) ? ''")
  .replace('alarmOutcome != null && alarmOutcome.skippedByCustom > 0',
   'context.usesKoreanFeatures && alarmOutcome != null && alarmOutcome.skippedByCustom > 0'))
edit('lib/screens/settings_tab.dart',lambda s:s.replace('skippedSlots.isNotEmpty\n',
 'context.usesKoreanFeatures && skippedSlots.isNotEmpty\n'))
edit('lib/screens/all_alarms_history_view.dart',lambda s:s.replace('if (alarmWithHistory.shiftType != null || alarmWithHistory.isOneTap)',
 'if (context.usesKoreanFeatures && alarmWithHistory.isOneTap || !alarmWithHistory.isOneTap && alarmWithHistory.shiftType != null)'))
edit('lib/screens/next_alarm_tab.dart',lambda s:s.replace("if ((alarm?.type == 'custom' || alarm?.presetSlot != null) &&",
 "if (context.usesKoreanFeatures && (alarm?.type == 'custom' || alarm?.presetSlot != null) &&")
 .replace('if (!mounted) return;\n      final confirmed', 'if (!mounted || !context.usesKoreanFeatures) return;\n      final confirmed')
 .replace('deletion.reservationFailed\n', 'context.usesKoreanFeatures && deletion.reservationFailed\n')
 .replace('deletion.fixedReplacement\n','context.usesKoreanFeatures && deletion.fixedReplacement\n')
 .replace("alarm.type == 'custom' ||\n", "context.usesKoreanFeatures && alarm.type == 'custom' ||\n")
 .replace('alarm.presetSlot != null)', 'context.usesKoreanFeatures && alarm.presetSlot != null)'))
edit('lib/screens/calendar_tab.dart',lambda s:s.replace('deletion.reservationFailed\n',
 'context.usesKoreanFeatures && deletion.reservationFailed\n').replace('deletion.fixedReplacement\n',
 'context.usesKoreanFeatures && deletion.fixedReplacement\n'))
edit('lib/widgets/onboarding_info_popups.dart',lambda s:s.replace("shownKey: 'one_touch_alarm_tutorial_shown',",
 "shownKey: 'one_touch_alarm_tutorial_shown',\n      koreanOnly: true,"))
