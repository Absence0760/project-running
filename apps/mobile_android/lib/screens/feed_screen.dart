import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../widgets/error_state.dart';
import 'profile_screen.dart';

/// Activity feed of public runs from people you follow, capped to the
/// last 14 days. Mirrors the web `/feed` route (decisions §31).
class FeedScreen extends StatefulWidget {
  final ApiClient api;
  const FeedScreen({super.key, required this.api});

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
  Set<String> _kudosBusy = {};

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load more: $e')),
      );
    }
  }

  Future<void> _toggleKudos(String runId) async {
    if (_kudosBusy.contains(runId)) return;
    final current = _engagement[runId] ??
        const EngagementSummary(
          kudosCount: 0,
          viewerHasKudos: false,
          commentCount: 0,
        );
    setState(() {
      _kudosBusy = {..._kudosBusy, runId};
      _engagement = {
        ..._engagement,
        runId: EngagementSummary(
          kudosCount: current.viewerHasKudos
              ? (current.kudosCount - 1).clamp(0, 1 << 30)
              : current.kudosCount + 1,
          viewerHasKudos: !current.viewerHasKudos,
          commentCount: current.commentCount,
        ),
      };
    });
    try {
      if (current.viewerHasKudos) {
        await widget.api.rescindKudos(runId);
      } else {
        await widget.api.giveKudos(runId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _engagement = {..._engagement, runId: current};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update kudos: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          final next = {..._kudosBusy};
          next.remove(runId);
          _kudosBusy = next;
        });
      }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: _loading
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
                                      entry: _entries[i],
                                      engagement: _engagement[_entries[i].run.id],
                                      kudosBusy:
                                          _kudosBusy.contains(_entries[i].run.id),
                                      onToggleKudos: () =>
                                          _toggleKudos(_entries[i].run.id),
                                      onAuthorTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ProfileScreen(
                                            api: widget.api,
                                            userId: _entries[i].author.id,
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
                ),
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
  final FeedEntry entry;
  final EngagementSummary? engagement;
  final bool kudosBusy;
  final VoidCallback onToggleKudos;
  final VoidCallback onAuthorTap;

  const _EntryCard({
    required this.entry,
    required this.engagement,
    required this.kudosBusy,
    required this.onToggleKudos,
    required this.onAuthorTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eng = engagement ??
        const EngagementSummary(
          kudosCount: 0,
          viewerHasKudos: false,
          commentCount: 0,
        );
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
          // Stats — distance / time / pace
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(
                  label: 'Distance',
                  value: _fmtKm(entry.run.distanceM),
                ),
                _Stat(
                  label: 'Time',
                  value: _fmtDuration(Duration(seconds: entry.run.durationS)),
                ),
                _Stat(
                  label: 'Pace',
                  value: _fmtPace(entry.run.distanceM, entry.run.durationS),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Footer — kudos + comment chips
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: kudosBusy ? null : onToggleKudos,
                  icon: Icon(
                    eng.viewerHasKudos
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: eng.viewerHasKudos
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                  label: Text(
                    '${eng.kudosCount}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: onAuthorTap,
                  icon: Icon(
                    Icons.chat_bubble_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(
                    '${eng.commentCount}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtKm(double metres) =>
      '${(metres / 1000).toStringAsFixed(2)} km';

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
                image: NetworkImage(avatarUrl!),
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
