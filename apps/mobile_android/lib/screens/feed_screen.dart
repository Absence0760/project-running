import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../preferences.dart';
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
    _ActivityOption('all', 'All', Icons.apps),
    _ActivityOption('run', 'Run', Icons.directions_run),
    _ActivityOption('walk', 'Walk', Icons.directions_walk),
    _ActivityOption('cycle', 'Cycle', Icons.directions_bike),
    _ActivityOption('hike', 'Hike', Icons.terrain),
  ];

  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  Object? _loadError;

  List<FeedEntry> _entries = const [];
  Map<String, EngagementSummary> _engagement = const {};
  List<UserProfileRow> _followees = const [];

  String _authorFilter = 'all';
  String _activityFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final api = widget.api;
      final results = await Future.wait([
        api.fetchFollowingFeed(
          limit: 20,
          authorId: _authorFilter == 'all' ? null : _authorFilter,
          activityType: _activityFilter,
        ),
        api.userId == null
            ? Future.value(const <UserProfileRow>[])
            : api.fetchFollowing(api.userId!, limit: 500),
      ]);
      final entries = results[0] as List<FeedEntry>;
      final followees = results[1] as List<UserProfileRow>;

      final engagement = entries.isEmpty
          ? const <String, ({int kudosCount, bool viewerHasKudos, int commentCount})>{}
          : await api.fetchEngagementSummaries(
              entries.map((e) => e.run.id).toList(),
            );
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
      final more = await widget.api.fetchFollowingFeed(
        limit: 20,
        cursor: (startedAt: last.run.startedAt, id: last.run.id),
        authorId: _authorFilter == 'all' ? null : _authorFilter,
        activityType: _activityFilter,
      );
      final moreEng = more.isEmpty
          ? const <String, ({int kudosCount, bool viewerHasKudos, int commentCount})>{}
          : await widget.api.fetchEngagementSummaries(
              more.map((e) => e.run.id).toList(),
            );
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
      showTopBanner(context, 'Could not load more: $e');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search),
            tooltip: 'Find people',
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
                  message: 'Could not load feed.',
                  onRetry: _loadInitial,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                                                  child: const Text('Load more'),
                                                ),
                                        ),
                                      );
                                    }
                                    return _EntryCard(
                                      key: ValueKey(_entries[i].run.id),
                                      api: widget.api,
                                      entry: _entries[i],
                                      initialEngagement:
                                          _engagement[_entries[i].run.id],
                                      onAuthorTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ProfileScreen(
                                            api: widget.api,
                                            userId: _entries[i].author.id,
                                          ),
                                        ),
                                      ),
                                      onCardTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PublicRunScreen(
                                            api: widget.api,
                                            runId: _entries[i].run.id,
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

  Widget _buildToolbar(ThemeData theme) {
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
                      label: Text(a.label),
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
              const DropdownMenuItem(
                value: 'all',
                child: Text('Everyone you follow'),
              ),
              ..._followees.map(
                (f) => DropdownMenuItem(
                  value: f.id,
                  child: Text(f.displayName ?? 'Runner'),
                ),
              ),
            ],
          ),
          Text(
            'Last 14 days',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
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
                  ? 'Your feed is empty'
                  : filtered
                      ? 'No matches'
                      : 'No recent activity',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              !hasFollows
                  ? 'Follow other runners to see their public runs here.'
                  : filtered
                      ? 'Nothing matches the current filters in the last 14 days.'
                      : 'Nobody you follow has logged a public run in the last 14 days.',
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
                child: const Text('Clear filters'),
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
  final String label;
  final IconData icon;
  const _ActivityOption(this.value, this.label, this.icon);
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
                      entry.author.displayName ?? 'Runner',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    _fmtRelative(entry.run.startedAt),
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
                    label: 'Distance',
                    value: formatDistanceForPref(entry.run.distanceM),
                  ),
                  _Stat(
                    label: 'Time',
                    value:
                        _fmtDuration(Duration(seconds: entry.run.durationS)),
                  ),
                  _Stat(
                    label: 'Pace',
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
    final secPerKm = durationS / (metres / 1000);
    final m = secPerKm ~/ 60;
    final s = (secPerKm % 60).round();
    return '$m:${s.toString().padLeft(2, '0')} /km';
  }

  static String _fmtRelative(DateTime started) {
    final ms = DateTime.now().difference(started).inMilliseconds;
    final mins = ms ~/ 60000;
    if (mins < 1) return 'just now';
    if (mins < 60) return '${mins}m ago';
    final hrs = mins ~/ 60;
    if (hrs < 24) return '${hrs}h ago';
    final days = hrs ~/ 24;
    if (days < 30) return '${days}d ago';
    return '${started.day}/${started.month}/${started.year}';
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
      showTopBanner(context, 'Could not update kudos: $e');
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
