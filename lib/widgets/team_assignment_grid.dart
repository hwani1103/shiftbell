import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../theme/app_colors.dart';

/// Shared by roster creation and team switching: number, shift and team badge
/// belong to one chip. My team's chip is grey and cannot be selected.
class TeamAssignmentGrid extends StatelessWidget {
  const TeamAssignmentGrid(
      {super.key,
      required this.pattern,
      required this.teamAtSlot,
      required this.isMine,
      required this.onTapSlot,
      this.canSelectSlot,
      this.selectedIndex,
      this.keyPrefix = 'team-assign-slot'});
  final List<String> pattern;
  final String? Function(int) teamAtSlot;
  final bool Function(int) isMine;
  final ValueChanged<int> onTapSlot;
  final bool Function(int)? canSelectSlot;
  final int? selectedIndex;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: colors.outlineVariant)),
      child: LayoutBuilder(builder: (context, constraints) {
        // Names never change the grid geometry. Ordinary text uses five
        // wider cells; enlarged accessibility text can reduce that count.
        final scaler = MediaQuery.textScalerOf(context);
        final baseStyle = DefaultTextStyle.of(context).style;
        final minimum = 48.w * math.max(1.0, scaler.scale(12) / 12);
        final columns = ((constraints.maxWidth + 6.w) / (minimum + 6.w))
            .floor()
            .clamp(1, 5);
        final width = (constraints.maxWidth - (columns - 1) * 6.w) / columns;
        double lineHeight(TextStyle style) {
          final painter = TextPainter(
            text: TextSpan(text: 'Ag근म', style: baseStyle.merge(style)),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            locale: Localizations.maybeLocaleOf(context),
            maxLines: 1,
          )..layout();
          final height = painter.height;
          painter.dispose();
          return height;
        }

        final shiftHeight =
            lineHeight(TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700));
        final badgeHeight = lineHeight(
            TextStyle(fontSize: 9.5.sp, fontWeight: FontWeight.bold));
        final height = math.max(width / 0.82, shiftHeight + badgeHeight + 30.h);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 6.w,
              mainAxisSpacing: 6.h,
              mainAxisExtent: height),
          itemCount: pattern.length,
          itemBuilder: (context, index) => TeamAssignmentChip(
            key: ValueKey('$keyPrefix-$index'),
            index: index,
            shift: pattern[index],
            team: teamAtSlot(index),
            isMine: isMine(index),
            selected: selectedIndex == index,
            onTap: isMine(index) || !(canSelectSlot?.call(index) ?? true)
                ? null
                : () => onTapSlot(index),
          ),
        );
      }),
    );
  }
}

class TeamAssignmentChip extends StatelessWidget {
  const TeamAssignmentChip(
      {super.key,
      required this.index,
      required this.shift,
      required this.team,
      required this.isMine,
      this.selected = false,
      this.onTap});
  final int index;
  final String shift;
  final String? team;
  final bool isMine;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final border = isMine
        ? colors.outlineVariant
        : selected
            ? kAppMainAccent
            : team != null
                ? kAppMainAccent.withValues(alpha: 0.6)
                : colors.outlineVariant;
    final fill = isMine
        ? colors.surfaceContainerHighest.withValues(alpha: 0.4)
        : selected
            ? kAppMainAccent.withValues(alpha: 0.18)
            : team != null
                ? kAppSurface
                : Colors.white;
    final badge = isMine
        ? colors.onSurfaceVariant.withValues(alpha: 0.7)
        : selected
            ? kAppMainAccent
            : kAppChipBorder;
    return InkWell(
      borderRadius: BorderRadius.circular(8.r),
      splashColor: kAppMainAccent.withValues(alpha: 0.25),
      highlightColor: kAppMainAccent.withValues(alpha: 0.15),
      onTap: onTap,
      child: Opacity(
          opacity: isMine ? 0.65 : 1,
          child: Container(
            decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(
                    color: border,
                    width: selected
                        ? 2.5
                        : team != null
                            ? 2
                            : 1)),
            child: Stack(children: [
              Positioned(
                  top: 4.h,
                  left: 4.w,
                  child: Text('${index + 1}',
                      style: TextStyle(
                          fontSize: 8.sp,
                          fontWeight: FontWeight.w600,
                          color:
                              colors.onSurfaceVariant.withValues(alpha: 0.7)))),
              Padding(
                  padding: EdgeInsets.fromLTRB(3.w, 8.h, 3.w, 4.h),
                  child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(shift,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface))),
                    if (team != null) ...[
                      SizedBox(height: 4.h),
                      Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 7.w, vertical: 2.h),
                          decoration: BoxDecoration(
                              color: badge,
                              borderRadius: BorderRadius.circular(20.r)),
                          child: Text(team!,
                              style: TextStyle(
                                  fontSize: 9.5.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white))),
                    ],
                  ]))),
            ]),
          )),
    );
  }
}
