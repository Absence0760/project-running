import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
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
        showTopBanner(context,
            AppLocalizations.of(context).profileLoadMoreFollowersFailed);
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
        showTopBanner(context,
            AppLocalizations.of(context).profileLoadMoreFollowingFailed);
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
      showTopBanner(
          context, AppLocalizations.of(context).profileFollowUpdateFailed('$e'));
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
    final l10n = AppLocalizations.of(context);
    final name = _summary?.displayName ?? l10n.profileThisRunner;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.profileBlockConfirmTitle(name)),
        content: Text(l10n.profileBlockConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.profileCancel),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.profileBlockConfirmAction),
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
      showTopBanner(
          context,
          AppLocalizations.of(context).profileBlocked(summary.displayName ??
              AppLocalizations.of(context).profileRunnerNoun));
    } catch (e) {
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).profileBlockFailed('$e'));
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
        AppLocalizations.of(context).profileUnblocked(summary?.displayName ??
            AppLocalizations.of(context).profileRunnerNoun),
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).profileUnblockFailed('$e'));
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
      showTopBanner(
          context, AppLocalizations.of(context).profileMarkAllReadFailed('$e'));
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
      showTopBanner(
          context, AppLocalizations.of(context).profileDismissFailed('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tabs = <Tab>[
      Tab(text: l10n.profileTabRuns),
      Tab(text: l10n.profileTabFollowers),
      Tab(text: l10n.profileTabFollowing),
      if (_isSelf) Tab(text: l10n.profileTabNotifications),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_summary?.displayName ?? l10n.profileTitle),
        actions: [
          if (!_isSelf)
            IconButton(
              tooltip: l10n.profileReportUser,
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
              tooltip: _blocked ? l10n.profileUnblock : l10n.profileBlock,
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
                  message: l10n.profileLoadError,
                  onRetry: _load,
                )
              : _summary == null
                  ? Center(child: Text(l10n.profileNotFound))
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
                                l10n.profileFollowersEmpty,
                                hasMore: _followersHasMore,
                                loadingMore: _loadingMoreFollowers,
                                onLoadMore: _loadMoreFollowers,
                              ),
                              _buildPeopleTab(
                                _following,
                                l10n.profileFollowingEmpty,
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
    final l10n = AppLocalizations.of(context);
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
                  s.displayName ?? l10n.profileRunnerFallback,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.profileFollowStats(s.followerCount, s.followingCount),
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
              child: Text(
                  s.viewerFollows ? l10n.profileFollowing : l10n.profileFollow),
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
            _isSelf
                ? AppLocalizations.of(context).profileRunsEmptySelf
                : AppLocalizations.of(context).profileRunsEmptyOther,
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
          final activity = ActivityType.fromName(r.activityType);
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
            subtitle: Text(
                '${formatDateMed(r.startedAt, localeToTag(Localizations.localeOf(context)))}  ·  $paceLine'),
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
                        label: Text(AppLocalizations.of(context)
                            .profileLoadMore(_kFollowsPageSize)),
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
            title: Text(p.displayName ??
                AppLocalizations.of(context).profileRunnerFallback),
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
    final l10n = AppLocalizations.of(context);
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
                segments: [
                  ButtonSegment(
                      value: 'all', label: Text(l10n.profileNotifAll)),
                  ButtonSegment(
                      value: 'unread', label: Text(l10n.profileNotifUnread)),
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
                  child: Text(l10n.profileMarkAllRead),
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
                          ? l10n.profileNotifsCaughtUp
                          : l10n.profileNotifsEmpty,
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
        title: Text(_verbFor(AppLocalizations.of(context), item)),
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
          tooltip: AppLocalizations.of(context).profileDismiss,
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


  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }

  static String _formatPace(double metres, int durationS) {
    if (metres <= 0 || durationS <= 0) return '—';
    return formatPaceForPref(durationS / (metres / 1000));
  }

  String _verbFor(AppLocalizations l10n, NotificationView item) {
    final name = item.actor?.displayName ?? l10n.profileNotifSomeone;
    final dist = item.runDistanceM != null
        ? formatDistanceForPref(item.runDistanceM!)
        : l10n.profileNotifYourRun;
    switch (item.row.kind) {
      case 'kudos':
        return l10n.profileNotifKudos(name, dist);
      case 'comment':
        return l10n.profileNotifComment(name, dist);
      case 'comment_reply':
        return l10n.profileNotifCommentReply(name);
      case 'follow':
        return l10n.profileNotifFollow(name);
      case 'event_rsvp':
        return item.eventTitle != null
            ? l10n.profileNotifEventRsvpTitled(name, item.eventTitle!)
            : l10n.profileNotifEventRsvp(name);
      case 'plan_update':
        return l10n.profileNotifPlanUpdate(name);
      case 'message':
        return l10n.profileNotifMessage(name);
      case 'club_post':
        return item.clubName != null
            ? l10n.profileNotifClubPostNamed(name, item.clubName!)
            : l10n.profileNotifClubPost(name);
      case 'run_completed':
        return item.runDistanceM != null
            ? l10n.profileNotifRunCompletedDist(
                name, formatDistanceForPref(item.runDistanceM!))
            : l10n.profileNotifRunCompleted(name);
      default:
        return l10n.profileNotifGeneric(name);
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
