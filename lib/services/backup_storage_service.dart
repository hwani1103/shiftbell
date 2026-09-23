// lib/services/backup_storage_service.dart
//
// ⭐ 사용자 데이터 백업("A번 요구사항") - 저장소 연동(Layer 2). 백업복구_설계.md
// 4장에서 결정한 대로 클라우드/로그인 없이 기기 로컬(MediaStore, Downloads/
// ShiftBell 폴더)에만 저장한다. 실제 파일 I/O는 Native(MainActivity.kt의
// writeBackupFile/readBackupFile)가 하고, 이 파일은 그 MethodChannel을 감싸는
// 얇은 래퍼일 뿐 - CLAUDE.md 규칙대로 채널은 kAlarmChannel 하나만 씀(새 채널 안 만듦).
//
// ⚠️ backup_service.dart(BackupPayload 조립/복원)와 마찬가지로 알람/근무패턴
// 로직은 전혀 참조하지 않는다.

import '../constants/platform_channel.dart';
import '../models/backup_payload.dart';
import 'backup_validator.dart';
import 'database_service.dart';

/// ⭐ 2026-09-23 (1.0.24 A) - 백업 파일 슬롯. 직접(설정의 "데이터 백업")과 자동이 각각 1개씩만 남고,
/// 새로 만들면 **같은 종류만** 교체됨(네이티브 BackupFileNaming.kt).
enum BackupKind {
  manual('manual'),
  auto('auto');

  const BackupKind(this.channelArg);
  final String channelArg;
}

class BackupStorageService {
  BackupStorageService._();
  static final BackupStorageService instance = BackupStorageService._();

  static const _channel = kAlarmChannel;

  /// 자동 탐지에서 최신순으로 확인할 최대 후보 수(네이티브는 직접·자동 슬롯 2개를 남기지만, 1.0.23 이하 옛 형식 파일까지 고려).
  static const _maxCandidates = 5;

  /// 백업 JSON 문자열을 [kind] 슬롯에 씀. 네이티브가 공개 전에 다시 읽어 확인하고, 성공하면 같은 종류의 옛 파일만 정리함.
  /// Android 10(Q) 미만 기기에서는 지원 안 함 - false 반환.
  Future<bool> write(String jsonContent, {required BackupKind kind}) async {
    try {
      final result = await _channel.invokeMethod<bool>(
          'writeBackupFile', {'content': jsonContent, 'kind': kind.channelArg});
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 기기에 저장된 백업 중 복원에 쓸 수 있는 가장 최근 것의 JSON. 없거나 미지원 기기면 null.
  ///
  /// ⭐ 2026-09-14 (출시전 교차 검토 X-07) - 예전엔 네이티브가 "schemaVersion + tables 형식인 첫 파일"에서 멈춰서, 최신 파일이
  /// 형식만 맞고 실제로는 비었거나 검증에 실패하면 더 오래된 정상 백업을 찾지 않았음. 이제 후보를 최신순으로 하나씩 받아
  /// 디코딩 → 근무 일정 존재 → 현재 스키마 기준 검증(BackupValidator)까지 통과한 첫 파일을 고름.
  Future<String?> read() async {
    for (var skip = 0; skip < _maxCandidates; skip++) {
      final String? content;
      try {
        content = await _channel.invokeMethod<String>('readBackupFile', {'skip': skip});
      } catch (e) {
        return null;
      }
      if (content == null) return null;
      if (await _isRestorable(content)) return content;
    }
    return null;
  }

  Future<bool> _isRestorable(String content) async {
    final payload = BackupPayload.tryDecode(content);
    if (payload == null || !BackupValidator.hasSchedule(payload)) return false;
    try {
      final db = await DatabaseService.instance.database;
      return (await BackupValidator.validate(payload, db)).isEmpty;
    } catch (_) {
      return false;
    }
  }

  /// ⭐ 2026-09-01 - [read]의 자동 탐지(MediaStore 쿼리)가 실기기에서 실패하는 것이 확인돼 추가한
  /// 수동 대안. 시스템 파일 선택기(SAF)를 띄워 사용자가 Download/ShiftBell/의 백업 파일을 직접
  /// 고르게 함 - 사용자가 명시적으로 고른 파일은 그 자리에서 접근 권한을 받으므로 소유권 메타데이터와
  /// 무관하게 항상 동작함. 사용자가 취소하거나 읽기 실패하면 null.
  ///
  /// ⭐ 2026-09-17 정정 - 자동 탐지가 실패하는 진짜 이유는 그동안 적어 둔 "삼성 OEM 버그"가 아니라,
  /// 앱을 삭제하면 MediaStore가 그 앱이 만든 행의 owner_package_name을 비우기 때문이다(파일은 남음).
  /// 이 앱은 저장소 권한이 없고 스코프드 스토리지라 자기가 소유한 파일만 보이므로,
  /// **앱을 지우고 다시 깔 때는 이전 백업을 자동으로 못 찾는 게 정상**이고, 이 수동 선택이 유일한 경로다.
  /// 측정값·근거는 MainActivity.readBackupFile() 주석의 "2026-09-17 정정" 참고.
  Future<String?> pickAndRead() async {
    try {
      return await _channel.invokeMethod<String>('pickBackupFile');
    } catch (e) {
      return null;
    }
  }
}
