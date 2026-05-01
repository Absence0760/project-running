import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../goals.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import 'add_run_screen.dart';
import 'run_detail_screen.dart';

/// Runs list showing local runs with sync status.
///
/// Rendering is lazy (`ListView.builder`) and the filtered/sorted view is
/// cached in state rather than recomputed on every rebuild — both of those
/// matter when the store has thousands of runs.
class RunsScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final SettingsSyncService? settingsSync;
  const RunsScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    this.settingsSync,
  });

  @override
  State<RunsScreen> createState() => _RunsScreenState();
}

enum _RunsSort { newest, oldest, longest, fastest }

enum _RunsRange { today, week, month, year, all, custom }

/// SharedPreferences key for the persisted filter blob (range / sort /
/// activity / source / custom-from / custom-to). Mirrors the web app's
/// `runs_filters_v1` key — the shape is screen-local, not roamed
/// through `user_settings`, because date filters are personal-context
/// (the device + moment), not a cross-device preference.
const String _kRunsFiltersKey = 'runs_filters_v1';

/// Page size for the cloud fetch + the visible-list window. Mirrors the
/// web app's `/runs` PAGE_SIZE so a returning user sees the same shape
/// of "first page + Load more" on both clients. Keep it small — the
/// list view is the cold-start frame, and pulling 200 rows over a
/// flaky cellular connection blocks the rest of the home screen.
const int _kRunsPageSize = 20;

/// True when the Load-more button should render at the bottom of the
/// runs list — either the local filtered superset has more rows beyond
/// `visibleCount`, or the cloud might have older runs we haven't
/// pulled yet. Pure helper kept top-level so its boundary conditions
/// can be unit-tested directly without mounting the screen.
///
/// The cloud branch is gated by [filterCutoff] / [oldestLocalStartedAt]:
/// the cloud cursor walks strictly older than the oldest local run, so
/// when the active range filter (today / week / month / year) has a
/// `from` boundary that the oldest local row already predates, no cloud
/// page can contain a match — hide the button instead of inviting a
/// fetch that would never grow `filteredCount`.
@visibleForTesting
bool shouldShowRunsLoadMore({
  required int visibleCount,
  required int filteredCount,
  required bool remoteHasMore,
  required bool apiSignedIn,
  DateTime? filterCutoff,
  DateTime? oldestLocalStartedAt,
}) {
  if (visibleCount < filteredCount) return true;
  if (!(remoteHasMore && apiSignedIn)) return false;
  if (filterCutoff != null &&
      oldestLocalStartedAt != null &&
      !oldestLocalStartedAt.isAfter(filterCutoff)) {
    return false;
  }
  return true;
}

class _RunsScreenState extends State<RunsScreen> {
  bool _syncing = false;
  bool _fetching = false;
  _RunsSort _sort = _RunsSort.newest;
  _RunsRange _range = _RunsRange.week;
  ActivityType? _activityFilter;
  /// `null` means "all sources" — the default. Non-null values match
  /// `Run.source` exactly; see `RunSource` in `core_models`.
  RunSource? _sourceFilter;

  /// Custom range bounds. Either may be `null` (open-ended on that
  /// side) — matches web's `customFrom` / `customTo`. Only consulted
  /// when `_range == _RunsRange.custom`. The values are kept across
  /// flips to/from custom so the user doesn't have to re-pick after
  /// switching to "All time" and back.
  DateTime? _customFrom;
  DateTime? _customTo;

  // Filtered + sorted full list (the slice _visible is taken from).
  // We keep the unfiltered superset around so the Load-more button can
  // reveal local rows before paying the cost of a cloud round-trip.
  List<Run> _filtered = const [];
  // What the UI actually renders — the first _visibleCount of _filtered.
  // Capped at _filtered.length so taking past the end is a no-op.
  List<Run> _visible = const [];
  Set<String> _unsyncedIds = const {};

  /// How many filtered rows the list is currently revealing. Resets to
  /// _kRunsPageSize whenever the filter/sort changes. Grows by
  /// _kRunsPageSize on each Load-more tap.
  int _visibleCount = _kRunsPageSize;
  /// True while a "Load more" cloud fetch is in flight. Disables the
  /// button and renders an inline progress indicator.
  bool _loadingMore = false;
  /// Whether the cloud is believed to have older runs the local store
  /// hasn't seen. Set to false when a paginated `getRuns` returns less
  /// than _kRunsPageSize rows (the standard "out of pages" signal).
  bool _remoteHasMore = true;

  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    widget.runStore.addListener(_onStoreChanged);
    widget.preferences.addListener(_onStoreChanged);
    _recompute();
    _hydrateFilters();
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
    setState(() {
      _recompute();
      final existing = widget.runStore.runs.map((r) => r.id).toSet();
      _selected.removeWhere((id) => !existing.contains(id));
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _recompute() {
    _filtered = _filterAndSort(
      widget.runStore.runs,
      _lowerCutoff(),
      _upperCutoff(),
      _sort,
      _activityFilter,
      _sourceFilter,
    );
    _visible = _filtered.length <= _visibleCount
        ? _filtered
        : _filtered.sublist(0, _visibleCount);
    _unsyncedIds = widget.runStore.unsyncedRuns.map((r) => r.id).toSet();
  }

  /// Reset paging window back to the first page. Called on filter /
  /// sort / range change so a user who narrows their view doesn't
  /// inherit the previous "Load more" depth.
  void _resetPaging() {
    _visibleCount = _kRunsPageSize;
    _remoteHasMore = true;
  }

  /// Restore range / sort / activity / source / custom-bounds from
  /// SharedPreferences so the user picks up where they left off across
  /// app restarts. Best-effort: any malformed blob is ignored and the
  /// in-memory defaults stand. Mirrors the web app's `runs_filters_v1`
  /// localStorage shape.
  Future<void> _hydrateFilters() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kRunsFiltersKey);
      if (raw == null || !mounted) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final rangeName = j['range'] as String?;
      final sortName = j['sort'] as String?;
      final activityName = j['activity'] as String?;
      final sourceName = j['source'] as String?;
      final fromMs = j['customFromMs'];
      final toMs = j['customToMs'];
      setState(() {
        if (rangeName != null) {
          _range = _RunsRange.values.firstWhere(
            (e) => e.name == rangeName,
            orElse: () => _range,
          );
        }
        if (sortName != null) {
          _sort = _RunsSort.values.firstWhere(
            (e) => e.name == sortName,
            orElse: () => _sort,
          );
        }
        _activityFilter =
            activityName == null ? null : ActivityType.fromName(activityName);
        _sourceFilter = sourceName == null
            ? null
            : RunSource.values.firstWhere(
                (e) => e.name == sourceName,
                orElse: () => RunSource.app,
              );
        if (fromMs is int) {
          _customFrom = DateTime.fromMillisecondsSinceEpoch(fromMs);
        }
        if (toMs is int) {
          _customTo = DateTime.fromMillisecondsSinceEpoch(toMs);
        }
        _resetPaging();
        _recompute();
      });
    } catch (_) {
      // Corrupt blob or storage unavailable — leave defaults in place.
    }
  }

  /// Persist the current filter selection. Fire-and-forget; a failed
  /// write isn't worth blocking the UI for, and the next change will
  /// retry.
  void _persistFilters() {
    SharedPreferences.getInstance().then((p) {
      p.setString(
        _kRunsFiltersKey,
        jsonEncode({
          'range': _range.name,
          'sort': _sort.name,
          'activity': _activityFilter?.name,
          'source': _sourceFilter?.name,
          'customFromMs': _customFrom?.millisecondsSinceEpoch,
          'customToMs': _customTo?.millisecondsSinceEpoch,
        }),
      );
    }).catchError((Object _) {
      // L4 best-effort persistence — never escalate.
    });
  }

  static List<Run> _filterAndSort(
    List<Run> all,
    DateTime? lowerCutoff,
    DateTime? upperCutoff,
    _RunsSort sort,
    ActivityType? activityFilter,
    RunSource? sourceFilter,
  ) {
    // Pipe filters through Iterable.where so we materialise a List
    // exactly once. When no filter applies and the requested sort
    // matches the store's natural newest-first order, we can return
    // the input directly (zero-alloc fast path) since the store hands
    // us an unmodifiable view that the caller only reads.
    Iterable<Run> stream = all;
    if (lowerCutoff != null) {
      stream = stream.where((r) => !r.startedAt.isBefore(lowerCutoff));
    }
    if (upperCutoff != null) {
      stream = stream.where((r) => !r.startedAt.isAfter(upperCutoff));
    }
    if (activityFilter != null) {
      stream = stream.where((r) {
        final type = ActivityType.fromName(
            r.metadata?['activity_type'] as String?);
        return type == activityFilter;
      });
    }
    if (sourceFilter != null) {
      stream = stream.where((r) => r.source == sourceFilter);
    }
    final noFilters = identical(stream, all);
    if (noFilters && sort == _RunsSort.newest) return all;
    final filtered =
        noFilters ? List<Run>.from(all) : stream.toList();
    switch (sort) {
      case _RunsSort.newest:
        filtered.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      case _RunsSort.oldest:
        filtered.sort((a, b) => a.startedAt.compareTo(b.startedAt));
      case _RunsSort.longest:
        filtered.sort((a, b) => b.distanceMetres.compareTo(a.distanceMetres));
      case _RunsSort.fastest:
        double pace(Run r) => r.distanceMetres < 10
            ? double.infinity
            : r.duration.inSeconds / (r.distanceMetres / 1000);
        filtered.sort((a, b) => pace(a).compareTo(pace(b)));
    }
    return filtered;
  }

  /// Lower bound of the active range filter, in local time. `null`
  /// means "no lower cutoff" (range = all, or custom with no `from`).
  DateTime? _lowerCutoff() {
    final now = DateTime.now();
    switch (_range) {
      case _RunsRange.today:
        return DateTime(now.year, now.month, now.day);
      case _RunsRange.week:
        return weekStartLocal(now);
      case _RunsRange.month:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 30));
      case _RunsRange.year:
        return DateTime(now.year, 1, 1);
      case _RunsRange.all:
        return null;
      case _RunsRange.custom:
        return _customFrom;
    }
  }

  /// Upper bound of the active range filter, in local time. Only
  /// `custom` carries an upper cutoff today — every other preset is
  /// open-ended on the high side ("today" runs from midnight to now,
  /// but a future run scheduled today would still show, which matches
  /// the web app's choice).
  DateTime? _upperCutoff() {
    if (_range == _RunsRange.custom) return _customTo;
    return null;
  }

  static String _rangeLabel(_RunsRange range) {
    switch (range) {
      case _RunsRange.today:
        return 'Today';
      case _RunsRange.week:
        return 'This week';
      case _RunsRange.month:
        return 'Last 30 days';
      case _RunsRange.year:
        return 'This year';
      case _RunsRange.all:
        return 'All time';
      case _RunsRange.custom:
        return 'Custom…';
    }
  }

  /// Header label for the active range. For preset ranges we render
  /// the static label; for custom we format the picked bounds inline
  /// so the user always sees what window the list is showing.
  String _activeRangeLabel() {
    if (_range != _RunsRange.custom) return _rangeLabel(_range);
    final from = _customFrom;
    final to = _customTo;
    if (from == null && to == null) return 'Custom…';
    if (from != null && to != null) {
      return '${_formatRangeDate(from)} – ${_formatRangeDate(to)}';
    }
    if (from != null) return 'From ${_formatRangeDate(from)}';
    return 'Until ${_formatRangeDate(to!)}';
  }

  /// Compact "May 1" / "May 1, 2025" date formatter for the header
  /// label. Year is omitted when it matches the current year so the
  /// usual case stays terse; included otherwise so "Jan 5" doesn't
  /// silently mean a different year than the user expects.
  static String _formatRangeDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    final base = '${months[d.month - 1]} ${d.day}';
    return d.year == now.year ? base : '$base, ${d.year}';
  }

  Future<void> _fetchRemote() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    setState(() => _fetching = true);
    try {
      // Two distinct paths, both bounded:
      //
      // - First load (since == null): fetch the first page only — same
      //   shape as the web app's `/runs` initial load. Older runs come
      //   in via "Load more" rather than a 200-row up-front pull. Sets
      //   `_remoteHasMore` based on whether the page filled, so the
      //   button knows when to stop.
      //
      // - Delta sync (since != null): pull every row modified since
      //   the last successful fetch. The cap is generous (200) because
      //   this catches up from a multi-device edit burst, not a cold
      //   library load — and the cap is one trip, not per-paint.
      final since = widget.preferences.runsLastFetchedAt;
      final fetchStartedAt = DateTime.now().toUtc();
      final remote = since == null
          ? await api.getRuns(limit: _kRunsPageSize)
          : await api.getRuns(limit: 200, updatedSince: since);
      await widget.runStore.saveManyFromRemote(remote);
      await widget.preferences.setRunsLastFetchedAt(fetchStartedAt);
      if (since == null && mounted) {
        setState(() => _remoteHasMore = remote.length == _kRunsPageSize);
      }
    } catch (e) {
      debugPrint('Fetch remote runs failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not refresh — check your connection')),
        );
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  /// Reveal the next page of runs. Two layers, in order:
  ///
  /// 1. If the local filtered list has more rows than we're currently
  ///    showing, just bump the visibility window — no network round-trip.
  /// 2. If we've revealed everything local and the cloud might still
  ///    have older runs (`_remoteHasMore`), fetch one page using the
  ///    oldest local run's `started_at` as a `before` cursor. Cursor
  ///    over offset because runs are append-only-by-time and a cursor
  ///    is stable against concurrent inserts/deletes.
  Future<void> _loadMore() async {
    if (_loadingMore) return;

    final hasMoreLocal = _visibleCount < _filtered.length;
    if (hasMoreLocal) {
      setState(() {
        _visibleCount += _kRunsPageSize;
        _recompute();
      });
      // After revealing locally, opportunistically pull the next cloud
      // page if we just hit the bottom of what's cached and the cloud
      // is believed to have more. Prevents a "tap, see new rows, tap
      // again, wait" two-step.
      if (_visibleCount >= _filtered.length && _remoteHasMore) {
        await _fetchOlderFromRemote();
      }
      return;
    }

    if (_remoteHasMore) {
      await _fetchOlderFromRemote();
    }
  }

  Future<void> _fetchOlderFromRemote() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      // Nothing to fetch — flip `_remoteHasMore` so the button hides
      // instead of perpetually offering a no-op.
      if (mounted) setState(() => _remoteHasMore = false);
      return;
    }

    setState(() => _loadingMore = true);
    try {
      // Oldest *unfiltered* local run drives the cursor — the cloud
      // doesn't know about local filters, and asking for "before
      // 2024-06-12 amongst this-week runs" would skip rows the user
      // never had.
      final all = widget.runStore.runs;
      final cursor = all.isEmpty ? DateTime.now() : all.last.startedAt;
      final remote =
          await api.getRuns(limit: _kRunsPageSize, before: cursor);
      await widget.runStore.saveManyFromRemote(remote);
      if (!mounted) return;
      setState(() {
        _remoteHasMore = remote.length == _kRunsPageSize;
        _visibleCount += _kRunsPageSize;
        _recompute();
      });
    } catch (e) {
      debugPrint('Load more runs failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load more runs')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
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

    try {
      await api.saveRunsBatch(unsynced);
      await widget.runStore.markManySynced(unsynced.map((r) => r.id));
      synced = unsynced.length;
    } catch (e) {
      lastError = e.toString();
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
    final failedIds = <String>{};
    final api = widget.apiClient;
    if (api != null && api.userId != null) {
      final runsToDelete =
          widget.runStore.runs.where((r) => ids.contains(r.id));
      for (final run in runsToDelete) {
        try {
          await api.deleteRun(run);
        } catch (e) {
          debugPrint('deleteRun failed for ${run.id}: $e');
          failedIds.add(run.id);
        }
      }
    }
    // Only delete locally the runs whose remote delete succeeded.
    // Runs whose remote delete failed are kept locally so they don't
    // silently resurface on the next sync, and queued for SyncService
    // to retry on its usual triggers (foreground, connectivity-on,
    // startup) — see data-sync audit P0-1.
    await widget.runStore.deleteMany(ids.difference(failedIds));
    if (failedIds.isNotEmpty) {
      await widget.runStore.markManyPendingRemoteDelete(failedIds);
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    if (failedIds.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${ids.length - failedIds.length} deleted; '
            '${failedIds.length} queued — will retry when back online.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $count run${count == 1 ? '' : 's'}')),
      );
    }
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
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton.extended(
                heroTag: 'history_add_run_fab',
                onPressed: _openAddRun,
                icon: const Icon(Icons.add),
                label: const Text('Add run'),
                tooltip: 'Add a run manually',
              ),
      ),
    );
  }

  void _openAddRun() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddRunScreen(
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
        ),
      ),
    );
  }

  /// Opens an airline-style bottom-sheet calendar (see
  /// `_RangeCalendarSheet`): scrollable month grid, two-tap selection
  /// with range highlighting, sticky Start / End chips, Apply at the
  /// bottom. The sheet snaps the picked range to start-of-day /
  /// end-of-day so `_filterAndSort` comparators include both endpoints
  /// inclusively. Dismiss without applying is a no-op.
  Future<void> _pickCustomRange() async {
    final result = await showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RangeCalendarSheet(
        initialFrom: _customFrom,
        initialTo: _customTo,
      ),
    );
    if (result == null || !mounted) return;
    final from = DateTime(
        result.start.year, result.start.month, result.start.day);
    final to = DateTime(
        result.end.year, result.end.month, result.end.day, 23, 59, 59, 999);
    setState(() {
      _range = _RunsRange.custom;
      _customFrom = from;
      _customTo = to;
      _resetPaging();
      _recompute();
    });
    _persistFilters();
  }

  AppBar _normalAppBar() {
    final unsyncedCount = widget.runStore.unsyncedCount;
    return AppBar(
      title: const Text('History'),
      actions: [
        PopupMenuButton<_RunsRange>(
          icon: const Icon(Icons.calendar_month_outlined),
          tooltip: 'Date range',
          onSelected: (v) async {
            // Custom always opens the picker, even when already selected
            // — that's the only way to change the bounds without first
            // flipping to a different range and back.
            if (v == _RunsRange.custom) {
              await _pickCustomRange();
              return;
            }
            setState(() {
              _range = v;
              _resetPaging();
              _recompute();
            });
            _persistFilters();
          },
          itemBuilder: (_) => _RunsRange.values
              .map((r) => CheckedPopupMenuItem(
                    value: r,
                    checked: _range == r,
                    child: Text(_rangeLabel(r)),
                  ))
              .toList(),
        ),
        PopupMenuButton<_RunsSort>(
          icon: const Icon(Icons.sort),
          tooltip: 'Sort',
          onSelected: (v) {
            setState(() {
              _sort = v;
              _resetPaging();
              _recompute();
            });
            _persistFilters();
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: _RunsSort.newest,
              checked: _sort == _RunsSort.newest,
              child: const Text('Newest first'),
            ),
            CheckedPopupMenuItem(
              value: _RunsSort.oldest,
              checked: _sort == _RunsSort.oldest,
              child: const Text('Oldest first'),
            ),
            CheckedPopupMenuItem(
              value: _RunsSort.longest,
              checked: _sort == _RunsSort.longest,
              child: const Text('Longest distance'),
            ),
            CheckedPopupMenuItem(
              value: _RunsSort.fastest,
              checked: _sort == _RunsSort.fastest,
              child: const Text('Best pace'),
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
      return _EmptyRuns(theme: theme);
    }
    return RefreshIndicator(
      onRefresh: _fetchRemote,
      child: _buildRunList(theme, unit),
    );
  }

  Widget _buildRunList(ThemeData theme, DistanceUnit unit) {
    // +1 for the header row; +1 for the empty-state message when filters
    // match nothing (so the filter chips stay visible and tappable);
    // +1 for the Load-more footer row when there's potentially another
    // page (more local rows under the filter or more on the cloud).
    final emptyAfterFilter = _visible.isEmpty;
    final allRuns = widget.runStore.runs;
    final oldestLocal = allRuns.isEmpty
        ? null
        : allRuns
            .map((r) => r.startedAt)
            .reduce((a, b) => a.isBefore(b) ? a : b);
    final showLoadMore = !emptyAfterFilter &&
        shouldShowRunsLoadMore(
          visibleCount: _visibleCount,
          filteredCount: _filtered.length,
          remoteHasMore: _remoteHasMore,
          apiSignedIn: widget.apiClient?.userId != null,
          filterCutoff: _lowerCutoff(),
          oldestLocalStartedAt: oldestLocal,
        );
    final loadMoreSlot = showLoadMore ? 1 : 0;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount:
          _visible.length + 1 + (emptyAfterFilter ? 1 : 0) + loadMoreSlot,
      itemBuilder: (context, index) {
        if (showLoadMore && index == _visible.length + 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : OutlinedButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more),
                      label: Text('Load $_kRunsPageSize more'),
                    ),
            ),
          );
        }
        if (index == 0) {
          return _RunsFilterHeader(
            rangeLabel: _activeRangeLabel(),
            visibleCount: _visible.length,
            activityFilter: _activityFilter,
            sourceFilter: _sourceFilter,
            onActivityChanged: (v) {
              setState(() {
                _activityFilter = v;
                _resetPaging();
                _recompute();
              });
              _persistFilters();
            },
            onSourceChanged: (v) {
              setState(() {
                _sourceFilter = v;
                _resetPaging();
                _recompute();
              });
              _persistFilters();
            },
          );
        }
        if (emptyAfterFilter && index == 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(Icons.event_busy,
                    size: 48, color: theme.colorScheme.outline),
                const SizedBox(height: 12),
                Text(
                  'No runs match these filters',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _activityFilter = null;
                      _sourceFilter = null;
                      _range = _RunsRange.all;
                      _customFrom = null;
                      _customTo = null;
                      _resetPaging();
                      _recompute();
                    });
                    _persistFilters();
                  },
                  child: const Text('Clear filters'),
                ),
              ],
            ),
          );
        }
        final runIndex = index - 1;
        if (runIndex < 0 || runIndex >= _visible.length) {
          return const SizedBox.shrink();
        }
        final run = _visible[runIndex];
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
                  routeStore: widget.routeStore,
                  preferences: widget.preferences,
                  apiClient: widget.apiClient,
                  settingsSync: widget.settingsSync,
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

class _EmptyRuns extends StatelessWidget {
  final ThemeData theme;
  const _EmptyRuns({required this.theme});

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

/// Header row + activity / source filter chips for [RunsScreen]. Pulled
/// out of the inline ListView builder so each chip tap doesn't re-run
/// the full builder closure for the header subtree on every setState —
/// the parent supplies new selections + callbacks, but the widget tree
/// itself is contained.
class _RunsFilterHeader extends StatelessWidget {
  final String rangeLabel;
  final int visibleCount;
  final ActivityType? activityFilter;
  final RunSource? sourceFilter;
  final ValueChanged<ActivityType?> onActivityChanged;
  final ValueChanged<RunSource?> onSourceChanged;

  const _RunsFilterHeader({
    required this.rangeLabel,
    required this.visibleCount,
    required this.activityFilter,
    required this.sourceFilter,
    required this.onActivityChanged,
    required this.onSourceChanged,
  });

  static const _sourceChips = <(RunSource, String)>[
    (RunSource.app, 'Recorded'),
    (RunSource.watch, 'Watch'),
    (RunSource.strava, 'Strava'),
    (RunSource.parkrun, 'parkrun'),
    (RunSource.healthkit, 'HealthKit'),
    (RunSource.healthconnect, 'Health Connect'),
  ];

  // Pastel purple for the selected chip background. The default
  // theme.colorScheme.secondaryContainer derived from the dusk seed
  // rendered as dark purple, dropping the label into low-contrast
  // territory. This matches the existing `lilac` palette entry in
  // ui_kit's AppPalette without pulling the package as a dep.
  static const _selectedChipColour = Color(0xFFD8CCFA);
  static const _selectedChipLabel = Color(0xFF120D22);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(rangeLabel, style: theme.textTheme.titleMedium),
            Text(
              '$visibleCount run${visibleCount == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ChipTheme(
          data: theme.chipTheme.copyWith(
            selectedColor: _selectedChipColour,
            secondarySelectedColor: _selectedChipColour,
            checkmarkColor: _selectedChipLabel,
            secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
                  color: _selectedChipLabel,
                ) ??
                const TextStyle(color: _selectedChipLabel),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: activityFilter == null,
                      onSelected: (_) => onActivityChanged(null),
                    ),
                    const SizedBox(width: 8),
                    for (final type in ActivityType.values) ...[
                      FilterChip(
                        avatar: Icon(type.icon, size: 18),
                        label: Text(type.label),
                        selected: activityFilter == type,
                        onSelected: (_) => onActivityChanged(type),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Source filter — matches the web's dashboard chip row so a
              // runner filtering by "Strava-imported only" on both
              // surfaces sees the same subset. `null` = all sources.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All sources'),
                      selected: sourceFilter == null,
                      onSelected: (_) => onSourceChanged(null),
                    ),
                    const SizedBox(width: 8),
                    for (final entry in _sourceChips) ...[
                      FilterChip(
                        label: Text(entry.$2),
                        selected: sourceFilter == entry.$1,
                        onSelected: (_) => onSourceChanged(entry.$1),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Airline-style date-range bottom sheet (Expedia / Delta / United
/// pattern). Vertically scrollable list of month grids, two-tap
/// selection with the in-between range highlighted, sticky Start / End
/// chips at the top, and a sticky Apply / Clear footer. Dismissing
/// without Apply discards the pending selection.
///
/// The sheet manages its own pending state and only commits to the
/// caller (via `Navigator.pop(DateTimeRange)`) when Apply is tapped
/// with both endpoints set. This keeps the screen-level filter from
/// thrashing while the user picks.
class _RangeCalendarSheet extends StatefulWidget {
  final DateTime? initialFrom;
  final DateTime? initialTo;

  const _RangeCalendarSheet({this.initialFrom, this.initialTo});

  @override
  State<_RangeCalendarSheet> createState() => _RangeCalendarSheetState();
}

class _RangeCalendarSheetState extends State<_RangeCalendarSheet> {
  static const List<String> _kMonthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const List<String> _kDowLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// Lower bound of the scrollable month list. 2 years back covers the
  /// vast majority of running history searches; older runs are reachable
  /// through the All-time preset.
  late final DateTime _firstMonth;

  /// Upper bound — current month + 1 year, so a user planning a future
  /// trip can still select dates ahead.
  late final DateTime _lastMonth;

  /// Total number of months between `_firstMonth` and `_lastMonth`,
  /// inclusive. Drives the ListView itemCount.
  late final int _monthCount;

  DateTime? _pendingFrom;
  DateTime? _pendingTo;

  /// Tracks where the user is in the two-tap flow so the chips can
  /// reflect the next required action ("Tap a date" → start vs end).
  bool get _selectingEnd => _pendingFrom != null && _pendingTo == null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _firstMonth = DateTime(now.year - 2, now.month);
    _lastMonth = DateTime(now.year + 1, now.month);
    _monthCount = (_lastMonth.year - _firstMonth.year) * 12 +
        (_lastMonth.month - _firstMonth.month) +
        1;
    _pendingFrom = _normalize(widget.initialFrom);
    _pendingTo = _normalize(widget.initialTo);
  }

  static DateTime? _normalize(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day);

  void _onTapDate(DateTime d) {
    final tapped = _normalize(d)!;
    setState(() {
      // Both already set → restart with `tapped` as the new start.
      if (_pendingFrom != null && _pendingTo != null) {
        _pendingFrom = tapped;
        _pendingTo = null;
        return;
      }
      // No start yet → first tap.
      if (_pendingFrom == null) {
        _pendingFrom = tapped;
        return;
      }
      // Start is set, picking the end. If the new tap is before start,
      // swap rather than reject — feels more forgiving than ignoring.
      if (tapped.isBefore(_pendingFrom!)) {
        _pendingTo = _pendingFrom;
        _pendingFrom = tapped;
      } else {
        _pendingTo = tapped;
      }
    });
  }

  void _clear() {
    setState(() {
      _pendingFrom = null;
      _pendingTo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canApply = _pendingFrom != null && _pendingTo != null;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: title + close.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Text('Select dates', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Start / End chips. Tapping one focuses that endpoint —
            // useful when the user wants to revise just the start.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _EndpointChip(
                      label: 'Start',
                      date: _pendingFrom,
                      active: _pendingFrom == null || !_selectingEnd,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _EndpointChip(
                      label: 'End',
                      date: _pendingTo,
                      active: _selectingEnd,
                    ),
                  ),
                ],
              ),
            ),
            // Day-of-week header row (sticky above the scrollable months).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  for (final dow in _kDowLabels)
                    Expanded(
                      child: Center(
                        child: Text(
                          dow,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Scrollable list of month grids.
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _monthCount,
                itemBuilder: (context, index) {
                  final month = _monthAtOffset(index);
                  return _MonthGrid(
                    month: month,
                    pendingFrom: _pendingFrom,
                    pendingTo: _pendingTo,
                    onTapDate: _onTapDate,
                  );
                },
              ),
            ),
            // Sticky footer: Clear (left) + Apply (right). Apply is
            // disabled until both endpoints are set so the caller never
            // gets a half-finished range.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed:
                        (_pendingFrom == null && _pendingTo == null) ? null : _clear,
                    child: const Text('Clear'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: canApply
                        ? () => Navigator.of(context).pop(
                              DateTimeRange(
                                start: _pendingFrom!,
                                end: _pendingTo!,
                              ),
                            )
                        : null,
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _monthAtOffset(int i) {
    final yr = _firstMonth.year + ((_firstMonth.month - 1 + i) ~/ 12);
    final mo = ((_firstMonth.month - 1 + i) % 12) + 1;
    return DateTime(yr, mo);
  }
}

/// Pill chip that shows one endpoint of the pending range. The active
/// chip is the one the next tap will populate (or replace) — driven
/// from `_selectingEnd` in the sheet's state.
class _EndpointChip extends StatelessWidget {
  final String label;
  final DateTime? date;
  final bool active;

  const _EndpointChip({
    required this.label,
    required this.date,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = active ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = active ? cs.onPrimaryContainer : cs.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? cs.primary : cs.outlineVariant,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg.withAlpha(180),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            date == null ? 'Tap a date' : _formatChip(date!),
            style: theme.textTheme.titleMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatChip(DateTime d) {
    const dows = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    final base = '${dows[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
    return d.year == now.year ? base : '$base, ${d.year}';
  }
}

/// One month's grid of day cells. Renders the month name + year header,
/// then a 7-column grid of cells aligned to a Monday-first week. Cells
/// outside the month show as blank spacers so adjacent months in the
/// scroll don't visually overlap.
class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime? pendingFrom;
  final DateTime? pendingTo;
  final ValueChanged<DateTime> onTapDate;

  const _MonthGrid({
    required this.month,
    required this.pendingFrom,
    required this.pendingTo,
    required this.onTapDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday-first leading offset: weekday is 1=Mon..7=Sun in Dart.
    final leading = firstOfMonth.weekday - 1;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
              '${_RangeCalendarSheetState._kMonthNames[month.month - 1]} '
              '${month.year}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (int row = 0; row < rows; row++)
            Row(
              children: [
                for (int col = 0; col < 7; col++)
                  Expanded(
                    child: _buildCell(context, row * 7 + col, leading,
                        daysInMonth, firstOfMonth),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCell(BuildContext context, int idx, int leading,
      int daysInMonth, DateTime firstOfMonth) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (idx < leading || idx >= leading + daysInMonth) {
      return const AspectRatio(aspectRatio: 1, child: SizedBox());
    }
    final day = idx - leading + 1;
    final date = DateTime(firstOfMonth.year, firstOfMonth.month, day);
    final isStart =
        pendingFrom != null && _sameDay(date, pendingFrom!);
    final isEnd = pendingTo != null && _sameDay(date, pendingTo!);
    final inRange = pendingFrom != null &&
        pendingTo != null &&
        date.isAfter(pendingFrom!) &&
        date.isBefore(pendingTo!);
    final isToday = _sameDay(date, DateTime.now());

    // Cell decoration. The range fill is a rectangle that touches the
    // sides of the cell so adjacent in-range cells form a continuous
    // bar; the start / end caps are circles on top.
    final cellChildren = <Widget>[];
    if (inRange || isStart || isEnd) {
      // Pill-fill background. Round the leading edge for the start
      // cap and the trailing edge for the end cap so the bar terminates
      // cleanly at both ends.
      final radiusLeft = isStart ? 999.0 : 0.0;
      final radiusRight = isEnd ? 999.0 : 0.0;
      cellChildren.add(
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(radiusLeft),
                  bottomLeft: Radius.circular(radiusLeft),
                  topRight: Radius.circular(radiusRight),
                  bottomRight: Radius.circular(radiusRight),
                ),
              ),
            ),
          ),
        ),
      );
    }
    // Endpoint cap: filled circle in the primary colour.
    if (isStart || isEnd) {
      cellChildren.add(
        Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    } else {
      // Plain day cell. Today gets an outlined circle when not selected.
      cellChildren.add(
        Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: isToday
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.primary, width: 1.4),
                  )
                : null,
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: inRange ? cs.onPrimaryContainer : cs.onSurface,
                fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: () => onTapDate(date),
          radius: 28,
          child: Stack(children: cellChildren),
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

