import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/services/friend_share_protocol.dart';
import 'package:shiftbell/services/friend_sync_service.dart';
import 'package:shiftbell/services/backup_policy.dart';

class MemoryTransport implements FriendShareTransport {
  Map<String, dynamic>? document;
  bool offline = false;
  Completer<void>? gate;
  Completer<void>? ack;
  final operations = <FriendShareWrite>[];
  @override
  Future<void> write(String owner, FriendShareWrite op,
      Future<bool> Function() isCurrent) async {
    operations.add(op);
    final wait = gate;
    gate = null;
    if (wait != null) await wait.future;
    if (offline) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    if (!await isCurrent()) throw FriendShareSuperseded();
    document = planFriendShareWrite(document, op) ?? document;
    final confirmation = ack;
    ack = null;
    if (confirmation != null) await confirmation.future;
  }
}

ShiftSchedule schedule([String shift = 'Day']) => ShiftSchedule(
    isRegular: true,
    pattern: [shift, 'Off'],
    todayIndex: 0,
    startDate: DateTime(2026, 10, 4),
    shiftTypes: [shift, 'Off']);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryTransport backend;
  late FriendSyncService service;
  FriendSyncService makeService() => FriendSyncService.forTesting(
      transport: backend,
      ownerId: () async => 'owner',
      submissionWait: const Duration(milliseconds: 20));
  setUp(() {
    binding.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    SharedPreferences.setMockInitialValues({});
    backend = MemoryTransport();
    service = makeService();
  });
  tearDown(() => binding.platformDispatcher.clearLocaleTestValue());

  test(
      'start/edit/dedupe/stop removes every schedule field; new share gets higher server generation',
      () async {
    expect(await service.startSharing(schedule: schedule(), ownerName: 'Owner'),
        'owner');
    final first = Map<String, dynamic>.from(backend.document!);
    await service.syncIfEnabled(schedule());
    expect(backend.operations, hasLength(1));
    await service.syncIfEnabled(schedule('Night'));
    expect(backend.document!['generation'], first['generation']);
    expect(
        backend.document!['revision'], greaterThan(first['revision'] as int));
    await service.stopSharing();
    expect(backend.document!.keys.toSet(), {
      'protocolVersion',
      'session',
      'generation',
      'revision',
      'revoked',
      'updatedAt'
    });
    expect((await service.getShareState()).intent, FriendShareIntent.off);
    expect(await service.startSharing(schedule: schedule(), ownerName: 'Owner'),
        'owner');
    expect(backend.document!['generation'],
        greaterThan(first['generation'] as int));
    expect(backend.document!['session'], isNot(first['session']));
  });

  test(
      'offline stop survives service restart and no schedule/English; reconnect retries tombstone',
      () async {
    await service.startSharing(schedule: schedule(), ownerName: 'Owner');
    backend.offline = true;
    await service.stopSharing();
    expect(
        (await service.getShareState()).intent, FriendShareIntent.stopPending);
    service = makeService();
    await service.syncIfEnabled(schedule('New'));
    expect(backend.document!['revoked'], false);
    binding.platformDispatcher.localeTestValue = const Locale('en', 'US');
    backend.offline = false;
    await service.onAppStarted(null);
    expect(backend.document!['revoked'], true);
    expect((await service.getShareState()).intent, FriendShareIntent.off);
  });

  test('late upload after offline stop cannot resurrect or clear pending',
      () async {
    await service.startSharing(schedule: schedule(), ownerName: 'Owner');
    final gate = Completer<void>();
    backend.gate = gate;
    await service.syncIfEnabled(schedule('Old queued'));
    backend.offline = true;
    await service.stopSharing();
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
        (await service.getShareState()).intent, FriendShareIntent.stopPending);
    backend.offline = false;
    await service.onNetworkReconnected(null);
    expect(backend.document!['revoked'], true);
  });

  test('late stop after immediate re-share cannot revoke the new session',
      () async {
    await service.startSharing(schedule: schedule(), ownerName: 'Owner');
    final gate = Completer<void>();
    backend.gate = gate;
    await service.stopSharing();
    await service.startSharing(
        schedule: schedule('New'), ownerName: 'New owner');
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(backend.document!['ownerName'], 'New owner');
    expect(backend.document!['revoked'], false);
    expect((await service.getShareState()).intent, FriendShareIntent.active);
  });

  test('A -> B -> A late ACK cannot confirm the new A revision', () async {
    await service.startSharing(schedule: schedule(), ownerName: 'Owner');
    final ack = Completer<void>();
    backend.ack = ack;
    await service.syncIfEnabled(schedule('B'));
    backend.offline = true;
    await service.syncIfEnabled(schedule());
    ack.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect((await service.getShareState()).dirty, true);
    backend.offline = false;
    await service.retryPending(schedule());
    expect((await service.getShareState()).dirty, false);
    expect(backend.document!['pattern'], ['Day', 'Off']);
  });

  test(
      'lost local generation: automatic resume denied, explicit start recovers above server',
      () async {
    await service.startSharing(schedule: schedule(), ownerName: 'Owner');
    await service.stopSharing();
    backend.document!['generation'] = 50;
    SharedPreferences.setMockInitialValues(
        {'friend_share_enabled': true, 'friend_share_my_name': 'Old'});
    service = makeService();
    await service.onAppStarted(schedule());
    expect(backend.document!['revoked'], true);
    expect((await service.getShareState()).intent, FriendShareIntent.off);
    await service.startSharing(schedule: schedule(), ownerName: 'Recovered');
    expect(backend.document!['generation'], 51);
    expect(backend.document!['ownerName'], 'Recovered');
  });

  test(
      'legacy active migration uses existing link and higher generation, without explicit opt-in',
      () async {
    backend.document = {
      'generation': 9,
      'revoked': false,
      'ownerName': 'Legacy'
    };
    SharedPreferences.setMockInitialValues({
      'friend_share_enabled': true,
      'friend_share_generation': 2,
      'friend_share_my_name': 'Owner'
    });
    await service.onAppStarted(schedule());
    expect(backend.document!['protocolVersion'], 2);
    expect(backend.document!['generation'], 10);
    expect((await service.getShareState()).dirty, false);
  });

  test(
      'stale revision and same-session restart after tombstone fail even without local callback',
      () async {
    await service.startSharing(schedule: schedule(), ownerName: 'Owner');
    final old = backend.operations.single;
    await service.syncIfEnabled(schedule('Night'));
    expect(() => planFriendShareWrite(backend.document, old),
        throwsA(isA<FriendShareSuperseded>()));
    await service.stopSharing();
    expect(() => planFriendShareWrite(backend.document, old),
        throwsA(isA<FriendShareSuperseded>()));
  });

  test(
      'durable v2 record excluded from backup and malformed record never auto-resumes',
      () async {
    expect(isBackupPreferenceKey('friend_share_state_v2'), false);
    expect(FriendSyncService.backupExcludedPreferenceKeys,
        contains('friend_share_state_v2'));
    SharedPreferences.setMockInitialValues(
        {'friend_share_state_v2': 'broken', 'friend_share_enabled': true});
    await service.onAppStarted(schedule()).catchError((_) {});
    expect(backend.operations, isEmpty);
  });

  test('unchanged payload retry after lost ACK is idempotent', () async {
    final ack = Completer<void>();
    backend.ack = ack;
    await service.startSharing(schedule: schedule(), ownerName: 'Owner');
    final before = Map<String, dynamic>.from(backend.document!);
    service = makeService();
    await service.onAppStarted(schedule());
    expect(backend.document, before);
    expect((await service.getShareState()).dirty, false);
    ack.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
}
