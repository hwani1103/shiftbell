// services/friend_sync_service.dart
//
// 친구 공유의 로컬 의도와 Firestore 제출을 한 곳에서 직렬화한다. Firestore의
// offline write Future는 서버 ACK까지 오래 끝나지 않을 수 있으므로 제한 시간 뒤에도
// dirty를 유지하고 다음 작업(특히 공유 중지)을 제출한다. 제한 시간은 제출 취소가 아니다.
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/friend_schedule.dart';
import '../models/shift_schedule.dart';
import 'firebase_bootstrap.dart';
import 'friend_share_service.dart';

enum FriendShareIntent { off, active, stopPending }

enum FriendSyncOutcome { confirmed, pending, rejected, skipped }

enum FriendFetchStatus { found, notFound, revoked, unavailable, invalid }

class FriendShareState {
  final FriendShareIntent intent;
  final bool dirty;
  final int generation;

  const FriendShareState({
    required this.intent,
    required this.dirty,
    required this.generation,
  });

  bool get isActive => intent == FriendShareIntent.active;
}

class FriendFetchResult {
  final FriendFetchStatus status;
  final FriendScheduleData? data;

  const FriendFetchResult._(this.status, [this.data]);

  const FriendFetchResult.found(FriendScheduleData data)
      : this._(FriendFetchStatus.found, data);
  const FriendFetchResult.notFound()
      : this._(FriendFetchStatus.notFound);
  const FriendFetchResult.revoked()
      : this._(FriendFetchStatus.revoked);
  const FriendFetchResult.unavailable()
      : this._(FriendFetchStatus.unavailable);
  const FriendFetchResult.invalid()
      : this._(FriendFetchStatus.invalid);

  bool get serverConfirmedUnavailable =>
      status == FriendFetchStatus.notFound || status == FriendFetchStatus.revoked;
}

class FriendSyncService {
  FriendSyncService._();
  static final instance = FriendSyncService._();

  static const _kEnabledKey = 'friend_share_enabled';
  static const _kMyNameKey = 'friend_share_my_name';
  static const _kIntentKey = 'friend_share_intent';
  static const _kDirtyKey = 'friend_share_dirty';
  static const _kGenerationKey = 'friend_share_generation';
  static const _kDesiredFingerprintKey =
      'friend_share_desired_fingerprint';
  static const _kConfirmedFingerprintKey =
      'friend_share_confirmed_fingerprint';

  /// G4 복원에서 제외해야 한다. UID가 바뀐 설치에 옛 공유 의도나 회차를 이식하면 안 된다.
  static const backupExcludedPreferenceKeys = <String>{
    _kEnabledKey,
    _kMyNameKey,
    _kIntentKey,
    _kDirtyKey,
    _kGenerationKey,
    _kDesiredFingerprintKey,
    _kConfirmedFingerprintKey,
  };

  static const _submissionWait = Duration(seconds: 5);

  Future<void> _serialTail = Future<void>.value();
  Future<String?>? _ownerIdInFlight;

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('friend_schedules');

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serialTail = _serialTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _requireWrite(Future<bool> write, String key) async {
    if (!await write) {
      throw StateError('공유 상태 저장 실패: $key');
    }
  }

  FriendShareIntent _parseIntent(String? raw, bool legacyEnabled) {
    switch (raw) {
      case 'active':
        return FriendShareIntent.active;
      case 'stop_pending':
        return FriendShareIntent.stopPending;
      case 'off':
        return FriendShareIntent.off;
      default:
        return legacyEnabled ? FriendShareIntent.active : FriendShareIntent.off;
    }
  }

  String _intentValue(FriendShareIntent intent) {
    switch (intent) {
      case FriendShareIntent.active:
        return 'active';
      case FriendShareIntent.stopPending:
        return 'stop_pending';
      case FriendShareIntent.off:
        return 'off';
    }
  }

  /// 기존 enabled 플래그만 있는 설치도 active 회차 1로 안전하게 올린다.
  Future<FriendShareState> getShareState() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyEnabled = prefs.getBool(_kEnabledKey) ?? false;
    final storedIntent = prefs.getString(_kIntentKey);
    final intent = _parseIntent(storedIntent, legacyEnabled);
    var generation = prefs.getInt(_kGenerationKey) ?? 0;
    var dirty = prefs.getBool(_kDirtyKey) ?? false;

    if (storedIntent == null) {
      if (intent == FriendShareIntent.active && generation < 1) {
        generation = 1;
        dirty = true;
        await _requireWrite(prefs.setInt(_kGenerationKey, generation),
            _kGenerationKey);
        await _requireWrite(prefs.setBool(_kDirtyKey, true), _kDirtyKey);
      }
      await _requireWrite(
          prefs.setString(_kIntentKey, _intentValue(intent)), _kIntentKey);
    }

    return FriendShareState(
      intent: intent,
      dirty: dirty,
      generation: generation,
    );
  }

  Future<String?> getOrCreateOwnerId() async {
    if (!firebaseReady) return null;
    final existing = FirebaseAuth.instance.currentUser;
    if (existing != null) return existing.uid;
    if (_ownerIdInFlight != null) return _ownerIdInFlight!;

    final completer = Completer<String?>();
    _ownerIdInFlight = completer.future;
    try {
      final credential = await FirebaseAuth.instance.signInAnonymously();
      completer.complete(credential.user?.uid);
    } catch (error) {
      print('⚠️ 친구공유 익명 로그인 실패: $error');
      completer.complete(null);
    } finally {
      _ownerIdInFlight = null;
    }
    return completer.future;
  }

  Future<bool> isSharingEnabled() async => (await getShareState()).isActive;

  Future<String?> savedMyName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kMyNameKey);
  }

  Map<String, dynamic> _activePayload(
    ShiftSchedule schedule,
    String ownerName,
    int generation,
  ) {
    return <String, dynamic>{
      'ownerName': ownerName,
      'isRegular': schedule.isRegular,
      'pattern': schedule.pattern,
      'todayIndex': schedule.todayIndex,
      'startDate': schedule.startDate?.toIso8601String(),
      'shiftColors': schedule.shiftColors ?? <String, int>{},
      'assignedDates': schedule.assignedDates ?? <String, String>{},
      'generation': generation,
      'revoked': false,
    };
  }

  dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }

  String _fingerprint(Map<String, dynamic> payload) =>
      jsonEncode(_canonicalize(payload));

  bool _validActivePayload(Map<String, dynamic> payload) {
    final validModel = FriendScheduleData.tryFromJson(<String, dynamic>{
          ...payload,
          'updatedAt': DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        }) != null;
    if (!validModel) return false;
    // Firestore 1 MiB 문서 한도 직전까지 보내지 않도록 timestamp 여유를 남긴다.
    return utf8.encode(jsonEncode(_canonicalize(payload))).length <= 800 * 1024;
  }

  Future<void> _markDesired(
    SharedPreferences prefs,
    String fingerprint,
  ) async {
    await _requireWrite(
        prefs.setString(_kDesiredFingerprintKey, fingerprint),
        _kDesiredFingerprintKey);
    await _requireWrite(prefs.setBool(_kDirtyKey, true), _kDirtyKey);
  }

  Future<void> _confirmActive(int generation, String fingerprint) async {
    final state = await getShareState();
    final prefs = await SharedPreferences.getInstance();
    if (state.intent != FriendShareIntent.active ||
        state.generation != generation ||
        prefs.getString(_kDesiredFingerprintKey) != fingerprint) {
      return;
    }
    await _requireWrite(
        prefs.setString(_kConfirmedFingerprintKey, fingerprint),
        _kConfirmedFingerprintKey);
    await _requireWrite(prefs.setBool(_kDirtyKey, false), _kDirtyKey);
  }

  Future<void> _confirmStopped(int generation) async {
    final state = await getShareState();
    if (state.intent != FriendShareIntent.stopPending ||
        state.generation != generation) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await _requireWrite(prefs.setBool(_kEnabledKey, false), _kEnabledKey);
    await _requireWrite(prefs.setBool(_kDirtyKey, false), _kDirtyKey);
    await _requireWrite(
        prefs.setString(_kIntentKey, _intentValue(FriendShareIntent.off)),
        _kIntentKey);
  }

  Future<FriendSyncOutcome> _observeWrite(
    Future<void> write,
    Future<void> Function() onConfirmed,
    String label,
  ) async {
    try {
      await write.timeout(_submissionWait);
      await onConfirmed();
      return FriendSyncOutcome.confirmed;
    } on TimeoutException {
      // Firestore가 이미 받은 offline write는 취소할 수 없다. 완료 콜백은 최신
      // intent/generation/fingerprint를 다시 검사하므로 옛 작업이 dirty를 지우지 못한다.
      unawaited(write.then((_) => onConfirmed()).catchError((Object error) {
        print('⚠️ 친구공유 $label 지연 제출 실패: $error');
      }));
      return FriendSyncOutcome.pending;
    } catch (error) {
      print('⚠️ 친구공유 $label 제출 실패: $error');
      return FriendSyncOutcome.rejected;
    }
  }

  Future<FriendSyncOutcome> _submitActive(
    ShiftSchedule schedule,
    String ownerName,
    int generation,
  ) {
    final payload = _activePayload(schedule, ownerName, generation);
    if (!_validActivePayload(payload)) {
      print('⚠️ 친구공유 업로드 거부: 허용 범위를 벗어난 스케줄 데이터');
      return Future.value(FriendSyncOutcome.rejected);
    }
    final fingerprint = _fingerprint(payload);
    return _enqueue(() async {
      final state = await getShareState();
      final prefs = await SharedPreferences.getInstance();
      if (state.intent != FriendShareIntent.active ||
          state.generation != generation ||
          prefs.getString(_kDesiredFingerprintKey) != fingerprint) {
        return FriendSyncOutcome.skipped;
      }
      if (!firebaseReady) return FriendSyncOutcome.pending;
      final ownerId = await getOrCreateOwnerId();
      if (ownerId == null) return FriendSyncOutcome.pending;

      // 실제 set 직전에 다시 검사한다. queued 작업이 기다리는 동안 stop/새 회차가
      // 들어왔다면 옛 payload를 SDK에 넘기지 않는다.
      final latest = await getShareState();
      final latestPrefs = await SharedPreferences.getInstance();
      if (latest.intent != FriendShareIntent.active ||
          latest.generation != generation ||
          latestPrefs.getString(_kDesiredFingerprintKey) != fingerprint) {
        return FriendSyncOutcome.skipped;
      }
      final serverPayload = <String, dynamic>{
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      return _observeWrite(
        _col.doc(ownerId).set(serverPayload),
        () => _confirmActive(generation, fingerprint),
        '업로드',
      );
    });
  }

  Future<String?> startSharing({
    required ShiftSchedule schedule,
    required String ownerName,
  }) async {
    final normalizedName = ownerName.trim();
    if (normalizedName.isEmpty || !firebaseReady) return null;
    final ownerId = await getOrCreateOwnerId();
    if (ownerId == null) return null;

    final before = await getShareState();
    final generation = before.intent == FriendShareIntent.active
        ? before.generation
        : before.generation + 1;
    final payload = _activePayload(schedule, normalizedName, generation);
    if (!_validActivePayload(payload)) return null;
    final fingerprint = _fingerprint(payload);
    final prefs = await SharedPreferences.getInstance();
    await _requireWrite(
        prefs.setInt(_kGenerationKey, generation), _kGenerationKey);
    await _requireWrite(
        prefs.setString(_kMyNameKey, normalizedName), _kMyNameKey);
    await _markDesired(prefs, fingerprint);
    await _requireWrite(prefs.setBool(_kEnabledKey, true), _kEnabledKey);
    await _requireWrite(
        prefs.setString(_kIntentKey, _intentValue(FriendShareIntent.active)),
        _kIntentKey);

    final outcome =
        await _submitActive(schedule, normalizedName, generation);
    return outcome == FriendSyncOutcome.rejected ? null : ownerId;
  }

  Future<void> syncIfEnabled(ShiftSchedule? schedule) async {
    try {
      if (schedule == null) return;
      final state = await getShareState();
      if (state.intent != FriendShareIntent.active) return;
      final prefs = await SharedPreferences.getInstance();
      final ownerName = prefs.getString(_kMyNameKey) ?? '';
      final payload = _activePayload(schedule, ownerName, state.generation);
      if (!_validActivePayload(payload)) {
        print('⚠️ 친구공유 동기화 보류: 허용 범위를 벗어난 스케줄 데이터');
        await _requireWrite(prefs.setBool(_kDirtyKey, true), _kDirtyKey);
        return;
      }
      final fingerprint = _fingerprint(payload);
      final alreadyConfirmed =
          prefs.getString(_kConfirmedFingerprintKey) == fingerprint;
      if (alreadyConfirmed && !state.dirty) return;

      await _markDesired(prefs, fingerprint);
      await _submitActive(schedule, ownerName, state.generation);
    } catch (error) {
      // schedule 저장 호출자는 이 Future를 기다리지 않는 경로도 있다. 로컬 저장을
      // 실패로 만들지 않고 dirty를 다음 재시도에 남긴다.
      print('⚠️ 친구공유 동기화 상태 저장 실패: $error');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kDirtyKey, true);
      } catch (_) {}
    }
  }

  Future<bool> updateMyName({
    required String newName,
    required ShiftSchedule schedule,
  }) async {
    final normalizedName = newName.trim();
    if (normalizedName.isEmpty) return false;
    final state = await getShareState();
    if (state.intent != FriendShareIntent.active) return false;
    final payload =
        _activePayload(schedule, normalizedName, state.generation);
    if (!_validActivePayload(payload)) return false;
    final prefs = await SharedPreferences.getInstance();
    await _requireWrite(
        prefs.setString(_kMyNameKey, normalizedName), _kMyNameKey);
    final fingerprint = _fingerprint(payload);
    await _markDesired(prefs, fingerprint);
    final outcome =
        await _submitActive(schedule, normalizedName, state.generation);
    return outcome == FriendSyncOutcome.confirmed;
  }

  /// 로컬에서는 호출 즉시 off로 보이고, 서버 delete 확인 전에는 stop_pending이다.
  /// D7 후속 선택 전이므로 이번 단계는 기존 서버 형식과 호환되는 delete를 유지한다.
  Future<void> stopSharing() async {
    final state = await getShareState();
    final prefs = await SharedPreferences.getInstance();
    await _requireWrite(
        prefs.setString(
            _kIntentKey, _intentValue(FriendShareIntent.stopPending)),
        _kIntentKey);
    await _requireWrite(prefs.setBool(_kEnabledKey, false), _kEnabledKey);
    await _requireWrite(prefs.setBool(_kDirtyKey, true), _kDirtyKey);
    await _submitStop(state.generation);
  }

  Future<FriendSyncOutcome> _submitStop(int generation) {
    return _enqueue(() async {
      if (!firebaseReady) return FriendSyncOutcome.pending;
      final ownerId = await getOrCreateOwnerId();
      if (ownerId == null) return FriendSyncOutcome.pending;

      // 이 delete는 큐에서 이후 새 회차 set보다 먼저 SDK에 제출된다. 서버 완료가
      // 늦어도 Firestore의 같은 클라이언트 write 순서가 새 회차를 마지막에 둔다.
      return _observeWrite(
        _col.doc(ownerId).delete(),
        () => _confirmStopped(generation),
        '중지',
      );
    });
  }

  Future<void> retryPending(ShiftSchedule? currentSchedule) async {
    final state = await getShareState();
    if (state.intent == FriendShareIntent.stopPending) {
      await _submitStop(state.generation);
      return;
    }
    if (state.intent == FriendShareIntent.active && currentSchedule != null) {
      await syncIfEnabled(currentSchedule);
    }
  }

  Future<void> onAppStarted(ShiftSchedule? currentSchedule) =>
      retryPending(currentSchedule);
  Future<void> onAppResumed(ShiftSchedule? currentSchedule) =>
      retryPending(currentSchedule);
  Future<void> onNetworkReconnected(ShiftSchedule? currentSchedule) =>
      retryPending(currentSchedule);

  /// G4는 복원 전 UID/generation/intent를 유지한 뒤 이 진입점만 호출한다.
  Future<void> onRestoreCompleted(ShiftSchedule? restoredSchedule) async {
    final state = await getShareState();
    if (state.intent == FriendShareIntent.active) {
      final prefs = await SharedPreferences.getInstance();
      await _requireWrite(prefs.setBool(_kDirtyKey, true), _kDirtyKey);
    }
    await retryPending(restoredSchedule);
  }

  /// 서버 강제 조회 결과를 notFound/revoked/offline·오류로 구분한다.
  Future<FriendFetchResult> fetchByOwnerIdDetailed(String ownerId) async {
    if (!firebaseReady || !FriendShareService.isValidOwnerId(ownerId)) {
      return const FriendFetchResult.unavailable();
    }
    try {
      final snapshot = await _col
          .doc(ownerId)
          .get(const GetOptions(source: Source.server));
      final raw = snapshot.data();
      if (!snapshot.exists || raw == null) {
        return const FriendFetchResult.notFound();
      }
      if (raw['revoked'] == true) {
        return const FriendFetchResult.revoked();
      }

      final updatedAtRaw = raw['updatedAt'];
      final updatedAtIso = updatedAtRaw is Timestamp
          ? updatedAtRaw.toDate().toIso8601String()
          : null;
      final data = FriendScheduleData.tryFromJson(<String, dynamic>{
        'ownerName': raw['ownerName'],
        'isRegular': raw['isRegular'],
        'pattern': raw['pattern'],
        'todayIndex': raw['todayIndex'],
        'startDate': raw['startDate'],
        'shiftColors': raw['shiftColors'],
        'assignedDates': raw['assignedDates'],
        'updatedAt': updatedAtIso,
      });
      return data == null
          ? const FriendFetchResult.invalid()
          : FriendFetchResult.found(data);
    } catch (error) {
      print('⚠️ 친구 스케줄 서버 조회 실패: $error');
      return const FriendFetchResult.unavailable();
    }
  }

  /// 웹뷰어 등 기존 호출자 호환. 상세 구분이 필요한 앱 캐시는 detailed API를 쓴다.
  Future<FriendScheduleData?> fetchByOwnerId(String ownerId) async {
    final result = await fetchByOwnerIdDetailed(ownerId);
    return result.data;
  }
}
