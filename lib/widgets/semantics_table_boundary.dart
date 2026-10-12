import 'package:flutter/widgets.dart';
import 'package:flutter/semantics.dart';

/// Recreates only a table subtree when the accessibility owner changes.
///
/// Flutter 3.41's RenderTable retains row/cell nodes across clearSemantics,
/// causing stale-owner assertions when accessibility is disabled and re-enabled.
/// Keep application state above this boundary. Remove this workaround once the
/// minimum Flutter SDK includes RenderTable.clearSemantics cache cleanup.
class SemanticsTableBoundary extends StatefulWidget {
  const SemanticsTableBoundary({super.key, required this.child});
  final Widget child;

  @override
  State<SemanticsTableBoundary> createState() => _SemanticsTableBoundaryState();
}

class _SemanticsTableBoundaryState extends State<SemanticsTableBoundary> {
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    SemanticsBinding.instance.addSemanticsEnabledListener(_ownerChanged);
  }

  void _ownerChanged() {
    setState(() => _generation++);
  }

  @override
  void dispose() {
    SemanticsBinding.instance.removeSemanticsEnabledListener(_ownerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: ValueKey(_generation), child: widget.child);
}
