// lib/screens/restore_backup_screen.dart
//
// ⭐ 사용자 데이터 백업("A번 요구사항") - 복구 UX(Layer 3). InitialRouter가
// "스케줄이 아직 없는" 상태(=신규 설치 또는 초기화 직후)에서 이 기기에 저장된
// 백업 파일을 발견하면, 곧바로 OnboardingScreen으로 보내는 대신 이 화면을
// 먼저 보여준다 - main.dart의 InitialRouter._navigate() 참고.
//
// ⚠️ 알람/근무패턴 로직은 전혀 참조하지 않는다 - BackupService.restoreAll()만
// 호출한다(그 함수 자체가 shift_schedule/shift_alarm_templates 등 원본 테이블에
// 값을 채워넣는 것으로 끝나고, 복구 후 앱이 평소처럼 시작되면 기존 알람 갱신
// 로직이 알아서 다시 채움 - 백업복구_설계.md 참고).
//
// ⭐ 2026-09-01 예외 - 딱 하나, AlarmRefreshService.forceRefresh()만 예외적으로
// 부른다(알람 데이터를 직접 건드리는 게 아니라 "지금 다시 계산해" 트리거일
// 뿐). 네이티브 갱신 엔진은 "하루 1번" 쿨다운이 있어서(AlarmRefreshUtil.
// checkAndTriggerRefresh), 복구 직전 이미 오늘 한 번 갱신됐던 상태면 DB
// 내용이 바뀐 걸 못 알아채고 지나갈 수 있음 - "근무표/이력엔 데이터가 있는데
// 다음 알람 탭엔 안 보였다가 한참 후에야 나타났다" 버그의 원인. force로
// 쿨다운을 무시하고 즉시 재생성시켜서 그 공백을 없앰.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n_extensions.dart';
import '../main.dart'; // ⭐ MainScreen import
import '../models/backup_payload.dart';
import '../services/backup_validator.dart';
import '../services/restore_coordinator.dart';
import '../services/database_service.dart';
import '../services/permission_service.dart';
import '../services/update_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_button.dart';
import 'onboarding_screen.dart';
import 'permission_intro_screen.dart';
import 'restore_interrupted_screen.dart';

class RestoreBackupScreen extends StatefulWidget {
  final BackupPayload payload;

  /// ⭐ 2026-09-01 - 백업_수면_컨디션_기능_검토_2026-09-01.md A1 수정. 이 화면은
  /// 원래 "아직 아무 진행 상태도 없는" 지점(InitialRouter/PermissionIntroScreen)
  /// 에서만 왔었는데, onboarding_screen.dart의 "백업 데이터 불러오기" 카드가
  /// 온보딩 1단계(근무명 입력) **도중에** `Navigator.push`로 이 화면을 여는
  /// 두 번째 진입 경로를 만들면서 전제가 깨짐 - "건너뛰기"/빈 백업 실패 시
  /// 항상 새 `OnboardingScreen`을 만들어 스택을 갈아치우다 보니, 이미 입력해둔
  /// 근무명 칩이 전부 초기화되는 문제가 있었음. `onCancel`을 지정하면 실패/취소
  /// 시 그 콜백만 부르고(보통 `Navigator.pop`) 끝냄 - 기존 두 진입 경로(진짜
  /// 신규 설치)는 이 값을 안 넘기므로 동작이 그대로 유지됨.
  final VoidCallback? onCancel;

  const RestoreBackupScreen({super.key, required this.payload, this.onCancel});

  @override
  State<RestoreBackupScreen> createState() => _RestoreBackupScreenState();
}

class _RestoreBackupScreenState extends State<RestoreBackupScreen> {
  bool _restoring = false;

  Future<void> _restore() async {
    setState(() => _restoring = true);
    // ⭐ 2026-09-04 - M2 수정(전체_코드_점검_리포트_2026-09-04.md). restoreAll()의
    // DB 트랜잭션은 이미 커밋됐는데 그 뒤 forceRefresh()/checkPermissions() 등이
    // 예외를 던지면, 커밋 전/후를 구분 안 하고 아래 catch가 무조건 "복구 실패"
    // 토스트를 띄웠음 - 사용자가 실패로 알고 다시 시도하지만 데이터는 이미
    // 되돌릴 수 없이 덮어써진 상태라 오해를 줌. 커밋 완료 여부를 추적해서
    // 커밋 후 실패는 다르게 처리한다.
    var dbCommitted = false;
    try {
      // ⭐ 2026-09-14 (출시전 감사 G4 #19) - 복원은 RestoreCoordinator(검증 → 작업 사본 → 잠금 → OS 정리 → DB/설정 → OS 재조정).
      // 근무 일정이 없는 빈 백업은 시작 전에 걸러 아무것도 바꾸지 않음.
      if (!BackupValidator.hasSchedule(widget.payload)) {
        if (!mounted) return;
        setState(() => _restoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.backupRestoreEmptyToast)),
        );
        if (widget.onCancel != null) {
          widget.onCancel!();
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
            (route) => false,
          );
        }
        return;
      }
      await RestoreCoordinator.instance.start(widget.payload, overwrite: false);
      dbCommitted = true;

      // ⭐ 2026-09-01 - "복구하기 -> 권한화면 -> 다시 백업화면"으로 무한
      // 반복되는 버그를 잡으며 추가한 안전장치. restoreAll()은 예외를 던지지
      // 않아도 "복구할 근무 일정 자체가 백업에 없었던" 경우(예: 근무 일정을
      // 설정하기 전에 백업했거나, 초기화 직후 상태가 자동 백업으로 그 위에
      // 덮어써진 경우)엔 아무 것도 채워넣지 못한 채 "성공"으로 끝난다. 그러면
      // PermissionIntroScreen이 다시 스케줄 없음 -> 백업 파일 있음으로 판단해
      // 이 화면을 또 띄우고, 사용자가 다시 [복구하기]를 눌러도 똑같은 빈 백업이라
      // 영원히 반복된다. 그래서 복구 직후 실제로 스케줄이 채워졌는지 직접
      // 확인하고, 비어있으면 루프를 끊고 곧장 온보딩으로 보낸다.
      final restoredSchedule = await DatabaseService.instance.getShiftSchedule();
      if (restoredSchedule == null) {
        if (!mounted) return;
        setState(() => _restoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.backupRestoreEmptyToast)),
        );
        if (widget.onCancel != null) {
          widget.onCancel!();
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
            (route) => false,
          );
        }
        return;
      }

      // ⭐ 2026-09-08 - "완전 새로 설치하고 백업으로 복구했는데, 메인화면에
      // 들어가자마자 '이번 업데이트는 꼭 확인해주세요'(업데이트 후 첫 실행
      // 안내) 팝업이 떴다"는 신고로 발견한 버그 수정. 이 안내는
      // markOnboardingBaselineVersion()으로 "방금 이 버전으로 막 시작한
      // 사람"이라는 기준선을 남겨야 신규 설치자에게 안 뜨는데, 그 호출이
      // onboarding_screen.dart(근무 설정 마법사를 끝까지 마치는 경로)에만
      // 있었고 이 백업 복구 경로엔 빠져 있었음 - 복구도 "이 기기에서는 방금
      // 막 시작한 것"과 똑같은 의미라 여기도 반드시 남겨야 함. 이후 화면이
      // 곧장 MainScreen으로 가든(아래) PermissionIntroScreen을 한 번 거쳐서
      // 가든(permission_intro_screen.dart의 _navigateToOnboarding, schedule
      // != null 분기) 상관없이 SharedPreferences에 이미 기록된 값이라 적용됨.
      await UpdateService.markOnboardingBaselineVersion();

      // ⭐ 위 import 주석 참고 - 네이티브의 "하루 1번" 갱신 쿨다운을 무시하고
      // 지금 막 바뀐 shift_schedule/shift_alarm_templates 기준으로 alarms
      // 테이블·실제 OS 알람을 즉시 재생성시킴.
      // (알람·일정 알림 재조정은 RestoreCoordinator의 os_reconciled 단계에서 이미 끝남 - 별도 forceRefresh 불필요)

      // ⭐ 2026-09-01 - "복구하기 눌렀더니 권한화면이 잠깐 보였다가 바로 달력으로
      // 넘어간다" 버그 수정. 이 화면은 이제 두 경로에서 온다: (1) 진짜 재설치 -
      // OS 권한(알림/정확한 알람/오버레이)이 실제로 전부 초기화된 상태라 반드시
      // 다시 받아야 함, (2) 온보딩 중 "이전 백업 불러오기" 카드 - 같은 설치
      // 안에서 이미 권한을 다 받았을 수 있는 상태. 예전엔 어느 경로든 무조건
      // permissions_requested를 false로 되돌리고 PermissionIntroScreen으로
      // 보냈는데, (2)처럼 실제 OS 권한이 이미 다 있으면 그 화면이 뜨자마자
      // 자기 스스로(_checkPermissionsAndNavigate) 통과된 걸 감지하고 곧장
      // MainScreen으로 넘어가버려서 "화면이 잠깐 보였다가 사라지는" 깜빡임으로
      // 보였던 것. 이제 실제 OS 권한 상태를 직접 확인해서, 진짜로 없을 때만
      // 권한 화면을 타게 함.
      final permissions = await PermissionService().checkPermissions();
      final osPermissionsGranted =
          permissions['notification']! && permissions['overlay']! && permissions['exactAlarm']!;

      if (!mounted) return;

      if (!osPermissionsGranted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('permissions_requested', false);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PermissionIntroScreen()),
          (route) => false,
        );
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen(initialIndex: kCalendarTabIndex)), // 달력탭
        (route) => false,
      );
    } on BackupValidationException {
      if (!mounted) return;
      setState(() => _restoring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupRestoreInvalidToast)),
      );
    } on RestoreIncompleteException {
      // 작업 기록이 남아 있음 - 이어서 완료 / 지금 데이터로 계속을 바로 묻는다
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RestoreInterruptedScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _restoring = false);

      if (dbCommitted) {
        // ⭐ M2 - DB 복구 자체는 이미 끝난 상태(재시도하면 안 됨). 여기서 예외가
        // 났다는 건 forceRefresh()/checkPermissions() 등 커밋 이후 단계라는
        // 뜻이므로 "복구 실패"라고 하지 않고, OS 권한을 다시 확인하는 안전한
        // 기본 경로(PermissionIntroScreen)로 그대로 보낸다. permissions_requested도
        // 여기서 놓치지 않도록 무조건 초기화(2026-09-01에 고쳤던 것과 같은 종류의
        // 갭이 이 catch 경로로 재발하지 않게 함).
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('permissions_requested', false);
        } catch (_) {}
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PermissionIntroScreen()),
          (route) => false,
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupRestoreFailedToast)),
      );
    }
  }

  void _skip() {
    if (widget.onCancel != null) {
      widget.onCancel!();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (route) => false,
    );
  }

  String _formatDate(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    // ⭐ 2026-09-14 (출시전 교차 검토 X-02) - 복원 중 뒤로가기로 화면을 벗어나 앱을 닫거나 다른 화면에서 데이터를 고치지 못하게 함
    return PopScope(
      canPop: !_restoring,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.restore, size: 64, color: kAppMainAccent),
                const SizedBox(height: 24),
                Text(
                  context.l10n.backupRestoreFoundTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.backupRestoreFoundDesc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.backupRestoreLastSavedAt(_formatDate(widget.payload.exportedAt)),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black45),
                ),
                const SizedBox(height: 36),
                if (_restoring)
                  Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(context.l10n.backupRestoreInProgress),
                    ],
                  )
                else ...[
                  AppButton(
                    onPressed: _restore,
                    child: Text(context.l10n.backupRestoreButton),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _skip,
                    child: Text(context.l10n.backupRestoreSkipButton),
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
