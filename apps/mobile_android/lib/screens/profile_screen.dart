import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';

import '../preferences.dart';
import '../social_service.dart';
import '../training_service.dart';
import '../widgets/error_state.dart';
import '../widgets/report_sheet.dart';
import '../widgets/run_track_preview.dart';
import '../widgets/top_banner.dart';
import 'club_detail_screen.dart';
import 'event_detail_screen.dart';
import 'public_run_screen.dart';

/// Page size for the followers / following tabs. Same value as the
/// runs + routes screens — the convention is one consistent page size
/// across surfaces (`docs/architecture/conventions.md § Pagination`).
const int _kFollowsPageSize = 20;

/// Public profile screen — mirrors the web `/u/[id]` page (decisions §31).
///
/// Four tabs: Runs (public-only), Followers, Following, Notifications.
/// The Notifications tab is gated to the viewer's own profile (the row-
/// level RLS would hide other users' notifications anyway, but showing
/// the tab on someone else's profile is misleading).
class ProfileScreen extends StatefulWidget {
  final ApiClient api;
  final String userId;
  final int initialTab;

  const ProfileScreen({
    super.key,
    required this.api,
    required this.userId,
    this.initialTab = 0,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late TabController _tabs;

  bool _loading = true;
  Object? _loadError;
  ProfileSummary? _summary;
  List<RunRow> _runs = const [];
  List<UserProfileRow> _followers = const [];
  List<UserProfileRow> _following = const [];
  List<NotificationView> _notifications = const [];
  bool _followBusy = false;
  bool _blocked = false;
  bool _blockBusy = false;
  String _notifFilter = 'all'; // 'all' | 'unread'
  Set<String> _dismissedNotifIds = {};

  // Pagination state for the Followers / Following tabs. Updated on
  // initial load + each Load-more tap; the boolean flags drive the
  // footer's visibility and the in-flight spinner.
  bool _followersHasMore = true;
  bool _followingHasMore = true;
  bool _loadingMoreFollowers = false;
  bool _loadingMoreFollowing = false;

  bool get _isSelf => widget.api.userId == widget.userId;
  int get _tabCount => _isSelf ? 4 : 3;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, _tabCount - 1),
    );
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final summaryF = widget.api.fetchProfileSummary(widget.userId);
      final runsF = widget.api.fetchPublicRunsByUser(widget.userId, limit: 30);
      // First page only; older follows / followers come in via
      // Load-more on the respective tab.
      final followersF =
          widget.api.fetchFollowers(widget.userId, limit: _kFollowsPageSize);
      final followingF =
          widget.api.fetchFollowing(widget.userId, limit: _kFollowsPageSize);
      final notifF = _isSelf
          ? widget.api.fetchNotificationViews(limit: 100)
          : Future.value(const <NotificationView>[]);
      final blockedF = _isSelf
          ? Future.value(false)
          : widget.api.isBlockedByViewer(widget.userId);

      final results = await Future.wait([
        summaryF,
        runsF,
        followersF,
        followingF,
        notifF,
        blockedF,
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as ProfileSummary?;
        _runs = results[1] as List<RunRow>;
        _followers = results[2] as List<UserProfileRow>;
        _following = results[3] as List<UserProfileRow>;
        _notifications = results[4] as List<NotificationView>;
        _blocked = results[5] as bool;
        _followersHasMore = _followers.length == _kFollowsPageSize;
        _followingHasMore = _following.length == _kFollowsPageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMoreFollowers() async {
    if (_loadingMoreFollowers || !_followersHasMore) return;
    setState(() => _loadingMoreFollowers = true);
    try {
      final more = await widget.api.fetchFollowers(
        widget.userId,
        limit: _kFollowsPageSize,
        offset: _followers.length,
      );
      if (!mounted) return;
      setState(() {
        _followers = [..._followers, ...more];
        _followersHasMore = more.length == _kFollowsPageSize;
      });
    } catch (e) {
      debugPrint('Load more followers failed: $e');
      if (mounted) {
        showTopBanner(context, 'Could not load more followers');
      }
    } finally {
      if (mounted) setState(() => _loadingMoreFollowers = false);
    }
  }

  Future<void> _loadMoreFollowing() async {
    if (_loadingMoreFollowing || !_followingHasMore) return;
    setState(() => _loadingMoreFollowing = true);
    try {
      final more = await widget.api.fetchFollowing(
        widget.userId,
        limit: _kFollowsPageSize,
        offset: _following.length,
      );
      if (!mounted) return;
      setState(() {
        _following = [..._following, ...more];
        _followingHasMore = more.length == _kFollowsPageSize;
      });
    } catch (e) {
      debugPrint('Load more following failed: $e');
      if (mounted) {
        showTopBanner(context, 'Could not load more following');
      }
    } finally {
      if (mounted) setState(() => _loadingMoreFollowing = false);
    }
  }

  Future<void> _toggleFollow() async {
    final summary = _summary;
    if (summary == null || _isSelf || _followBusy) return;
    setState(() => _followBusy = true);
    final wasFollowing = summary.viewerFollows;
    // Optimistic update
    setState(() {
      _summary = ProfileSummary(
        id: summary.id,
        displayName: summary.displayName,
        avatarUrl: summary.avatarUrl,
        followerCount: wasFollowing
            ? (summary.followerCount - 1).clamp(0, 1 << 30)
            : summary.followerCount + 1,
        followingCount: summary.followingCount,
        viewerFollows: !wasFollowing,
      );
    });
    try {
      if (wasFollowing) {
        await widget.api.unfollowUser(widget.userId);
      } else {
        await widget.api.followUser(widget.userId);
      }
    } catch (e) {
      if (!mounted) return;
      // Roll back on failure.
      setState(() => _summary = summary);
      showTopBanner(context, 'Could not update follow: $e');
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _toggleBlock() async {
    if (_isSelf || _blockBusy) return;
    if (_blocked) {
      await _doUnblock();
      return;
    }
    final ok = await _confirmBlock();
    if (ok != true) return;
    await _doBlock();
  }

  Future<bool?> _confirmBlock() {
    final name = _summary?.displayName ?? 'this runner';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block $name?'),
        content: const Text(
          "They won't be able to follow you, give kudos to your runs, "
          'or comment on them. Any existing follow between you in '
          'either direction will be cleared. You can unblock from '
          'this page at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  Future<void> _doBlock() async {
    final summary = _summary;
    if (summary == null) return;
    setState(() => _blockBusy = true);
    try {
      await widget.api.blockUser(widget.userId);
      if (!mounted) return;
      // Block subsumes unfollow on both sides — the RPC drains
      // existing follow rows, so the local follow state must reflect
      // that or the Follow button would lie until reload.
      setState(() {
        _blocked = true;
        _summary = ProfileSummary(
          id: summary.id,
          displayName: summary.displayName,
          avatarUrl: summary.avatarUrl,
          followerCount: summary.viewerFollows
              ? (summary.followerCount - 1).clamp(0, 1 << 30)
              : summary.followerCount,
          followingCount: summary.followingCount,
          viewerFollows: false,
        );
      });
      showTopBanner(context, 'Blocked ${summary.displayName ?? 'runner'}');
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Could not block: $e');
    } finally {
      if (mounted) setState(() => _blockBusy = false);
    }
  }

  Future<void> _doUnblock() async {
    final summary = _summary;
    setState(() => _blockBusy = true);
    try {
      await widget.api.unblockUser(widget.userId);
      if (!mounted) return;
      setState(() => _blocked = false);
      showTopBanner(
        context,
        'Unblocked ${summary?.displayName ?? 'runner'}',
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Could not unblock: $e');
    } finally {
      if (mounted) setState(() => _blockBusy = false);
    }
  }

  Future<void> _markNotifRead(NotificationView item) async {
    if (item.row.readAt != null) return;
    final now = DateTime.now();
    setState(() {
      _notifications = _notifications
          .map((n) => n.row.id == item.row.id
              ? NotificationView(
                  row: NotificationRow(
                    id: n.row.id,
                    userId: n.row.userId,
                    actorId: n.row.actorId,
                    kind: n.row.kind,
                    runId: n.row.runId,
                    commentId: n.row.commentId,
                    readAt: now,
                    createdAt: n.row.createdAt,
                    eventId: n.row.eventId,
                  ),
                  actor: n.actor,
                  runDistanceM: n.runDistanceM,
                  commentExcerpt: n.commentExcerpt,
                  eventTitle: n.eventTitle,
                  eventClubSlug: n.eventClubSlug,
                )
              : n)
          .toList();
    });
    try {
      await widget.api.markNotificationRead(item.row.id);
    } catch (_) {
      /* best-effort */
    }
  }

  Future<void> _markAllNotifsRead() async {
    try {
      await widget.api.markAllNotificationsRead();
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _notifications = _notifications
            .map((n) => NotificationView(
                  row: NotificationRow(
                    id: n.row.id,
                    userId: n.row.userId,
                    actorId: n.row.actorId,
                    kind: n.row.kind,
                    runId: n.row.runId,
                    commentId: n.row.commentId,
                    readAt: n.row.readAt ?? now,
                    createdAt: n.row.createdAt,
                    eventId: n.row.eventId,
                  ),
                  actor: n.actor,
                  runDistanceM: n.runDistanceM,
                  commentExcerpt: n.commentExcerpt,
                  eventTitle: n.eventTitle,
                  eventClubSlug: n.eventClubSlug,
                ))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Failed to mark all read: $e');
    }
  }

  Future<void> _dismissNotif(String id) async {
    setState(() {
      _dismissedNotifIds = {..._dismissedNotifIds, id};
    });
    try {
      await widget.api.deleteNotification(id);
    } catch (e) {
      if (!mounted) return;
      // Roll back the optimistic dismiss.
      setState(() {
        _dismissedNotifIds = _dismissedNotifIds.difference({id});
      });
      showTopBanner(context, 'Failed to dismiss: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = <Tab>[
      const Tab(text: 'Runs'),
      const Tab(text: 'Followers'),
      const Tab(text: 'Following'),
      if (_isSelf) const Tab(text: 'Notifications'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_summary?.displayName ?? 'Profile'),
        actions: [
          if (!_isSelf)
            IconButton(
              tooltip: 'Report user',
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => showReportSheet(
                context,
                api: widget.api,
                targetKind: 'user',
                targetId: widget.userId,
              ),
            ),
          if (!_isSelf)
            IconButton(
              tooltip: _blocked ? 'Unblock this profile' : 'Block this profile',
              icon: Icon(
                Icons.block,
                color: _blocked ? Theme.of(context).colorScheme.error : null,
              ),
              isSelected: _blocked,
              onPressed: _blockBusy ? null : _toggleBlock,
            ),
        ],
        bottom: TabBar(controller: _tabs, isScrollable: true, tabs: tabs),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorState(
                  message: 'Could not load profile.',
                  onRetry: _load,
                )
              : _summary == null
                  ? const Center(child: Text('Profile not found.'))
                  : Column(
                      children: [
                        _buildHeader(theme),
                        const Divider(height: 1),
                        Expanded(
                          child: TabBarView(
                            controller: _tabs,
                            children: [
                              _buildRunsTab(theme),
                              _buildPeopleTab(
                                _followers,
                                'No followers yet.',
                                hasMore: _followersHasMore,
                                loadingMore: _loadingMoreFollowers,
                                onLoadMore: _loadMoreFollowers,
                              ),
                              _buildPeopleTab(
                                _following,
                                'Not following anyone yet.',
                                hasMore: _followingHasMore,
                                loadingMore: _loadingMoreFollowing,
                                onLoadMore: _loadMoreFollowing,
                              ),
                              if (_isSelf) _buildNotificationsTab(theme),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final s = _summary!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          _Avatar(displayName: s.displayName, avatarUrl: s.avatarUrl, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.displayName ?? 'Runner',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.followerCount} follower${s.followerCount == 1 ? '' : 's'} · ${s.followingCount} following',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!_isSelf)
            FilledButton.tonal(
              onPressed: _followBusy ? null : _toggleFollow,
              child: Text(s.viewerFollows ? 'Following' : 'Follow'),
            ),
        ],
      ),
    );
  }

  Widget _buildRunsTab(ThemeData theme) {
    if (_runs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _isSelf ? "You haven't shared any runs yet." : 'No public runs yet.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _runs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = _runs[i];
          // Mirrors the History tab's `_RunTile`: leading is a track
          // preview when the run carries a `trackUrl`, falling back to
          // the activity-type icon otherwise. Tap-into-detail routes
          // through `PublicRunScreen` (which takes a `runId`) so this
          // works for non-owner viewers too.
          final activityName =
              (r.metadata is Map ? (r.metadata as Map)['activity_type'] : null)
                  as String?;
          final activity = ActivityType.fromName(activityName);
          final dist = formatDistanceForPref(r.distanceM);
          final paceLine =
              '${_formatDuration(Duration(seconds: r.durationS))} · ${_formatPace(r.distanceM, r.durationS)}';
          final trackUrl = r.trackUrl;
          final leading = SizedBox(
            width: 56,
            height: 40,
            child: Center(
              child: trackUrl != null
                  ? RunTrackPreview(
                      runId: r.id,
                      trackUrl: trackUrl,
                      api: widget.api,
                      ownerUserId: widget.userId,
                    )
                  : CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(activity.icon,
                          color: theme.colorScheme.primary),
                    ),
            ),
          );
          return ListTile(
            leading: leading,
            title: Row(
              children: [
                Icon(activity.icon,
                    size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Text(dist),
              ],
            ),
            subtitle: Text('${_formatDate(r.startedAt)}  ·  $paceLine'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PublicRunScreen(api: widget.api, runId: r.id),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPeopleTab(
    List<UserProfileRow> people,
    String emptyMessage, {
    required bool hasMore,
    required bool loadingMore,
    required Future<void> Function() onLoadMore,
  }) {
    if (people.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyMessage),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        // +1 row for the Load-more footer when the cloud might still
        // have more pages (api hint is `lastPage.length == pageSize`).
        itemCount: people.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          if (hasMore && i == people.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: loadingMore
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : OutlinedButton.icon(
                        onPressed: onLoadMore,
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Load $_kFollowsPageSize more'),
                      ),
              ),
            );
          }
          final p = people[i];
          return ListTile(
            leading: _Avatar(
              displayName: p.displayName,
              avatarUrl: p.avatarUrl,
              size: 40,
            ),
            title: Text(p.displayName ?? 'Runner'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ProfileScreen(api: widget.api, userId: p.id),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildNotificationsTab(ThemeData theme) {
    final visible = (_notifFilter == 'unread'
            ? _notifications.where((n) => n.row.readAt == null)
            : _notifications)
        .where((n) => !_dismissedNotifIds.contains(n.row.id))
        .toList();
    final hasUnread =
        _notifications.any((n) => n.row.readAt == null);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All')),
                  ButtonSegment(value: 'unread', label: Text('Unread')),
                ],
                selected: {_notifFilter},
                onSelectionChanged: (s) =>
                    setState(() => _notifFilter = s.first),
                showSelectedIcon: false,
              ),
              const Spacer(),
              if (hasUnread)
                TextButton(
                  onPressed: _markAllNotifsRead,
                  child: const Text('Mark all read'),
                ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _notifFilter == 'unread'
                          ? "You're all caught up."
                          : 'No notifications yet.',
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) =>
                        _buildNotifRow(theme, visible[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildNotifRow(ThemeData theme, NotificationView item) {
    final unread = item.row.readAt == null;
    return Container(
      color: unread
          ? theme.colorScheme.primary.withValues(alpha: 0.06)
          : null,
      child: ListTile(
        leading: _Avatar(
          displayName: item.actor?.displayName,
          avatarUrl: item.actor?.avatarUrl,
          size: 40,
        ),
        title: Text(_verbFor(item)),
        subtitle: item.commentExcerpt != null
            ? Text(
                '"${item.commentExcerpt}"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              )
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Dismiss',
          onPressed: () => _dismissNotif(item.row.id),
        ),
        onTap: () => _onNotifTap(item),
      ),
    );
  }

  Future<void> _onNotifTap(NotificationView item) async {
    await _markNotifRead(item);
    if (!mounted) return;
    final kind = item.row.kind;
    if (kind == 'event_rsvp' &&
        item.row.eventId != null &&
        item.eventClubSlug != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailScreen(
            social: SocialService(),
            clubSlug: item.eventClubSlug!,
            eventId: item.row.eventId!,
          ),
        ),
      );
    } else if (kind == 'club_post' && item.clubSlug != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ClubDetailScreen(
            social: SocialService(),
            training: TrainingService(),
            slug: item.clubSlug!,
          ),
        ),
      );
    } else if (kind == 'run_completed' && item.row.runId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PublicRunScreen(api: widget.api, runId: item.row.runId!),
        ),
      );
    }
  }

  // ─────────────── format helpers ───────────────

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }

  static String _formatPace(double metres, int durationS) {
    if (metres <= 0 || durationS <= 0) return '—';
    final secPerKm = durationS / (metres / 1000);
    final m = secPerKm ~/ 60;
    final s = (secPerKm % 60).round();
    return '$m:${s.toString().padLeft(2, '0')} /km';
  }

  String _verbFor(NotificationView item) {
    final name = item.actor?.displayName ?? 'Someone';
    final dist = item.runDistanceM != null
        ? formatDistanceForPref(item.runDistanceM!)
        : 'your run';
    switch (item.row.kind) {
      case 'kudos':
        return '$name gave kudos to your $dist';
      case 'comment':
        return '$name commented on your $dist';
      case 'comment_reply':
        return '$name replied to your comment';
      case 'follow':
        return '$name started following you';
      case 'event_rsvp':
        return item.eventTitle != null
            ? '$name RSVP\'d Going to your event "${item.eventTitle}"'
            : '$name RSVP\'d Going to your event';
      case 'plan_update':
        return '$name updated your training plan';
      case 'message':
        return '$name sent you a message';
      case 'club_post':
        return item.clubName != null
            ? '$name posted in ${item.clubName}'
            : '$name posted in a club you\'re in';
      case 'run_completed':
        return item.runDistanceM != null
            ? '$name completed a ${formatDistanceForPref(item.runDistanceM!)} run'
            : '$name completed a run';
      default:
        return '$name interacted with your activity';
    }
  }
}

/// Circular avatar with image fallback to the first letter of the
/// display name. Used in the header, follower / following lists, and
/// notification rows. Inlined here rather than promoted to `ui_kit`
/// until a third caller materialises.
class _Avatar extends StatelessWidget {
  final String? displayName;
  final String? avatarUrl;
  final double size;

  const _Avatar({this.displayName, this.avatarUrl, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letter = (displayName?.isNotEmpty ?? false)
        ? displayName![0].toUpperCase()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary,
        image: avatarUrl != null && avatarUrl!.isNotEmpty
            ? DecorationImage(
                // Decode at ~3× the rendered size rather than full
                // source resolution — saves memory in long lists.
                image: ResizeImage(
                  NetworkImage(avatarUrl!),
                  width: (size * 3).round(),
                  height: (size * 3).round(),
                ),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? Text(
              letter,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}
