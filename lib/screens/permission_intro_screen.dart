import '../widgets/adaptive_layout.dart';
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
  bool _warningOpen = false;
  bool _allSatisfied = false;

  void _permissionsChanged(PermissionSnapshot state) {
    if (!mounted) return;
    setState(() => _allSatisfied = state.allSatisfied);
    if (!state.allSatisfied) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _allSatisfied &&
          ModalRoute.of(context)?.isCurrent == true) {
        _continue();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: AdaptiveFormBody(
          child: SafeArea(
              child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 40, 24, 16),
                              child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              context.l10n.permissionGetStarted,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineMedium),
                                          const SizedBox(height: 12),
                                          Text(context.l10n.permissionIntro),
                                          const SizedBox(height: 24),
                                          PermissionPanel(
                                              actionRequiredOnly: true,
                                              continueAfterGrant: true,
                                              onChanged: _permissionsChanged),
                                        ]),
                                    if (!_allSatisfied)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 24),
                                          child: TextButton(
                                              onPressed: _checking
                                                  ? null
                                                  : _skipPermissions,
                                              child: Text(
                                                  context.l10n.commonNotNow))),
                                  ]))))))));

  Future<void> _continue() async {
    if (_checking || _isNavigating || _warningOpen) return;
    setState(() => _checking = true);
    final state = await PermissionService().snapshot();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_requested', true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _allSatisfied = state.allSatisfied;
    });
    if (state.allSatisfied) {
      await _navigateToOnboarding();
    } else {
      _showPermissionWarning();
    }
  }

  Future<void> _skipPermissions() async {
    if (_checking || _isNavigating || _warningOpen) return;
    setState(() => _checking = true);
    // 나중에 하기 → 경고 다이얼로그 표시
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_requested', true);

    if (!mounted) return;
    setState(() => _checking = false);
    _showPermissionWarning();
  }

  void _showPermissionWarning() {
    if (_warningOpen || !mounted) return;
    _warningOpen = true;
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ShiftEditorDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: colorScheme.tertiary, size: 28.0),
            SizedBox(width: 8.0),
            Flexible(
              child: Text(
                context.l10n.permissionSomeDenied,
                style: TextStyle(fontSize: 16.0),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.permissionSomeDeniedDesc,
              style: TextStyle(fontSize: 14.0, height: 1.5),
            ),
            SizedBox(height: 16.0),
            Text(
              context.l10n.permissionCanAllowLater,
              style: TextStyle(
                fontSize: 13.0,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              if (context.mounted) await showPermissionSettings(context);
            },
            child: Text(context.l10n.commonGoToSettings),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToOnboarding();
            },
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
            ),
            child: Text(context.l10n.commonContinue),
          ),
        ],
      ),
    ).whenComplete(() {
      _warningOpen = false;
      if (mounted && _allSatisfied) _continue();
    });
  }

  // ⭐ 2026-09-01 - "백업 복구했는데 온보딩 어디에도 그 화면이 안 나온다" 버그
  // 수정. 원인: 사용자 데이터 백업("A번 요구사항")의 복구 확인 화면
  // (RestoreBackupScreen)은 main.dart의 InitialRouter._navigate()에만 연결해
  // 뒀었는데, 실제 "권한 안내 화면을 막 통과한" 순간은 이 함수(당시
  // _navigateToOnboarding)가 그 InitialRouter를 다시 거치지 않고 곧장
  // `/onboarding`으로 직행했음(named route). 그래서 진짜 신규 설치 흐름에서는
  // 백업 확인 로직이 있으나 마나였음 - 이 함수가 그 "권한 화면 다음" 분기의
  // 진짜 트리거였다.
  //
  // 이 참에 반대 방향 버그도 같이 고침: RestoreBackupScreen에서 복구를 마친
  // 뒤 OS 권한을 다시 받게 하려고 이 화면으로 돌아오는데(restore_backup_screen.dart),
  // 그 경우 스케줄이 이미 채워져 있으므로 여기서 다시 온보딩으로 보내면 안 되고
  // 곧장 MainScreen으로 가야 함 - InitialRouter의 3단 분기(권한→스케줄 유무→
  // 백업 유무)와 동일한 판단을 여기서도 그대로 반복함.
  Future<void> _navigateToOnboarding() async {
    if (_isNavigating) return; // 중복 방지
    _isNavigating = true;

    final schedule = await DatabaseService.instance.getShiftSchedule();

    if (schedule != null) {
      // 이미 스케줄이 있음 - 방금 백업을 복구하고 돌아온 경우. 온보딩 마법사를
      // 다시 태울 이유가 없으므로 곧장 메인 화면으로.
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (context) =>
                const MainScreen(initialIndex: kCalendarTabIndex)), // 달력탭
      );
      return;
    }

    // 스케줄이 없음 - 진짜 신규 설치(또는 초기화 직후). 온보딩으로 보내기 전에
    // 이 기기에 예전 백업이 남아있는지 마지막으로 확인 - MediaStore는 앱을
    // 지워도 파일이 안 지워지므로(backup_storage_service.dart 참고).
    final backupJson = await BackupStorageService.instance.read();
    BackupPayload? payload;
    if (backupJson != null) {
      try {
        payload = BackupPayload.decode(backupJson);
      } catch (e) {
        payload = null; // 손상된 백업 파일 - 조용히 무시하고 신규 설치처럼 진행
      }
    }

    if (!mounted) return;
    if (payload != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (context) => RestoreBackupScreen(payload: payload!)),
      );
    } else {
      Navigator.of(context).pushReplacementNamed('/onboarding');
    }
  }
}
