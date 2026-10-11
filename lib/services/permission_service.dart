import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/platform_channel.dart';

enum AppPermissionState { granted, denied, unknown, notApplicable }

enum AppPermission { notification, overlay, exactAlarm, fullScreen }

enum ExactAlarmPermissionState { granted, denied, unknown }

bool permissionSatisfied(AppPermissionState state) =>
    state == AppPermissionState.granted ||
    state == AppPermissionState.notApplicable;

class PermissionSnapshot {
  const PermissionSnapshot(this.states,
      {this.alarmChannel = AppPermissionState.unknown,
      this.xiaomi = false,
      this.sdk = 0});
  final Map<AppPermission, AppPermissionState> states;
  final AppPermissionState alarmChannel;
  final bool xiaomi;
  final int sdk;
  AppPermissionState operator [](AppPermission permission) =>
      states[permission] ?? AppPermissionState.unknown;
  bool get allSatisfied =>
      AppPermission.values.every((p) => permissionSatisfied(this[p])) &&
      permissionSatisfied(alarmChannel);
  factory PermissionSnapshot.parse(Map<dynamic, dynamic> data) {
    AppPermissionState state(Object? value) =>
        AppPermissionState.values.firstWhere((s) => s.name == value,
            orElse: () => AppPermissionState.unknown);
    return PermissionSnapshot(
        {for (final p in AppPermission.values) p: state(data[p.name])},
        alarmChannel: state(data['alarmChannel']),
        xiaomi: data['xiaomi'] == true,
        sdk: data['sdk'] is int ? data['sdk'] as int : 0);
  }
}

class PermissionOpenResult {
  const PermissionOpenResult(this.opened, {this.interactionCompleted = false});
  final bool opened;
  // A runtime prompt callback completes the interaction. Starting an external
  // settings activity does not; the UI must wait for the app to resume.
  final bool interactionCompleted;
}

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();
  static const _platform = kAlarmChannel;
  bool _opening = false;

  Future<PermissionSnapshot> snapshot() async {
    try {
      final data = await _platform
          .invokeMapMethod<dynamic, dynamic>('permissionSnapshot');
      return PermissionSnapshot.parse(data ?? {});
    } catch (_) {
      return const PermissionSnapshot({});
    }
  }

  /// Return value reports an attempted/opened settings route, never a grant.
  Future<bool> openPermission(String kind) async =>
      (await openPermissionRoute(kind)).opened;

  Future<PermissionOpenResult> openPermissionRoute(String kind) async {
    if (_opening) return const PermissionOpenResult(false);
    _opening = true;
    try {
      final current = await snapshot();
      final permission =
          AppPermission.values.where((p) => p.name == kind).firstOrNull;
      if (permission != null && permissionSatisfied(current[permission]))
        return const PermissionOpenResult(true, interactionCompleted: true);
      if (kind == 'notification' && current.sdk >= 33) {
        final status = await Permission.notification.status;
        final prefs = await SharedPreferences.getInstance();
        if (status.isDenied &&
            !await Permission.notification.shouldShowRequestRationale &&
            !(prefs.getBool('notification_request_attempted') ?? false)) {
          await prefs.setBool('notification_request_attempted', true);
          // Android may return empty results when the prompt is dismissed with
          // Back. Complete that native callback too; approval is reread below
          // by the caller rather than inferred from request completion.
          final opened = await _platform
                  .invokeMethod<bool>('requestNotificationPermission') ==
              true;
          return PermissionOpenResult(opened, interactionCompleted: true);
        }
      }
      final opened = await _platform
              .invokeMethod<bool>('openPermissionSettings', {'kind': kind}) ==
          true;
      return PermissionOpenResult(opened);
    } catch (_) {
      return const PermissionOpenResult(false);
    } finally {
      _opening = false;
    }
  }

  // Compatibility for existing alarm scheduling diagnostics. Unknown stays false.
  Future<ExactAlarmPermissionState> checkExactAlarmPermissionState() async {
    try {
      final value = await _platform.invokeMethod('checkExactAlarmPermission');
      return value == true
          ? ExactAlarmPermissionState.granted
          : value == false
              ? ExactAlarmPermissionState.denied
              : ExactAlarmPermissionState.unknown;
    } catch (_) {
      return ExactAlarmPermissionState.unknown;
    }
  }

  Future<bool> checkExactAlarmPermission() async =>
      await checkExactAlarmPermissionState() ==
      ExactAlarmPermissionState.granted;
  Future<void> requestExactAlarmPermission() async {
    await openPermission('exactAlarm');
  }

  Future<Map<String, bool>> checkPermissions() async {
    final value = await snapshot();
    return {
      for (final p in AppPermission.values)
        p.name: permissionSatisfied(value[p]),
      'alarmChannel': permissionSatisfied(value.alarmChannel)
    };
  }

  /// Legacy debug entry: open only the first missing item, never chain settings.
  Future<bool> requestAllPermissions() async {
    final current = await snapshot();
    if (current.allSatisfied) return true;
    for (final p in AppPermission.values) {
      if (!permissionSatisfied(current[p])) {
        await openPermission(p.name);
        return false;
      }
    }
    await openPermission('alarmChannel');
    return false;
  }

  Future<void> openSettings() async {
    await openPermission('app');
  }
}

/// Serial reads with one trailing refresh: a resume never commits an older read.
class PermissionController extends ChangeNotifier {
  PermissionController({Future<PermissionSnapshot> Function()? read})
      : _read = read ?? PermissionService().snapshot;
  final Future<PermissionSnapshot> Function() _read;
  PermissionSnapshot value = const PermissionSnapshot({});
  Future<void>? _pending;
  bool _dirty = false;
  bool _disposed = false;
  Future<void> refresh() {
    _dirty = true;
    return _pending ??= _refresh().whenComplete(() => _pending = null);
  }

  Future<void> _refresh() async {
    while (_dirty && !_disposed) {
      _dirty = false;
      PermissionSnapshot next;
      try {
        next = await _read();
      } catch (_) {
        next = const PermissionSnapshot({});
      }
      if (_disposed) return;
      if (_dirty) continue;
      value = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
