import 'package:flutter/material.dart';
import '../widgets/unavailable_feature.dart';

/// Compatibility type for old development tests. No release entry point exists.
/// Foreign first releases do not provide sleep or recovery functionality.
class EnglishConditionTab extends StatelessWidget {
  const EnglishConditionTab({super.key, required this.onDisabled, required this.onConfirmed});
  final VoidCallback onDisabled;
  final Future<void> Function() onConfirmed;
  @override
  Widget build(BuildContext context) => const UnavailableFeature();
}
