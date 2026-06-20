import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../badges.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart';
import '../social_service.dart';
import '../widgets/badge_grid.dart';
import '../widgets/error_state.dart';
import '../widgets/run_track_preview.dart';
import 'people_screen.dart';
import 'profile_screen.dart';
import 'public_run_screen.dart';
import '../widgets/top_banner.dart';

/// Activity feed of public runs from people you follow, capped to the
/// last 14 days. Mirrors the web `/feed` route (decisions §31).
class FeedScreen extends StatefulWidget {
  final ApiClient api;
  /// Embedded mode skips the Scaffold/AppBar wrapping. Used by the
  /// SocialScreen Material TabBar host so a single Scaffold owns the
  /// tab chrome instead of nesting one per inner screen.
  final bool embedded;
  const FeedScreen({super.key, required this.api, this.embedded = false});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  static const _activities = <_ActivityOption>[
    _ActivityOption('all', Icons.apps),
    _ActivityOption('run', Icons.directions_run),
    _ActivityOption('walk', Icons.directions_walk),
    _ActivityOption('cycle', Icons.directions_bike),
    _ActivityOption('hike', Icons.terrain),
    _ActivityOption('lift', Icons.fitness_center),
  ];

  String _activityLabel(AppLocalizations l10n, String value) {
    switch (value) {
      case 'run':
        return l10n.feedActivityRun;
      case 'walk':
        return l10n.feedActivityWalk;
      case 'cycle':
        return l10n.feedActivityCycle;
      case 'hike':
        return l10n.feedActivityHike;
      case 'lift':
        return l10n.feedActivityLift;
      default:
        return l10n.feedActivityAll;
    }
  }

  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  Object? _loadError;

  List<ActivityFeedEntry> _entries = const [];
  Map<String, EngagementSummary> _engagement = const {};
  List<UserProfileRow> _followees = const [];
  List<BadgeAwardEntry> _badgeAwards = const [];

  String _authorFilter = 'all';
  String _activityFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  // Recent badge awards from people you follow — an auxiliary feed adornment
  // (L4). A failure here must never blank the core feed, so it loads on its
  // own and degrades to no strip.
  Future<void> _loadBadgeAwards() async {
    try {
      final awards = await widget.api.fetchFollowingBadgeAwards(limit: 6);
      if (!mounted) return;
      setState(() => _badgeAwards = awards);
    } catch (_) {
      if (!mounted) return;
      setState(() => _badgeAwards = const []);
    }
  }

  // Engagement (kudos / comments) only exists for runs. Lift cards carry no
  // engagement footer.
  static List<String> _runIds(List<ActivityFeedEntry> es) =>
      es.whereType<RunFeedEntry>().map((e) => e.run.id).toList();

  Future<void> _loadInitial() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    _loadBadgeAwards();
    try {
      final api = widget.api;
      final results = await Future.wait([
        api.fetchFollowingActivityFeed(
          limit: 20,
          authorId: _authorFilter == 'all' ? null : _authorFilter,
          activityType: _activityFilter,
        ),
        // Following list — drives the author-filter dropdown.
        // Capped at 200 to keep payload small (was 500 — overkill
        // for the dropdown UI). Users following more than 200
        // accounts can still filter via search; if a power-user
        // case emerges we'll add a "load more authors" affordance
        // rather than always pulling the long-tail of inactive
        // follows.
        api.userId == null
            ? Future.value(const <UserProfileRow>[])
            : api.fetchFollowing(api.userId!, limit: 200),
      ]);
      final entries = results[0] as List<ActivityFeedEntry>;
      final followees = results[1] as List<UserProfileRow>;

      final runIds = _runIds(entries);
      final engagement = runIds.isEmpty
          ? const <String, ({int kudosCount, bool viewerHasKudos, int commentCount})>{}
          : await api.fetchEngagementSummaries(runIds);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _followees = followees;
        _engagement = {
          for (final id in engagement.keys)
            id: EngagementSummary(
              kudosCount: engagement[id]!.kudosCount,
              viewerHasKudos: engagement[id]!.viewerHasKudos,
              commentCount: engagement[id]!.commentCount,
            ),
        };
        _exhausted = entries.length < 20;
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

  Future<void> _loadMore() async {
    if (_loadingMore || _exhausted || _entries.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final last = _entries.last;
      final more = await widget.api.fetchFollowingActivityFeed(
        limit: 20,
        cursor: (startedAt: last.startedAt, id: last.id),
        authorId: _authorFilter == 'all' ? null : _authorFilter,
        activityType: _activityFilter,
      );
      final moreRunIds = _runIds(more);
      final moreEng = moreRunIds.isEmpty
          ? const <String, ({int kudosCount, bool viewerHasKudos, int commentCount})>{}
          : await widget.api.fetchEngagementSummaries(moreRunIds);
      if (!mounted) return;
      setState(() {
        _entries = [..._entries, ...more];
        _engagement = {
          ..._engagement,
          for (final id in moreEng.keys)
            id: EngagementSummary(
              kudosCount: moreEng[id]!.kudosCount,
              viewerHasKudos: moreEng[id]!.viewerHasKudos,
              commentCount: moreEng[id]!.commentCount,
            ),
        };
        _exhausted = more.length < 20;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showTopBanner(
          context, AppLocalizations.of(context).feedLoadMoreFailed('$e'));
    }
  }

  void _setActivity(String value) {
    if (value == _activityFilter) return;
    setState(() => _activityFilter = value);
    _loadInitial();
  }

  void _setAuthor(String? value) {
    if (value == null || value == _authorFilter) return;
    setState(() => _authorFilter = value);
    _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.embedded) {
      return _buildBody(theme);
    }
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.feedTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search),
            tooltip: l10n.feedFindPeople,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PeopleScreen(api: widget.api),
                ),
              );
            },
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    return _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorState(
                  message: AppLocalizations.of(context).feedLoadError,
                  onRetry: _loadInitial,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_badgeAwards.isNotEmpty) _buildBadgeStrip(theme),
                    if (_followees.isNotEmpty) _buildToolbar(theme),
                    Expanded(
                      child: _entries.isEmpty
                          ? _buildEmpty(theme)
                          : RefreshIndicator(
                              onRefresh: _loadInitial,
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (n) {
                                  if (n.metrics.pixels >=
                                          n.metrics.maxScrollExtent - 200 &&
                                      !_loadingMore &&
                                      !_exhausted) {
                                    _loadMore();
                                  }
                                  return false;
                                },
                                child: ListView.separated(
                                  padding: const EdgeInsets.all(12),
                                  itemCount:
                                      _entries.length + (_exhausted ? 0 : 1),
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (_, i) {
                                    if (i >= _entries.length) {
                                      return Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: _loadingMore
                                              ? const CircularProgressIndicator()
                                              : TextButton(
                                                  onPressed: _loadMore,
                                                  child: Text(
                                                      AppLocalizations.of(
                                                              context)
                                                          .feedLoadMore),
                                                ),
                                        ),
                                      );
                                    }
                                    final entry = _entries[i];
                                    void openAuthor() => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ProfileScreen(
                                              api: widget.api,
                                              userId: entry.author.id,
                                            ),
                                          ),
                                        );
                                    if (entry is LiftFeedEntry) {
                                      return _LiftEntryCard(
                                        key: ValueKey(entry.id),
                                        entry: entry,
                                        onAuthorTap: openAuthor,
                                      );
                                    }
                                    final run = entry as RunFeedEntry;
                                    return _EntryCard(
                                      key: ValueKey(run.run.id),
                                      api: widget.api,
                                      entry: FeedEntry(
                                          run: run.run, author: run.author),
                                      initialEngagement: _engagement[run.run.id],
                                      onAuthorTap: openAuthor,
                                      onCardTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PublicRunScreen(
                                            api: widget.api,
                                            runId: run.run.id,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                    ),
                  ],
                );
  }

  Widget _buildBadgeStrip(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _badgeAwards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final a = _badgeAwards[i];
            final tierColor = badgeTierColor(a.badge.tier);
            final name = a.authorName ?? l10n.badgesARunner;
            final label = badgeLabelFor(l10n, a.badge.badgeKey, a.badge.tier);
            final icon = badgeIconData(
              tierFor(a.badge.badgeKey, a.badge.tier)?.icon ?? 'military_tech',
            );
            return ActionChip(
              avatar: Icon(icon, size: 18, color: tierColor),
              label: Text(
                l10n.badgesFeedEarned(name, label),
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ProfileScreen(api: widget.api, userId: a.authorId),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<String>(
            segments: _activities
                .map((a) => ButtonSegment<String>(
                      value: a.value,
                      icon: Icon(a.icon),
                      label: Text(_activityLabel(l10n, a.value)),
                    ))
                .toList(),
            selected: {_activityFilter},
            onSelectionChanged: (s) => _setActivity(s.first),
            showSelectedIcon: false,
          ),
          DropdownButton<String>(
            value: _authorFilter,
            onChanged: _setAuthor,
            items: [
              DropdownMenuItem(
                value: 'all',
                child: Text(l10n.feedEveryoneYouFollow),
              ),
              ..._followees.map(
                (f) => DropdownMenuItem(
                  value: f.id,
                  child: Text(f.displayName ?? l10n.feedRunnerFallback),
                ),
              ),
            ],
          ),
          Text(
            l10n.feedLast14Days,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final hasFollows = _followees.isNotEmpty;
    final filtered = _activityFilter != 'all' || _authorFilter != 'all';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              !hasFollows
                  ? l10n.feedEmptyTitle
                  : filtered
                      ? l10n.feedNoMatchesTitle
                      : l10n.feedNoActivityTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              !hasFollows
                  ? l10n.feedEmptyBody
                  : filtered
                      ? l10n.feedNoMatchesBody
                      : l10n.feedNoActivityBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (filtered) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _authorFilter = 'all';
                    _activityFilter = 'all';
                  });
                  _loadInitial();
                },
                child: Text(l10n.feedClearFilters),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActivityOption {
  final String value;
  final IconData icon;
  const _ActivityOption(this.value, this.icon);
}

class _EntryCard extends StatelessWidget {
  final ApiClient api;
  final FeedEntry entry;
  final EngagementSummary? initialEngagement;
  final VoidCallback onAuthorTap;
  final VoidCallback onCardTap;

  const _EntryCard({
    super.key,
    required this.api,
    required this.entry,
    required this.initialEngagement,
    required this.onAuthorTap,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — author row
          InkWell(
            onTap: onAuthorTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  _MiniAvatar(
                    displayName: entry.author.displayName,
                    avatarUrl: entry.author.avatarUrl,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.author.displayName ??
                          AppLocalizations.of(context).feedRunnerFallback,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    fmtRelative(entry.run.startedAt,
                        localeToTag(Localizations.localeOf(context))),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Track thumbnail — banner-style preview of the run shape so
          // the card's most distinctive signal sits above the fold.
          if (entry.run.trackUrl != null && entry.run.trackUrl!.isNotEmpty)
            InkWell(
              onTap: onCardTap,
              child: Container(
                height: 120,
                color: theme.colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: RunTrackPreview(
                  runId: entry.run.id,
                  trackUrl: entry.run.trackUrl,
                  api: api,
                  ownerUserId: entry.author.id,
                ),
              ),
            ),
          if (entry.run.trackUrl != null && entry.run.trackUrl!.isNotEmpty)
            const Divider(height: 1),
          // Stats — distance / time / pace; tap opens PublicRunScreen.
          InkWell(
            onTap: onCardTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Stat(
                    label: AppLocalizations.of(context).runStatDistance,
                    value: formatDistanceForPref(entry.run.distanceM),
                  ),
                  _Stat(
                    label: AppLocalizations.of(context).runStatTime,
                    value:
                        _fmtDuration(Duration(seconds: entry.run.durationS)),
                  ),
                  _Stat(
                    label: AppLocalizations.of(context).runStatPace,
                    value: _fmtPace(entry.run.distanceM, entry.run.durationS),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Kudos / comment chips. Stateful so toggling kudos rebuilds
          // only this footer instead of the parent FeedScreen and every
          // other visible card.
          _EngagementFooter(
            api: api,
            runId: entry.run.id,
            initialEngagement: initialEngagement,
            onCommentTap: onAuthorTap,
          ),
        ],
      ),
    );
  }

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }

  static String _fmtPace(double metres, int durationS) {
    if (metres <= 0 || durationS <= 0) return '—';
    return formatPaceForPref(durationS / (metres / 1000));
  }

}

class _EngagementFooter extends StatefulWidget {
  final ApiClient api;
  final String runId;
  final EngagementSummary? initialEngagement;
  final VoidCallback? onCommentTap;

  const _EngagementFooter({
    required this.api,
    required this.runId,
    required this.initialEngagement,
    this.onCommentTap,
  });

  @override
  State<_EngagementFooter> createState() => _EngagementFooterState();
}

class _EngagementFooterState extends State<_EngagementFooter> {
  static const _empty = EngagementSummary(
    kudosCount: 0,
    viewerHasKudos: false,
    commentCount: 0,
  );

  late EngagementSummary _eng;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _eng = widget.initialEngagement ?? _empty;
  }

  @override
  void didUpdateWidget(_EngagementFooter old) {
    super.didUpdateWidget(old);
    // Pick up a fresher engagement value pushed by the parent (e.g. when
    // the feed reloads) — but only if the user hasn't toggled locally
    // since, in which case our optimistic state is the truth.
    final fresh = widget.initialEngagement;
    if (!_busy && fresh != null && fresh != old.initialEngagement) {
      _eng = fresh;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final prev = _eng;
    setState(() {
      _busy = true;
      _eng = EngagementSummary(
        kudosCount: prev.viewerHasKudos
            ? (prev.kudosCount - 1).clamp(0, 1 << 30)
            : prev.kudosCount + 1,
        viewerHasKudos: !prev.viewerHasKudos,
        commentCount: prev.commentCount,
      );
    });
    try {
      if (prev.viewerHasKudos) {
        await widget.api.rescindKudos(widget.runId);
      } else {
        await widget.api.giveKudos(widget.runId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _eng = prev);
      showTopBanner(
          context, AppLocalizations.of(context).feedKudosUpdateFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _busy ? null : _toggle,
            icon: Icon(
              _eng.viewerHasKudos
                  ? Icons.favorite
                  : Icons.favorite_border,
              color: _eng.viewerHasKudos
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              size: 18,
            ),
            label: Text(
              '${_eng.kudosCount}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton.icon(
            onPressed: widget.onCommentTap,
            icon: Icon(
              Icons.chat_bubble_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            label: Text(
              '${_eng.commentCount}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// A public gym workout rendered as a "lift card" — title + set count +
/// total volume, distinct from a run card. Mirrors web's lift-card branch
/// in SocialFeed. No kudos / comments footer (engagement is run-only).
class _LiftEntryCard extends StatelessWidget {
  final LiftFeedEntry entry;
  final VoidCallback onAuthorTap;

  const _LiftEntryCard({
    super.key,
    required this.entry,
    required this.onAuthorTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final title = entry.title?.trim();
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onAuthorTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  _MiniAvatar(
                    displayName: entry.author.displayName,
                    avatarUrl: entry.author.avatarUrl,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.author.displayName ?? l10n.feedRunnerFallback,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    fmtRelative(entry.startedAt,
                        localeToTag(Localizations.localeOf(context))),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.fitness_center,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (title == null || title.isEmpty)
                            ? l10n.feedLiftUntitled
                            : title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Stat(
                      label: l10n.feedLiftSetsLabel,
                      value: '${entry.setCount}',
                    ),
                    if (entry.volumeKg > 0) ...[
                      const SizedBox(width: 32),
                      _Stat(
                        label: l10n.feedLiftVolume,
                        value: WeightFormat.format(
                            entry.volumeKg, activeWeightUnit),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final String? displayName;
  final String? avatarUrl;
  const _MiniAvatar({this.displayName, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letter = (displayName?.isNotEmpty ?? false)
        ? displayName![0].toUpperCase()
        : '?';
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary,
        image: avatarUrl != null && avatarUrl!.isNotEmpty
            ? DecorationImage(
                // ResizeImage decodes the avatar at ~3× the rendered
                // 32 dp circle instead of full source resolution — big
                // memory win when scrolling a feed full of cards.
                image: ResizeImage(
                  NetworkImage(avatarUrl!),
                  width: 96,
                  height: 96,
                ),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? Text(
              letter,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}
