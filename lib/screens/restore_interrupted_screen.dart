// lib/screens/restore_interrupted_screen.dart
//
// ⭐ 2026-09-14 (출시전 감사 G4 #19) - 앱 시작 시 중단된 백업 복원 작업(RestoreCoordinator 작업 기록)이 남아 있으면
// InitialRouter가 다른 화면보다 먼저 이 화면을 띄운다. 사용자가 데이터를 고칠 수 있는 화면에 들어가기 전에 선택하게 해서,
// "자동 이어하기가 중단 뒤 바뀐 내용을 몰래 덮어쓰는" 경로를 막는다(설계 17번).
//  - 이어서 복원하기: 같은 작업 사본·ID 매핑으로 남은 단계 완료 → 앱 재시작.
//  - 지금 데이터로 계속 쓰기: 현재 DB 기준으로 알람·일정 알림 예약을 다시 맞추고 작업 기록 삭제 → 앱 재시작.
//  - 사본이 없거나 손상됐으면 이어서 할 수 없다고 알리고, 현재 데이터 기준 정리 후 계속만 제공.
// 그동안 알람은 네이티브가 현재 DB 기준으로 정상 동작한다(RestoreGate 죽은 잠금 해제).
//
// ⭐ 2026-09-14 (출시전 교차 검토 X-03/X-06) - 재시작은 이 프로세스에서 울리는 알람이 끝난 뒤에만. "지금 데이터로 계속"의
// 재조정이 실패하면 작업 기록이 남으므로 재시작하지 않고 이 화면에서 다시 선택하게 함.

import 'package:flutter/material.dart';

import '../l10n/l10n_extensions.dart';
import '../services/app_restart.dart';
import '../services/restore_coordinator.dart';
import '../theme/app_colors.dart';
import '../widgets/app_button.dart';

class RestoreInterruptedScreen extends StatefulWidget {
  const RestoreInterruptedScreen({super.key});

  @override
  State<RestoreInterruptedScreen> createState() => _RestoreInterruptedScreenState();
}

class _RestoreInterruptedScreenState extends State<RestoreInterruptedScreen> {
  bool _working = false;
  bool _copyLost = false;
  bool _waitingAlarm = false;

  Future<void> _restartApp() async {
    await restartAppWhenNoAlarmRinging(onWaiting: () {
      if (mounted && !_waitingAlarm) setState(() => _waitingAlarm = true);
    });
  }

  void _showIncomplete() {
    if (!mounted) return;
    setState(() => _working = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.backupRestoreIncompleteToast)),
    );
  }

  Future<void> _resume() async {
    setState(() => _working = true);
    try {
      await RestoreCoordinator.instance.resume();
      await _restartApp();
    } on RestoreCopyLostException {
      if (!mounted) return;
      setState(() {
        _working = false;
        _copyLost = true;
      });
    } catch (e) {
      _showIncomplete();
    }
  }

  Future<void> _keepCurrent() async {
    setState(() => _working = true);
    try {
      await RestoreCoordinator.instance.safeEnd();
    } catch (_) {
      // 재조정을 끝내지 못해 작업 기록이 남음 - 알람은 네이티브가 현재 DB로 동작. 여기서 다시 선택 가능
      _showIncomplete();
      return;
    }
    await _restartApp();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                const Icon(Icons.restore, size: 64, color: kAppMainAccent),
                const SizedBox(height: 24),
                Text(
                  l10n.restoreInterruptedTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  _copyLost ? l10n.restoreInterruptedCopyLost : l10n.restoreInterruptedDesc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
                ),
                const SizedBox(height: 36),
                if (_working)
                  Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(l10n.restoreInterruptedInProgress, textAlign: TextAlign.center),
                      if (_waitingAlarm) ...[
                        const SizedBox(height: 12),
                        Text(
                          l10n.restoreWaitingAlarmEnd,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
                        ),
                      ],
                    ],
                  )
                else if (_copyLost)
                  AppButton(
                    onPressed: _keepCurrent,
                    child: Text(l10n.commonContinue),
                  )
                else ...[
                  AppButton(
                    onPressed: _resume,
                    child: Text(l10n.restoreInterruptedResumeButton),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _keepCurrent,
                    child: Text(l10n.restoreInterruptedKeepButton),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
