from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
p = ROOT/'lib/screens/permission_intro_screen.dart'
s = p.read_text('utf-8')
tail = s[s.index('  Future<void> _skipPermissions()'):]
tail = tail.replace('await PermissionService().openSettings();', 'if (context.mounted) await showPermissionSettings(context);')
# The existing backup/schedule routing below is preserved verbatim.
header = '''import '../widgets/adaptive_layout.dart';
import '../widgets/permission_panel.dart';
import 'package:flutter/material.dart';
import '../widgets/shift_editor_dialog.dart';
import '../services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n_extensions.dart';
import '../main.dart';
import '../models/backup_payload.dart';
import '../services/backup_storage_service.dart';
import '../services/database_service.dart';
import 'restore_backup_screen.dart';

class PermissionIntroScreen extends StatefulWidget {
  const PermissionIntroScreen({super.key});
  @override
  State<PermissionIntroScreen> createState() => _PermissionIntroScreenState();
}

class _PermissionIntroScreenState extends State<PermissionIntroScreen> {
  bool _isNavigating = false;
  bool _checking = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: AdaptiveFormBody(child: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.l10n.permissionGetStarted, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(context.l10n.permissionIntro),
        const SizedBox(height: 24),
        const PermissionPanel(),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _checking ? null : _continue,
          child: Text(context.l10n.commonNext))),
        SizedBox(width: double.infinity, child: TextButton(
          onPressed: _checking ? null : _skipPermissions,
          child: Text(context.l10n.commonNotNow))),
      ])))));

  Future<void> _continue() async {
    if (_checking || _isNavigating) return;
    setState(() => _checking = true);
    final state = await PermissionService().snapshot();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_requested', true);
    if (!mounted) return;
    setState(() => _checking = false);
    if (state.allSatisfied) { await _navigateToOnboarding(); }
    else { _showPermissionWarning(); }
  }

'''
p.write_text(header+tail,'utf-8')
p=ROOT/'lib/screens/restore_backup_screen.dart'
s=p.read_text('utf-8')
s=s.replace("permissions['notification']! && permissions['overlay']! && permissions['exactAlarm']!", "permissions.values.every((granted) => granted)")
p.write_text(s,'utf-8')
p=ROOT/'lib/widgets/permission_warning_banner.dart'
s=p.read_text('utf-8')
s=s.replace("import '../services/permission_service.dart';", "import '../services/permission_service.dart';\nimport 'permission_panel.dart';")
s=s.replace('  bool _showBanner = false;', '  final _controller = PermissionController();\n  bool _showBanner = false;')
s=s.replace('    WidgetsBinding.instance.addObserver(this);', '    WidgetsBinding.instance.addObserver(this);\n    _controller.addListener(_updateBanner);')
s=s.replace('    WidgetsBinding.instance.removeObserver(this);', '    WidgetsBinding.instance.removeObserver(this);\n    _controller.dispose();')
start=s.index('  Future<void> _checkPermissions() async {')
end=s.index('  @override\n  Widget build',start)
s=s[:start]+'''  Future<void> _checkPermissions() => _controller.refresh();

  void _updateBanner() {
    if (!mounted) return;
    final state = _controller.value;
    final missing = <String>[];
    for (final p in AppPermission.values) {
      if (!permissionSatisfied(state[p])) {
        final title = permissionTitle(context, p);
        missing.add(state[p] == AppPermissionState.unknown
          ? context.l10n.permissionStatusUnknown(title) : title);
      }
    }
    if (!permissionSatisfied(state.alarmChannel)) {
      missing.add(state.alarmChannel == AppPermissionState.denied
        ? context.l10n.permissionAlarmChannelBlocked : context.l10n.permissionAlarmChannelUnknown);
    }
    setState(() { _missingPermissions = missing; _showBanner = missing.isNotEmpty; });
  }

'''+s[end:]
s=s.replace('await PermissionService().openSettings();', 'await showPermissionSettings(context);\n              _checkPermissions();')
p.write_text(s,'utf-8')
for filename in ['lib/screens/settings_tab.dart', 'lib/screens/help_screen.dart']:
 p=ROOT/filename; s=p.read_text('utf-8')
 s="import '../widgets/permission_panel.dart';\n"+s
 if 'settings_tab' in filename:
  anchor='              ListTile(\n                leading: Icon(Icons.help_outline,'
  assert anchor in s
  s=s.replace(anchor, '''              ListTile(
                leading: const Icon(Icons.lock_clock),
                title: Text(context.l10n.permissionSettingsTitle),
                onTap: () => showPermissionSettings(context),
              ),
'''+anchor)
 else:
  anchor='        title: Text(l10n.settingsHelp),'
  s=s.replace(anchor, anchor+'''
        actions: [IconButton(icon: const Icon(Icons.lock_clock),
          tooltip: l10n.permissionSettingsTitle,
          onPressed: () => showPermissionSettings(context))],''')
 p.write_text(s,'utf-8')
