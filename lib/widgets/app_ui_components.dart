import 'shift_chip_label.dart';
import 'package:flutter/material.dart';
import '../constants/layout_limits.dart';
import '../theme/app_ui_theme.dart';

class AppUiText extends StatelessWidget {
  const AppUiText(this.data,
      {super.key,
      this.role = AppTextRole.body,
      this.tone = AppTextTone.normal,
      this.textAlign});
  final String data;
  final AppTextRole role;
  final AppTextTone tone;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) => Text(data,
      textScaler: TextScaler.noScaling,
      style: AppTypography.style(context, role, tone: tone),
      textAlign: textAlign);
}

enum AppUiAction { primary, secondary, danger, quiet }

/// Measure real child layouts before stretching a row. IntrinsicHeight can
/// underestimate a ListTile with a wrapped subtitle.
class AppUiEqualHeightRow extends StatelessWidget {
  const AppUiEqualHeightRow(
      {super.key, required this.children, this.gap = AppUiMetrics.gap});
  final List<Widget> children;
  final double gap;
  @override
  Widget build(BuildContext context) => Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
          columnWidths: {
            for (var i = 1; i < children.length * 2 - 1; i += 2)
              i: FixedColumnWidth(gap)
          },
          children: [
            TableRow(children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox.shrink(),
                children[i],
              ],
            ])
          ]);
}

/// Permission actions and 'later' can use these same roles without changing
/// permission state or navigation logic.
class AppUiButton extends StatelessWidget {
  const AppUiButton(
      {super.key,
      this.label,
      this.child,
      required this.onPressed,
      this.action = AppUiAction.primary,
      this.icon,
      this.compact = false,
      this.emphasized = false,
      this.padding,
      this.fontSize})
      : assert(label != null || child != null);
  final String? label;
  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final double? fontSize;
  final VoidCallback? onPressed;
  final AppUiAction action;
  final IconData? icon;
  final bool compact;

  /// Filled semantic color for actions that must stand out from page surfaces.
  final bool emphasized;
  @override
  Widget build(BuildContext context) {
    final p = AppUiPalette.of(context);
    final background = switch (action) {
      AppUiAction.primary => p.primary,
      AppUiAction.secondary => emphasized ? p.primary : p.soft,
      AppUiAction.danger => emphasized ? p.danger : p.dangerSurface,
      AppUiAction.quiet => p.surface,
    };
    final foreground = switch (action) {
      AppUiAction.primary => p.onPrimary,
      AppUiAction.danger => emphasized ? p.onDanger : p.danger,
      AppUiAction.secondary => emphasized ? p.onPrimary : p.text,
      AppUiAction.quiet => p.secondaryText,
    };
    final style = FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: p.disabledSurface,
        disabledForegroundColor: p.disabledText,
        elevation: 0,
        minimumSize: Size(
            0,
            compact
                ? AppUiMetrics.compactButtonHeight
                : AppUiMetrics.buttonHeight),
        padding: padding ??
            EdgeInsets.symmetric(
                horizontal: compact ? 12 : 20, vertical: compact ? 8 : 12),
        textStyle: AppTypography.style(context, AppTextRole.button)
            .copyWith(fontSize: fontSize),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUiMetrics.controlRadius)));
    final child = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Flexible(
              child: this.child ??
                  Text(label!,
                      textScaler: TextScaler.noScaling,
                      textAlign:
                          icon == null ? TextAlign.center : TextAlign.start))
        ]);
    if (action == AppUiAction.quiet) {
      return TextButton(style: style, onPressed: onPressed, child: child);
    }
    return FilledButton(style: style, onPressed: onPressed, child: child);
  }
}

class AppUiCard extends StatelessWidget {
  const AppUiCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(20)});
  final EdgeInsetsGeometry padding;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = AppUiPalette.of(context);
    return Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(AppUiMetrics.cardRadius),
            border: Border.all(color: p.border)),
        child: child);
  }
}

/// Name stays vertically centred; optional index always occupies top-left.
class AppUiShiftChip extends StatelessWidget {
  const AppUiShiftChip(
      {super.key,
      required this.name,
      this.team,
      this.index,
      this.size = AppChipSize.regular,
      this.onDelete,
      this.onTap,
      this.selected = false,
      this.enabled = true,
      this.badge,
      this.selectionMode = false});
  final String name;
  final String? team, badge;
  final int? index;
  final AppChipSize size;
  final VoidCallback? onDelete, onTap;
  final bool selected, enabled, selectionMode;
  static double heightFor(AppChipSize size) => switch (size) {
        AppChipSize.compact => 36,
        AppChipSize.regular => 40,
        AppChipSize.large => 48,
      };
  @override
  Widget build(BuildContext context) {
    final p = AppUiPalette.of(context);
    final compact = size == AppChipSize.compact;
    final ink = !enabled
        ? p.disabledText
        : selected
            ? p.onPrimary
            : p.chipText;
    final radius = BorderRadius.circular(24);
    return Semantics(
        selected: selected,
        button: onTap != null,
        enabled: enabled,
        label: [
          if (index != null) '$index',
          if (team != null) team!,
          name,
          if (badge != null) badge!
        ].join(' '),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: compact
                  ? ShiftChipMetrics.compactMaxWidth
                  : ShiftChipMetrics.regularMaxWidth),
          child: Material(
            color: !enabled
                ? p.disabledSurface
                : selected
                    ? p.primary
                    : p.chipSurface,
            shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(
                    color: selectionMode
                        ? p.selectionOutline
                        : selected
                            ? p.primary
                            : p.chipBorder,
                    width: selectionMode ? 2 : 1.5)),
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: radius,
              child: SizedBox(
                  height: heightFor(size),
                  child: LayoutBuilder(
                      builder: (context, box) =>
                          Stack(fit: StackFit.expand, children: [
                            Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: compact
                                        ? ShiftChipMetrics
                                            .compactHorizontalPadding
                                        : ShiftChipMetrics
                                            .regularHorizontalPadding,
                                    vertical: ShiftChipMetrics.verticalPadding),
                                child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (team != null) ...[
                                        AppUiText(team!,
                                            role: AppTextRole.chip,
                                            tone: !enabled
                                                ? AppTextTone.disabled
                                                : selected
                                                    ? AppTextTone.onPrimary
                                                    : AppTextTone.chip),
                                        const SizedBox(
                                            width: ShiftChipMetrics.teamSpacing)
                                      ],
                                      Expanded(
                                          child: ShiftChipLabel(
                                              label: name,
                                              color: ink,
                                              size: size)),
                                      if (onDelete != null)
                                        IconButton(
                                            onPressed: onDelete,
                                            icon: const Icon(Icons.close,
                                                size: 16)),
                                    ])),
                            if (index != null)
                              ShiftChipIndex(
                                  index: index!,
                                  name: name,
                                  chipSize: size,
                                  available: box.biggest,
                                  color: ink,
                                  team: team,
                                  hasDelete: onDelete != null),
                            if (badge != null)
                              Positioned(
                                  left: 5,
                                  right: 5,
                                  bottom: 2,
                                  child: Center(
                                      child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(badge!,
                                              textScaler: TextScaler.noScaling,
                                              style: AppTypography.style(
                                                      context,
                                                      AppTextRole.chipBadge)
                                                  .copyWith(color: ink))))),
                          ]))),
            ),
          ),
        ));
  }
}

class AppUiDialog extends StatelessWidget {
  const AppUiDialog(
      {super.key,
      required this.title,
      required this.content,
      required this.actions,
      this.showClose = true});
  final String title;
  final bool showClose;
  final Widget content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => AlertDialog(
        constraints:
            BoxConstraints(maxWidth: AppLayout.of(context).dialogWidth),
        insetPadding: const EdgeInsets.all(16),
        scrollable: true,
        title: Row(children: [
          Expanded(child: AppUiText(title, role: AppTextRole.section)),
          if (showClose)
            IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close))
        ]),
        content: content,
        actions: actions,
      );
}

/// Gentle repeating attention feedback without resizing the surrounding layout.
/// Stops when the action is completed or motion reduction is requested.
class AppUiAttention extends StatefulWidget {
  const AppUiAttention({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<AppUiAttention> createState() => _AppUiAttentionState();
}

class _AppUiAttentionState extends State<AppUiAttention>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _pulse;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: AppUiMotion.attentionCycle);
    _pulse = _buildPulse();
  }

  Animation<double> _buildPulse() => TweenSequence<double>([
        TweenSequenceItem(
            tween: Tween(begin: 1.0, end: 0.0)
                .chain(CurveTween(curve: Curves.easeInOut)),
            weight: 1),
        TweenSequenceItem(
            tween: Tween(begin: 0.0, end: 1.0)
                .chain(CurveTween(curve: Curves.easeInOut)),
            weight: 1),
      ]).animate(_controller);

  void _syncMotion() {
    final durationChanged = _controller.duration != AppUiMotion.attentionCycle;
    _controller.duration = AppUiMotion.attentionCycle;
    if (widget.enabled && !_reduced) {
      if (durationChanged || !_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppUiMotion.reduceMotion(context);
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant AppUiAttention oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pulse = _buildPulse();
    _syncMotion();
  }

  @override
  void reassemble() {
    super.reassemble();
    _pulse = _buildPulse();
    _syncMotion();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: Tween(begin: AppUiMotion.attentionLowOpacity, end: 1.0)
          .animate(_pulse),
      child: ScaleTransition(
          scale: Tween(begin: AppUiMotion.attentionLowScale, end: 1.0)
              .animate(_pulse),
          child: widget.child));
}
