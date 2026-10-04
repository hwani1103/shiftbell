import 'package:flutter/material.dart';

// Mint separates my team from the timetable's pale indigo surface.
const kMyTeamBackground = Color(0xFFC8E6D5);

class TeamLabel extends StatelessWidget {
  const TeamLabel({super.key, required this.name, required this.isMine});
  final String name;
  final bool isMine;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
            color: isMine
                ? kMyTeamBackground
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6)),
        child: Text(name,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: isMine
                    ? const Color(0xFF205442)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
      );
}
