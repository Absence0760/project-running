import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../auth_error.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../notification_groups.dart';
import '../preferences.dart';
import '../social_service.dart';
import '../training_service.dart';
import '../widgets/badge_grid.dart';
import '../widgets/error_state.dart';
import '../widgets/report_sheet.dart';
import '../widgets/run_track_preview.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import 'club_detail_screen.dart';
import 'event_detail_screen.dart';
import 'public_run_screen.dart';

/// Page size for the followers / following tabs. Same value as the
/// runs + routes screens — the convention is one consistent page size
/// across surfaces (`docs/architecture/conventions.md § Pagination`).
const int _kFollowsPageSize = 20;

/// The profile's tabs, in render order. Callers that deep-link into a tab
/// name it; the index is derived from [_ProfileScreenState._tabOrder], so
/// inserting a tab can never silently re-point an existing deep link the
/// way a bare index literal did (the bell landed on Following once Badges
/// was inserted ahead of it).
enum ProfileTab { runs, badges, followers, following, notifications }

/// Public profile screen — mirrors the web `/u/[id]` page (decisions §31).
///
/// Tabs: Runs (public-only), Achievements, Followers, Following,
/// Notifications. The Notifications tab is gated to the viewer's own
/// profile (the row-level RLS would hide other users' notifications
/// anyway, but showing the tab on someone else's profile is misleading).
class ProfileScreen extends StatefulWidget {
  final ApiClient api;
  final String userId;
  final ProfileTab initialTab;

  const ProfileScreen({
    super.key,
    required this.api,
    required this.userId,
    this.initialTab = ProfileTab.runs,
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

  bool _runsLoading = true;
  Object? _runsError;
  List<RunRow> _runs = const [];

  bool _followersLoading = true;
  Object? _followersError;
  List<UserProfileRow> _followers = const [];

  bool _followingLoading = true;
  Object? _followingError;
  List<UserProfileRow> _following = const [];

  bool _badgesLoading = true;
  Object? _badgesError;
  List<AchievementRow> _badges = const [];

  bool _notificationsLoading = true;
  Object? _notificationsError;
  List<NotificationView> _notifications = const [];
  bool _followBusy = false;
  bool _blocked = false;
  bool _blockBusy = false;
  String _notifFilter = 'all'; // 'all' | 'unread'
  Set<String> _dismissedNotifIds = {};
  Set<String> _expandedGroups = {};

  // Pagination state for the Followers / Following tabs. Updated on
  // initial load + each Load-more tap; the boolean flags drive the
  // footer's visibility and the in-flight spinner.
  bool _followersHasMore = true;
  bool _followingHasMore = true;
  bool _loadingMoreFollowers = false;
  bool _loadingMoreFollowing = false;

  bool get _isSelf => widget.api.userId == widget.userId;

  /// Single source of tab order — the TabBar labels, the TabBarView
  /// children, and the deep-link index all read it, so they cannot drift.
  List<ProfileTab> get _tabOrder => [
        ProfileTab.runs,
        ProfileTab.badges,
        ProfileTab.followers,
        ProfileTab.following,
        if (_isSelf) ProfileTab.notifications,
      ];

  @override
  void initState() {
    super.initState();
    final order = _tabOrder;
    // A tab this profile doesn't carry (Notifications on someone else's)
    // has no index — open on the first tab rather than a nearby one.
    final requested = order.indexOf(widget.initialTab);
    _tabs = TabController(
      length: order.length,
      vsync: this,
      initialIndex: requested < 0 ? 0 : requested,
    );
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // Each independent fetch owns its loading / error / data so a failure
  // in one section (a broken Achievements query, a stale followers page)
  // scopes to that tab's ErrorState + Retry instead of blanking the whole
  // profile. The summary drives the header, which is structurally required
  // to render anything, so it alone gates the page.
  Future<void> _load() async {
    await Future.wait([
      _loadSummary(),
      _loadRuns(),
      _loadFollowers(),
      _loadFollowing(),
      _loadBadges(),
      if (_isSelf) _loadNotifications(),
    ]);
  }

  Future<void> _loadSummary() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final summary = await widget.api.fetchProfileSummary(widget.userId);
      var blocked = false;
      if (!_isSelf) {
        try {
          blocked = await widget.api.isBlockedByViewer(widget.userId);
        } catch (e) {
          debugPrint('profile blocked check failed: $e');
        }
      }
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _blocked = blocked;
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

  Future<void> _loadRuns() async {
    if (!mounted) return;
    setState(() {
      _runsLoading = true;
      _runsError = null;
    });
    try {
      final runs =
          await widget.api.fetchPublicRunsByUser(widget.userId, limit: 30);
      if (!mounted) return;
      setState(() {
        _runs = runs;
        _runsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _runsError = e;
        _runsLoading = false;
      });
    }
  }

  // First page only; older follows / followers come in via Load-more on
  // the respective tab.
  Future<void> _loadFollowers() async {
    if (!mounted) return;
    setState(() {
      _followersLoading = true;
      _followersError = null;
    });
    try {
      final followers =
          await widget.api.fetchFollowers(widget.userId, limit: _kFollowsPageSize);
      if (!mounted) return;
      setState(() {
        _followers = followers;
        _followersHasMore = followers.length == _kFollowsPageSize;
        _followersLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _followersError = e;
        _followersLoading = false;
      });
    }
  }

  Future<void> _loadFollowing() async {
    if (!mounted) return;
    setState(() {
      _followingLoading = true;
      _followingError = null;
    });
    try {
      final following =
          await widget.api.fetchFollowing(widget.userId, limit: _kFollowsPageSize);
      if (!mounted) return;
      setState(() {
        _following = following;
        _followingHasMore = following.length == _kFollowsPageSize;
        _followingLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _followingError = e;
        _followingLoading = false;
      });
    }
  }

  Future<void> _loadBadges() async {
    if (!mounted) return;
    setState(() {
      _badgesLoading = true;
      _badgesError = null;
    });
    try {
      final badges = await widget.api.fetchUserBadges(widget.userId);
      if (!mounted) return;
      setState(() {
        _badges = badges;
        _badgesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _badgesError = e;
        _badgesLoading = false;
      });
    }
  }

  Future<void> _loadNotifications() async {
    if (!_isSelf || !mounted) return;
    setState(() {
      _notificationsLoading = true;
      _notificationsError = null;
    });
    try {
      final notifications = await widget.api.fetchNotificationViews(limit: 100);
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _notificationsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notificationsError = e;
        _notificationsLoading = false;
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
    if (!await ensureSignedIn(context,
        viewerId: widget.api.userId, api: widget.api, onSignedIn: _load)) {
      return;
    }
    if (!mounted) return;
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
      debugPrint('profile follow update failed: $e');
      if (!mounted) return;
      // Roll back on failure.
      setState(() => _summary = summary);
      showTopBanner(
          context,
          AppLocalizations.of(context).profileFollowUpdateFailed(
              friendlyError(AppLocalizations.of(context), e)));
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
      debugPrint('profile block failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).profileBlockFailed(friendlyError(AppLocalizations.of(context), e)));
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
      debugPrint('profile unblock failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).profileUnblockFailed(friendlyError(AppLocalizations.of(context), e)));
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
      debugPrint('profile mark all read failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).profileMarkAllReadFailed(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  Future<void> _dismissNotif(String id) async {
    setState(() {
      _dismissedNotifIds = {..._dismissedNotifIds, id};
    });
    try {
      await widget.api.deleteNotification(id);
    } catch (e) {
      debugPrint('profile dismiss failed: $e');
      if (!mounted) return;
      // Roll back the optimistic dismiss.
      setState(() {
        _dismissedNotifIds = _dismissedNotifIds.difference({id});
      });
      showTopBanner(
          context, AppLocalizations.of(context).profileDismissFailed(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final order = _tabOrder;

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
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [for (final tab in order) Tab(text: _tabLabel(l10n, tab))],
        ),
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
                              for (final tab in order) _tabView(theme, l10n, tab)
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
          IdentityAvatar(
            seed: s.id,
            name: s.displayName,
            size: 56,
            imageUrl: s.avatarUrl,
          ),
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
                // The user_follows select is authenticated-only, so a
                // signed-out viewer's counts are always zero — hide the
                // line rather than present the zeros as fact.
                if (widget.api.userId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.profileFollowStats(s.followerCount, s.followingCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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

  String _tabLabel(AppLocalizations l10n, ProfileTab tab) => switch (tab) {
        ProfileTab.runs => l10n.profileTabRuns,
        ProfileTab.badges => l10n.badgesSectionTitle,
        ProfileTab.followers => l10n.profileTabFollowers,
        ProfileTab.following => l10n.profileTabFollowing,
        ProfileTab.notifications => l10n.profileTabNotifications,
      };

  Widget _tabView(ThemeData theme, AppLocalizations l10n, ProfileTab tab) =>
      switch (tab) {
        ProfileTab.runs => _tabScope(
            loading: _runsLoading,
            error: _runsError,
            onRetry: _loadRuns,
            child: () => _buildRunsTab(theme),
          ),
        ProfileTab.badges => _tabScope(
            loading: _badgesLoading,
            error: _badgesError,
            onRetry: _loadBadges,
            child: () => BadgeGrid(badges: _badges, isOwner: _isSelf),
          ),
        ProfileTab.followers => _tabScope(
            loading: _followersLoading,
            error: _followersError,
            onRetry: _loadFollowers,
            child: () => _buildPeopleTab(
              _followers,
              l10n.profileFollowersEmpty,
              hasMore: _followersHasMore,
              loadingMore: _loadingMoreFollowers,
              onLoadMore: _loadMoreFollowers,
            ),
          ),
        ProfileTab.following => _tabScope(
            loading: _followingLoading,
            error: _followingError,
            onRetry: _loadFollowing,
            child: () => _buildPeopleTab(
              _following,
              l10n.profileFollowingEmpty,
              hasMore: _followingHasMore,
              loadingMore: _loadingMoreFollowing,
              onLoadMore: _loadMoreFollowing,
            ),
          ),
        ProfileTab.notifications => _tabScope(
            loading: _notificationsLoading,
            error: _notificationsError,
            onRetry: _loadNotifications,
            child: () => _buildNotificationsTab(theme),
          ),
      };

  Widget _tabScope({
    required bool loading,
    required Object? error,
    required Future<void> Function() onRetry,
    required Widget Function() child,
  }) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return ErrorState(
        message: AppLocalizations.of(context).profileSectionError,
        onRetry: onRetry,
      );
    }
    return child();
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
      return EmptyState(
        icon: Icons.people_outline,
        title: emptyMessage,
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
            leading: IdentityAvatar(
              seed: p.id,
              name: p.displayName,
              size: 40,
              imageUrl: p.avatarUrl,
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
    final viewById = {for (final v in visible) v.row.id: v};
    final groups =
        groupNotifications(visible.map((v) => v.row).toList());
    final entries = <({NotificationGroup? group, NotificationView? sub})>[];
    for (final g in groups) {
      entries.add((group: g, sub: null));
      if (g.otherCount > 0 && _expandedGroups.contains(g.key)) {
        for (final o in g.others) {
          final ov = viewById[o.id];
          if (ov != null) entries.add((group: null, sub: ov));
        }
      }
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
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
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      if (e.group != null) {
                        return _buildNotifGroupRow(
                            theme, e.group!, viewById);
                      }
                      return _buildNotifRow(theme, e.sub!, isSub: true);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildNotifRow(ThemeData theme, NotificationView item,
      {bool isSub = false}) {
    final unread = item.row.readAt == null;
    return Container(
      color: unread
          ? theme.colorScheme.primary.withValues(alpha: 0.06)
          : null,
      child: ListTile(
        contentPadding: isSub
            ? const EdgeInsets.only(left: 40, right: 8)
            : null,
        leading: IdentityAvatar(
          seed: item.actor?.id ?? item.row.id,
          name: item.actor?.displayName,
          size: isSub ? 32 : 40,
          imageUrl: item.actor?.avatarUrl,
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

  Widget _buildNotifGroupRow(ThemeData theme, NotificationGroup group,
      Map<String, NotificationView> viewById) {
    final l10n = AppLocalizations.of(context);
    final lead = viewById[group.lead.id];
    if (lead == null) return const SizedBox.shrink();
    final unread = group.unreadCount > 0;
    final expanded = _expandedGroups.contains(group.key);
    final title = group.otherCount > 0
        ? _verbFor(l10n, lead,
            nameOverride: l10n.profileNotifNameAndOthers(
                _notifName(l10n, lead), group.otherCount))
        : _verbFor(l10n, lead);
    return Container(
      color: unread
          ? theme.colorScheme.primary.withValues(alpha: 0.06)
          : null,
      child: ListTile(
        leading: IdentityAvatar(
          seed: lead.actor?.id ?? lead.row.id,
          name: lead.actor?.displayName,
          size: 40,
          imageUrl: lead.actor?.avatarUrl,
        ),
        title: Text(title),
        subtitle: lead.commentExcerpt != null
            ? Text(
                '"${lead.commentExcerpt}"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unread)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${group.unreadCount}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onPrimary),
                ),
              ),
            if (group.otherCount > 0)
              IconButton(
                icon: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20),
                tooltip: expanded
                    ? l10n.profileNotifShowLess
                    : l10n.profileNotifAndOthers(group.otherCount),
                onPressed: () => setState(() {
                  _expandedGroups = expanded
                      ? (_expandedGroups.difference({group.key}))
                      : ({..._expandedGroups, group.key});
                }),
              ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: l10n.profileDismiss,
              onPressed: () => _dismissGroup(group),
            ),
          ],
        ),
        onTap: () => _openGroup(group, viewById),
      ),
    );
  }

  Future<void> _openGroup(NotificationGroup group,
      Map<String, NotificationView> viewById) async {
    final lead = viewById[group.lead.id];
    if (lead == null) return;
    for (final o in group.others) {
      final ov = viewById[o.id];
      if (ov != null && ov.row.readAt == null) {
        await _markNotifRead(ov);
      }
    }
    if (!mounted) return;
    await _onNotifTap(lead);
  }

  Future<void> _dismissGroup(NotificationGroup group) async {
    for (final row in [group.lead, ...group.others]) {
      await _dismissNotif(row.id);
    }
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

  String _notifName(AppLocalizations l10n, NotificationView item) =>
      item.actor?.displayName ?? l10n.profileNotifSomeone;

  String _verbFor(AppLocalizations l10n, NotificationView item,
      {String? nameOverride}) {
    final name = nameOverride ?? _notifName(l10n, item);
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

