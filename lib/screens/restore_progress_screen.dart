// lib/screens/restore_progress_screen.dart
//
// ⭐ 2026-09-14 (출시전 교차 검토 X-02/X-03) - 설정 탭 "백업 데이터 불러오기"(덮어쓰기 복원) 실행 화면.
// 예전엔 설정 탭 안에서 복원을 돌려서
//  - 진행 중에도 하단 탭 이동이 가능했고, 다른 탭에서 옛 화면 상태로 근무표·메모·알람을 저장하면 복원한 DB를 다시 덮어쓸 수 있었음
//  - 탭을 옮기면 SettingsTab이 dispose돼 완료 후 필수 재시작이 `mounted` 검사에 걸려 생략됐음
//  - 재시작이 프로세스를 끝내 울리던 알람까지 끊었음
// 이제 앱 루트 네비게이터에 전체 화면으로 올려 뒤로가기·탭 이동을 막고, 이 화면이 직접 복원 → (울리는 알람이 있으면 끝날 때까지 대기)
// → 재시작까지 끝낸다. 복원이 아무것도 바꾸기 전에 실패한 경우만 결과를 들고 닫힌다.

import 'package:flutter/material.dart';

import '../l10n/l10n_extensions.dart';
import '../models/backup_payload.dart';
import '../services/app_restart.dart';
import '../services/backup_validator.dart';
import '../services/restore_coordinator.dart';
import '../theme/app_colors.dart';

/// 화면이 닫히며 돌려주는 결과 - 둘 다 "데이터는 그대로"인 경우. 성공·미완료는 닫히지 않고 앱을 재시작함.
enum RestoreProgressOutcome { invalid, failed }

class RestoreProgressScreen extends StatefulWidget {
  final BackupPayload payload;

  const RestoreProgressScreen({super.key, required this.payload});

  @override
  State<RestoreProgressScreen> createState() => _RestoreProgressScreenState();
}

class _RestoreProgressScreenState extends State<RestoreProgressScreen> {
  String? _resultMessage;
  bool _waitingAlarm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      await RestoreCoordinator.instance.start(widget.payload, overwrite: true);
      if (mounted) setState(() => _resultMessage = context.l10n.settingsRestoreFromBackupSuccessToast);
    } on BackupValidationException {
      if (mounted) Navigator.of(context).pop(RestoreProgressOutcome.invalid);
      return;
    } on RestoreIncompleteException {
      // 작업 기록이 남음 - 재시작하면 앱 시작 화면에서 이어서 완료/지금 데이터로 계속을 묻는다
      if (mounted) setState(() => _resultMessage = context.l10n.backupRestoreIncompleteToast);
    } catch (e) {
      // 잠금·작업 사본 저장 등 변경 전 단계에서 실패 - 데이터는 그대로
      debugPrint('🧯 [restore] 복원 시작 실패: $e');
      if (mounted) Navigator.of(context).pop(RestoreProgressOutcome.failed);
      return;
    }
    await restartAppWhenNoAlarmRinging(onWaiting: () {
      if (mounted && !_waitingAlarm) setState(() => _waitingAlarm = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.settings_backup_restore, size: 64, color: kAppMainAccent),
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 20),
                  Text(
                    _resultMessage ?? l10n.settingsRestoreFromBackupInProgress,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.5),
                  ),
                  if (_waitingAlarm) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.restoreWaitingAlarmEnd,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    l10n.restoreDoNotLeave,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.black45, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
