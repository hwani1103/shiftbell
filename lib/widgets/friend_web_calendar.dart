import 'dart:math' as math;
import 'semantics_table_boundary.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../l10n/l10n_extensions.dart';
import '../constants/layout_limits.dart';
import '../models/friend_schedule.dart';
import '../models/shift_schedule.dart';
import '../utils/holiday_util.dart';

/// Shared read-only main-white calendar for web links and native friend views.
/// Browser controls, folds and the optional install row can change the viewport
/// at any time; a short viewport scrolls rather than clipping the cells.
class FriendWebCalendar extends StatefulWidget {
  const FriendWebCalendar({
    super.key,
    required this.friendName,
    required this.data,
    required this.showPwaAddressBarHint,
    required this.showQuickInstallButton,
    this.onQuickInstallTap,
    this.onInstallTap,
    this.initialDay,
    this.showInstallPrompt = true,
    this.actions,
  });

  final String friendName;
  final FriendScheduleData data;
  final bool showPwaAddressBarHint, showQuickInstallButton;
  final VoidCallback? onQuickInstallTap, onInstallTap;
  final DateTime? initialDay;
  final bool showInstallPrompt;
  final List<Widget>? actions;

  @override
  State<FriendWebCalendar> createState() => _FriendWebCalendarState();
}

class _FriendWebCalendarState extends State<FriendWebCalendar> {
  late final _today = widget.initialDay ?? DateTime.now();
  late DateTime _focusedDay = DateTime(_today.year, _today.month);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler:
            media.textScaler.clamp(minScaleFactor: 1, maxScaleFactor: 1.3),
      ),
      child: Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    // Same 360dp typography reference as the app's main-white theme, bounded
    // independently of ScreenUtil so an unfolded browser cannot inflate text.
    final wide = MediaQuery.sizeOf(context).width > 500;
    final window = MediaQuery.sizeOf(context);
    final shortCover = AppLayout.of(context).isShortCover;
    final horizontalCells = shortCover || (wide && window.aspectRatio >= 1.25);
    final compact = shortCover || horizontalCells;
    final inlineSync = wide || shortCover;
    final unit = wide || shortCover ? 1.0 : (window.width / 360).clamp(.9, 1.2);
    final scaler = MediaQuery.textScalerOf(context);
    TextStyle style(double size,
            {Color color = Colors.black87,
            FontWeight weight = FontWeight.w600}) =>
        TextStyle(
            fontSize: size * unit,
            height: 1.15,
            color: color,
            fontWeight: weight);
    double height(String text, TextStyle textStyle, double width,
        {int lines = 1, TextScaler? textScaler}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textScaler: textScaler ?? scaler,
        textDirection: Directionality.of(context),
        maxLines: lines,
      )..layout(maxWidth: math.max(1, width));
      final result = painter.height.ceilToDouble();
      painter.dispose();
      return result;
    }

    final name = widget.friendName.isEmpty
        ? context.l10n.friendDefaultDisplayName
        : widget.friendName;
    final title = context.l10n.friendScheduleOf(name);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        actions: widget.actions,
        toolbarHeight: compact
            ? 44
            : wide
                ? 48
                : kToolbarHeight,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.black87,
        title: Text(title,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: style(17)),
      ),
      body: SafeArea(child: LayoutBuilder(builder: (context, bounds) {
        final width = bounds.maxWidth;
        final shiftStyle = style(wide ? 13.5 : 11, weight: FontWeight.bold);
        final holidayStyle = style(9.5, color: Colors.red.shade600);
        // Match main-white's bounded inner-display body typography. Only the
        // shift label scales on the inner display; no memo column is needed.
        final dateStyle =
            style(wide || shortCover ? 14 : 16, weight: FontWeight.w600);
        final bandHeight =
            math.max(20 * unit, height('가9', shiftStyle, width) + 4);
        // Keep dates vertically centered below the shift. Short covers and
        // landscape inner displays use the spare width for a holiday column;
        // taller displays reserve a single holiday line above the date.
        final annotationHeight =
            height('가', holidayStyle, width, textScaler: TextScaler.noScaling);
        final minRow = bandHeight +
            (horizontalCells ? 0 : annotationHeight * 2) +
            height('28', dateStyle, width,
                textScaler: wide || shortCover ? TextScaler.noScaling : null) +
            8;
        final weekHeight = math.max(
            (compact ? 24 : 28) * unit, height('일', style(13), width) + 4);
        final synced = widget.data.updatedAt.toLocal();
        final syncText = context.l10n
            .friendLastSyncedAt(DateFormat('yyyy.MM.dd HH:mm').format(synced));
        final syncStyle =
            style(11.5, color: Colors.grey.shade700, weight: FontWeight.normal);
        final syncHeight =
            inlineSync ? 0.0 : height(syncText, syncStyle, width - 32) + 12;
        final monthHeight = math.max(compact ? 44.0 : 48.0,
            height('2026년 12월', style(17), width - 112) + 12);

        Widget text(String value, TextStyle textStyle, {int lines = 2}) =>
            Text(value,
                style: textStyle,
                maxLines: lines,
                overflow: TextOverflow.ellipsis);

        final hint = !widget.showInstallPrompt
            ? null
            : !widget.showPwaAddressBarHint
                ? context.l10n.friendOpenInBrowserHint
                : widget.showQuickInstallButton
                    ? context.l10n.friendQuickInstallHint
                    : null;
        final quickButton = hint != null && widget.showPwaAddressBarHint;
        final hintStyle = style(11, color: Colors.brown.shade800);
        final quickWidth = math.min(width * .42, 128 * unit);
        final hintTextWidth = width - 32 - (quickButton ? quickWidth + 8 : 0);
        final hintHeight = hint == null
            ? 0.0
            : 4 +
                math.max(
                    height(hint, hintStyle, hintTextWidth, lines: 3),
                    quickButton
                        ? math.max(
                            44.0,
                            height(context.l10n.friendQuickInstallButton,
                                    style(11.5), quickWidth - 16,
                                    lines: 2) +
                                16)
                        : 0.0);

        final footerStyle = style(12,
            color: const Color(0xFF344275), weight: FontWeight.normal);
        final installWidth = math.min(width * .32, 104 * unit);
        final footerPadding = compact ? 2.0 : 6.0;
        final footerHeight = footerPadding * 2 +
            math.max(
                height(context.l10n.friendWebAppTagline, footerStyle,
                    width - 52 - installWidth, lines: 3),
                math.max(
                    44.0,
                    height(context.l10n.friendInstallApp, style(12),
                            installWidth - 16,
                            lines: 2) +
                        16));
        final surroundingHeight = hintHeight +
            syncHeight +
            monthHeight +
            (widget.showInstallPrompt ? footerHeight + 12 : 6);
        final calendarHeight = math.max(
            minRow * 6 + weekHeight, bounds.maxHeight - surroundingHeight);

        return SingleChildScrollView(
          key: const ValueKey('friend-web-scroll'),
          child: Column(children: [
            if (hint != null)
              Container(
                key: const ValueKey('friend-web-pwa-banner'),
                height: hintHeight.toDouble(),
                color: const Color(0xFFFFF4D4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Row(children: [
                  Expanded(child: text(hint, hintStyle, lines: 3)),
                  if (quickButton) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                        width: quickWidth,
                        child: TextButton(
                          onPressed: widget.onQuickInstallTap,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.all(8),
                            backgroundColor: Colors.brown.shade700,
                            foregroundColor: Colors.white,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(context.l10n.friendQuickInstallButton,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: style(11.5, color: Colors.white)),
                        )),
                  ],
                ]),
              ),
            if (!inlineSync)
              SizedBox(
                  height: syncHeight,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child:
                          Center(child: text(syncText, syncStyle, lines: 1)))),
            SizedBox(
                height: monthHeight,
                child: Row(children: [
                  IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .previousMonthTooltip,
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left)),
                  Expanded(
                      child: Center(
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                  DateFormat.yMMMM(
                                          Localizations.localeOf(context)
                                              .toString())
                                      .format(_focusedDay),
                                  style: style(17, weight: FontWeight.bold))))),
                  IconButton(
                      tooltip:
                          MaterialLocalizations.of(context).nextMonthTooltip,
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right)),
                  if (inlineSync)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(syncText,
                            style: syncStyle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ])),
            SizedBox(
              key: const ValueKey('friend-web-grid'),
              height: calendarHeight,
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SemanticsTableBoundary(child: TableCalendar(
                    firstDay: DateTime(_today.year - 3),
                    lastDay: DateTime(_today.year + 3, 12, 31),
                    focusedDay: _focusedDay,
                    locale: Localizations.localeOf(context).languageCode == 'ko'
                        ? 'ko_KR'
                        : 'en_US',
                    headerVisible: false,
                    // Vertical drags must reach the outer scroll view when
                    // larger text makes the PWA/footer content taller.
                    availableGestures: AvailableGestures.horizontalSwipe,
                    // A fold/PWA row changes the available height immediately.
                    // Constrain the package's internal height animation as well
                    // as our outer box, so its previous tall page cannot spill.
                    shouldFillViewport: true,
                    sixWeekMonthsEnforced: true,
                    daysOfWeekHeight: weekHeight,
                    rowHeight: (calendarHeight - weekHeight) / 6,
                    daysOfWeekStyle: DaysOfWeekStyle(
                        weekdayStyle: style(13), weekendStyle: style(13)),
                    calendarStyle: CalendarStyle(
                      cellMargin: EdgeInsets.zero,
                      cellPadding: EdgeInsets.zero,
                      tableBorder:
                          TableBorder.all(color: const Color(0xFFDADCE2)),
                    ),
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (_, day, __) => _cell(
                          context,
                          day,
                          unit,
                          bandHeight,
                          annotationHeight,
                          shiftStyle,
                          holidayStyle,
                          dateStyle),
                      outsideBuilder: (_, day, __) => _cell(
                          context,
                          day,
                          unit,
                          bandHeight,
                          annotationHeight,
                          shiftStyle,
                          holidayStyle,
                          dateStyle),
                      todayBuilder: (_, day, __) => _cell(
                          context,
                          day,
                          unit,
                          bandHeight,
                          annotationHeight,
                          shiftStyle,
                          holidayStyle,
                          dateStyle),
                    ),
                    onPageChanged: (day) => setState(() => _focusedDay = day),
                  ))),
            ),
            if (widget.showInstallPrompt)
              Container(
                key: const ValueKey('friend-web-app-banner'),
                height: footerHeight.toDouble(),
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                padding: EdgeInsets.symmetric(
                    horizontal: 10, vertical: footerPadding),
                decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(
                      child: text(context.l10n.friendWebAppTagline, footerStyle,
                          lines: 3)),
                  const SizedBox(width: 8),
                  SizedBox(
                      width: installWidth,
                      child: TextButton(
                          onPressed: widget.onInstallTap,
                          style: TextButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.all(8),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          child: Text(context.l10n.friendInstallApp,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style:
                                  style(12, color: const Color(0xFF344275))))),
                ]),
              ),
          ]),
        );
      })),
    );
  }

  void _changeMonth(int delta) {
    final day = DateTime(_focusedDay.year, _focusedDay.month + delta);
    if (day.year < _today.year - 3 || day.year > _today.year + 3) return;
    setState(() => _focusedDay = day);
  }

  Widget _cell(
      BuildContext context,
      DateTime day,
      double unit,
      double bandHeight,
      double annotationHeight,
      TextStyle shiftStyle,
      TextStyle holidayStyle,
      TextStyle dateStyle) {
    final outside =
        day.month != _focusedDay.month || day.year != _focusedDay.year;
    final today = isSameDay(day, _today) && !outside;
    final shift = widget.data.getShiftForDate(day);
    final hasShift = shift.isNotEmpty && shift != kUnsetShiftSentinel;
    final pattern = widget.data.getPatternShiftForDate(day);
    final modified = hasShift && pattern.isNotEmpty && pattern != shift;
    final holiday = getHolidayName(day,
        isKorean: Localizations.localeOf(context).languageCode == 'ko');
    final red = holiday != null || day.weekday == DateTime.sunday;
    final ink = red ? Colors.red.shade600 : const Color(0xFF202124);
    final shiftColor = Color(widget.data.shiftColors[shift] ?? 0xFFE0E0E0);
    final key = DateFormat('yyyy-MM-dd').format(day);
    final window = MediaQuery.sizeOf(context);
    final shortCover = AppLayout.of(context).isShortCover;
    final horizontal =
        shortCover || (window.width > 500 && window.aspectRatio >= 1.25);
    return Padding(
      key: ValueKey('friend-cell-$key'),
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          key: ValueKey('friend-shift-band-$key'),
          height: bandHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: hasShift
              ? BoxDecoration(
                  color: shiftColor,
                  borderRadius: BorderRadius.circular(3),
                  border: modified
                      ? const Border(left: BorderSide(width: 3))
                      : null)
              : null,
          child: hasShift
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(shift,
                      key: ValueKey('friend-shift-$key'),
                      maxLines: 1,
                      softWrap: false,
                      style: shiftStyle.copyWith(
                          color: ShiftSchedule.getTextColor(shiftColor))),
                )
              : null,
        ),
        Expanded(
            child: Stack(children: [
          if (holiday != null)
            Positioned(
                top: 0,
                bottom: horizontal ? 0 : null,
                left: horizontal ? (window.width - 12) / 7 * .38 : 0,
                right: 0,
                child: Center(
                    child: SizedBox(
                        height: annotationHeight,
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              holiday,
                              key: ValueKey('friend-holiday-$key'),
                              textScaler: TextScaler.noScaling,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: holidayStyle.copyWith(
                                  color: outside
                                      ? holidayStyle.color!
                                          .withValues(alpha: .65)
                                      : holidayStyle.color),
                            ))))),
          Align(
              alignment: horizontal ? Alignment.centerLeft : Alignment.center,
              child: FractionallySizedBox(
                  widthFactor: horizontal ? .38 : 1,
                  child: Center(
                      child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: horizontal ? 2 : 6 * unit, vertical: 2),
                    decoration: today
                        ? BoxDecoration(
                            color: red
                                ? Colors.lime.shade200
                                : const Color(0xFF5061A6),
                            borderRadius: BorderRadius.circular(4))
                        : null,
                    child: Text('${day.day}',
                        key: ValueKey('friend-date-$key'),
                        textScaler: window.width > 500 || shortCover
                            ? TextScaler.noScaling
                            : null,
                        maxLines: 1,
                        style: dateStyle.copyWith(
                            color: today && !red
                                ? Colors.white
                                : outside
                                    ? ink.withValues(alpha: .55)
                                    : ink)),
                  )))),
        ])),
      ]),
    );
  }
}
