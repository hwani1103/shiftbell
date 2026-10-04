import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';
import '../models/friend_schedule.dart';
import '../widgets/friend_web_calendar.dart';
import 'friend_list_screen.dart';

/// One read-only main-white calendar for shared links and in-app friends.
/// The app keeps its back/list navigation and never shows installation UI.
class FriendCalendarView extends StatelessWidget {
  const FriendCalendarView({
    super.key,
    required this.friendName,
    required this.data,
    this.showInstallPrompt = false,
    this.showPwaAddressBarHint = true,
    this.showQuickInstallButton = false,
    this.onQuickInstallTap,
    this.onInstallTap,
  });

  final String friendName;
  final FriendScheduleData data;
  final bool showInstallPrompt;
  final bool showPwaAddressBarHint;
  final bool showQuickInstallButton;
  final VoidCallback? onQuickInstallTap;
  final VoidCallback? onInstallTap;

  @override
  Widget build(BuildContext context) => FriendWebCalendar(
        friendName: friendName,
        data: data,
        showInstallPrompt: showInstallPrompt,
        showPwaAddressBarHint: showPwaAddressBarHint,
        showQuickInstallButton: showQuickInstallButton,
        onQuickInstallTap: onQuickInstallTap,
        onInstallTap: onInstallTap,
        actions: showInstallPrompt
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.groups_outlined),
                  tooltip: context.l10n.friendShareTitle,
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const FriendListScreen())),
                ),
              ],
      );
}
