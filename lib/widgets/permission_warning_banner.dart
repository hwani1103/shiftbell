import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../l10n/l10n_extensions.dart';
import '../services/permission_service.dart';
import 'permission_panel.dart';
import '../theme/app_ui_theme.dart';
import 'app_ui_components.dart';

class PermissionWarningBanner extends StatefulWidget {
  const PermissionWarningBanner({super.key});

  @override
  State<PermissionWarningBanner> createState() =>
      _PermissionWarningBannerState();
}

class _PermissionWarningBannerState extends State<PermissionWarningBanner>
    with WidgetsBindingObserver {
  final _controller = PermissionController();
  bool _showBanner = false;
  List<String> _missingPermissions = [];
  Locale? _permissionLocale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_updateBanner);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_permissionLocale != locale) {
      _permissionLocale = locale;
      _checkPermissions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 다시 활성화되면 권한 재확인
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() => _controller.refresh();

  void _updateBanner() {
    if (!mounted) return;
    final state = _controller.value;
    final missing = <String>[];
    for (final p in AppPermission.values) {
      if (!permissionSatisfied(state[p])) {
        final title = permissionTitle(context, p);
        missing.add(state[p] == AppPermissionState.unknown
            ? context.l10n.permissionStatusUnknown(title)
            : title);
      }
    }
    if (!permissionSatisfied(state.alarmChannel)) {
      missing.add(state.alarmChannel == AppPermissionState.denied
          ? context.l10n.permissionAlarmChannelBlocked
          : context.l10n.permissionAlarmChannelUnknown);
    }
    setState(() {
      _missingPermissions = missing;
      _showBanner = missing.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showBanner) {
      return const SizedBox.shrink();
    }

    if (Theme.of(context).extension<AppUiPalette>() != null) {
      final p = AppUiPalette.of(context);
      return AppUiCard(
          padding: const EdgeInsets.all(4),
          child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                iconColor: p.secondaryText,
                collapsedIconColor: p.secondaryText,
                title: Row(children: [
                  Icon(Icons.info_outline, size: 18, color: p.secondaryText),
                  const SizedBox(width: 8),
                  Expanded(
                      child: AppUiText(
                          context.l10n.permissionRequiredNotGranted,
                          role: AppTextRole.supporting)),
                  const SizedBox(width: 8),
                  AppUiButton(
                      label: context.l10n.navSettings,
                      compact: true,
                      action: AppUiAction.secondary,
                      onPressed: () async {
                        await showPermissionSettings(context);
                        _checkPermissions();
                      }),
                ]),
                children: [
                  ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 100),
                      child: SingleChildScrollView(
                          child: AppUiText(_missingPermissions.join(', '),
                              role: AppTextRole.supporting,
                              tone: AppTextTone.secondary)))
                ],
              )));
    }
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.tertiary.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colorScheme.tertiary,
            size: 24.sp,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.permissionRequiredNotGranted,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _missingPermissions.join(', '),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          TextButton(
            onPressed: () async {
              await showPermissionSettings(context);
              _checkPermissions();
            },
            style: TextButton.styleFrom(
              backgroundColor: colorScheme.tertiary,
              foregroundColor: colorScheme.onTertiary,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            child: Text(
              context.l10n.navSettings,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
