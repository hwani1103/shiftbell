import 'package:flutter/material.dart';

/// A quiet entrance shared by first-use and release-note dialogs.
Future<T?> showSoftInfoDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: Duration(milliseconds: reduceMotion ? 0 : 320),
    pageBuilder: (context, animation, secondaryAnimation) =>
        SafeArea(child: builder(context)),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final eased =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: eased,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .025), end: Offset.zero)
              .animate(eased),
          child: ScaleTransition(
            scale: Tween(begin: .97, end: 1.0).animate(eased),
            child: child,
          ),
        ),
      );
    },
  );
}
