import 'dart:math' as math;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../hr_zones.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../route_simplify.dart';
import '../run_stats.dart';
import '../settings_sync.dart';
import '../widgets/live_run_map.dart';
import '../widgets/track_segment.dart';
import '../widgets/run_gear_chips.dart';
import '../widgets/run_photos.dart';
import '../widgets/run_segment_efforts.dart';
import '../widgets/run_share_card.dart';
import '../widgets/run_social_section.dart';
import '../widgets/workout_review_section.dart';
import '../widgets/top_banner.dart';

/// Detail view for a completed run, showing the route map, splits, and stats.
class RunDetailScreen extends StatefulWidget {
  final Run run;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final ApiClient? apiClient;
  final SettingsSyncService? settingsSync;

  const RunDetailScreen({
    super.key,
    required this.run,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    this.apiClient,
    this.settingsSync,
  });

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen>
    with SingleTickerProviderStateMixin {
  late Run run = widget.run;
  bool _loadingTrack = false;
  bool _trackFetchFailed = false;
  Route? _linkedRoute;
  /// Map-match metadata + matched track. L4 per docs/conventions.md
  /// § Layered resilience — the raw `run.track` keeps rendering on
  /// first paint; this lands in the background and the map widget
  /// switches to it when present. A failure here cannot break the
  /// page.
  RunMatchInfo? _matchInfo;
  /// True while an owner-initiated re-match RPC is in flight. Drives
  /// the disabled state on the Re-match button so a rapid double-tap
  /// can't fire two redundant enqueues (the unique-index dedupe would
  /// catch it server-side anyway, but the UI feedback matters).
  bool _rematchBusy = false;
  /// Auto-link suggestion: when run.routeId is null AND the track
  /// confidently overlaps one of the runner's saved routes, surface
  /// a one-tap "Looks like you ran X — link?" banner. Stays null
  /// (and the banner doesn't render) until that confidence test
  /// passes; same conservative thresholds as the web version.
  RouteMatchCandidate? _suggestedRoute;
  bool _linkingRoute = false;

  /// Animation state for the "replay" feature. `null` index = not
  /// replaying. Non-null = the current step into `run.track`. Held in a
  /// ValueNotifier so the 60 Hz controller tick only rebuilds the map
  /// subtree (wrapped in ValueListenableBuilder below) instead of the
  /// whole ListView and its O(n) splits / best-efforts / HR-zone math.
  AnimationController? _replayController;
  final ValueNotifier<int?> _replayIndex = ValueNotifier<int?>(null);

  /// Currently-tapped segment of the track. Drives the floating stats
  /// card overlaid on the map. Null when nothing is selected.
  SelectedSegment? _selectedSegment;

  // Memoised derived stats. The recorder only ever appends to a run's
  // track (or a fresh fetch swaps the whole `run` object), so a matching
  // (id, length) pair guarantees the underlying waypoints are unchanged
  // and any O(n) walk over them can be reused.
  String? _statsCacheRunId;
  int _statsCacheTrackLen = -1;
  DistanceUnit? _statsCacheSplitsUnit;
  double? _cachedElevationGain;
  double? _cachedElevationLoss;
  Duration? _cachedMovingTime;
  List<MapEntry<String, Duration>>? _cachedBestEfforts;
  List<_Split>? _cachedSplits;
  ({int min, int max, int avg})? _cachedBpmStats;
  List<HrZoneBucket>? _cachedHrBuckets;
  bool _hrCacheChecked = false;

  void _resetStatsCacheIfStale() {
    if (_statsCacheRunId == run.id &&
        _statsCacheTrackLen == run.track.length) {
      return;
    }
    _statsCacheRunId = run.id;
    _statsCacheTrackLen = run.track.length;
    _cachedElevationGain = null;
    _cachedElevationLoss = null;
    _cachedMovingTime = null;
    _cachedBestEfforts = null;
    _cachedSplits = null;
    _statsCacheSplitsUnit = null;
    _cachedBpmStats = null;
    _cachedHrBuckets = null;
    _hrCacheChecked = false;
  }

  @override
  void initState() {
    super.initState();
    _loadLinkedRoute();
    _maybeFetchTrack();
    _maybeFetchMatchedTrack();
    _maybeSuggestRoute();
  }

  /// Auto-link discovery. Skips the round-trip when we already have a
  /// route_id (nothing to suggest) or no usable track (nothing to
  /// match against). Conservative scoring: needs both the
  /// start+end-offset check AND the length-similarity check to pass
  /// before showing the banner — false positives would teach the
  /// runner to ignore the prompt.
  Future<void> _maybeSuggestRoute() async {
    final api = widget.apiClient;
    if (api == null) return;
    if (run.routeId != null) return;
    if (run.track.length < 2) return;
    try {
      final candidates = await api.fetchRoutesIntersectingTrack(run.track);
      if (candidates.isEmpty) return;
      final best = candidates.first;
      final lengthRatio = (best.distanceM - run.distanceMetres).abs() /
          math.max(run.distanceMetres, 1);
      if (best.startOffsetM + best.endOffsetM < 200 && lengthRatio < 0.2) {
        if (mounted) setState(() => _suggestedRoute = best);
      }
    } catch (e) {
      debugPrint('route-suggest fetch failed for ${run.id}: $e');
    }
  }

  Future<void> _acceptSuggestedRoute() async {
    final candidate = _suggestedRoute;
    final api = widget.apiClient;
    if (candidate == null || api == null) return;
    setState(() => _linkingRoute = true);
    try {
      await api.linkRunToRoute(run.id, candidate.id);
      if (!mounted) return;
      setState(() {
        run = Run(
          id: run.id,
          startedAt: run.startedAt,
          duration: run.duration,
          distanceMetres: run.distanceMetres,
          track: run.track,
          routeId: candidate.id,
          source: run.source,
          externalId: run.externalId,
          metadata: run.metadata,
          createdAt: run.createdAt,
        );
        _suggestedRoute = null;
      });
      _loadLinkedRoute();
      showTopBanner(context, 'Linked to ${candidate.name}');
    } catch (e) {
      debugPrint('linkRunToRoute failed: $e');
      if (mounted) {
        showTopBanner(context, 'Could not link route');
      }
    } finally {
      if (mounted) setState(() => _linkingRoute = false);
    }
  }

  /// Background fetch of `run_matched_tracks` + the matched gz when
  /// status='matched'. Owner-read RLS hides the row from non-owners,
  /// so a non-null result means the runner is viewing their own run
  /// AND the worker has touched it. Silent on every failure path —
  /// the page renders the raw track without it.
  Future<void> _maybeFetchMatchedTrack() async {
    final api = widget.apiClient;
    if (api == null) return;
    try {
      final info = await api.fetchRunMatchedTrack(run.id);
      if (mounted) setState(() => _matchInfo = info);
    } catch (e) {
      debugPrint('matched-track fetch failed for ${run.id}: $e');
    }
  }

  /// Owner-only: force a fresh map-match against the current track.
  /// Resets `run_matched_tracks` to `pending` and queues a `map_match`
  /// job server-side. Mirrors the web's `handleRematch` on
  /// `/runs/[id]`. Re-reads the row immediately so the pill flips to
  /// 'pending' without a manual refresh; the dedupe unique-index on
  /// jobs swallows a second click while the first job is queued.
  Future<void> _handleRematch() async {
    final api = widget.apiClient;
    if (api == null || _rematchBusy) return;
    setState(() => _rematchBusy = true);
    try {
      await api.enqueueRunRematch(run.id);
      final info = await api.fetchRunMatchedTrack(run.id);
      if (!mounted) return;
      setState(() => _matchInfo = info);
      showTopBanner(context, 'Re-snapping to roads…');
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Re-match failed: $e');
    } finally {
      if (mounted) setState(() => _rematchBusy = false);
    }
  }

  @override
  void dispose() {
    _replayController?.dispose();
    _replayIndex.dispose();
    super.dispose();
  }

  /// Toggle trace replay. Builds the controller lazily on first tap so a
  /// `TickerProvider` isn't burning CPU on every run-detail open.
  /// Duration is deliberately fixed at 15 s rather than scaled to run
  /// length — a 10 k replay should feel about the same as a marathon's.
  void _toggleReplay() {
    final ctl = _replayController;
    if (ctl == null) {
      if (run.track.length < 2) return;
      final c = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 15),
      );
      c.addListener(() {
        final len = run.track.length;
        final idx = (c.value * (len - 1)).floor().clamp(0, len - 1);
        if (idx != _replayIndex.value) {
          _replayIndex.value = idx;
        }
      });
      c.addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          _replayIndex.value = null;
        }
      });
      _replayController = c;
      c.forward(from: 0);
      _replayIndex.value = 0;
      return;
    }
    if (ctl.isAnimating) {
      ctl.stop();
    } else {
      // Restart from 0 if we're at the end; otherwise resume.
      if (ctl.value >= 1.0) {
        ctl.forward(from: 0);
      } else {
        ctl.forward();
      }
    }
    setState(() {});
  }

  /// If the run is attached to a saved route (manual-entry runs usually
  /// are), resolve it from the local route store so we can show its planned
  /// path on the map when the run itself has no GPS track.
  void _loadLinkedRoute() {
    final id = run.routeId;
    if (id == null) return;
    try {
      _linkedRoute =
          widget.routeStore.routes.where((r) => r.id == id).firstOrNull;
    } catch (_) {
      _linkedRoute = null;
    }
  }

  /// If this run came from the cloud (track empty but track_url present),
  /// download the GPS waypoints from Storage and update the local store so
  /// next time we don't need to refetch.
  Future<void> _maybeFetchTrack() async {
    if (run.track.isNotEmpty) return;
    final trackUrl = run.metadata?['track_url'] as String?;
    if (trackUrl == null) return;
    final api = widget.apiClient;
    if (api == null) return;

    setState(() => _loadingTrack = true);
    try {
      final track = await api.fetchTrack(run);
      if (track.isEmpty) return;
      // Update the in-memory run for display but don't persist the full
      // track back to LocalRunStore — it's already stored gzipped in
      // Supabase Storage and re-saving it as uncompressed JSON would
      // duplicate ~80 KB per run on disk (~300 MB for a power user with
      // years of history). Next open re-fetches from Storage (fast — dio
      // HTTP cache).
      final updated = Run(
        id: run.id,
        startedAt: run.startedAt,
        duration: run.duration,
        distanceMetres: run.distanceMetres,
        track: track,
        routeId: run.routeId,
        source: run.source,
        externalId: run.externalId,
        metadata: run.metadata,
        createdAt: run.createdAt,
      );
      if (mounted) setState(() => run = updated);
    } catch (e) {
      debugPrint('Failed to fetch track for ${run.id}: $e');
      if (mounted) setState(() => _trackFetchFailed = true);
    } finally {
      if (mounted) setState(() => _loadingTrack = false);
    }
  }

  String get _title => (run.metadata?['title'] as String?) ?? _formatDate(run.startedAt);
  String get _notes => (run.metadata?['notes'] as String?) ?? '';

  static const _metresPerMile = 1609.344;

  Future<void> _editDetails() async {
    final unit = widget.preferences.unit;
    final titleCtl = TextEditingController(text: _title);
    final notesCtl = TextEditingController(text: _notes);

    // Distance + duration are editable only when there's no GPS track to
    // contradict the typed values. Recorded runs derive these from the
    // waypoints and editing them here would desync the map, splits, and
    // the fastest-5k PB from the headline numbers.
    final canEditStats = run.track.isEmpty;
    final distanceCtl = TextEditingController(
      text: canEditStats ? _distanceToInput(run.distanceMetres, unit) : '',
    );
    final hoursCtl = TextEditingController(
      text: canEditStats ? run.duration.inHours.toString() : '',
    );
    final minutesCtl = TextEditingController(
      text: canEditStats ? (run.duration.inMinutes % 60).toString() : '',
    );
    final secondsCtl = TextEditingController(
      text: canEditStats ? (run.duration.inSeconds % 60).toString() : '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit run'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: titleCtl,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtl,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 4,
              ),
              if (canEditStats) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: distanceCtl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Distance',
                    suffixText: UnitFormat.distanceLabel(unit),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Duration'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: _durationSubField(hoursCtl, 'h')),
                    const SizedBox(width: 8),
                    Expanded(child: _durationSubField(minutesCtl, 'm')),
                    const SizedBox(width: 8),
                    Expanded(child: _durationSubField(secondsCtl, 's')),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    double newDistance = run.distanceMetres;
    Duration newDuration = run.duration;
    if (canEditStats) {
      final parsedDistance = _parseDistanceMetres(distanceCtl.text, unit);
      final parsedDuration = _parseDuration(
        hoursCtl.text,
        minutesCtl.text,
        secondsCtl.text,
      );
      if (parsedDistance == null || parsedDuration == null) {
        if (!mounted) return;
        showTopBanner(context, 'Enter a valid distance and duration');
        return;
      }
      newDistance = parsedDistance;
      newDuration = parsedDuration;
    }

    final metadata = Map<String, dynamic>.from(run.metadata ?? {});
    metadata['title'] = titleCtl.text.trim();
    metadata['notes'] = notesCtl.text.trim();

    final updated = Run(
      id: run.id,
      startedAt: run.startedAt,
      duration: newDuration,
      distanceMetres: newDistance,
      track: run.track,
      routeId: run.routeId,
      source: run.source,
      externalId: run.externalId,
      metadata: metadata,
      createdAt: run.createdAt,
    );
    await widget.runStore.update(updated);
    if (!mounted) return;
    setState(() => run = updated);
  }

  Widget _durationSubField(TextEditingController ctl, String suffix) {
    return TextField(
      controller: ctl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        isDense: true,
        suffixText: suffix,
      ),
    );
  }

  static String _distanceToInput(double metres, DistanceUnit unit) {
    if (unit == DistanceUnit.mi) {
      return (metres / _metresPerMile).toStringAsFixed(2);
    }
    return (metres / 1000).toStringAsFixed(2);
  }

  static double? _parseDistanceMetres(String raw, DistanceUnit unit) {
    final v = double.tryParse(raw.trim());
    if (v == null || v <= 0) return null;
    return unit == DistanceUnit.mi ? v * _metresPerMile : v * 1000;
  }

  static Duration? _parseDuration(String h, String m, String s) {
    final hi = int.tryParse(h.trim().isEmpty ? '0' : h.trim());
    final mi = int.tryParse(m.trim().isEmpty ? '0' : m.trim());
    final si = int.tryParse(s.trim().isEmpty ? '0' : s.trim());
    if (hi == null || mi == null || si == null) return null;
    if (hi < 0 || mi < 0 || si < 0) return null;
    final total = Duration(hours: hi, minutes: mi, seconds: si);
    if (total.inSeconds <= 0) return null;
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit run',
            onPressed: _editDetails,
          ),
          IconButton(
            icon: const Icon(Icons.add_road_outlined),
            tooltip: 'Save as route',
            onPressed: _saveAsRoute,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share run',
            onPressed: _shareRun,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete run',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
        children: [
          // Map: show the recorded track if we have one; otherwise fall back
          // to the linked route's planned path. Manual-entry runs with no
          // route attached skip the map entirely.
          if (run.track.isNotEmpty || _linkedRoute != null)
            SizedBox(
              height: 280,
              child: Stack(
                children: [
                  ValueListenableBuilder<int?>(
                    valueListenable: _replayIndex,
                    builder: (context, replayIndex, _) {
                      // Prefer the matched line when the worker has
                      // produced one. Stats (splits, elevation, HR
                      // zones) keep deriving from the raw `run.track`
                      // because those are properties of what the
                      // runner did, not how the projected line is
                      // drawn — switching the visual layer must not
                      // alter the numbers.
                      final mapTrack = _matchInfo?.hasRenderableTrack == true
                          ? _matchInfo!.track!
                          : run.track;
                      return LiveRunMap(
                        track: mapTrack,
                        plannedRoute: mapTrack.isEmpty
                            ? _linkedRoute?.waypoints
                            : null,
                        followRunner: false,
                        activity: mapTrack.isNotEmpty ? _activityType : null,
                        currentPosition: replayIndex != null &&
                                replayIndex < run.track.length
                            ? run.track[replayIndex]
                            : null,
                        showDecorations: mapTrack.isNotEmpty,
                        useMilesForDecorations:
                            widget.preferences.unit == DistanceUnit.mi,
                        totalDistanceM: run.distanceMetres,
                        onSegmentSelect: mapTrack.isNotEmpty
                            ? (seg) => setState(() => _selectedSegment = seg)
                            : null,
                      );
                    },
                  ),
                  if (_selectedSegment != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _SegmentStatsCard(
                        segment: _selectedSegment!,
                        unit: widget.preferences.unit,
                        onDismiss: () =>
                            setState(() => _selectedSegment = null),
                      ),
                    ),
                  if (_matchInfo != null &&
                      _matchInfo!.status != MatchStatus.matched)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _MatchStatusPill(
                        status: _matchInfo!.status,
                        // RLS on `run_matched_tracks` only returns the
                        // row to the owner, so a non-null `_matchInfo`
                        // already implies the viewer is the owner.
                        // The RPC self-gates with 42501 anyway as a
                        // defence in depth.
                        onRematch: widget.apiClient == null
                            ? null
                            : _handleRematch,
                        busy: _rematchBusy,
                      ),
                    ),
                  if (run.track.length >= 2)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'run-trace-replay',
                        onPressed: _toggleReplay,
                        tooltip: _replayController?.isAnimating == true
                            ? 'Pause replay'
                            : 'Replay this run',
                        child: Icon(
                          _replayController?.isAnimating == true
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                      ),
                    ),
                  if (_loadingTrack)
                    const Positioned(
                      top: 12,
                      right: 12,
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Loading GPS data...',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_trackFetchFailed && run.track.isEmpty)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off, size: 14,
                                  color: Theme.of(context).colorScheme.outline),
                              const SizedBox(width: 8),
                              const Text('GPS track unavailable offline',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Auto-link suggestion: only renders when run.routeId is null
          // AND the track confidently overlaps a saved route. Same
          // policy as web: dismissable, one-tap link.
          if (_suggestedRoute != null && run.routeId == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _RouteSuggestBanner(
                routeName: _suggestedRoute!.name,
                onLink: _linkingRoute ? null : _acceptSuggestedRoute,
                onDismiss: () => setState(() => _suggestedRoute = null),
              ),
            ),

          // Activity type + notes
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Icon(_activityType.icon, size: 18, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Text(
                  _activityType.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          if (_notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(_notes, style: theme.textTheme.bodyMedium),
            ),

          // Primary stats — each cell is Expanded so a long value like
          // "1:15:30" can't push the row past the screen edge. For runs
          // with no GPS track (manual entries, summary imports) the
          // "Moving" column is dropped — it's identical to "Time" and
          // four cells are too tight on a phone.
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: _StatBig(
                    label: 'Distance',
                    value: UnitFormat.distanceValue(run.distanceMetres, unit),
                    unit: UnitFormat.distanceLabel(unit),
                  ),
                ),
                Expanded(
                  child: _StatBig(
                    label: 'Time',
                    value: _formatDuration(run.duration),
                  ),
                ),
                if (_showMovingTime)
                  Expanded(
                    child: _StatBig(
                      label: 'Moving',
                      value: _formatDuration(_movingTime),
                    ),
                  ),
                Expanded(
                  child: _StatBig(
                    label: _activityType.usesSpeed ? 'Avg Speed' : 'Pace',
                    value: _activityType.usesSpeed
                        ? UnitFormat.speed(_movingPaceSecPerKm, unit)
                        : UnitFormat.pace(_movingPaceSecPerKm, unit),
                    unit: _activityType.usesSpeed
                        ? UnitFormat.speedLabel(unit)
                        : UnitFormat.paceLabel(unit),
                  ),
                ),
              ],
            ),
          ),

          // Secondary stats
          if (run.track.length >= 2 || _hasElevation) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  if (_hasElevation) ...[
                    Expanded(
                      child: _StatSmall(
                        icon: Icons.trending_up,
                        label: 'Elev Gain',
                        value: '${_elevationGain.round()}m',
                      ),
                    ),
                    Expanded(
                      child: _StatSmall(
                        icon: Icons.trending_down,
                        label: 'Elev Loss',
                        value: '${_elevationLoss.round()}m',
                      ),
                    ),
                  ],
                  Expanded(
                    child: _StatSmall(
                      icon: Icons.local_fire_department,
                      label: 'Calories',
                      value: '$_estimatedCalories kcal',
                    ),
                  ),
                  if (_steps > 0)
                    Expanded(
                      child: _StatSmall(
                        icon: Icons.directions_walk,
                        label: 'Steps',
                        value: '$_steps',
                      ),
                    ),
                  if (_cadence > 0)
                    Expanded(
                      child: _StatSmall(
                        icon: Icons.speed,
                        label: 'Cadence',
                        value: '$_cadence spm',
                      ),
                    ),
                  if (_avgBpm > 0)
                    Expanded(
                      child: _StatSmall(
                        icon: Icons.favorite,
                        label: 'Avg HR',
                        value: '$_avgBpm bpm',
                      ),
                    ),
                ],
              ),
            ),
          ],

          const Divider(),

          // Route comparison — show PB and attempt history when this run
          // was done on a saved route.
          ..._buildRouteComparison(theme, unit),

          // Elevation chart
          if (_hasElevation) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Elevation', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ElevationChart(
                track: run.track,
                theme: theme,
                unit: unit,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
          ],

          // Laps
          if (_laps.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Laps', style: theme.textTheme.titleMedium),
            ),
            ..._buildLaps(theme, unit),
            const Divider(),
          ],

          // Best efforts — auto-detect fastest 1k, 1mi, 5k, 10k, HM, M
          if (run.track.length >= 2) ...[
            ..._buildBestEfforts(theme, unit),
          ],

          // Structured-workout review — only when the recorder linked
          // this run to a planned plan_workouts row.
          WorkoutReviewSection(metadata: run.metadata),

          // HR zone breakdown — only when the track carries per-point bpm
          // (Strava streams, FIT/TCX imports, future watch recorders).
          ..._buildHrZoneBreakdown(theme),

          // Splits — only when there's a track to compute them from.
          if (run.track.length >= 2) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Splits', style: theme.textTheme.titleMedium),
            ),
            ..._buildSplits(theme, unit),
          ],

          // Segment efforts — auto-generated client-side when this run
          // is linked to a saved route the viewer owns (decisions §37).
          if (widget.apiClient != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Segments', style: theme.textTheme.titleMedium),
            ),
            RunSegmentEfforts(
              api: widget.apiClient!,
              runId: run.id,
              runOwnerId: widget.apiClient!.userId,
              routeId: run.routeId,
              track: run.track,
            ),
          ],

          // Local RunDetail only opens runs owned by the viewer, so the
          // viewer is also the run owner — gates "delete any comment".
          if (widget.apiClient != null && widget.apiClient!.userId != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RunGearChips(
                api: widget.apiClient!,
                runId: run.id,
                runOwnerId: widget.apiClient!.userId!,
              ),
            ),
            RunSocialSection(
              api: widget.apiClient!,
              runId: run.id,
              runOwnerId: widget.apiClient!.userId,
            ),
            RunPhotos(
              api: widget.apiClient!,
              runId: run.id,
              runOwnerId: widget.apiClient!.userId!,
            ),
          ],

          const SizedBox(height: 32),
        ],
        ),
      ),
    );
  }

  ActivityType get _activityType =>
      ActivityType.fromName(run.metadata?['activity_type'] as String?);

  bool get _hasElevation =>
      run.track.any((w) => w.elevationMetres != null);

  List<Map<String, dynamic>> get _laps {
    final laps = run.metadata?['laps'];
    if (laps is List) return List<Map<String, dynamic>>.from(laps);
    return const [];
  }

  List<Widget> _buildLaps(ThemeData theme, DistanceUnit unit) {
    // Canonical per-lap shape (`docs/metadata.md` § laps):
    //   { index, start_offset_s, distance_m, duration_s }
    // `distance_m` and `duration_s` are the *per-lap* deltas, not the
    // cumulative totals — display each lap's own work, not running totals.
    return _laps.map((lap) {
      final number = (lap['index'] as num).toInt();
      final distM = (lap['distance_m'] as num).toDouble();
      final durS = (lap['duration_s'] as num).toInt();
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.tertiaryContainer,
          child: Icon(Icons.flag, size: 18, color: theme.colorScheme.tertiary),
        ),
        title: Text('Lap $number'),
        subtitle: Text(UnitFormat.distance(distM, unit)),
        trailing: Text(
          _formatDuration(Duration(seconds: durS)),
          style: theme.textTheme.titleMedium,
        ),
      );
    }).toList();
  }

  /// Moving time — elapsed with stops excluded, derived from the GPS track.
  /// Falls back to the full duration when the track is missing or too
  /// sparse to compute a meaningful value (e.g. imported runs without GPS).
  Duration get _movingTime {
    _resetStatsCacheIfStale();
    return _cachedMovingTime ??= _computeMovingTime();
  }

  Duration _computeMovingTime() {
    if (run.track.length < 2) return run.duration;
    final computed = movingTimeOf(run.track);
    if (computed.inSeconds == 0) return run.duration;
    return computed;
  }

  /// Whether to render the "Moving" stat cell. Hidden when the value is
  /// going to equal the total duration anyway — either because there's no
  /// GPS track to compute it from, or because the runner never stopped.
  /// Avoids a fourth stat cramping the row on a phone.
  bool get _showMovingTime {
    if (run.track.length < 2) return false;
    return _movingTime.inSeconds != run.duration.inSeconds;
  }

  double? get _movingPaceSecPerKm {
    if (run.distanceMetres < 10) return null;
    final seconds = _movingTime.inSeconds;
    if (seconds < 1) return null;
    return seconds / (run.distanceMetres / 1000);
  }

  double get _elevationGain {
    _resetStatsCacheIfStale();
    return _cachedElevationGain ??= _computeElevationGain();
  }

  double _computeElevationGain() {
    double gain = 0;
    for (int i = 1; i < run.track.length; i++) {
      final prev = run.track[i - 1].elevationMetres;
      final curr = run.track[i].elevationMetres;
      if (prev != null && curr != null && curr > prev) gain += curr - prev;
    }
    return gain;
  }

  double get _elevationLoss {
    _resetStatsCacheIfStale();
    return _cachedElevationLoss ??= _computeElevationLoss();
  }

  double _computeElevationLoss() {
    double loss = 0;
    for (int i = 1; i < run.track.length; i++) {
      final prev = run.track[i - 1].elevationMetres;
      final curr = run.track[i].elevationMetres;
      if (prev != null && curr != null && curr < prev) loss += prev - curr;
    }
    return loss;
  }

  int get _estimatedCalories {
    return (70 * _activityType.kcalPerKgPerKm * run.distanceMetres / 1000)
        .round();
  }

  int get _steps {
    final s = run.metadata?['steps'];
    if (s is int) return s;
    if (s is num) return s.toInt();
    return 0;
  }

  /// Average cadence in steps-per-minute, derived as
  /// `steps / moving_time_minutes`. Mirrors the web formula at
  /// `apps/web/src/routes/runs/[id]/+page.svelte` (`avgCadence`).
  /// Returns 0 when the input is too thin to compute meaningfully
  /// (no steps, or under 30 s of moving time) so the tile collapses
  /// to "0 spm" instead of misreporting.
  int get _cadence {
    final steps = _steps;
    final movingSeconds = _movingTime.inSeconds;
    if (steps <= 0 || movingSeconds < 30) return 0;
    return (steps / (movingSeconds / 60)).round();
  }

  /// Average heart rate in BPM. Watch apps (watch_ios, watch_wear) write
  /// this during a run; the phone's own `run_recorder` doesn't populate
  /// it today (no BLE strap integration on mobile_android yet). Returns
  /// 0 when absent so the tile renders conditionally.
  int get _avgBpm {
    final v = run.metadata?['avg_bpm'];
    if (v is int) return v;
    if (v is num) return v.round();
    return 0;
  }

  static const _bestEffortDistances = <String, double>{
    '1 km': 1000,
    '1 mi': 1609.344,
    '5 km': 5000,
    '10 km': 10000,
    'Half Marathon': 21097,
    'Marathon': 42195,
  };

  List<MapEntry<String, Duration>> get _bestEfforts {
    _resetStatsCacheIfStale();
    return _cachedBestEfforts ??= _computeBestEfforts();
  }

  List<MapEntry<String, Duration>> _computeBestEfforts() {
    final out = <MapEntry<String, Duration>>[];
    for (final e in _bestEffortDistances.entries) {
      final best = fastestWindowOf(run.track, e.value);
      if (best != null) out.add(MapEntry(e.key, best));
    }
    return out;
  }

  List<Widget> _buildBestEfforts(ThemeData theme, DistanceUnit unit) {
    final efforts = _bestEfforts;
    if (efforts.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text('Best Efforts', style: theme.textTheme.titleMedium),
      ),
      ...efforts.map((e) {
        final paceSecPerKm =
            e.value.inSeconds / (_bestEffortDistances[e.key]! / 1000);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.tertiaryContainer,
            child: Icon(Icons.emoji_events,
                size: 18, color: theme.colorScheme.tertiary),
          ),
          title: Text(e.key),
          subtitle: Text(_activityType.usesSpeed
              ? '${UnitFormat.speed(paceSecPerKm, unit)} ${UnitFormat.speedLabel(unit)}'
              : '${UnitFormat.pace(paceSecPerKm, unit)} ${UnitFormat.paceLabel(unit)}'),
          trailing: Text(
            _formatDuration(e.value),
            style: theme.textTheme.titleMedium,
          ),
        );
      }),
      const Divider(),
    ];
  }

  List<Widget> _buildRouteComparison(ThemeData theme, DistanceUnit unit) {
    if (run.routeId == null) return const [];

    final thisActivity = run.metadata?['activity_type'] as String? ?? 'run';
    final attempts = widget.runStore.runs
        .where((r) =>
            r.routeId == run.routeId &&
            r.distanceMetres > 100 &&
            (r.metadata?['activity_type'] as String? ?? 'run') == thisActivity)
        .toList()
      ..sort((a, b) => a.duration.compareTo(b.duration));

    if (attempts.length < 2) return const [];

    final best = attempts.first;
    final isBest = best.id == run.id;
    final delta = run.duration - best.duration;
    final rank = attempts.indexWhere((r) => r.id == run.id) + 1;

    final routeName = _linkedRoute?.name ?? 'this route';

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text('Route History', style: theme.textTheme.titleMedium),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isBest ? Icons.emoji_events : Icons.timer,
                      size: 20,
                      color: isBest
                          ? const Color(0xFFEAB308)
                          : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isBest
                            ? 'Personal best on $routeName'
                            : '${_formatDeltaDuration(delta)} behind PB',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isBest
                              ? const Color(0xFFEAB308)
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Attempt $rank of ${attempts.length}  '
                  '—  PB: ${_formatDuration(best.duration)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Divider(),
    ];
  }

  static String _formatDeltaDuration(Duration d) {
    final total = d.abs();
    final h = total.inHours;
    final m = total.inMinutes % 60;
    final s = total.inSeconds % 60;
    final prefix = d.isNegative ? '-' : '+';
    if (h > 0) return '$prefix${h}h ${m}m';
    if (m > 0) return '$prefix${m}m ${s}s';
    return '$prefix${s}s';
  }

  List<Widget> _buildHrZoneBreakdown(ThemeData theme) {
    _resetStatsCacheIfStale();
    if (!_hrCacheChecked) {
      _cachedBpmStats = bpmStatsOf(run.track);
      _cachedHrBuckets = _cachedBpmStats == null
          ? const []
          : hrZoneBreakdown(run.track, cutoffs: _userHrCutoffs());
      _hrCacheChecked = true;
    }
    final stats = _cachedBpmStats;
    if (stats == null) return const [];
    final buckets = _cachedHrBuckets!;
    if (buckets.isEmpty) return const [];

    const colors = [
      Color(0xFF90CAF9), // Z1 Recovery
      Color(0xFF4CAF50), // Z2 Easy
      Color(0xFFFFC107), // Z3 Aerobic
      Color(0xFFFF9800), // Z4 Threshold
      Color(0xFFF44336), // Z5 Max
    ];

    Widget bar() {
      final total =
          buckets.fold<int>(0, (sum, b) => sum + (b.pct < 0 ? 0 : b.pct));
      if (total <= 0) return const SizedBox.shrink();
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 14,
          child: Row(
            children: [
              for (final b in buckets)
                Expanded(
                  flex: (b.pct < 0 ? 0 : b.pct).clamp(0, 100),
                  child: Container(color: colors[b.index]),
                ),
            ],
          ),
        ),
      );
    }

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text('Heart rate zones', style: theme.textTheme.titleMedium),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Row(
          children: [
            _StatSmall(
              icon: Icons.favorite,
              label: 'Avg',
              value: '${stats.avg} bpm',
            ),
            const SizedBox(width: 16),
            _StatSmall(
              icon: Icons.south,
              label: 'Min',
              value: '${stats.min}',
            ),
            const SizedBox(width: 16),
            _StatSmall(
              icon: Icons.north,
              label: 'Max',
              value: '${stats.max}',
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: bar(),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            for (final b in buckets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors[b.index],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Zone ${b.index + 1} · ${b.label}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (b.seconds != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          _formatZoneSeconds(b.seconds!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${b.pct}%',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      const Divider(),
    ];
  }

  /// Pull the user's `hr_zones` from the universal settings bag.
  /// Returns null when not signed in / not configured / malformed —
  /// `hrZoneBreakdown` falls back to the default 60/70/80/90/100 %
  /// HR-max bands in that case.
  List<int>? _userHrCutoffs() {
    final svc = widget.settingsSync?.service;
    if (svc == null) return null;
    final raw = svc.effective<Map>(SettingsKeys.hrZones);
    if (raw == null) return null;
    final out = <int>[];
    for (final k in const ['z1', 'z2', 'z3', 'z4', 'z5']) {
      final v = raw[k];
      if (v is! num) return null;
      out.add(v.round());
    }
    if (out.length != 5) return null;
    // Cutoffs must be strictly increasing for the zone-index math to make
    // sense; reject malformed configurations.
    for (var i = 1; i < out.length; i++) {
      if (out[i] <= out[i - 1]) return null;
    }
    return out;
  }

  static String _formatZoneSeconds(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }

  List<_Split> _splitsFor(DistanceUnit unit) {
    _resetStatsCacheIfStale();
    if (_cachedSplits != null && _statsCacheSplitsUnit == unit) {
      return _cachedSplits!;
    }
    _cachedSplits = _computeSplits(unit);
    _statsCacheSplitsUnit = unit;
    return _cachedSplits!;
  }

  List<_Split> _computeSplits(DistanceUnit unit) {
    if (run.track.length < 2) return const [];
    const metresPerMile = 1609.344;
    final tickLength = unit == DistanceUnit.mi ? metresPerMile : 1000.0;
    final splits = <_Split>[];
    double cumulative = 0;
    int nextTick = 1;
    DateTime tickStart = run.track.first.timestamp ?? run.startedAt;

    for (int i = 1; i < run.track.length; i++) {
      final a = run.track[i - 1];
      final b = run.track[i];
      cumulative += _haversine(a.lat, a.lng, b.lat, b.lng);

      while (cumulative >= nextTick * tickLength) {
        final tickEnd = b.timestamp ?? run.startedAt;
        final splitTime = tickEnd.difference(tickStart);
        splits.add(_Split(nextTick, splitTime));
        tickStart = tickEnd;
        nextTick++;
      }
    }
    return splits;
  }

  List<Widget> _buildSplits(ThemeData theme, DistanceUnit unit) {
    if (run.track.length < 2) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('No GPS data for splits'),
        ),
      ];
    }

    const metresPerMile = 1609.344;
    final tickLength = unit == DistanceUnit.mi ? metresPerMile : 1000.0;
    final unitLabel = UnitFormat.distanceLabel(unit);

    final splits = _splitsFor(unit);

    if (splits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Run too short for a full $unitLabel split'),
        ),
      ];
    }

    // Find fastest and slowest for highlighting + bar scaling.
    final splitSeconds = splits.map((s) => s.duration.inSeconds).toList();
    final fastestSec = splitSeconds.reduce(math.min);
    final slowestSec = splitSeconds.reduce(math.max);
    final secRange = slowestSec - fastestSec;

    return splits.map((s) {
      final sec = s.duration.inSeconds;
      final paceSecPerKm = sec / (tickLength / 1000);
      final isFastest = sec == fastestSec && secRange > 0;
      final isSlowest = sec == slowestSec && secRange > 0;

      // Bar width: fastest = 100%, slowest = 40%, others proportional.
      final barFraction = secRange > 0
          ? 1.0 - ((sec - fastestSec) / secRange) * 0.6
          : 0.7;

      final barColor = isFastest
          ? const Color(0xFF34D399)
          : isSlowest
              ? const Color(0xFFF87171)
              : theme.colorScheme.primary.withOpacity(0.5);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                '${s.tick}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: barFraction.clamp(0.1, 1.0),
                  child: Container(
                    height: 26,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      _activityType.usesSpeed
                          ? UnitFormat.speed(paceSecPerKm, unit)
                          : UnitFormat.pace(paceSecPerKm, unit),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 54,
              child: Text(
                _formatDuration(s.duration),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  /// Save this run's GPS track as a reusable route. Prompts for a name
  /// (default: the run's title) and simplifies the track via
  /// Ramer–Douglas–Peucker so the saved route isn't noisy.
  Future<void> _saveAsRoute() async {
    if (run.track.length < 2) {
      showTopBanner(context, "This run has no GPS track to save as a route");
      return;
    }

    final nameCtl = TextEditingController(text: _title);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as route'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Save this GPS trace as a route you can follow again.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Route name',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final name = nameCtl.text.trim().isEmpty ? _title : nameCtl.text.trim();
    final simplified = simplifyTrack(run.track, epsilonMetres: 10);
    final gain = computeElevationGain(run.track);

    final route = Route(
      id: const Uuid().v4(),
      userId: widget.apiClient?.userId ?? '',
      name: name,
      waypoints: simplified,
      distanceMetres: run.distanceMetres,
      elevationGainMetres: gain,
      createdAt: DateTime.now(),
    );
    await widget.routeStore.save(route);

    if (!mounted) return;
    showTopBanner(context, 'Saved "$name" — ${simplified.length} waypoints '
          '(${run.track.length - simplified.length} smoothed out)',);
  }

  /// Open the share sheet — lets the user share an image of the run card or
  /// the raw GPX trace. Also marks the run as public so the web share page
  /// at /share/run/{id} can display it without authentication.
  Future<void> _shareRun() async {
    final api = widget.apiClient;
    if (api != null && api.userId != null) {
      try {
        await api.makeRunPublic(run.id);
      } catch (e) {
        debugPrint('makeRunPublic failed: $e');
      }
    }
    if (!mounted) return;
    await showRunShareSheet(
      context,
      run: run,
      preferences: widget.preferences,
      title: _title,
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete run?'),
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
    if (ok == true) {
      final api = widget.apiClient;
      if (api != null && api.userId != null) {
        try {
          await api.deleteRun(run);
        } catch (_) {}
      }
      await widget.runStore.delete(run.id);
      if (context.mounted) Navigator.pop(context);
    }
  }

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
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}

class _Split {
  final int tick;
  final Duration duration;
  const _Split(this.tick, this.duration);
}

class _StatSmall extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatSmall({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.outline),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _StatBig extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const _StatBig({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Interactive elevation + pace chart. Drag or tap to see elevation and
/// pace at any point along the run. The fill is colored by pace zones:
/// green for fast segments, amber for average, red for slow.
class _ElevationChart extends StatefulWidget {
  final List<Waypoint> track;
  final ThemeData theme;
  final DistanceUnit unit;
  const _ElevationChart({
    required this.track,
    required this.theme,
    required this.unit,
  });

  @override
  State<_ElevationChart> createState() => _ElevationChartState();
}

class _ElevationChartState extends State<_ElevationChart> {
  double? _touchFraction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_touchFraction != null) _buildCrosshairLabel(),
        SizedBox(
          height: 120,
          child: GestureDetector(
            onPanStart: (d) => _onTouch(d.localPosition),
            onPanUpdate: (d) => _onTouch(d.localPosition),
            onPanEnd: (_) => setState(() => _touchFraction = null),
            onTapDown: (d) => _onTouch(d.localPosition),
            onTapUp: (_) => setState(() => _touchFraction = null),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                return CustomPaint(
                  painter: _ElevationPacePainter(
                    track: widget.track,
                    theme: widget.theme,
                    touchFraction: _touchFraction,
                  ),
                  size: Size(constraints.maxWidth, 120),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _onTouch(Offset local) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final chartWidth = box.size.width;
    if (chartWidth <= 0) return;
    setState(() {
      _touchFraction = (local.dx / chartWidth).clamp(0.0, 1.0);
    });
  }

  Widget _buildCrosshairLabel() {
    final frac = _touchFraction!;
    final idx = (frac * (widget.track.length - 1)).round()
        .clamp(0, widget.track.length - 1);
    final w = widget.track[idx];
    final ele = w.elevationMetres;

    // Compute cumulative distance to this point.
    double cumDist = 0;
    for (var i = 1; i <= idx; i++) {
      cumDist += _haversine(
        widget.track[i - 1].lat,
        widget.track[i - 1].lng,
        widget.track[i].lat,
        widget.track[i].lng,
      );
    }

    // Local pace: compute from a ~200m window around this point.
    String paceStr = '--';
    if (idx >= 2 && idx < widget.track.length - 1) {
      final windowStart = (idx - 5).clamp(0, widget.track.length - 1);
      final windowEnd = (idx + 5).clamp(0, widget.track.length - 1);
      final a = widget.track[windowStart];
      final b = widget.track[windowEnd];
      if (a.timestamp != null && b.timestamp != null) {
        double segDist = 0;
        for (var i = windowStart + 1; i <= windowEnd; i++) {
          segDist += _haversine(
            widget.track[i - 1].lat, widget.track[i - 1].lng,
            widget.track[i].lat, widget.track[i].lng,
          );
        }
        if (segDist > 10) {
          final dtSec =
              b.timestamp!.difference(a.timestamp!).inMilliseconds / 1000.0;
          if (dtSec > 0) {
            final secPerKm = dtSec / segDist * 1000;
            paceStr = UnitFormat.pace(secPerKm, widget.unit);
          }
        }
      }
    }

    final theme = widget.theme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            UnitFormat.distance(cumDist, widget.unit),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          if (ele != null)
            Text(
              '${ele.round()}m',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(width: 16),
          Text(
            '$paceStr ${UnitFormat.paceLabel(widget.unit)}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}

class _ElevationPacePainter extends CustomPainter {
  final List<Waypoint> track;
  final ThemeData theme;
  final double? touchFraction;

  _ElevationPacePainter({
    required this.track,
    required this.theme,
    this.touchFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final elevations = <double>[];
    final paces = <double?>[];

    for (int i = 0; i < track.length; i++) {
      elevations.add(track[i].elevationMetres ?? 0);

      if (i == 0) {
        paces.add(null);
        continue;
      }
      final a = track[i - 1];
      final b = track[i];
      if (a.timestamp == null || b.timestamp == null) {
        paces.add(null);
        continue;
      }
      final dt = b.timestamp!.difference(a.timestamp!).inMilliseconds / 1000.0;
      final dist = _haversine(a.lat, a.lng, b.lat, b.lng);
      if (dt <= 0 || dist < 1) {
        paces.add(null);
      } else {
        paces.add(dt / dist * 1000);
      }
    }

    if (elevations.length < 2) return;

    final minEle = elevations.reduce(math.min);
    final maxEle = elevations.reduce(math.max);
    final range = (maxEle - minEle).abs() < 1 ? 1.0 : maxEle - minEle;

    // Compute pace percentiles for coloring.
    final validPaces =
        paces.where((p) => p != null && p > 60 && p < 1200).toList();
    final medianPace = validPaces.isNotEmpty
        ? (validPaces.cast<double>()..sort())[validPaces.length ~/ 2]
        : 300.0;

    // Draw filled segments colored by pace.
    for (int i = 1; i < elevations.length; i++) {
      final x0 = (i - 1) / (elevations.length - 1) * size.width;
      final x1 = i / (elevations.length - 1) * size.width;
      final y0 =
          size.height - ((elevations[i - 1] - minEle) / range) * size.height;
      final y1 =
          size.height - ((elevations[i] - minEle) / range) * size.height;

      final p = paces[i];
      Color segColor;
      if (p == null || p < 60 || p > 1200) {
        segColor = theme.colorScheme.primary.withOpacity(0.15);
      } else if (p < medianPace * 0.9) {
        segColor = const Color(0xFF34D399).withOpacity(0.35);
      } else if (p > medianPace * 1.1) {
        segColor = const Color(0xFFF87171).withOpacity(0.35);
      } else {
        segColor = const Color(0xFFFBBF24).withOpacity(0.25);
      }

      final fill = Path()
        ..moveTo(x0, size.height)
        ..lineTo(x0, y0)
        ..lineTo(x1, y1)
        ..lineTo(x1, size.height)
        ..close();
      canvas.drawPath(fill, Paint()..color = segColor);
    }

    // Elevation line.
    final linePath = Path();
    for (int i = 0; i < elevations.length; i++) {
      final x = i / (elevations.length - 1) * size.width;
      final y =
          size.height - ((elevations[i] - minEle) / range) * size.height;
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = theme.colorScheme.primary
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Min/max labels.
    final labelStyle = TextStyle(color: theme.dividerColor, fontSize: 10);
    final maxText = TextPainter(
      text: TextSpan(text: '${maxEle.round()}m', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    maxText.paint(canvas, const Offset(4, 0));

    final minText = TextPainter(
      text: TextSpan(text: '${minEle.round()}m', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    minText.paint(canvas, Offset(4, size.height - minText.height));

    // Touch crosshair.
    if (touchFraction != null) {
      final tx = touchFraction! * size.width;
      final tIdx =
          (touchFraction! * (elevations.length - 1)).round().clamp(0, elevations.length - 1);
      final ty = size.height -
          ((elevations[tIdx] - minEle) / range) * size.height;

      canvas.drawLine(
        Offset(tx, 0),
        Offset(tx, size.height),
        Paint()
          ..color = theme.colorScheme.onSurface.withOpacity(0.4)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        Offset(tx, ty),
        5,
        Paint()..color = theme.colorScheme.primary,
      );
      canvas.drawCircle(
        Offset(tx, ty),
        5,
        Paint()
          ..color = theme.colorScheme.surface
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  @override
  bool shouldRepaint(covariant _ElevationPacePainter old) =>
      old.track != track || old.touchFraction != touchFraction;
}

/// Auto-link prompt: "Looks like you ran *X*". Mirrors the web
/// `.route-suggest-banner` on `/runs/[id]`. Inline (not a snackbar)
/// because the user may want to compare the suggestion with the map
/// before acting; a transient toast forces a hasty decision.
class _RouteSuggestBanner extends StatelessWidget {
  final String routeName;
  final VoidCallback? onLink;
  final VoidCallback onDismiss;

  const _RouteSuggestBanner({
    required this.routeName,
    required this.onLink,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.link, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Looks like you ran '),
                    TextSpan(
                      text: routeName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ]),
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  'Link this run to that route?',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: onLink,
            child: const Text('Link'),
          ),
        ],
      ),
    );
  }
}

/// Small frosted-glass pill that surfaces the map-match status when
/// it's anything other than `matched` (the silent default — the
/// cleaner line speaks for itself). Mirrors the shape of the web's
/// `.match-pill` on `/runs/[id]`.
///
/// When [onRematch] is non-null and the status is `skipped` or
/// `failed`, the pill exposes a small "Re-match" button — the same
/// owner-only affordance the web has. Hidden for `pending` (the job
/// is already in flight; another enqueue is a no-op via the dedupe
/// unique index) and for `matched` (the pill itself doesn't render).
/// While the callback's Future is in flight [busy] is true so the
/// host can disable the action.
class _MatchStatusPill extends StatelessWidget {
  final MatchStatus status;
  final VoidCallback? onRematch;
  final bool busy;
  const _MatchStatusPill({
    required this.status,
    this.onRematch,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (status) {
      MatchStatus.pending => (Icons.hourglass_top, 'Snapping to roads…'),
      MatchStatus.skipped => (Icons.block, 'Not snapped (too few points)'),
      MatchStatus.failed => (Icons.error_outline, 'Snap failed — showing raw track'),
      MatchStatus.matched => (Icons.check_circle, 'Snapped'),
    };
    final showRematch =
        onRematch != null && status != MatchStatus.pending;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (showRematch) ...[
            const SizedBox(width: 10),
            InkWell(
              onTap: busy ? null : onRematch,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.refresh,
                      size: 14,
                      color: busy ? Colors.white38 : Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      busy ? 'Queueing…' : 'Re-match',
                      style: TextStyle(
                        color: busy ? Colors.white38 : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentStatsCard extends StatelessWidget {
  final SelectedSegment segment;
  final DistanceUnit unit;
  final VoidCallback onDismiss;

  const _SegmentStatsCard({
    required this.segment,
    required this.unit,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final dur = segment.duration;
    final pace = segment.paceSecondsPerKm;
    final stats = <Widget>[
      _stat('Distance', UnitFormat.distance(segment.distanceMetres, unit)),
      if (dur != null) _stat('Time', _formatDur(dur)),
      if (pace != null)
        _stat('Pace',
            '${UnitFormat.pace(pace, unit)} ${UnitFormat.paceLabel(unit)}'),
      if (segment.avgBpm != null) _stat('HR', '${segment.avgBpm} bpm'),
      if (segment.eleGainMetres > 0)
        _stat('Gain', '+${segment.eleGainMetres.round()} m'),
    ];
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: stats,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Dismiss',
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }

  static Widget _stat(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: Color(0xFF64748B),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  static String _formatDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

