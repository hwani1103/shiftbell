import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/layout_limits.dart';

/// Natural-height sections; phone children keep their original ListView layout.
class AdaptiveSectionList extends StatefulWidget {
  const AdaptiveSectionList(
      {super.key,
      required this.children,
      this.padding,
      this.controller,
      this.physics,
      this.minColumnWidth = 320,
      this.fullWidthFirst = false});
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final double minColumnWidth;
  final bool fullWidthFirst;

  @override
  State<AdaptiveSectionList> createState() => _AdaptiveSectionListState();
}

class _AdaptiveSectionListState extends State<AdaptiveSectionList> {
  final _keys = <int, GlobalKey>{};

  @override
  Widget build(BuildContext context) {
    final children = widget.children;
    final controller = widget.controller;
    final physics = widget.physics;
    final padding = widget.padding;
    Widget kept(int index) => KeyedSubtree(
        key: _keys.putIfAbsent(index, GlobalKey.new), child: children[index]);
    final profile = AppLayout.of(context);
    if (!profile.isWide) {
      return ListView(
          controller: controller,
          physics: physics,
          padding: padding,
          children: [for (var i = 0; i < children.length; i++) kept(i)]);
    }
    return LayoutBuilder(builder: (context, constraints) {
      final insets =
          (padding ?? EdgeInsets.zero).resolve(Directionality.of(context));
      final width = math.max(0.0, constraints.maxWidth - insets.horizontal);
      final columns = width >= widget.minColumnWidth * 2 + 16 ? 2 : 1;
      final cellWidth = (width - (columns - 1) * 16) / columns;
      final sections = [
        for (var i = 0; i < children.length; i++)
          if (!(children[i] is SizedBox &&
                  (children[i] as SizedBox).child == null) &&
              children[i] is! Divider)
            i
      ];
      return ListView(
          controller: controller,
          physics: physics,
          padding: padding,
          children: [
            Wrap(spacing: 16, runSpacing: 16, children: [
              for (final i in sections)
                SizedBox(
                    width: (widget.fullWidthFirst && i == 0) ||
                            children[i] is Text ||
                            children[i] is Align
                        ? width
                        : cellWidth,
                    child: kept(i)),
            ])
          ]);
    });
  }
}

/// Short cover / wide sheets can scroll their whole form when a keyboard leaves
/// less space than the original fixed header needs. The ordinary phone path is
/// unchanged, including its existing memo-list scrolling behavior.
class AdaptiveSheetBody extends StatelessWidget {
  const AdaptiveSheetBody(
      {super.key, required this.child, this.minHeight = 480});
  final Widget child;
  final double minHeight;
  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    if (!layout.usesBoundedCalendar) return child;
    return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
            child: SizedBox(
                height: math.max(minHeight, constraints.maxHeight),
                child: child)));
  }
}

class AdaptiveScrollableSheet extends StatelessWidget {
  const AdaptiveScrollableSheet({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    return layout.isWide || layout.isShortCover
        ? SafeArea(child: SingleChildScrollView(child: child))
        : child;
  }
}

/// Let EditableText reveal itself in one scroll view, then restore the sheet
/// when the keyboard closes. No estimated offsets or delayed keyboard timers.
class KeyboardAwareSheetBody extends StatefulWidget {
  const KeyboardAwareSheetBody({super.key, required this.child});
  final Widget child;
  @override
  State<KeyboardAwareSheetBody> createState() => _KeyboardAwareSheetBodyState();
}

class _KeyboardAwareSheetBodyState extends State<KeyboardAwareSheetBody> {
  final _scroll = ScrollController();
  bool _keyboardOpen = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final open = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (_keyboardOpen && !open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic);
        }
      });
    }
    _keyboardOpen = open;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SingleChildScrollView(controller: _scroll, child: widget.child);
}

class AdaptiveScheduleFrame extends StatefulWidget {
  const AdaptiveScheduleFrame(
      {super.key,
      required this.header,
      required this.dateStrip,
      required this.dateGrid,
      required this.timeline,
      required this.divider});
  final Widget header, dateStrip, dateGrid, timeline, divider;
  @override
  State<AdaptiveScheduleFrame> createState() => _AdaptiveScheduleFrameState();
}

class _AdaptiveScheduleFrameState extends State<AdaptiveScheduleFrame> {
  final _timelineKey = GlobalKey();
  @override
  Widget build(BuildContext context) {
    final timeline = KeyedSubtree(key: _timelineKey, child: widget.timeline);
    return Center(
        child: FractionallySizedBox(
            widthFactor: 1,
            child: Column(children: [
              widget.header,
              widget.dateStrip,
              widget.divider,
              Expanded(child: timeline)
            ])));
  }
}

/// The same content has a hero column and a controls column on wide windows.
class AdaptiveHeroLayout extends StatelessWidget {
  const AdaptiveHeroLayout(
      {super.key, required this.children, required this.splitIndex});
  final List<Widget> children;
  final int splitIndex;
  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    if (!layout.isWide) return Column(children: children);
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
          flex: layout.isSquare ? 5 : 4,
          child: Column(children: children.take(splitIndex).toList())),
      const SizedBox(width: 24),
      Expanded(
          flex: 5, child: Column(children: children.skip(splitIndex).toList())),
    ]);
  }
}

/// On short covers keep the existing composition in one viewport. The ring is
/// already smaller there; this only scales down any remaining excess height.
class AdaptiveHeroViewport extends StatelessWidget {
  const AdaptiveHeroViewport(
      {super.key, required this.child, required this.padding, this.physics});
  final Widget child;
  final EdgeInsets padding;
  final ScrollPhysics? physics;
  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    if (!layout.isShortCover &&
        !layout.isTallCover &&
        !layout.isBalancedInner) {
      return SingleChildScrollView(
          padding: padding, physics: physics, child: child);
    }
    return LayoutBuilder(
        builder: (context, bounds) => Padding(
              padding: padding,
              child: SizedBox.expand(
                  child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(
                    width: bounds.maxWidth - padding.horizontal, child: child),
              )),
            ));
  }
}

/// Grows with the window. The form stays mounted while the window is resized.
class AdaptiveFormBody extends StatelessWidget {
  const AdaptiveFormBody({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
            width: layout.isWide ? layout.formWidth : double.infinity,
            height: double.infinity,
            child: child));
  }
}
