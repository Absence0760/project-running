import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../goals.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_activities.dart';
import '../local_food_store.dart';
import '../local_gym_store.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../runs_history_items.dart';
import '../settings_sync.dart';
import '../widgets/activity_timeline_list.dart';
import '../widgets/gym_compose_sheet.dart';
import '../widgets/log_sheet.dart';
import '../widgets/nutrition_log_sheet.dart';
import '../widgets/run_track_preview.dart';
import '../widgets/track_preview.dart';
import 'add_run_screen.dart';
import 'gym_detail_screen.dart';
import 'gym_screen.dart';
import 'nutrition_screen.dart';
import 'run_detail_screen.dart';
import '../widgets/top_banner.dart';

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

  /// Gym store, present only when History is mounted from the multi-modal
  /// home shell. When null (or [apiClient] is signed out) the unified
  /// activities timeline is simply not offered and the screen stays the
  /// run-only history it has always been — graceful degradation, same shape
  /// as the api-null fallback elsewhere on this screen. Pushing this screen
  /// WITHOUT a gymStore (e.g. the "View all runs" link from the timeline) is
  /// how we get the dedicated, offline-first run-list surface — the mobile
  /// analogue of web's /runs page (decisions §63 amendment).
  final LocalGymStore? gymStore;

  /// Food store, only needed so the Meals tab's "View all" can open
  /// NutritionScreen. Null on the run-only + run-list-only mounts.
  final LocalFoodStore? foodStore;

  /// When false the in-screen All/Runs/Lifts/Meals chip row is suppressed
  /// and the timeline stays pinned to All. The Fitness hub's All sub-tab
  /// passes false because the hub's own TabBar already owns that axis —
  /// without it the hub would show a duplicate chip strip on top of its
  /// tab strip. Default true preserves the standalone History behaviour.
  final bool showKindChips;

  /// When set, the run-list AppBar surfaces a Routes action. The Fitness
  /// hub's Runs sub-tab supplies this so Routes is co-located with the run
  /// surface (relocated out of Social). Null elsewhere — no Routes affordance.
  final VoidCallback? onOpenRoutes;

  /// When set, the run-list AppBar surfaces a Training-plans action. The
  /// Fitness hub's Runs sub-tab supplies this so Plans is co-located with the
  /// run surface (relocated out of the Run-tab idle button). Null elsewhere.
  final VoidCallback? onOpenPlans;

  /// When false the cloud slot (sync-unsynced badge / refresh / offline) is
  /// suppressed. The Fitness hub's Runs sub-tab passes false so the sync
  /// affordance lives only on the All tab — the two tabs sit side by side and
  /// duplicating the cloud slot both clutters and overflows the Runs AppBar.
  final bool showSyncActions;

  /// Static AppBar title. The Fitness hub's Runs sub-tab passes "Runs" so its
  /// title matches the Gym / Nutrition sibling tabs; the range + count status
  /// the title otherwise carries then renders as a row in the filter header
  /// instead (its pre-polish home), so the active date filter stays visible.
  /// Null keeps the range + count title (the All tab + standalone mounts).
  final String? titleText;

  const RunsScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    this.settingsSync,
    this.gymStore,
    this.foodStore,
    this.showKindChips = true,
    this.onOpenRoutes,
    this.onOpenPlans,
    this.showSyncActions = true,
    this.titleText,
  });

  @override
  State<RunsScreen> createState() => _RunsScreenState();
}

enum _RunsSort { newest, oldest, longest, fastest }

enum _RunsRange { today, week, month, year, all, custom }

/// Kind filter for the unified activities timeline (multi_modal.md § History).
/// `run` drops back to the full run list (with all its filters); the others
/// render the cross-modality timeline.
enum _HistoryKind { all, run, lift, meal }

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

/// Single leading-slot width for every `_RunTile` variant (track
/// preview, selecting checkbox, or activity icon fallback). Locking
/// this to one value keeps the title column anchored at the same
/// x-position regardless of which leading the row happens to render.
const double _kLeadingWidth = 72;

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

  /// Unified activities timeline (runs + lifts + meals), assembled from the
  /// three offline-first LOCAL stores (not the server feed) so History always
  /// reflects every modality the device has, works offline, and updates live
  /// the moment a run / lift / meal is logged. Rebuilt synchronously on any
  /// store change; `_hasLift` / `_hasMeal` are derived alongside so `build`
  /// doesn't rescan the list every frame.
  List<ActivityRow> _activities = const [];
  bool _hasLift = false;
  bool _hasMeal = false;
  _HistoryKind _kind = _HistoryKind.all;

  /// True once a SECOND modality has data AND the gym store is wired in
  /// (multi-modal home shell). Drives timeline mode — a pure runner, or a
  /// run-only / pushed run-list mount that passes no gym store, stays on the
  /// inline run list (anti-clutter).
  bool get _hasModalityData =>
      widget.gymStore != null && (_hasLift || _hasMeal);

  /// The in-screen chip row is only shown when this surface owns the kind
  /// axis. The Fitness hub's All sub-tab passes `showKindChips: false` so the
  /// hub's TabBar is the single kind selector (no duplicate strip).
  bool get _showChips => widget.showKindChips && _hasModalityData;

  /// Whenever a second modality has data, EVERY tab — including Runs — renders
  /// the unified timeline (matching web: the Runs tab is timeline rows + a
  /// "View all" link to the full run list, not the inline run toolbar). The
  /// inline run list still backs the no-data path (offline / pure runner /
  /// the pushed run-list-only mount), which stays fully offline-first.
  bool get _timelineMode => _hasModalityData;

  /// Snapshot of `runStore.runs` IDs from the previous listener tick.
  /// Used by `_onStoreChanged` to detect freshly-added runs so we can
  /// auto-clear sticky activity / source filters that would otherwise
  /// hide them — fixes the field report "I added a run manually and
  /// it didn't show in History". The dashboard reads runs unfiltered
  /// so it always reflects the save; the History filter chips persist
  /// across sessions via SharedPreferences and were silently dropping
  /// the new entry.
  Set<String> _previousRunIds = const {};

  @override
  void initState() {
    super.initState();
    widget.runStore.addListener(_onStoreChanged);
    widget.preferences.addListener(_onStoreChanged);
    // The timeline is assembled from the local stores, so it must rebuild when
    // a lift / meal is logged (or synced in) just as it does for runs.
    widget.gymStore?.addListener(_onActivitySourceChanged);
    widget.foodStore?.addListener(_onActivitySourceChanged);
    _recompute();
    _rebuildActivities();
    // Seed the "previously seen ids" set with whatever the store
    // already holds at mount. Without this seed, the very first
    // listener tick would treat every existing run as "newly added"
    // and reset filters even when the user just opened History.
    _previousRunIds =
        widget.runStore.summaries.map((s) => s.id).toSet();
    _hydrateFilters();
    _fetchRemote();
    _hydrateModalities();
  }

  /// Pull the gym + food local stores fresh from the server so the unified
  /// timeline shows lifts / meals even when History is the entry point. The
  /// dashboard + gym / nutrition screens hydrate these too, but History is a
  /// first-class consumer now and can't assume it was reached through one of
  /// them (that assumption was the bug behind "no Lifts tab"). Each hop is
  /// wrapped independently (layered resilience); on success `replaceFromServer`
  /// notifies, which repaints the timeline + reveals the chips. Skipped on the
  /// run-only / pushed run-list mount (no gym store) and when signed out.
  Future<void> _hydrateModalities() async {
    final api = widget.apiClient;
    final gymStore = widget.gymStore;
    if (api == null || api.userId == null || gymStore == null) return;
    try {
      final fresh = await api.fetchGymWorkoutsWithSets(limit: 100);
      await gymStore.replaceFromServer(fresh, fetchLimit: 100);
    } catch (e) {
      debugPrint('History gym hydrate failed: $e');
    }
    final foodStore = widget.foodStore;
    if (foodStore == null) return;
    try {
      final now = DateTime.now();
      final weekStart = DateTime(now.year, now.month, now.day - 6);
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final fresh = await api.fetchFoodLog(from: weekStart, to: tomorrow);
      await foodStore.replaceFromServer(
        [for (final r in fresh) r.toJson()],
        windowStart: weekStart,
        windowEnd: tomorrow,
      );
    } catch (e) {
      debugPrint('History food hydrate failed: $e');
    }
  }

  /// Rebuild the unified timeline from the local stores — synchronous, no
  /// network. The data is whatever the offline-first stores hold; recording a
  /// run or logging a lift / meal lands in those stores and shows here at once
  /// (the store listeners call this). A run-only / pushed run-list mount (no
  /// gym store) offers no timeline. Mutates state in place; callers wrap it in
  /// setState (or run it inside initState).
  void _rebuildActivities() {
    final gym = widget.gymStore;
    if (gym == null) {
      _activities = const [];
      _hasLift = false;
      _hasMeal = false;
      return;
    }
    _activities = buildLocalActivities(
      // The timeline caps each source at its limit (200) and only needs the
      // newest slice — the resident window covers it without materialising the
      // whole history.
      runs: widget.runStore.recentWindow(),
      workouts: gym.workouts,
      foods: widget.foodStore?.rows ?? const <Map<String, dynamic>>[],
    );
    _hasLift = _activities.any((a) => a.kind == 'lift');
    _hasMeal = _activities.any((a) => a.kind == 'meal');
  }

  /// Gym / food store changed → re-assemble the timeline.
  void _onActivitySourceChanged() {
    if (!mounted) return;
    setState(_rebuildActivities);
  }

  /// Pull-to-refresh: refresh the run page from the cloud. The run-store update
  /// fans out through `_onStoreChanged`, which re-assembles the timeline; the
  /// gym / food stores are refreshed by their own surfaces.
  Future<void> _refreshAll() async {
    await _fetchRemote();
  }

  @override
  void dispose() {
    widget.runStore.removeListener(_onStoreChanged);
    widget.preferences.removeListener(_onStoreChanged);
    widget.gymStore?.removeListener(_onActivitySourceChanged);
    widget.foodStore?.removeListener(_onActivitySourceChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    // Detect added runs against the FULL index, not the resident window — a
    // sync can add older runs that never enter the window.
    final existing = widget.runStore.summaries.map((s) => s.id).toSet();
    final added = existing.difference(_previousRunIds);
    setState(() {
      _recompute();
      // Runs feed the timeline too — keep it in step with the run store.
      _rebuildActivities();
      _selected.removeWhere((id) => !existing.contains(id));
      if (_selected.isEmpty) _selecting = false;
      // If runs were added but none of them survive the current
      // activity / source filter, the user just saved a run they can't
      // see — auto-clear those two filters so the new entry surfaces.
      // The range filter (week / month / all) is preserved on purpose:
      // a user with "This year" selected probably wants to keep that.
      // _previousRunIds is seeded in initState BEFORE the listener can
      // fire, so `added` is always the genuine delta (never a startup
      // bulk seed).
      if (added.isNotEmpty &&
          (_activityFilter != null || _sourceFilter != null) &&
          !_filtered.any((r) => added.contains(r.id))) {
        _activityFilter = null;
        _sourceFilter = null;
        _resetPaging();
        _recompute();
        // Defer the persist so we don't fight an in-flight setState.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _persistFilters();
        });
      }
    });
    _previousRunIds = existing;
  }

  void _recompute() {
    // Filter / sort over the FULL-history index (track-less summary-runs) so
    // every range / sort / "all time" stays correct once the store windows.
    _filtered = _filterAndSort(
      widget.runStore.summaryRuns,
      _lowerCutoff(),
      _upperCutoff(),
      _sort,
      _activityFilter,
      _sourceFilter,
    );
    final slice = _filtered.length <= _visibleCount
        ? _filtered
        : _filtered.sublist(0, _visibleCount);
    // Resolve the visible slice to resident full runs where possible — the
    // newest window carries the GPS track / track_url that drives the row
    // thumbnail. Rows outside the window stay summary-runs (stats + a fallback
    // icon, no thumbnail) and hydrate their full run on tap via runById.
    final resident = {for (final r in widget.runStore.runs) r.id: r};
    _visible = [for (final s in slice) resident[s.id] ?? s];
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
        return weekStartLocal(now,
            weekStartDay: widget.settingsSync?.service
                    ?.effective<String>(SettingsKeys.weekStartDay) ??
                'monday');
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

  static String _rangeLabel(_RunsRange range, AppLocalizations l10n) {
    switch (range) {
      case _RunsRange.today:
        return l10n.historyRangeToday;
      case _RunsRange.week:
        return l10n.historyRangeWeek;
      case _RunsRange.month:
        return l10n.historyRangeMonth;
      case _RunsRange.year:
        return l10n.historyRangeYear;
      case _RunsRange.all:
        return l10n.historyRangeAll;
      case _RunsRange.custom:
        return l10n.historyRangeCustom;
    }
  }

  /// Header label for the active range. For preset ranges we render
  /// the static label; for custom we format the picked bounds inline
  /// so the user always sees what window the list is showing.
  String _activeRangeLabel(AppLocalizations l10n) {
    if (_range != _RunsRange.custom) return _rangeLabel(_range, l10n);
    final from = _customFrom;
    final to = _customTo;
    if (from == null && to == null) return l10n.historyRangeCustom;
    final tag = localeToTag(Localizations.localeOf(context));
    if (from != null && to != null) {
      return '${_formatRangeDate(from, tag)} – ${_formatRangeDate(to, tag)}';
    }
    if (from != null) return l10n.historyRangeFrom(_formatRangeDate(from, tag));
    return l10n.historyRangeUntil(_formatRangeDate(to!, tag));
  }

  /// Compact "May 1" / "May 1, 2025" date formatter for the header
  /// label. Year is omitted when it matches the current year so the
  /// usual case stays terse; included otherwise so "Jan 5" doesn't
  /// silently mean a different year than the user expects.
  static String _formatRangeDate(DateTime d, String tag) {
    final now = DateTime.now();
    return d.year == now.year
        ? formatDateShort(d, tag)
        : formatDateMed(d, tag);
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
        showTopBanner(
            context, AppLocalizations.of(context).historyRefreshFailed);
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
      // Oldest run overall drives the cloud cursor — read it from the
      // full-history index (the resident window's oldest would re-fetch runs
      // already on disk). summaries are newest-first, so .last is the oldest.
      final all = widget.runStore.summaries;
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
        showTopBanner(
            context, AppLocalizations.of(context).historyLoadMoreFailed);
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _syncAll() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      showTopBanner(context, l10n.historySignInToSync);
      return;
    }

    final unsynced = widget.runStore.unsyncedRuns;
    if (unsynced.isEmpty) return;

    setState(() => _syncing = true);
    int synced = 0;
    String? lastError;

    try {
      final failed = await api.saveRunsBatch(unsynced);
      // Same partial-success contract as SyncService — only mark
      // the runs whose track upload succeeded.
      await widget.runStore.markManySynced(
        unsynced.where((r) => !failed.contains(r.id)).map((r) => r.id),
      );
      synced = unsynced.length - failed.length;
      if (failed.isNotEmpty) {
        lastError = l10n.historySyncTrackFailed(failed.length);
      }
    } catch (e) {
      lastError = e.toString();
    }

    setState(() => _syncing = false);

    if (!mounted) return;
    if (lastError != null) {
      showTopBanner(
          context, l10n.historySyncPartial(synced, unsynced.length, lastError));
    } else {
      showTopBanner(context, l10n.historySyncAllDone(synced));
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
    final l10n = AppLocalizations.of(context);
    final count = _selected.length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.historyDeleteConfirmTitle(count)),
        content: Text(l10n.historyDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.historyCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.historyDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final ids = Set<String>.from(_selected);
    final failedIds = <String>{};
    final api = widget.apiClient;
    if (api != null && api.userId != null) {
      // Hydrate the selected runs (some may be outside the resident window) —
      // deleteRun reads metadata.track_url to clean up the Storage track, so a
      // track-less summary wouldn't remove the blob.
      final runsToDelete = <Run>[];
      for (final id in ids) {
        final run = await widget.runStore.runById(id);
        if (run != null) runsToDelete.add(run);
      }
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
      // Stamp the queued failures with the current user so a sign-out
      // → other user sign-in cycle doesn't drain User A's pending
      // deletes under User B's session (RLS would reject every one
      // and the queue would get stuck). See `docs/architecture/decisions.md § 67`
      // for the parallel run owner-tag design.
      await widget.runStore.markManyPendingRemoteDelete(
        failedIds,
        ownerUserId: api?.userId,
      );
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    if (failedIds.isNotEmpty) {
      showTopBanner(
          context,
          l10n.historyDeletePartial(
              ids.length - failedIds.length, failedIds.length));
    } else {
      showTopBanner(context, l10n.historyDeleteDone(count));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    final totalCount = widget.runStore.summaries.length;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _clearSelection();
      },
      child: Scaffold(
        appBar: _selecting ? _selectionAppBar(l10n) : _normalAppBar(l10n),
        body: _buildBody(theme, l10n, unit, totalCount),
        floatingActionButton: _selecting ? null : _buildAddFab(l10n),
      ),
    );
  }

  /// The add affordance follows the active timeline chip, mirroring web
  /// `/history`: the cross-modal All view opens a run / lift / meal picker; a
  /// single-modality tab adds straight into that modality beside its "View
  /// all" link. A run-only mount (no gym store, so no chips) keeps the plain
  /// Add-run FAB it has always had.
  Widget _buildAddFab(AppLocalizations l10n) {
    final kind = _timelineMode ? _kind : _HistoryKind.run;
    final (String label, String tooltip, VoidCallback onPressed) = switch (kind) {
      _HistoryKind.all => (l10n.logSheetTitle, l10n.historyLogTooltip, _openLogPicker),
      _HistoryKind.run => (l10n.historyAddRun, l10n.historyAddRunTooltip, _openAddRun),
      _HistoryKind.lift => (l10n.logLift, l10n.historyLogTooltip, _openAddLift),
      _HistoryKind.meal => (l10n.logFood, l10n.historyLogTooltip, _openAddMeal),
    };
    return FloatingActionButton.extended(
      heroTag: 'history_add_fab',
      onPressed: onPressed,
      icon: const Icon(Icons.add),
      label: Text(label),
      tooltip: tooltip,
    );
  }

  /// All-view add: a run / lift / meal picker (the same sheet the home Log FAB
  /// uses), then route into that modality's one-shot composer. Reuses the
  /// most-recently-logged ordering and records the pick so the MRU stays
  /// honest across both entry points.
  Future<void> _openLogPicker() async {
    final action = await showLogSheet(
      context: context,
      recent: logActionFromWire(widget.preferences.lastLogType),
    );
    if (action == null || !mounted) return;
    await widget.preferences.setLastLogType(action.wire);
    switch (action) {
      case LogAction.run:
        _openAddRun();
      case LogAction.lift:
        await _openAddLift();
      case LogAction.food:
        await _openAddMeal();
    }
  }

  Future<void> _openAddLift() async {
    final store = widget.gymStore;
    if (store == null) return;
    final saved = await showGymComposeSheet(
      context: context,
      store: store,
      suggestions: gymExerciseSuggestions(store.workouts),
    );
    if (saved == true) await _drainModalitySync(store.syncWithServer);
  }

  Future<void> _openAddMeal() async {
    final store = widget.foodStore;
    if (store == null) return;
    final saved = await showNutritionLogSheet(context: context, store: store);
    if (saved == true) await _drainModalitySync(store.syncWithServer);
  }

  /// Best-effort drain of a just-logged lift / meal to the server (the local
  /// store already notified, so the timeline updated regardless). Layered
  /// resilience: a failure leaves the row pending for the next sync trigger.
  Future<void> _drainModalitySync(Future<void> Function(ApiClient) sync) async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    try {
      await sync(api);
    } catch (e) {
      debugPrint('History log sync failed: $e');
    }
  }

  void _openAddRun() {
    Navigator.push(
      context,
      MaterialPageRoute(
        // Full-screen dialog (slide-up + close affordance) to match the
        // app's other create/edit-entity surfaces (gear, club, goal, …).
        fullscreenDialog: true,
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

  AppBar _normalAppBar(AppLocalizations l10n) {
    final unsyncedCount = widget.runStore.unsyncedCount;
    final visibleCount = _visible.length;
    // Move the date-range label + visible-count into the AppBar
    // title so the otherwise-empty left half of the bar carries
    // meaningful state. Pre-polish this lived on its own row at
    // the top of `_RunsFilterHeader` directly under an empty
    // AppBar — half a row of dead vertical real estate. The new
    // title row composes the range ("This week") with a small
    // count chip ("12 runs") next to it.
    return AppBar(
      // A hub-supplied static title wins (the Runs sub-tab reads "Runs" like
      // its Gym / Nutrition siblings; the range + count status renders in the
      // filter header instead). In timeline mode the range / count title is
      // run-specific noise — show a neutral History title (the run toolbar
      // returns on the Runs chip).
      title: widget.titleText != null
          ? Text(widget.titleText!)
          : _timelineMode
          ? Text(l10n.navHistory)
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // Custom ranges render as a two-date span ("Dec 15, 2023 –
                // Jan 20, 2024"), which — alongside up to six AppBar actions
                // on a narrow phone — overruns the title slot and trips a
                // RenderFlex overflow. Ellipsize the range label so the count
                // chip stays visible instead.
                Flexible(
                  child: Text(
                    _activeRangeLabel(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.historyCount(visibleCount),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
      actions: [
        if (widget.onOpenRoutes != null)
          IconButton(
            icon: const Icon(Icons.route),
            tooltip: l10n.fitnessRunsRoutes,
            onPressed: widget.onOpenRoutes,
          ),
        if (widget.onOpenPlans != null)
          IconButton(
            icon: const Icon(Icons.event_note),
            tooltip: l10n.fitnessRunsPlans,
            onPressed: widget.onOpenPlans,
          ),
        if (!_timelineMode)
        PopupMenuButton<_RunsRange>(
          icon: const Icon(Icons.calendar_month_outlined),
          tooltip: l10n.historyDateRangeTooltip,
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
                    child: Text(_rangeLabel(r, l10n)),
                  ))
              .toList(),
        ),
        if (!_timelineMode)
        PopupMenuButton<_RunsSort>(
          icon: const Icon(Icons.sort),
          tooltip: l10n.historySortTooltip,
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
              child: Text(l10n.historySortNewest),
            ),
            CheckedPopupMenuItem(
              value: _RunsSort.oldest,
              checked: _sort == _RunsSort.oldest,
              child: Text(l10n.historySortOldest),
            ),
            CheckedPopupMenuItem(
              value: _RunsSort.longest,
              checked: _sort == _RunsSort.longest,
              child: Text(l10n.historySortLongest),
            ),
            CheckedPopupMenuItem(
              value: _RunsSort.fastest,
              checked: _sort == _RunsSort.fastest,
              child: Text(l10n.historySortFastest),
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
        else if (widget.showSyncActions && unsyncedCount > 0)
          // The unsynced badge sits in the rightmost AppBar action slot.
          // Without the trailing padding the badge label clips against
          // the screen edge as soon as the count gets to two digits.
          // `Badge.count` also caps the rendered text at "99+" so a
          // pile-up after a long offline trip doesn't blow out the
          // badge width either.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Badge.count(
              count: unsyncedCount,
              child: IconButton(
                icon: const Icon(Icons.cloud_upload),
                tooltip: l10n.historySyncTooltip(unsyncedCount),
                onPressed: _syncAll,
              ),
            ),
          )
        else if (widget.showSyncActions && widget.apiClient?.userId != null)
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: l10n.historyRefreshTooltip,
            onPressed: _fetchRemote,
          )
        else if (widget.showSyncActions)
          IconButton(
            icon: const Icon(Icons.cloud_off),
            tooltip: l10n.historyOfflineTooltip,
            onPressed: null,
          ),
      ],
    );
  }

  AppBar _selectionAppBar(AppLocalizations l10n) {
    final allSelected =
        _visible.isNotEmpty && _selected.length == _visible.length;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: l10n.historyCancelTooltip,
        onPressed: _clearSelection,
      ),
      title: Text(l10n.historySelectionTitle(_selected.length)),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip:
              allSelected ? l10n.historyClearSelectionTooltip : l10n.historySelectAllTooltip,
          onPressed: allSelected
              ? () => setState(() => _selected.clear())
              : _selectAllVisible,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.historyDeleteTooltip,
          onPressed: _selected.isEmpty ? null : _deleteSelected,
        ),
      ],
    );
  }

  Widget _buildBody(
      ThemeData theme, AppLocalizations l10n, DistanceUnit unit, int totalCount) {
    // A user with no runs but who has logged lifts / meals should still see
    // their timeline — only fall back to the "no runs" empty state when there
    // is genuinely nothing across any modality (mirrors web's gym-only fix).
    if (totalCount == 0 && !_hasModalityData) {
      return _EmptyRuns(theme: theme, l10n: l10n);
    }

    final Widget content = _timelineMode
        ? ActivityTimelineList(
            activities: _kind == _HistoryKind.all
                ? _activities
                : _activities
                    .where((a) => a.kind == _kind.name)
                    .toList(growable: false),
            unit: unit,
            onTapRun: _openActivityRun,
            onTapLift: _openActivityLift,
            onRefresh: _refreshAll,
          )
        : RefreshIndicator(
            onRefresh: _refreshAll,
            child: _buildRunList(theme, l10n, unit),
          );

    if (!_showChips) return content;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _KindChipRow(
                kind: _kind,
                hasLift: _hasLift,
                hasMeal: _hasMeal,
                onChanged: (k) => setState(() => _kind = k),
              ),
            ),
            // Each single-modality tab links to that modality's full page,
            // mirroring web's per-tab "View all" header: Runs → the dedicated
            // offline-first run list, Lifts → Gym, Meals → Nutrition. The All
            // tab is cross-modal and has no single destination.
            if (_kind != _HistoryKind.all)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: TextButton(
                  onPressed: _openViewAll,
                  child: Text(l10n.historyViewAll),
                ),
              ),
          ],
        ),
        Expanded(child: content),
      ],
    );
  }

  /// "View all" from a single-modality timeline tab → that modality's full
  /// surface. Runs opens this same screen WITHOUT a gym store, which renders
  /// the dedicated, offline-first run list (filters / sort / pagination /
  /// bulk-delete) — the mobile analogue of web's /runs page.
  void _openViewAll() {
    switch (_kind) {
      case _HistoryKind.run:
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RunsScreen(
              apiClient: widget.apiClient,
              runStore: widget.runStore,
              routeStore: widget.routeStore,
              preferences: widget.preferences,
              settingsSync: widget.settingsSync,
            ),
          ),
        );
      case _HistoryKind.lift:
        final store = widget.gymStore;
        if (store == null) return;
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => GymScreen(api: widget.apiClient, store: store),
          ),
        );
      case _HistoryKind.meal:
        final store = widget.foodStore;
        if (store == null) return;
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => NutritionScreen(
              api: widget.apiClient,
              store: store,
              settingsSync: widget.settingsSync,
            ),
          ),
        );
      case _HistoryKind.all:
        break;
    }
  }

  /// Open a run row from the timeline. The run is usually in the local store
  /// (same data backs both); for one beyond the cached page, fetch it by id.
  Future<void> _openActivityRun(ActivityRow row) async {
    // Local-first: a resident run or one hydrated from disk; only fall back to
    // the cloud when the run isn't on the device at all.
    var run = await widget.runStore.runById(row.id);
    run ??= await widget.apiClient?.fetchRunById(row.id);
    if (run == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(
          run: run!,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          apiClient: widget.apiClient,
          settingsSync: widget.settingsSync,
        ),
      ),
    );
  }

  void _openActivityLift(ActivityRow row) {
    final store = widget.gymStore;
    if (store == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GymDetailScreen(
          api: widget.apiClient,
          store: store,
          workoutId: row.id,
        ),
      ),
    );
  }

  Widget _buildRunList(ThemeData theme, AppLocalizations l10n, DistanceUnit unit) {
    // +1 for the header row; +1 for the empty-state message when filters
    // match nothing (so the filter chips stay visible and tappable);
    // +1 for the Load-more footer row when there's potentially another
    // page (more local rows under the filter or more on the cloud).
    final emptyAfterFilter = _visible.isEmpty;
    // Oldest run overall (full index, newest-first → last is oldest) gates the
    // cloud "load more" — not the resident window's oldest.
    final allSummaries = widget.runStore.summaries;
    final oldestLocal =
        allSummaries.isEmpty ? null : allSummaries.last.startedAt;
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
    // Group visible runs into month-section headers + run tiles.
    // Pure helper in `lib/runs_history_items.dart` so the grouping
    // shape can be unit-tested without a widget pump.
    final items = emptyAfterFilter
        ? const <HistoryItem>[]
        : buildHistoryItems(_visible,
            now: DateTime.now(),
            localeTag: localeToTag(Localizations.localeOf(context)));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount:
          items.length + 1 + (emptyAfterFilter ? 1 : 0) + loadMoreSlot,
      itemBuilder: (context, index) {
        if (showLoadMore && index == items.length + 1) {
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
                      label: Text(l10n.historyLoadMore(_kRunsPageSize)),
                    ),
            ),
          );
        }
        if (index == 0) {
          return _RunsFilterHeader(
            l10n: l10n,
            rangeLabel: _activeRangeLabel(l10n),
            visibleCount: _visible.length,
            showRangeRow: widget.titleText != null,
            summary: summariseRuns(_filtered),
            unit: unit,
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
                  l10n.historyNoMatch,
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
                  child: Text(l10n.historyClearFilters),
                ),
              ],
            ),
          );
        }
        final itemIndex = index - 1;
        if (itemIndex < 0 || itemIndex >= items.length) {
          return const SizedBox.shrink();
        }
        final item = items[itemIndex];
        if (item is HistoryMonthHeader) {
          return _MonthHeaderRow(label: item.label);
        }
        final run = (item as HistoryRun).run;
        return _RunTile(
          key: ValueKey(run.id),
          api: widget.apiClient,
          run: run,
          unit: unit,
          theme: theme,
          isUnsynced: _unsyncedIds.contains(run.id),
          selecting: _selecting,
          selected: _selected.contains(run.id),
          onTap: () async {
            if (_selecting) {
              _toggleSelection(run.id);
              return;
            }
            // `run` may be a track-less summary (a row outside the resident
            // window) — hydrate the full run before opening detail.
            final full = await widget.runStore.runById(run.id) ?? run;
            if (!context.mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RunDetailScreen(
                  run: full,
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

/// Month section header rendered between runs in the History list.
/// Compact, non-tappable label — purely a visual anchor while
/// scrolling. Same vertical rhythm as the filter pills above so the
/// list reads as a clean month-by-month timeline.
class _MonthHeaderRow extends StatelessWidget {
  final String label;
  const _MonthHeaderRow({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.08,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}

/// Kind chips above the History body (All / Runs / Lifts / Meals). Only the
/// kinds that have data render — empty-kind chips are hidden, not disabled
/// (anti-clutter checklist). Mirrors the web `/history` kind chips.
class _KindChipRow extends StatelessWidget {
  final _HistoryKind kind;
  final bool hasLift;
  final bool hasMeal;
  final ValueChanged<_HistoryKind> onChanged;

  const _KindChipRow({
    required this.kind,
    required this.hasLift,
    required this.hasMeal,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chips = <(_HistoryKind, String)>[
      (_HistoryKind.all, l10n.historyKindAll),
      (_HistoryKind.run, l10n.historyKindRuns),
      if (hasLift) (_HistoryKind.lift, l10n.historyKindLifts),
      if (hasMeal) (_HistoryKind.meal, l10n.historyKindMeals),
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            for (final (k, label) in chips) ...[
              ChoiceChip(
                label: Text(label),
                selected: kind == k,
                onSelected: (_) => onChanged(k),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
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
  final ApiClient? api;

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
    required this.api,
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
    final date = formatDateShort(
        run.startedAt, localeToTag(Localizations.localeOf(context)));
    // Per-row vert chip — persona-hunt Round 3 finding Ultra #4
    // (mobile twin of web `/runs/+page.svelte`). Mirrors the web
    // condition: render only when `metadata.elevation_m` is positive
    // so layouts don't widen on runs with no elevation signal.
    final vertRaw = run.metadata?['elevation_m'];
    final vertMetres = (vertRaw is num && vertRaw > 0) ? vertRaw.toDouble() : 0.0;
    final vertLabel = vertMetres > 0
        ? '  ·  ${UnitFormat.elevation(vertMetres, unit)} ↑'
        : '';

    final trackUrl = run.metadata?['track_url'] as String?;
    final hasInlineTrack = run.track.length >= 2;
    final Widget leading = SizedBox(
      width: _kLeadingWidth,
      height: 40,
      child: Center(
        child: selecting
            ? Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              )
            : hasInlineTrack
                ? TrackPreview(points: run.track)
                : (trackUrl != null && api != null)
                    ? RunTrackPreview(trackUrl: trackUrl, api: api!)
                    : CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(activity.icon,
                            color: theme.colorScheme.primary),
                      ),
      ),
    );

    final semanticsLabel = [
      '$dist ${activity.label.toLowerCase()}',
      date,
      dur,
      trailingMetric,
      if (vertMetres > 0) '${UnitFormat.elevation(vertMetres, unit)} elevation gain',
      if (isUnsynced) 'not yet synced',
    ].join(', ');

    // Split the trailing metric into value + unit pieces so the
    // numeric reads as the hero and the unit/label as supporting
    // metadata. `trailingMetric` is "{value} {unit}" — find the
    // last space and pivot.
    final lastSpace = trailingMetric.lastIndexOf(' ');
    final trailingValue =
        lastSpace > 0 ? trailingMetric.substring(0, lastSpace) : trailingMetric;
    final trailingUnit =
        lastSpace > 0 ? trailingMetric.substring(lastSpace + 1) : '';
    return Semantics(
      label: semanticsLabel,
      button: true,
      selected: selected,
      child: Card(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : null,
        child: ListTile(
          leading: leading,
          // Title row: activity icon (signature colour, not outline-
          // grey) + bold distance text. Pre-polish the distance was
          // bodyMedium-default-weight which read as "metadata"; the
          // distance is the run's primary identifier and deserves
          // hero treatment.
          title: Row(
            children: [
              Icon(activity.icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                dist,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          // Subtitle: date · duration · activity-label. Adding the
          // activity word ("run", "walk", "cycle", "trail run")
          // makes a glanceable list of mixed activities readable
          // without expanding the row. Same `·` separator used by
          // the routes-list polish.
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '$date  ·  $dur  ·  ${activity.label.toLowerCase()}$vertLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Trailing: pace value (bold) + unit (small, muted)
          // stacked. Pre-polish was a single small bodySmall text
          // — the pace got visually lost. Stack treatment matches
          // the run-detail screen's `_Stat` widget shape.
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    trailingValue,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isUnsynced) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: AppLocalizations.of(context).historyQueuedToSync,
                      child: Icon(
                        Icons.cloud_upload_outlined,
                        size: 16,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                ],
              ),
              if (trailingUnit.isNotEmpty)
                Text(
                  trailingUnit,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
            ],
          ),
          onTap: onTap,
          onLongPress: onLongPress,
        ),
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

}

class _EmptyRuns extends StatelessWidget {
  final ThemeData theme;
  final AppLocalizations l10n;
  const _EmptyRuns({required this.theme, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_run, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(l10n.historyEmptyTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            l10n.historyEmptyBody,
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
  final AppLocalizations l10n;
  /// Active date-range label + visible-run count. Rendered as the header's
  /// leading row only when [showRangeRow] is set — on mounts where the AppBar
  /// title carries them instead (range + count anchor the title by default)
  /// they stay out of the body so the status isn't shown twice.
  final String rangeLabel;
  final int visibleCount;
  final bool showRangeRow;
  /// Aggregate over the *full filtered set* (not the paginated slice).
  /// Drives the small stats chip under the range label so a user can
  /// see "47 km · 5h" without scrolling — and the chip updates live
  /// as filter chips toggle.
  final HistoryFilterSummary summary;
  /// User's distance-unit preference for formatting the chip.
  final DistanceUnit unit;
  final ActivityType? activityFilter;
  final RunSource? sourceFilter;
  final ValueChanged<ActivityType?> onActivityChanged;
  final ValueChanged<RunSource?> onSourceChanged;

  const _RunsFilterHeader({
    required this.l10n,
    required this.rangeLabel,
    required this.visibleCount,
    this.showRangeRow = false,
    required this.summary,
    required this.unit,
    required this.activityFilter,
    required this.sourceFilter,
    required this.onActivityChanged,
    required this.onSourceChanged,
  });

  /// The selectable run sources in display order. Labels are resolved
  /// from [AppLocalizations] at build time rather than baked in here.
  static const _sourceOrder = <RunSource>[
    RunSource.app,
    RunSource.watch,
    RunSource.strava,
    RunSource.parkrun,
    RunSource.healthkit,
    RunSource.healthconnect,
  ];

  static String _sourceName(RunSource src, AppLocalizations l10n) {
    return switch (src) {
      RunSource.app => l10n.historySourceRecorded,
      RunSource.watch => l10n.historySourceWatch,
      RunSource.strava => l10n.historySourceStrava,
      RunSource.parkrun => l10n.historySourceParkrun,
      RunSource.healthkit => l10n.historySourceHealthKit,
      RunSource.healthconnect => l10n.historySourceHealthConnect,
      _ => l10n.historySourceAll,
    };
  }

  /// Format the summary chip — e.g. "47.0 km · 5h 25m". The run
  /// count already prints to the right of the range label, so the
  /// chip skips it and shows volume + time only.
  static String _summaryLine(HistoryFilterSummary s, DistanceUnit unit) {
    final dist = UnitFormat.distance(s.totalDistanceM, unit);
    final h = s.totalDuration.inHours;
    final m = s.totalDuration.inMinutes % 60;
    final time = h > 0 ? '${h}h ${m}m' : '${m}m';
    return '$dist  ·  $time';
  }

  static String _sourceLabel(RunSource? src, AppLocalizations l10n) {
    if (src == null) return l10n.historySourceAll;
    return _sourceName(src, l10n);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The default ChipTheme derived from the dusk seed renders the
    // selected state as dark purple — low-contrast against the dark
    // surface in dark mode and over-saturated against parchment in
    // light. Branch on brightness so the selected chip stays legible
    // on both palettes. Hex values mirror ui_kit's AppPalette
    // (lilac / midnight + parchment) without taking the package dep.
    final isDark = theme.brightness == Brightness.dark;
    final selectedChipBg =
        isDark ? const Color(0xFF5A4985) : const Color(0xFFD8CCFA);
    final selectedChipLabel =
        isDark ? const Color(0xFFF7F3EC) : const Color(0xFF120D22);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Range label + run count anchor the AppBar title by default (filling
        // the previously-empty left half of the bar); on static-title mounts
        // (the hub's Runs sub-tab) they return to this, their pre-polish home.
        if (showRangeRow)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '$rangeLabel · ${l10n.historyCount(visibleCount)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        // Summary line ("47 km · 5h 12m") — the metric that actually
        // changes as filter chips toggle, so it earns the body slot.
        if (summary.runCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 0, bottom: 4),
            child: Text(
              _summaryLine(summary, unit),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        const SizedBox(height: 8),
        ChipTheme(
          data: theme.chipTheme.copyWith(
            selectedColor: selectedChipBg,
            secondarySelectedColor: selectedChipBg,
            checkmarkColor: selectedChipLabel,
            secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
                  color: selectedChipLabel,
                ) ??
                TextStyle(color: selectedChipLabel),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text(l10n.historyFilterAll),
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
        ),
        const SizedBox(height: 8),
        // Source filter collapsed into a popup so the 7-entry list doesn't
        // need its own scrollable row. Matches the AppBar's existing
        // PopupMenuButton pattern for date-range and sort.
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<RunSource?>(
              tooltip: l10n.historySourceFilterTooltip,
              initialValue: sourceFilter,
              onSelected: onSourceChanged,
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: null,
                  checked: sourceFilter == null,
                  child: Text(l10n.historySourceAll),
                ),
                for (final src in _sourceOrder)
                  CheckedPopupMenuItem(
                    value: src,
                    checked: sourceFilter == src,
                    child: Text(_sourceName(src, l10n)),
                  ),
              ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_alt_outlined,
                      size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    l10n.historySourceLabel(_sourceLabel(sourceFilter, l10n)),
                    style: theme.textTheme.bodyMedium,
                  ),
                  Icon(Icons.arrow_drop_down,
                      size: 18, color: theme.colorScheme.outline),
                ],
              ),
            ),
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
  /// Lower bound of the navigable range. 2 years back covers the vast
  /// majority of running history searches; older runs are reachable via
  /// the All-time preset.
  late final DateTime _firstMonth;

  /// Upper bound — current month + 1 year, so a user planning a future
  /// trip can still select dates ahead.
  late final DateTime _lastMonth;

  DateTime? _pendingFrom;
  DateTime? _pendingTo;

  /// Currently displayed month. Replaces the previous vertical-scroll
  /// list of every month between [_firstMonth] and [_lastMonth] — we now
  /// page through one month at a time via the chevrons + the year /
  /// month dropdowns. Mirrors the web `DateRangePicker.svelte` shape.
  late DateTime _viewMonth;

  /// Tracks where the user is in the two-tap flow so the chips can
  /// reflect the next required action ("Tap a date" → start vs end).
  bool get _selectingEnd => _pendingFrom != null && _pendingTo == null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _firstMonth = DateTime(now.year - 2, now.month);
    _lastMonth = DateTime(now.year + 1, now.month);
    _pendingFrom = _normalize(widget.initialFrom);
    _pendingTo = _normalize(widget.initialTo);
    // Anchor the visible month on the user's existing `from` pick, or
    // today when the picker is opened fresh — never the bottom of the
    // 3-year range.
    final anchor = _pendingFrom ?? now;
    _viewMonth = _clampMonth(DateTime(anchor.year, anchor.month));
  }

  static DateTime? _normalize(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day);

  /// Clamp [m] (month-of-year-1) into the navigable range so a callers
  /// passing month=13 / month=0 etc. roll over cleanly.
  DateTime _clampMonth(DateTime m) {
    if (m.isBefore(_firstMonth)) return _firstMonth;
    if (m.isAfter(_lastMonth)) return _lastMonth;
    return m;
  }

  bool get _atFirstMonth =>
      _viewMonth.year == _firstMonth.year && _viewMonth.month == _firstMonth.month;
  bool get _atLastMonth =>
      _viewMonth.year == _lastMonth.year && _viewMonth.month == _lastMonth.month;

  void _setView(int year, int month) {
    // Roll over month underflows / overflows into year deltas so a
    // caller can pass month=0 (Dec, year-1) or month=13 (Jan, year+1)
    // without doing the math.
    var y = year;
    var m = month;
    while (m < 1) {
      y -= 1;
      m += 12;
    }
    while (m > 12) {
      y += 1;
      m -= 12;
    }
    setState(() {
      _viewMonth = _clampMonth(DateTime(y, m));
    });
  }

  void _stepMonth(int delta) =>
      _setView(_viewMonth.year, _viewMonth.month + delta);

  void _stepYear(int delta) =>
      _setView(_viewMonth.year + delta, _viewMonth.month);

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
    final l10n = AppLocalizations.of(context);
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
                  Text(l10n.historyRangePickerTitle,
                      style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.historyCancelTooltip,
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
                      label: l10n.historyRangeStart,
                      date: _pendingFrom,
                      active: _pendingFrom == null || !_selectingEnd,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _EndpointChip(
                      label: l10n.historyRangeEnd,
                      date: _pendingTo,
                      active: _selectingEnd,
                    ),
                  ),
                ],
              ),
            ),
            // Month / year nav row. Mirrors the web picker: month
            // dropdown + chevrons on the left, year dropdown + chevrons
            // on the right. Stepping past December rolls into January
            // of the next year (and vice versa) inside `_setView`.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _NavGroup(
                      onPrev: _atFirstMonth ? null : () => _stepMonth(-1),
                      onNext: _atLastMonth ? null : () => _stepMonth(1),
                      prevTooltip: l10n.historyPrevMonth,
                      nextTooltip: l10n.historyNextMonth,
                      child: DropdownButton<int>(
                        value: _viewMonth.month,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        alignment: Alignment.center,
                        items: [
                          for (int m = 1; m <= 12; m++)
                            DropdownMenuItem(
                              value: m,
                              alignment: Alignment.center,
                              child: Text(formatMonthName(DateTime(2000, m),
                                  localeToTag(Localizations.localeOf(context)))),
                            ),
                        ],
                        onChanged: (m) {
                          if (m != null) _setView(_viewMonth.year, m);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NavGroup(
                      onPrev: _viewMonth.year <= _firstMonth.year
                          ? null
                          : () => _stepYear(-1),
                      onNext: _viewMonth.year >= _lastMonth.year
                          ? null
                          : () => _stepYear(1),
                      prevTooltip: l10n.historyPrevYear,
                      nextTooltip: l10n.historyNextYear,
                      child: DropdownButton<int>(
                        value: _viewMonth.year,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        alignment: Alignment.center,
                        items: [
                          for (int y = _firstMonth.year;
                              y <= _lastMonth.year;
                              y++)
                            DropdownMenuItem(
                              value: y,
                              alignment: Alignment.center,
                              child: Text('$y'),
                            ),
                        ],
                        onChanged: (y) {
                          if (y != null) _setView(y, _viewMonth.month);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Day-of-week header row.
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
                  // 2026-01-05 is a Monday; step i days for a Monday-first row.
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Center(
                        child: Text(
                          formatDowNarrow(DateTime(2026, 1, 5).add(Duration(days: i)),
                              localeToTag(Localizations.localeOf(context))),
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
            // Single visible month — paged in via chevrons / dropdowns.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _MonthGrid(
                  month: _viewMonth,
                  pendingFrom: _pendingFrom,
                  pendingTo: _pendingTo,
                  onTapDate: _onTapDate,
                  showHeader: false,
                ),
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
                    child: Text(l10n.historyRangeClear),
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
                    child: Text(l10n.historyRangeApply),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// One half of the month / year nav row: a leading "previous" chevron,
/// the supplied [child] (a [DropdownButton]) sandwiched between, and a
/// trailing "next" chevron. Disabling [onPrev] / [onNext] greys out the
/// corresponding chevron at the navigable edges.
class _NavGroup extends StatelessWidget {
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final String prevTooltip;
  final String nextTooltip;
  final Widget child;

  const _NavGroup({
    required this.onPrev,
    required this.onNext,
    required this.prevTooltip,
    required this.nextTooltip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: prevTooltip,
            onPressed: onPrev,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          ),
          Expanded(child: child),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: nextTooltip,
            onPressed: onNext,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          ),
        ],
      ),
    );
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
            date == null
                ? AppLocalizations.of(context).historyRangeTapDate
                : _formatChip(date!, localeToTag(Localizations.localeOf(context))),
            style: theme.textTheme.titleMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatChip(DateTime d, String tag) {
    final now = DateTime.now();
    final base = formatDowDateShort(d, tag);
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

  /// When `false`, the inner "Month YYYY" header is suppressed. The
  /// range picker turns this off because the nav row above the grid
  /// already shows the same month + year via the dropdowns.
  final bool showHeader;

  const _MonthGrid({
    required this.month,
    required this.pendingFrom,
    required this.pendingTo,
    required this.onTapDate,
    this.showHeader = true,
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
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text(
                '${formatMonthName(month, localeToTag(Localizations.localeOf(context)))} '
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

