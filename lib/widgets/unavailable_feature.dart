import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';

/// Neutral exit for a Korean-only route retained across a language change.
/// Do not advertise the unavailable feature or alter its stored data.
class UnavailableFeature extends StatelessWidget {
  const UnavailableFeature({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.appTitle)),
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(context.l10n.commonGoBack),
          ),
        ),
      );
}
