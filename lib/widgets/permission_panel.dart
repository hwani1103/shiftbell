import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';
import '../services/permission_service.dart';

String permissionTitle(BuildContext context, AppPermission p) => switch (p) {
      AppPermission.notification => context.l10n.permissionNotification,
      AppPermission.overlay => context.l10n.permissionOverlay,
      AppPermission.exactAlarm => context.l10n.permissionExactAlarm,
      AppPermission.fullScreen => context.l10n.permissionFullScreen,
    };

Future<void> showPermissionSettings(BuildContext context) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) => FractionallySizedBox(
            heightFactor: .9,
            child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    24, 24, 24, 24 + MediaQuery.viewPaddingOf(context).bottom),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outline,
                          borderRadius: BorderRadius.circular(2))),
                  Text(context.l10n.permissionSettingsTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(context.l10n.permissionSettingsDescription,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.4)),
                  const SizedBox(height: 20),
                  const PermissionPanel(),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.commonClose)),
                ]))));

class PermissionPanel extends StatefulWidget {
  const PermissionPanel({
    super.key,
    this.actionRequiredOnly = false,
    this.continueAfterGrant = false,
    this.onChanged,
  });

  final bool actionRequiredOnly;

  /// Onboarding only: continue after verifying the selected permission on return.
  final bool continueAfterGrant;
  final ValueChanged<PermissionSnapshot>? onChanged;
  @override
  State<PermissionPanel> createState() => _PermissionPanelState();
}

class _PermissionPanelState extends State<PermissionPanel>
    with WidgetsBindingObserver {
  final controller = PermissionController();
  final busyState = ValueNotifier(false);
  bool get busy => busyState.value;
  bool _helpOpen = false;
  String? _pendingPermission;
  bool _returnedFromSettings = false;
  int _requestGeneration = 0;
  Timer? _nextPermissionTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_changed);
    controller.refresh();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    widget.onChanged?.call(controller.value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _cancelNextPermission();
    }
    if (state == AppLifecycleState.resumed) {
      _returnedFromSettings = true;
      final generation = _requestGeneration;
      controller.refresh().then((_) {
        if (mounted && !busy && generation == _requestGeneration) {
          _continueAfterVerifiedGrant();
        }
      });
    }
  }

  @override
  void dispose() {
    _cancelNextPermission();
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    busyState.dispose();
    super.dispose();
  }

  Future<void> _open(String kind) async {
    if (busy) return;
    _cancelNextPermission();
    _requestGeneration++;
    _pendingPermission = widget.continueAfterGrant &&
            !_helpOpen &&
            (kind == 'alarmChannel' ||
                AppPermission.values.any((p) => p.name == kind))
        ? kind
        : null;
    _returnedFromSettings = false;
    setState(() => busyState.value = true);
    var opened = false;
    try {
      final result = await PermissionService().openPermissionRoute(kind);
      opened = result.opened;
      if (result.interactionCompleted) _returnedFromSettings = true;
      await controller.refresh();
    } finally {
      if (mounted) setState(() => busyState.value = false);
    }
    if (!mounted) return;
    if (!opened) {
      _pendingPermission = null;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.permissionOpenFailed)));
    } else {
      // Runtime dialogs finish on their callback; settings activities finish on
      // resume. A successful launch is never evidence that permission was given.
      _continueAfterVerifiedGrant();
    }
  }

  AppPermissionState _permissionState(String kind) => kind == 'alarmChannel'
      ? controller.value.alarmChannel
      : controller
          .value[AppPermission.values.firstWhere((p) => p.name == kind)];

  void _continueAfterVerifiedGrant() {
    final kind = _pendingPermission;
    if (kind == null) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final state = _permissionState(kind);
    if (state != AppPermissionState.granted && !_returnedFromSettings) return;
    _pendingPermission = null;
    if (state != AppPermissionState.granted ||
        _helpOpen ||
        ModalRoute.of(context)?.isCurrent != true) return;
    final generation = _requestGeneration;
    _cancelNextPermission();
    // Let the app settle after returning from the previous system settings page.
    late final Timer timer;
    timer = Timer(const Duration(milliseconds: 350), () async {
      await controller.refresh();
      if (!mounted ||
          _nextPermissionTimer != timer ||
          generation != _requestGeneration) return;
      _nextPermissionTimer = null;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (busy ||
          _helpOpen ||
          !widget.continueAfterGrant ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
          ModalRoute.of(context)?.isCurrent != true ||
          _permissionState(kind) != AppPermissionState.granted) return;
      final remaining = [
        ...AppPermission.values.map((p) => p.name),
        'alarmChannel',
      ].where((p) => !permissionSatisfied(_permissionState(p)));
      if (remaining.isEmpty) return;
      final next = remaining.first;
      // Unknown observations require a manual retry, rather than another launch.
      if (_permissionState(next) == AppPermissionState.denied) {
        _open(next);
      }
    });
    _nextPermissionTimer = timer;
  }

  void _cancelNextPermission() {
    _nextPermissionTimer?.cancel();
    _nextPermissionTimer = null;
  }

  String _state(AppPermissionState state) => switch (state) {
        AppPermissionState.granted => context.l10n.permissionGranted,
        AppPermissionState.denied => context.l10n.permissionNeedsSettings,
        AppPermissionState.unknown => context.l10n.permissionUnknown,
        AppPermissionState.notApplicable =>
          context.l10n.permissionNotApplicable,
      };
  Future<void> _lockHelp({bool troubleshooting = false}) async {
    if (_helpOpen || busy) return;
    _cancelNextPermission();
    _helpOpen = true;
    try {
      final xiaomi = controller.value.xiaomi;
      await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (sheetContext) => FractionallySizedBox(
              heightFactor: .8,
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: AnimatedBuilder(
                      animation: Listenable.merge([controller, busyState]),
                      builder: (_, __) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    xiaomi
                                        ? sheetContext
                                            .l10n.permissionXiaomiTitle
                                        : sheetContext
                                            .l10n.permissionLockScreenHelp,
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .titleLarge),
                                const SizedBox(height: 16),
                                Text(xiaomi
                                    ? sheetContext.l10n.permissionXiaomiBody
                                    : sheetContext
                                        .l10n.permissionLockScreenHelpBody),
                                if (xiaomi && troubleshooting)
                                  Text(sheetContext
                                      .l10n.permissionLockScreenHelpBody),
                                const SizedBox(height: 16),
                                if (!troubleshooting) ...[
                                  Text(sheetContext.l10n.permissionReturnGuide),
                                  const SizedBox(height: 16),
                                ],
                                if (controller
                                        .value[AppPermission.fullScreen] !=
                                    AppPermissionState.granted)
                                  Text(_state(controller
                                      .value[AppPermission.fullScreen])),
                                if (controller
                                        .value[AppPermission.fullScreen] ==
                                    AppPermissionState.denied)
                                  Text(sheetContext.l10n.permissionStillDenied),
                                if (xiaomi)
                                  FilledButton(
                                      onPressed:
                                          busy ? null : () => _open('xiaomi'),
                                      child: Text(sheetContext
                                          .l10n.permissionOpenOemSettings)),
                                if (controller.value.sdk >= 34 &&
                                    !permissionSatisfied(controller
                                        .value[AppPermission.fullScreen]))
                                  OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => _open('fullScreen'),
                                      child: Text(sheetContext.l10n
                                          .permissionOpenFullScreenSettings)),
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(sheetContext),
                                    child: Text(sheetContext.l10n.commonClose)),
                              ])))));
    } finally {
      _helpOpen = false;
      if (mounted) await controller.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final descriptions = [
      l.permissionNotificationDesc,
      l.permissionOverlayDesc,
      l.permissionExactAlarmDesc,
      l.permissionFullScreenDesc
    ];
    final icons = [
      Icons.notifications_active,
      Icons.phone_android,
      Icons.alarm_on,
      Icons.lock_clock
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final p in AppPermission.values.where((p) =>
          !widget.actionRequiredOnly ||
          !permissionSatisfied(controller.value[p])))
        Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: EdgeInsets.all(widget.actionRequiredOnly ? 12 : 16),
            decoration: BoxDecoration(
                color: Color.alphaBlend(
                    colors.onSurface.withOpacity(0.025), colors.surface),
                border: Border.all(color: colors.onSurface.withOpacity(0.15)),
                borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: EdgeInsets.only(
                      right: widget.actionRequiredOnly ? 10 : 16, top: 4),
                  child: Icon(icons[p.index],
                      color: colors.primary,
                      size: widget.actionRequiredOnly ? 20 : 24)),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(permissionTitle(context, p),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(descriptions[p.index],
                        style: TextStyle(
                            fontSize: widget.actionRequiredOnly ? 13 : null,
                            color: colors.onSurfaceVariant,
                            height: 1.4)),
                    if (widget.actionRequiredOnly)
                      Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(_state(controller.value[p]),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                            _settingsButton(p),
                          ])
                    else ...[
                      const SizedBox(height: 8),
                      Text(_state(controller.value[p]),
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: controller.value[p] ==
                                      AppPermissionState.granted
                                  ? colors.primary
                                  : colors.onSurface)),
                      if (!permissionSatisfied(controller.value[p])) ...[
                        if (p == AppPermission.overlay) ...[
                          const SizedBox(height: 8),
                          Text(l.permissionOverlayRouteGuide,
                              style: TextStyle(
                                  color: colors.onSurfaceVariant, height: 1.4)),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton(
                            key: ValueKey('permission-${p.name}'),
                            onPressed: busy
                                ? null
                                : () async {
                                    if (p == AppPermission.fullScreen &&
                                        controller.value.xiaomi) {
                                      await _lockHelp();
                                    } else {
                                      await _open(p.name);
                                    }
                                  },
                            child: Text(l.navSettings)),
                      ],
                    ],
                  ])),
            ])),
      if (!permissionSatisfied(controller.value.alarmChannel)) ...[
        Text(controller.value.alarmChannel == AppPermissionState.denied
            ? l.permissionAlarmChannelBlocked
            : l.permissionAlarmChannelUnknown),
        OutlinedButton(
            onPressed: busy ? null : () => _open('alarmChannel'),
            child: Text(l.navSettings)),
      ],
    ]);
  }

  Widget _settingsButton(AppPermission p) => OutlinedButton(
      key: ValueKey('permission-${p.name}'),
      style: OutlinedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          disabledBackgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
          disabledForegroundColor:
              Theme.of(context).colorScheme.onPrimaryContainer,
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          animationDuration: Duration.zero,
          side: BorderSide(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
              width: 1.25),
          textStyle: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 12)),
      onPressed: busy
          ? null
          : () async {
              if (p == AppPermission.fullScreen && controller.value.xiaomi) {
                await _lockHelp();
              } else {
                await _open(p.name);
              }
            },
      child: Text(context.l10n.navSettings));
}
