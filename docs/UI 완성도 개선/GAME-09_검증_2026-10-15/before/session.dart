import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'replay.dart';
import 'hearts.dart';

abstract interface class ProgressStore {
  Future<String?> read();
  Future<void> write(String value);
}

final class MemoryProgressStore implements ProgressStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

enum SessionMode {
  hub,
  planning,
  replaying,
  paused,
  failureReview,
  successReview,
}

enum SessionNotice { invalidDestination, budgetUsed, saveFailed, corruptSave }

final class GameSessionController extends ChangeNotifier {
  final LevelPack pack;
  final ProgressStore store;
  bool unlockAllForTesting;
  final DateTime Function() clock;
  late DateTime _heartClock;
  bool foreground = true;
  final _hearts = <String, LevelHearts>{};
  bool hasPlayed = false;
  final double playbackRate;
  SessionMode mode = SessionMode.hub;
  SessionNotice? notice;
  late LevelSpec level;
  int levelIndex = 0;
  String? selectedUnitId;
  int routeRevision = 0;
  int _generation = 0;
  bool _disposed = false;
  bool ready = false;
  bool rulesSeen = false, gateRulesSeen = false, portalRulesSeen = false;
  void markRulesSeen({bool gates = false, bool portals = false}) {
    rulesSeen = true;
    gateRulesSeen |= gates;
    portalRulesSeen |= portals;
    _persist();
  }

  bool _returnPaused = false;
  final _completed = <LevelIdentity>{};
  Map<String, List<Cell>> _draft = {};
  List<UnitRoute>? _routeSnapshot;
  (LevelIdentity, int)? _executionKey;
  bool _executionValid = false;
  (LevelIdentity, int, String)? _destinationKey;
  List<Cell> _destinationSnapshot = const [];
  SimulationTrace? trace;
  ReplayCursor? replay;
  Future<void> _saveTail = Future.value();
  String? _pendingSave;
  GameSessionController(
    this.pack,
    this.store, {
    this.unlockAllForTesting = false,
    this.playbackRate = 1,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    if (pack.levels.isEmpty) throw ArgumentError('Empty pack');
    if (!playbackRate.isFinite || playbackRate <= 0)
      throw ArgumentError('Positive playback rate required');
    for (final l in pack.levels) {
      final checked = const LevelValidator().validate(l);
      if (!checked.isValid) throw ArgumentError(checked.issues);
    }
    _loadLevel(0);
    _heartClock = this.clock().toUtc();
  }
  LevelHearts get hearts =>
      _hearts.putIfAbsent(level.identity.levelId, LevelHearts.new);
  bool get unlimitedHearts => unlockAllForTesting;
  void toggleTesting() {
    unlockAllForTesting = !unlockAllForTesting;
    notifyListeners();
  }

  /// Called by an app-wide timer, including while the level list is visible.
  void tickHearts({bool notify = true}) {
    if (!ready || _disposed) return;
    final now = clock().toUtc();
    final elapsed = now.difference(_heartClock);
    if (elapsed.isNegative) return;
    final active = _hearts.values.any((h) => h.recovering);
    for (final h in _hearts.values) {
      h.elapse(elapsed, foreground: foreground);
    }
    _heartClock = now;
    if (active) {
      _persist();
      if (notify) notifyListeners();
    }
  }

  void setForeground(bool value) {
    tickHearts(notify: false);
    foreground = value;
    if (!ready || _disposed) return;
    _persist();
    notifyListeners();
  }

  List<UnitRoute> get routes => _routeSnapshot ??= List.unmodifiable([
    for (final u in level.units) UnitRoute(u.id, _draft[u.id]!),
  ]);
  RoutePlan get plan =>
      RoutePlan(level.identity, routes, revision: routeRevision);
  bool get editable => ready && mode == SessionMode.planning;
  bool get canExecute {
    if (!editable || (!unlimitedHearts && hearts.available == 0)) return false;
    final key = (level.identity, routeRevision);
    if (key != _executionKey) {
      _executionKey = key;
      _executionValid = const RouteValidator().validate(level, plan).isValid;
    }
    return _executionValid;
  }

  bool get canUndo =>
      editable && selectedUnitId != null && _draft[selectedUnitId]!.isNotEmpty;
  Set<LevelIdentity> get completedLevels => Set.unmodifiable(_completed);
  bool isCompleted(int i) => _completed.contains(pack.levels[i].identity);
  int get unlockedIndex {
    if (unlockAllForTesting) return pack.levels.length - 1;
    var i = 0;
    while (i < pack.levels.length - 1 && isCompleted(i)) {
      i++;
    }
    return i;
  }

  Cell currentFor(String id) => _draft[id]!.isEmpty
      ? level.units.singleWhere((u) => u.id == id).start
      : level.afterEndpoint(_draft[id]!.last);
  List<Cell> get destinations {
    if (!editable ||
        selectedUnitId == null ||
        _draft[selectedUnitId]!.length >= level.maxCommands)
      return const [];
    final key = (level.identity, routeRevision, selectedUnitId!);
    if (key != _destinationKey) {
      _destinationKey = key;
      _destinationSnapshot = List.unmodifiable(
        legalDestinations(level, currentFor(selectedUnitId!)),
      );
    }
    return _destinationSnapshot;
  }

  Future<void> initialize() async {
    final generation = _generation;
    try {
      final saved = await store.read();
      if (_disposed || generation != _generation) return;
      if (saved != null) _restore(saved);
    } catch (_) {
      if (!_disposed && generation == _generation)
        notice = SessionNotice.corruptSave;
    }
    if (!_disposed && generation == _generation) {
      ready = true;
      notifyListeners();
    }
  }

  void _restore(String source) {
    if (source.length > LevelParser.maxJsonBytes)
      throw const FormatException('Oversize save');
    final json = jsonDecode(source);
    if (json is! Map ||
        json['schemaVersion'] != 1 ||
        json['packId'] != pack.id ||
        json['packRevision'] != pack.revision)
      throw const FormatException('Stale save');
    rulesSeen = json['rulesSeen'] == true;
    gateRulesSeen = json['gateRulesSeen'] == true;
    portalRulesSeen = json['portalRulesSeen'] == true;
    hasPlayed = json['hasPlayed'] is bool
        ? json['hasPlayed'] as bool
        : json['draft'] != null;
    final savedHearts = json['hearts'];
    if (savedHearts is Map) {
      for (final l in pack.levels) {
        final restored = LevelHearts.restore(savedHearts[l.identity.levelId]);
        if (restored != null) _hearts[l.identity.levelId] = restored;
      }
      final stamp = json['heartClockMs'];
      if (stamp is int && stamp >= 0 && stamp <= 8640000000000000) {
        final elapsed = clock().toUtc().difference(
          DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: true),
        );
        for (final h in _hearts.values) {
          h.elapse(elapsed, foreground: false);
        }
      }
    }
    _heartClock = clock().toUtc();
    final completed = json['completed'];
    if (completed is! List || completed.length > pack.levels.length)
      throw const FormatException('Invalid progress');
    final identities = <LevelIdentity>{};
    for (final saved in completed) {
      for (final l in pack.levels) {
        if (saved is Map &&
            saved['packId'] == l.identity.packId &&
            saved['levelId'] == l.identity.levelId &&
            saved['revision'] == l.identity.revision &&
            saved['ruleSetId'] == l.identity.ruleSetId)
          identities.add(l.identity);
      }
    }
    _completed.addAll(identities);
    final draft = json['draft'];
    if (draft != null) {
      final parsed = const LevelParser().parsePlan(jsonEncode(draft));
      if (!parsed.isValid) {
        notice = SessionNotice.corruptSave;
        return;
      }
      final i = pack.levels.indexWhere(
        (l) => l.identity == parsed.value!.levelIdentity,
      );
      if (i < 0 ||
          !const RouteValidator()
              .validate(
                pack.levels[i],
                parsed.value!,
                mode: RouteValidationMode.draft,
              )
              .isValid) {
        notice = SessionNotice.corruptSave;
        return;
      }
      _loadLevel(i);
      _draft = {
        for (final r in parsed.value!.routes) r.unitId: r.endpoints.toList(),
      };
      _routeSnapshot = null;
      routeRevision = parsed.value!.revision;
    }
    // A persisted replay is never restarted after a process restart.
    mode = SessionMode.hub;
  }

  void _loadLevel(int index) {
    levelIndex = index;
    level = pack.levels[index];
    _draft = {for (final u in level.units) u.id: []};
    _routeSnapshot = null;
    selectedUnitId = null;
    routeRevision = 0;
    trace = null;
    replay = null;
    _returnPaused = false;
  }

  void openLevel(int index) {
    if (!ready || index < 0 || index > unlockedIndex) return;
    _generation++;
    if (index != levelIndex) _loadLevel(index);
    selectedUnitId = null;
    hasPlayed = true;
    mode = _returnPaused && replay != null
        ? SessionMode.paused
        : SessionMode.planning;
    notice = null;
    _persist();
    notifyListeners();
  }

  void selectUnit(String id) {
    if (!editable || !_draft.containsKey(id)) return;
    selectedUnitId = id;
    notice = null;
    _persist();
    notifyListeners();
  }

  bool append(Cell destination) {
    if (!editable || selectedUnitId == null) return false;
    final id = selectedUnitId!;
    final endpoints = _draft[id]!;
    if (endpoints.length >= level.maxCommands) {
      notice = SessionNotice.budgetUsed;
      notifyListeners();
      return false;
    }
    final unit = level.units.singleWhere((u) => u.id == id);
    final checked = const RouteValidator().validateRoute(
      level,
      unit,
      UnitRoute(id, [...endpoints, destination]),
      mode: RouteValidationMode.draft,
    );
    if (!checked.isValid) {
      notice = SessionNotice.invalidDestination;
      notifyListeners();
      return false;
    }
    endpoints.add(destination);
    _edited();
    return true;
  }

  void undo() {
    if (!canUndo) return;
    final id = selectedUnitId!;
    _draft[id]!.removeLast();
    selectedUnitId = id;
    _edited();
  }

  void clearSelected() {
    if (!editable || selectedUnitId == null) return;
    _draft[selectedUnitId]!.clear();
    _edited();
  }

  void restart() {
    if (!ready || mode == SessionMode.replaying) return;
    _draft = {for (final u in level.units) u.id: []};
    selectedUnitId = null;
    mode = SessionMode.planning;
    _edited();
  }

  void _edited() {
    _routeSnapshot = null;
    routeRevision++;
    _generation++;
    trace = null;
    replay = null;
    _returnPaused = false;
    notice = null;
    _persist();
    notifyListeners();
  }

  void execute({bool reducedMotion = false}) {
    tickHearts(notify: false);
    if (!canExecute) return;
    final result = const SimulationEngine().simulate(level, plan);
    if (result is! SimulationTrace) {
      notice = SessionNotice.invalidDestination;
      notifyListeners();
      return;
    }
    trace = result;
    replay = ReplayCursor(result);
    if (!unlimitedHearts) hearts.spend();
    _persist();
    mode = reducedMotion ? SessionMode.paused : SessionMode.replaying;
    notifyListeners();
  }

  void advance(Duration elapsed) {
    if (mode != SessionMode.replaying || replay == null) return;
    replay!.advance(elapsed, playbackRate: playbackRate);
    _finishIfNeeded();
    notifyListeners();
  }

  void nextScene() {
    if (mode != SessionMode.paused || replay == null) return;
    replay!.seek(replay!.position.floorToDouble() + 1);
    _finishIfNeeded();
    notifyListeners();
  }

  void _finishIfNeeded() {
    if (!replay!.isAtEnd) return;
    mode = trace!.outcome == SimulationOutcome.success
        ? SessionMode.successReview
        : SessionMode.failureReview;
    if (mode == SessionMode.successReview && _completed.add(level.identity))
      _persist();
  }

  void pause() {
    if (mode != SessionMode.replaying) return;
    mode = SessionMode.paused;
    notifyListeners();
  }

  void resume() {
    if (mode == SessionMode.paused) {
      mode = SessionMode.replaying;
      notifyListeners();
    }
  }

  void replayAgain({bool reducedMotion = false}) {
    if (trace == null ||
        trace!.routeRevision != routeRevision ||
        trace!.levelIdentity != level.identity ||
        (mode != SessionMode.failureReview &&
            mode != SessionMode.successReview))
      return;
    replay = ReplayCursor(trace!);
    mode = reducedMotion ? SessionMode.paused : SessionMode.replaying;
    notifyListeners();
  }

  void seek(double value) {
    if (replay == null ||
        (mode != SessionMode.failureReview &&
            mode != SessionMode.successReview &&
            mode != SessionMode.paused))
      return;
    replay!.seek(value);
    notifyListeners();
  }

  void editFailure({String? unitId}) {
    if (mode != SessionMode.failureReview) return;
    mode = SessionMode.planning;
    trace = null;
    replay = null;
    if (unitId != null && _draft.containsKey(unitId)) selectedUnitId = unitId;
    notifyListeners();
  }

  void leave() {
    if (mode == SessionMode.hub) return;
    _returnPaused = mode == SessionMode.replaying || mode == SessionMode.paused;
    mode = SessionMode.hub;
    _persist();
    notifyListeners();
  }

  Map<String, Object?> _snapshot() => {
    'schemaVersion': 1,
    'rulesSeen': rulesSeen,
    'gateRulesSeen': gateRulesSeen,
    'portalRulesSeen': portalRulesSeen,
    'hasPlayed': hasPlayed,
    'heartClockMs': _heartClock.millisecondsSinceEpoch,
    'hearts': {for (final e in _hearts.entries) e.key: e.value.toJson()},
    'packId': pack.id,
    'packRevision': pack.revision,
    'completed': _completed.map((i) => i.toJson()).toList(),
    'selectedUnitId': selectedUnitId,
    'draft': {
      'levelIdentity': level.identity.toJson(),
      'routeRevision': routeRevision,
      'routes': routes.map((r) => r.toJson()).toList(),
    },
  };
  void _persist() {
    _pendingSave = jsonEncode(_snapshot());
    _saveTail = _saveTail.then((_) async {
      final pending = _pendingSave;
      if (pending == null) return;
      _pendingSave = null;
      try {
        await store.write(pending);
      } catch (_) {
        // Keep the latest snapshot for an explicit retry, never overwrite it
        // with the older failed write.
        _pendingSave ??= jsonEncode(_snapshot());
        if (!_disposed) {
          notice = SessionNotice.saveFailed;
          notifyListeners();
        }
      }
    });
  }

  Future<void> flush() => _saveTail;
  void retrySave() {
    notice = null;
    _persist();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
