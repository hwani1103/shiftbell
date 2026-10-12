// Durable sharing intent and server-enforced, non-deletable revocation records.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/friend_schedule.dart';
import '../models/shift_schedule.dart';
import 'diag_log.dart';
import 'firebase_bootstrap.dart';
import 'friend_share_service.dart';
import 'friend_share_protocol.dart';

enum FriendShareIntent { off, active, stopPending }

enum FriendSyncOutcome { confirmed, pending, rejected, skipped }

enum FriendFetchStatus { found, notFound, revoked, unavailable, invalid }

class FriendShareState {
  const FriendShareState(
      {required this.intent, required this.dirty, required this.generation});
  final FriendShareIntent intent;
  final bool dirty;
  final int generation;
  bool get isActive => intent == FriendShareIntent.active;
}

class FriendFetchResult {
  const FriendFetchResult._(this.status, [this.data]);
  const FriendFetchResult.found(FriendScheduleData data)
      : this._(FriendFetchStatus.found, data);
  const FriendFetchResult.notFound() : this._(FriendFetchStatus.notFound);
  const FriendFetchResult.revoked() : this._(FriendFetchStatus.revoked);
  const FriendFetchResult.unavailable() : this._(FriendFetchStatus.unavailable);
  const FriendFetchResult.invalid() : this._(FriendFetchStatus.invalid);
  final FriendFetchStatus status;
  final FriendScheduleData? data;
  bool get serverConfirmedUnavailable =>
      status == FriendFetchStatus.notFound ||
      status == FriendFetchStatus.revoked;
}

class _LocalShare {
  _LocalShare(
      {required this.intent,
      required this.generation,
      required this.session,
      this.revision = 0,
      this.dirty = false,
      this.explicitStart = false,
      this.name = '',
      this.desired,
      this.confirmed});
  FriendShareIntent intent;
  int generation;
  String session;
  int revision;
  bool dirty;
  bool explicitStart;
  String name;
  String? desired;
  String? confirmed;

  factory _LocalShare.fromJson(Map<String, dynamic> value) => _LocalShare(
      intent: FriendShareIntent.values.byName(value['intent'] as String),
      generation: value['generation'] as int,
      session: value['session'] as String,
      revision: value['revision'] as int,
      dirty: value['dirty'] as bool,
      explicitStart: value['explicitStart'] as bool,
      name: value['name'] as String,
      desired: value['desired'] as String?,
      confirmed: value['confirmed'] as String?);
  Map<String, dynamic> toJson() => {
        'intent': intent.name,
        'generation': generation,
        'session': session,
        'revision': revision,
        'dirty': dirty,
        'explicitStart': explicitStart,
        'name': name,
        'desired': desired,
        'confirmed': confirmed
      };
  bool matches(FriendShareWrite operation) =>
      session == operation.session &&
      revision == operation.revision &&
      generation == operation.generation &&
      intent ==
          (operation.stop
              ? FriendShareIntent.stopPending
              : FriendShareIntent.active);
}

class FriendSyncService {
  FriendSyncService._()
      : _transport = FirestoreFriendShareTransport(),
        _ownerOverride = null,
        _submissionWait = const Duration(seconds: 5);
  @visibleForTesting
  FriendSyncService.forTesting(
      {required FriendShareTransport transport,
      required Future<String?> Function() ownerId,
      Duration submissionWait = const Duration(seconds: 5)})
      : _transport = transport,
        _ownerOverride = ownerId,
        _submissionWait = submissionWait;
  static final instance = FriendSyncService._();
  final FriendShareTransport _transport;
  final Future<String?> Function()? _ownerOverride;
  final Duration _submissionWait;
  bool get _ready => _ownerOverride != null || firebaseReady;
  bool get _sharingAvailable =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ko';
  static const _localKey = 'friend_share_state_v2';
  static const backupExcludedPreferenceKeys = <String>{
    'friend_share_enabled',
    'friend_share_my_name',
    'friend_share_intent',
    'friend_share_dirty',
    'friend_share_generation',
    'friend_share_desired_fingerprint',
    'friend_share_confirmed_fingerprint',
    _localKey,
  };
  Future<void>? _localTail;
  bool _localCacheNeedsReload = false;
  Future<void>? _networkTail;
  Future<String?>? _ownerIdInFlight;
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('friend_schedules');

  Future<T> _local<T>(Future<T> Function(_LocalShare state) action) async {
    final previous = _localTail;
    final released = Completer<void>();
    _localTail = released.future;
    try {
      if (previous != null) await previous;
      return await action(await _load());
    } finally {
      released.complete();
      if (identical(_localTail, released.future)) _localTail = null;
    }
  }

  Future<_LocalShare> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_localCacheNeedsReload) {
      await prefs.reload();
      _localCacheNeedsReload = false;
    }
    final encoded = prefs.getString(_localKey);
    // Corrupt state is an error, never an excuse to silently create a new session.
    if (encoded != null) {
      return _LocalShare.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
    }
    final legacy = prefs.getString('friend_share_intent');
    final intent = legacy == 'stop_pending'
        ? FriendShareIntent.stopPending
        : legacy == 'active' ||
                (legacy == null &&
                    prefs.getBool('friend_share_enabled') == true)
            ? FriendShareIntent.active
            : FriendShareIntent.off;
    var generation = prefs.getInt('friend_share_generation') ?? 0;
    if (intent == FriendShareIntent.active && generation < 1) generation = 1;
    final state = _LocalShare(
        intent: intent,
        generation: generation,
        session: const Uuid().v4(),
        revision: 1,
        dirty: intent != FriendShareIntent.off,
        name: prefs.getString('friend_share_my_name') ?? '',
        desired: prefs.getString('friend_share_desired_fingerprint'),
        confirmed: prefs.getString('friend_share_confirmed_fingerprint'));
    await _save(state);
    return state;
  }

  Future<void> _save(_LocalShare state) async {
    final prefs = await SharedPreferences.getInstance();
    // One preference write commits intent, session, revision and payload identity.
    // Legacy keys are compatibility mirrors, never the new writer's source of truth.
    try {
      if (!await prefs.setString(_localKey, jsonEncode(state.toJson()))) {
        throw StateError('Could not persist sharing intent');
      }
    } catch (_) {
      // SharedPreferences updates memory before the write completes.
      // Reload before trusting local state after a failed write.
      _localCacheNeedsReload = true;
      rethrow;
    }
    await prefs.setString(
        'friend_share_intent',
        switch (state.intent) {
          FriendShareIntent.stopPending => 'stop_pending',
          FriendShareIntent.active => 'active',
          FriendShareIntent.off => 'off'
        });
    await prefs.setBool(
        'friend_share_enabled', state.intent == FriendShareIntent.active);
    await prefs.setBool('friend_share_dirty', state.dirty);
    await prefs.setInt('friend_share_generation', state.generation);
    if (state.name.isNotEmpty) {
      await prefs.setString('friend_share_my_name', state.name);
    }
    if (state.desired != null) {
      await prefs.setString('friend_share_desired_fingerprint', state.desired!);
    } else {
      await prefs.remove('friend_share_desired_fingerprint');
    }
    if (state.confirmed != null) {
      await prefs.setString(
          'friend_share_confirmed_fingerprint', state.confirmed!);
    } else {
      await prefs.remove('friend_share_confirmed_fingerprint');
    }
  }

  Future<FriendShareState> getShareState() =>
      _local((s) async => FriendShareState(
          intent: s.intent, dirty: s.dirty, generation: s.generation));
  Future<bool> isSharingEnabled() async => (await getShareState()).isActive;
  Future<String?> savedMyName() =>
      _local((s) async => s.name.isEmpty ? null : s.name);

  Future<String?> getOrCreateOwnerId() async {
    if (_ownerOverride != null) return _ownerOverride!();
    if (!firebaseReady) return null;
    final existing = FirebaseAuth.instance.currentUser;
    if (existing != null) return existing.uid;
    if (_ownerIdInFlight != null) return _ownerIdInFlight!;
    final done = Completer<String?>();
    _ownerIdInFlight = done.future;
    try {
      done.complete(
          (await FirebaseAuth.instance.signInAnonymously()).user?.uid);
    } catch (_) {
      done.complete(null);
    } finally {
      _ownerIdInFlight = null;
    }
    return done.future;
  }

  Map<String, dynamic> _payload(ShiftSchedule schedule, String name) => {
        'ownerName': FriendScheduleData.clampOwnerName(name),
        'isRegular': schedule.isRegular,
        'pattern': schedule.pattern,
        'todayIndex': schedule.todayIndex,
        'startDate': schedule.startDate?.toIso8601String(),
        'shiftColors': schedule.shiftColors ?? <String, int>{},
        'assignedDates': schedule.assignedDates ?? <String, String>{}
      };
  dynamic _canonical(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  String _fingerprint(Map<String, dynamic> payload) =>
      jsonEncode(_canonical(payload));
  bool _valid(Map<String, dynamic> payload) =>
      FriendScheduleData.tryFromJson(
              {...payload, 'updatedAt': '1970-01-01T00:00:00.000Z'}) !=
          null &&
      utf8.encode(_fingerprint(payload)).length <= 800 * 1024;
  FriendShareWrite _operation(_LocalShare s, [Map<String, dynamic>? payload]) =>
      FriendShareWrite(
          session: s.session,
          revision: s.revision,
          generation: s.generation,
          stop: s.intent == FriendShareIntent.stopPending,
          explicitStart: s.explicitStart,
          payload: payload);

  Future<void> _confirmed(FriendShareWrite op) => _local((s) async {
        if (!s.matches(op)) return;
        s.dirty = false;
        s.explicitStart = false;
        if (op.stop) {
          s.intent = FriendShareIntent.off;
          s.desired = null;
          s.confirmed = null;
        } else {
          s.confirmed = s.desired;
        }
        await _save(s);
      });
  Future<bool> _isCurrent(FriendShareWrite op) =>
      _local((s) async => s.matches(op) && (op.stop || _sharingAvailable));

  Future<FriendSyncOutcome> _submit(FriendShareWrite op) {
    final done = Completer<FriendSyncOutcome>();
    final previous = _networkTail;
    final released = Completer<void>();
    _networkTail = released.future;
    unawaited(() async {
      try {
        if (previous != null) await previous;
        if (!await _isCurrent(op)) {
          done.complete(FriendSyncOutcome.skipped);
          return;
        }
        if (!_ready) {
          done.complete(FriendSyncOutcome.pending);
          return;
        }
        final owner = await getOrCreateOwnerId();
        if (owner == null) {
          done.complete(FriendSyncOutcome.pending);
          return;
        }
        final write = _transport.write(owner, op, () => _isCurrent(op));
        try {
          await write.timeout(_submissionWait);
          await _confirmed(op);
          done.complete(FriendSyncOutcome.confirmed);
        } on TimeoutException {
          unawaited(
              write.then((_) => _confirmed(op)).catchError((Object error) {
            DiagLog.log('SHARE_SYNC_FAIL',
                {'op': 'late', 'error': error.runtimeType.toString()});
          }));
          done.complete(FriendSyncOutcome.pending);
        } on FriendShareSuperseded {
          // A newer server session/revocation wins over automatic retries.
          await _local((s) async {
            if (s.matches(op)) {
              s.intent = FriendShareIntent.off;
              s.dirty = false;
              await _save(s);
            }
          });
          done.complete(FriendSyncOutcome.skipped);
        } on FirebaseException catch (error) {
          done.complete(['unavailable', 'deadline-exceeded', 'aborted']
                  .contains(error.code)
              ? FriendSyncOutcome.pending
              : FriendSyncOutcome.rejected);
        }
      } catch (error) {
        DiagLog.log('SHARE_SYNC_FAIL', {
          'op': op.stop ? 'stop' : 'upload',
          'error': error.runtimeType.toString()
        });
        done.complete(FriendSyncOutcome.rejected);
      } finally {
        released.complete();
        if (identical(_networkTail, released.future)) _networkTail = null;
      }
    }());
    return done.future;
  }

  Future<String?> startSharing(
      {required ShiftSchedule schedule, required String ownerName}) async {
    final name = FriendScheduleData.clampOwnerName(ownerName.trim());
    if (!_sharingAvailable || !_ready || name.isEmpty) return null;
    final payload = _payload(schedule, name);
    if (!_valid(payload)) return null;
    final owner = await getOrCreateOwnerId();
    if (owner == null) return null;
    final op = await _local((s) async {
      s.intent = FriendShareIntent.active;
      s.generation++;
      s.session = const Uuid().v4();
      s.revision = 1;
      s.explicitStart = true;
      s.name = name;
      s.dirty = true;
      s.desired = _fingerprint(payload);
      s.confirmed = null;
      await _save(s);
      return _operation(s, payload);
    });
    final outcome = await _submit(op);
    return outcome == FriendSyncOutcome.rejected ||
            outcome == FriendSyncOutcome.skipped
        ? null
        : owner;
  }

  Future<FriendShareWrite?> _prepareActive(ShiftSchedule schedule,
          {String? name}) =>
      _local((s) async {
        if (s.intent != FriendShareIntent.active) return null;
        final payload = _payload(schedule, name ?? s.name);
        if (!_valid(payload)) {
          s.dirty = true;
          await _save(s);
          return null;
        }
        final fingerprint = _fingerprint(payload);
        if (!s.dirty && s.confirmed == fingerprint) return null;
        if (fingerprint != s.desired) s.revision++;
        if (name != null) s.name = name;
        s.desired = fingerprint;
        s.dirty = true;
        await _save(s);
        return _operation(s, payload);
      });

  Future<void> syncIfEnabled(ShiftSchedule? schedule) async {
    try {
      if (!_sharingAvailable) {
        if ((await getShareState()).isActive) {
          await stopSharing();
        } else {
          await _retryStop();
        }
        return;
      }
      if (schedule == null) {
        await _retryStop();
        return;
      }
      final op = await _prepareActive(schedule);
      if (op != null) await _submit(op);
    } catch (error) {
      DiagLog.log('SHARE_SYNC_FAIL',
          {'op': 'prepare', 'error': error.runtimeType.toString()});
    }
  }

  Future<bool> updateMyName(
      {required String newName, required ShiftSchedule schedule}) async {
    final name = FriendScheduleData.clampOwnerName(newName.trim());
    if (name.isEmpty || !_sharingAvailable) return false;
    final op = await _prepareActive(schedule, name: name);
    return op != null && await _submit(op) == FriendSyncOutcome.confirmed;
  }

  /// Commit a local privacy barrier before any reset/delete can proceed. Offline
  /// means pending; a new schedule never opts the user back into sharing.
  Future<void> stopSharing() async {
    final op = await _local((s) async {
      if (s.intent == FriendShareIntent.off) return null;
      if (s.intent != FriendShareIntent.stopPending) s.revision++;
      s.intent = FriendShareIntent.stopPending;
      s.dirty = true;
      s.explicitStart = false;
      s.desired = null;
      s.confirmed = null;
      await _save(s);
      return _operation(s);
    });
    if (op != null) await _submit(op);
  }

  Future<void> _retryStop() async {
    final op = await _local((s) async =>
        s.intent == FriendShareIntent.stopPending ? _operation(s) : null);
    if (op != null) await _submit(op);
  }

  Future<void> retryPending(ShiftSchedule? schedule) async {
    final state = await getShareState();
    if (state.intent == FriendShareIntent.stopPending) {
      await _retryStop();
      return;
    }
    await syncIfEnabled(schedule);
  }

  Future<void> onAppStarted(ShiftSchedule? schedule) => retryPending(schedule);
  Future<void> onAppResumed(ShiftSchedule? schedule) => retryPending(schedule);
  Future<void> onNetworkReconnected(ShiftSchedule? schedule) =>
      retryPending(schedule);
  Future<void> onRestoreCompleted(ShiftSchedule? schedule) async {
    await _local((s) async {
      if (s.intent == FriendShareIntent.active) {
        s.dirty = true;
        await _save(s);
      }
    });
    await retryPending(schedule);
  }

  Future<FriendFetchResult> fetchByOwnerIdDetailed(String ownerId) async {
    if (!firebaseReady || !FriendShareService.isValidOwnerId(ownerId)) {
      return const FriendFetchResult.unavailable();
    }
    try {
      final snapshot =
          await _col.doc(ownerId).get(const GetOptions(source: Source.server));
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
      DiagLog.log('SHARE_FETCH_FAIL', {'error': error.runtimeType.toString()});
      return const FriendFetchResult.unavailable();
    }
  }

  /// 웹뷰어 등 기존 호출자 호환. 상세 구분이 필요한 앱 캐시는 detailed API를 쓴다.
  Future<FriendScheduleData?> fetchByOwnerId(String ownerId) async {
    final result = await fetchByOwnerIdDetailed(ownerId);
    return result.data;
  }
}
