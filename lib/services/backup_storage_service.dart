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

class BackupStorageService {
  BackupStorageService._();
  static final BackupStorageService instance = BackupStorageService._();

  static const _channel = kAlarmChannel;

  /// 백업 JSON 문자열을 기기 저장소에 씀(항상 같은 파일 하나를 덮어씀).
  /// Android 10(Q) 미만 기기에서는 지원 안 함 - false 반환.
  Future<bool> write(String jsonContent) async {
    try {
      final result = await _channel
          .invokeMethod<bool>('writeBackupFile', {'content': jsonContent});
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 기기에 저장된 백업 JSON 문자열을 읽어옴. 없거나 미지원 기기면 null.
  Future<String?> read() async {
    try {
      return await _channel.invokeMethod<String>('readBackupFile');
    } catch (e) {
      return null;
    }
  }

  /// ⭐ 2026-09-01 - [read]의 자동 탐지(MediaStore 쿼리)가 일부 기기(확인된 사례:
  /// 삼성 기기 - MediaStore가 저장한 행의 owner_package_name이 NULL로 남는
  /// OEM 버그로 추정, 우리 쪽 쿼리 코드로는 못 고침)에서 실패하는 게 확인돼서
  /// 추가한 수동 대안. 시스템 파일 선택기(SAF)를 띄워 사용자가 직접
  /// Downloads/ShiftBell/shiftbell_backup.json을 고르게 함 - 사용자가 명시적으로
  /// 고른 파일에 대한 접근 권한은 그 자리에서 새로 받기 때문에 소유권 메타데이터
  /// 버그와 무관하게 항상 동작함. 사용자가 취소하거나 읽기 실패하면 null.
  Future<String?> pickAndRead() async {
    try {
      return await _channel.invokeMethod<String>('pickBackupFile');
    } catch (e) {
      return null;
    }
  }
}
