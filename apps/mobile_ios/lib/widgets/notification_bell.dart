import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../screens/profile_screen.dart';

/// Notification bell icon for the dashboard action toolbar. Mirrors
/// `apps/web/src/lib/components/NotificationBell.svelte`. Tapping
/// navigates to the user's own ProfileScreen with the Notifications
/// tab pre-selected (initialTab=3). A red dot covers the bell when
/// the unread count is non-zero — the actual count text is hosted on
/// the Notifications tab itself, so the dashboard surface stays a
/// glance.
///
/// The unread count is fetched on mount via
/// `ApiClient.fetchUnreadNotificationCount`. Failures are swallowed
/// (L4 — auxiliary effect, must not break the dashboard render
/// per docs/architecture/conventions.md). When [api] has no signed-in user, the
/// bell renders empty — the dashboard's `if (api != null)` gate is
/// the canonical signed-in check, but the widget is defensive.
class NotificationBell extends StatefulWidget {
  final ApiClient api;

  const NotificationBell({super.key, required this.api});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final count = await widget.api.fetchUnreadNotificationCount();
      if (!mounted) return;
      setState(() => _unread = count);
    } catch (_) {
      // L4 — auxiliary effect. A failed unread fetch must not break
      // the dashboard. Leave the badge dark.
    }
  }

  void _open() {
    final uid = widget.api.userId;
    if (uid == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            // Tab index 3 = Notifications (Runs/Followers/Following/
            // Notifications). Out-of-range values are clamped by
            // ProfileScreen's TabController init.
            builder: (_) => ProfileScreen(
              api: widget.api,
              userId: uid,
              initialTab: 3,
            ),
          ),
        )
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: _open,
        ),
        if (_unread > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
