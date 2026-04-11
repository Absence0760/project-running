import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import '../local_run_store.dart';
import '../preferences.dart';
import 'run_detail_screen.dart';

/// Run history showing local runs with sync status.
///
/// Rendering is lazy (`ListView.builder`) and the filtered/sorted view is
/// cached in state rather than recomputed on every rebuild — both of those
/// matter when the store has thousands of runs.
class HistoryScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;
  final Preferences preferences;
  const HistoryScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.preferences,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

enum _HistorySort { newest, oldest, longest, fastest }

enum _HistoryRange { today, week, month, year, all }

class _HistoryScreenState extends State<HistoryScreen> {
  bool _syncing = false;
  bool _fetching = false;
  _HistorySort _sort = _HistorySort.newest;
  _HistoryRange _range = _HistoryRange.week;

  // Derived view — recomputed when the store, filter, or sort changes,
  // never on an unrelated rebuild. Keeps scroll jank down at 10k+ runs.
  List<Run> _visible = const [];
  Set<String> _unsyncedIds = const {};

  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    widget.runStore.addListener(_onStoreChanged);
    widget.preferences.addListener(_onStoreChanged);
    _recompute();
    _fetchRemote();
  }

  @override
  void dispose() {
    widget.runStore.removeListener(_onStoreChanged);
    widget.preferences.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    _recompute();
    // A run we had selected may have been deleted / replaced — drop any
    // dangling ids so the "N selected" count stays honest.
    final existing = widget.runStore.runs.map((r) => r.id).toSet();
    _selected.removeWhere((id) => !existing.contains(id));
    if (_selected.isEmpty) _selecting = false;
    setState(() {});
  }

  void _recompute() {
    _visible = _filterAndSort(widget.runStore.runs, _range, _sort);
    _unsyncedIds = widget.runStore.unsyncedRuns.map((r) => r.id).toSet();
  }

  static List<Run> _filterAndSort(
    List<Run> all,
    _HistoryRange range,
    _HistorySort sort,
  ) {
    final cutoff = _rangeCutoff(range);
    final filtered = cutoff == null
        ? List<Run>.from(all)
        : all.where((r) => !r.startedAt.isBefore(cutoff)).toList();
    switch (sort) {
      case _HistorySort.newest:
        filtered.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      case _HistorySort.oldest:
        filtered.sort((a, b) => a.startedAt.compareTo(b.startedAt));
      case _HistorySort.longest:
        filtered.sort((a, b) => b.distanceMetres.compareTo(a.distanceMetres));
      case _HistorySort.fastest:
        double pace(Run r) => r.distanceMetres < 10
            ? double.infinity
            : r.duration.inSeconds / (r.distanceMetres / 1000);
        filtered.sort((a, b) => pace(a).compareTo(pace(b)));
    }
    return filtered;
  }

  static DateTime? _rangeCutoff(_HistoryRange range) {
    final now = DateTime.now();
    switch (range) {
      case _HistoryRange.today:
        return DateTime(now.year, now.month, now.day);
      case _HistoryRange.week:
        // Start of the current ISO week (Monday 00:00 local).
        final startOfToday = DateTime(now.year, now.month, now.day);
        final daysFromMonday = (now.weekday - DateTime.monday) % 7;
        return startOfToday.subtract(Duration(days: daysFromMonday));
      case _HistoryRange.month:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 30));
      case _HistoryRange.year:
        return DateTime(now.year, 1, 1);
      case _HistoryRange.all:
        return null;
    }
  }

  static String _rangeLabel(_HistoryRange range) {
    switch (range) {
      case _HistoryRange.today:
        return 'Today';
      case _HistoryRange.week:
        return 'This week';
      case _HistoryRange.month:
        return 'Last 30 days';
      case _HistoryRange.year:
        return 'This year';
      case _HistoryRange.all:
        return 'All time';
    }
  }

  Future<void> _fetchRemote() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    setState(() => _fetching = true);
    try {
      final remote = await api.getRuns(limit: 200);
      for (final run in remote) {
        await widget.runStore.saveFromRemote(run);
      }
    } catch (e) {
      debugPrint('Fetch remote runs failed: $e');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _syncAll() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in from Settings to sync runs')),
      );
      return;
    }

    final unsynced = widget.runStore.unsyncedRuns;
    if (unsynced.isEmpty) return;

    setState(() => _syncing = true);
    int synced = 0;
    String? lastError;

    for (final run in unsynced) {
      try {
        await api.saveRun(run);
        await widget.runStore.markSynced(run.id);
        synced++;
      } catch (e) {
        lastError = e.toString();
      }
    }

    setState(() => _syncing = false);

    if (!mounted) return;
    if (lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Synced $synced/${unsynced.length}. Error: $lastError')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('All $synced runs synced')),
      );
    }
  }

  // ── Selection mode ────────────────────────────────────────────────

  void _enterSelection(String firstId) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(firstId);
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selecting = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _selectAllVisible() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_visible.map((r) => r.id));
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count run${count == 1 ? '' : 's'}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final ids = Set<String>.from(_selected);
    await widget.runStore.deleteMany(ids);
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted $count run${count == 1 ? '' : 's'}')),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    final totalCount = widget.runStore.runs.length;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _clearSelection();
      },
      child: Scaffold(
        appBar: _selecting ? _selectionAppBar() : _normalAppBar(),
        body: _buildBody(theme, unit, totalCount),
      ),
    );
  }

  AppBar _normalAppBar() {
    final unsyncedCount = widget.runStore.unsyncedCount;
    return AppBar(
      title: const Text('History'),
      actions: [
        PopupMenuButton<_HistoryRange>(
          icon: const Icon(Icons.calendar_month_outlined),
          tooltip: 'Date range',
          onSelected: (v) {
            setState(() {
              _range = v;
              _recompute();
            });
          },
          itemBuilder: (_) => _HistoryRange.values
              .map((r) => CheckedPopupMenuItem(
                    value: r,
                    checked: _range == r,
                    child: Text(_rangeLabel(r)),
                  ))
              .toList(),
        ),
        PopupMenuButton<_HistorySort>(
          icon: const Icon(Icons.sort),
          tooltip: 'Sort',
          onSelected: (v) {
            setState(() {
              _sort = v;
              _recompute();
            });
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: _HistorySort.newest,
              checked: _sort == _HistorySort.newest,
              child: const Text('Newest first'),
            ),
            CheckedPopupMenuItem(
              value: _HistorySort.oldest,
              checked: _sort == _HistorySort.oldest,
              child: const Text('Oldest first'),
            ),
            CheckedPopupMenuItem(
              value: _HistorySort.longest,
              checked: _sort == _HistorySort.longest,
              child: const Text('Longest distance'),
            ),
            CheckedPopupMenuItem(
              value: _HistorySort.fastest,
              checked: _sort == _HistorySort.fastest,
              child: const Text('Fastest pace'),
            ),
          ],
        ),
        if (_fetching || _syncing)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (unsyncedCount > 0)
          Badge(
            label: Text('$unsyncedCount'),
            child: IconButton(
              icon: const Icon(Icons.cloud_upload),
              tooltip: 'Sync $unsyncedCount runs',
              onPressed: _syncAll,
            ),
          )
        else if (widget.apiClient?.userId != null)
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: 'Refresh from cloud',
            onPressed: _fetchRemote,
          )
        else
          const IconButton(
            icon: Icon(Icons.cloud_off),
            tooltip: 'Offline',
            onPressed: null,
          ),
      ],
    );
  }

  AppBar _selectionAppBar() {
    final allSelected =
        _visible.isNotEmpty && _selected.length == _visible.length;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel',
        onPressed: _clearSelection,
      ),
      title: Text('${_selected.length} selected'),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected ? 'Clear' : 'Select all',
          onPressed: allSelected
              ? () => setState(() => _selected.clear())
              : _selectAllVisible,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: _selected.isEmpty ? null : _deleteSelected,
        ),
      ],
    );
  }

  Widget _buildBody(ThemeData theme, DistanceUnit unit, int totalCount) {
    if (totalCount == 0) {
      return _EmptyHistory(theme: theme);
    }
    if (_visible.isEmpty) {
      return _EmptyFilter(
        theme: theme,
        label: _rangeLabel(_range),
        onShowAll: () {
          setState(() {
            _range = _HistoryRange.all;
            _recompute();
          });
        },
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchRemote,
      child: _buildRunList(theme, unit),
    );
  }

  Widget _buildRunList(ThemeData theme, DistanceUnit unit) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _visible.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_rangeLabel(_range), style: theme.textTheme.titleMedium),
                Text(
                  '${_visible.length} run${_visible.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        }
        final run = _visible[index - 1];
        return _RunTile(
          key: ValueKey(run.id),
          run: run,
          unit: unit,
          theme: theme,
          isUnsynced: _unsyncedIds.contains(run.id),
          selecting: _selecting,
          selected: _selected.contains(run.id),
          onTap: () {
            if (_selecting) {
              _toggleSelection(run.id);
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RunDetailScreen(
                  run: run,
                  runStore: widget.runStore,
                  preferences: widget.preferences,
                  apiClient: widget.apiClient,
                ),
              ),
            );
          },
          onLongPress: () {
            if (_selecting) return;
            _enterSelection(run.id);
          },
        );
      },
    );
  }
}

class _RunTile extends StatelessWidget {
  final Run run;
  final DistanceUnit unit;
  final ThemeData theme;
  final bool isUnsynced;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RunTile({
    super.key,
    required this.run,
    required this.unit,
    required this.theme,
    required this.isUnsynced,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final dist = UnitFormat.distance(run.distanceMetres, unit);
    final dur = _formatDuration(run.duration);
    final paceSecPerKm = run.distanceMetres < 10
        ? null
        : run.duration.inSeconds / (run.distanceMetres / 1000);
    final activity =
        ActivityType.fromName(run.metadata?['activity_type'] as String?);
    final trailingMetric = activity.usesSpeed
        ? '${UnitFormat.speed(paceSecPerKm, unit)} ${UnitFormat.speedLabel(unit)}'
        : '${UnitFormat.pace(paceSecPerKm, unit)} ${UnitFormat.paceLabel(unit)}';
    final date = _formatDate(run.startedAt);

    final leading = selecting
        ? Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          )
        : CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(activity.icon, color: theme.colorScheme.primary),
          );

    return Card(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      child: ListTile(
        leading: leading,
        title: Text(dist),
        subtitle: Text('$date  •  $dur'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(trailingMetric, style: theme.textTheme.bodySmall),
            if (isUnsynced) ...[
              const SizedBox(width: 8),
              Icon(Icons.cloud_off,
                  size: 16, color: theme.colorScheme.outline),
            ],
          ],
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }
}

class _EmptyHistory extends StatelessWidget {
  final ThemeData theme;
  const _EmptyHistory({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_run, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('No runs yet', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Tap the Run tab to start your first run',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFilter extends StatelessWidget {
  final ThemeData theme;
  final String label;
  final VoidCallback onShowAll;
  const _EmptyFilter({
    required this.theme,
    required this.label,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('No runs in $label', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onShowAll,
            child: const Text('Show all time'),
          ),
        ],
      ),
    );
  }
}
