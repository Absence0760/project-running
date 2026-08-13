import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        ActivityLoaderKind,
        AppSemanticColors,
        FullBodyLoader,
        ProgressBar,
        StatusPill;

import '../l10n/gen/app_localizations.dart';
import '../live_cutoff_eta.dart';
import '../live_freshness.dart';
import '../preferences.dart';
import '../roadbook.dart';
import '../route_geometry.dart';
import '../widgets/cutoff_card.dart';
import '../widgets/error_state.dart';
import '../widgets/live_run_map.dart';
import 'public_run_screen.dart';

/// Live spectator screen — mirrors the web `/live/[run_id]` page.
/// Hydrates the existing `live_run_pings` for a run, then subscribes
/// to new INSERTs via Supabase Realtime. RLS gates visibility (a
/// public run's pings are world-readable; a private run's pings are
/// owner-only).
///
/// Privacy-zone trust contract: this client renders pings verbatim. It
/// does NOT have the broadcaster's privacy zones (fetching them client-
/// side would defeat the point — anyone watching a public live run
/// could read off the broadcaster's home / work coordinates). The
/// single line of defence is the `live_run_pings_drop_in_zone`
/// BEFORE-INSERT trigger from migration
/// `20260618_001_clip_live_run_pings_to_privacy_zones.sql`, which
/// silently drops any ping whose (lat, lng) falls inside a zone before
/// the row reaches Realtime. If that trigger is dropped, weakened, or
/// renamed, this screen will start surfacing zone coordinates to every
/// spectator. The pgtap regression in
/// `apps/backend/supabase/tests/rls_live_run_pings_trigger_test.sql`
/// pins the trigger so a future migration can't silently undo it.
class LiveSpectatorScreen extends StatefulWidget {
  final ApiClient api;
  final String runId;

  const LiveSpectatorScreen({
    super.key,
    required this.api,
    required this.runId,
  });

  @override
  State<LiveSpectatorScreen> createState() => _LiveSpectatorScreenState();
}

class _LiveSpectatorScreenState extends State<LiveSpectatorScreen> {
  bool _loading = true;
  Object? _loadError;
  String _status = 'connecting';
  final List<Waypoint> _trace = [];
  double _distanceM = 0;
  int _elapsedS = 0;

  // Freshness: epoch-ms of the last ping (UTC-normalised) plus a 1s
  // clock so "updated N ago" / the stale badge recompute even while no
  // new ping arrives. Without this a lost-signal runner stays a fresh
  // "Live" dot forever (the spectator + SAR staleness-honesty bug).
  int? _lastPingAtMs;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;
  Timer? _freshnessTimer;
  // Counts freshness ticks so the concluded_at re-check fires ~every 15s
  // (not every second) while live.
  int _concludedCheckTick = 0;

  // True once the latest ingested ping carries the privacy-zone `coarse`
  // flag (migration 20270121_001): a ~1 km-coarsened in-zone last-seen
  // fix the DB keeps for SAR. When set, the map dot renders approximate
  // and an "approximate" badge + sub-line surface — a SAR watcher must
  // not read it as a precise current position.
  bool _lastPingCoarse = false;

  RealtimeChannel? _channel;

  // Predictive next-cutoff projection (mirror web `/live/[id]`). The route's
  // cutoff legs + waypoints are resolved once on hydrate when the run links to
  // a public route carrying cutoff markers; the card stays hidden otherwise.
  List<RoadbookLeg> _cutoffLegs = const [];
  List<Waypoint> _routeWaypoints = const [];

  // The runner's latest position + a sliding buffer of the most recent
  // distance/elapsed samples. The pace used for the projection is the average
  // over the buffer (oldest→newest), so a single noisy fix can't swing the ETA.
  ({double lat, double lng})? _latestPos;
  final List<({double distanceM, int elapsedS})> _recentSamples = [];
  static const int _paceWindow = 5;

  @override
  void initState() {
    super.initState();
    _hydrate();
    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
      if (_status == 'live' && ++_concludedCheckTick % 15 == 0) {
        _maybeCheckConcluded();
      }
    });
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    final ch = _channel;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    super.dispose();
  }

  Future<void> _hydrate() async {
    try {
      // Resolve the run's terminal state first (mirror web's
      // `ensureRunIsVisible` reading `public_runs` → `runIsFinished`). A
      // race-marked DNF and a finished run are terminal: we freeze on the
      // saved totals and never open the realtime subscription, so a stale
      // share link to a completed run reads "Finished" / "DNF" instead of
      // looping forever on "Connecting" / "Live". This is distinct from
      // the freshness "Delayed" state, which is a *live* runner whose
      // last ping went stale (signal loss), not a terminal outcome.
      final run = await widget.api.fetchPublicRunById(widget.runId);
      if (!mounted) return;
      await _loadCutoffLegs(run?.routeId, run?.startedAt);
      if (!mounted) return;
      final rows = await widget.api.fetchLiveRunPings(widget.runId);
      if (!mounted) return;
      for (final row in rows) {
        _ingest(row);
      }
      if (run != null && run.isDnf) {
        setState(() {
          _loading = false;
          _status = 'dnf';
          _distanceM = run.distanceM;
          _elapsedS = run.durationS;
        });
        return;
      }
      // A stamped concluded_at (migration 20270427_001) is the positive
      // terminal signal and wins over the pings — the recorder now keeps
      // them, so a concluded run still has a backlog and would otherwise
      // read live. runIsFinished stays as the belt-and-braces inference
      // for older runs saved before the marker existed.
      if (run != null && (run.concludedAt != null || runIsFinished(run))) {
        setState(() {
          _loading = false;
          _status = 'finished';
          _distanceM = run.distanceM;
          _elapsedS = run.durationS;
        });
        return;
      }
      setState(() {
        _loading = false;
        _status = _trace.isEmpty ? 'idle' : 'live';
      });
      _subscribe();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  /// Resolve the route's cutoff legs + waypoints for the next-cutoff card.
  /// Best-effort (L4): any failure leaves the card hidden — the live trace +
  /// staleness badge are the always-works baseline and must never break on a
  /// route-fetch error. `public_runs` nulls `route_id` when the joined route
  /// isn't itself public, so a null id here also cleanly hides the card.
  Future<void> _loadCutoffLegs(String? routeId, DateTime? startedAt) async {
    if (routeId == null || routeId.isEmpty) return;
    try {
      final result = await widget.api.fetchRouteById(routeId);
      final waypoints = result.route?.waypoints ?? const <Waypoint>[];
      if (waypoints.length < 2) return;
      final markers = await widget.api.fetchRouteMarkers(routeId);
      final legs = buildRoadbook(
        [
          for (final w in waypoints)
            RoadbookWaypoint(lat: w.lat, lng: w.lng, ele: w.elevationMetres),
        ],
        [
          for (final m in markers)
            RoadbookMarker(
              positionM: m.positionM,
              kind: m.kind,
              label: m.label,
              meta: m.meta,
            ),
        ],
        // A cutoff clock resolves to an elapsed limit only against the start's
        // time of day (local, as the web /live page reads it) — without this
        // every `cutoff_clock` marker, the only kind either editor can
        // author, yields no cutoff and the card never appears.
        startClockMin: startedAt == null
            ? null
            : (startedAt.toLocal().hour * 60 + startedAt.toLocal().minute)
                .toDouble(),
        // The nominal goal doesn't reach the card (the projection comes from
        // the runner's own pace) but it does pick which DAY a cutoff clock
        // lands on for a race that runs past midnight.
        goalSeconds: polylineLengthMetres(waypoints),
        model: PacingModel.even,
      ).legs;
      if (!legs.any((l) => l.cutoff != null)) return;
      _cutoffLegs = legs;
      _routeWaypoints = waypoints;
    } catch (e) {
      // Fail closed: keep the card hidden on any route/marker fetch error.
      debugPrint('spectator cutoff-leg load failed: $e');
    }
  }

  void _subscribe() {
    _channel = Supabase.instance.client
        .channel('live-run:${widget.runId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_run_pings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'run_id',
            value: widget.runId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (!mounted) return;
            setState(() {
              _ingest(row);
              _status = 'live';
            });
          },
        )
        .subscribe();
  }

  void _ingest(Map<String, dynamic> row) {
    final lat = (row['lat'] as num?)?.toDouble();
    final lng = (row['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final ele = (row['ele'] as num?)?.toDouble();
    final at = row['at'] as String?;
    // tryParse never throws — a manually-edited row or future format
    // change would otherwise crash the realtime callback (no outer
    // catch) and tear down live tracking for the spectator.
    final parsedAt = at == null ? null : DateTime.tryParse(at);
    // Absolute epoch-ms (UTC-normalised) so the freshness age is correct
    // regardless of the spectator's device time zone.
    if (parsedAt != null) {
      _lastPingAtMs = parsedAt.toUtc().millisecondsSinceEpoch;
    }
    _trace.add(Waypoint(
      lat: lat,
      lng: lng,
      elevationMetres: ele,
      timestamp: parsedAt,
    ));
    _latestPos = (lat: lat, lng: lng);
    _lastPingCoarse = row['coarse'] == true;
    final dist = (row['distance_m'] as num?)?.toDouble();
    if (dist != null) _distanceM = dist;
    final elapsed = (row['elapsed_s'] as num?)?.toInt();
    if (elapsed != null) _elapsedS = elapsed;
    if (dist != null && elapsed != null) {
      _recentSamples.add((distanceM: dist, elapsedS: elapsed));
      if (_recentSamples.length > _paceWindow) _recentSamples.removeAt(0);
    }
  }

  /// Average pace over the recent-samples buffer (oldest→newest), in
  /// seconds per km, or null when there's no positive-distance span to
  /// derive it from. Mirrors the web card's `recentPaceSecPerKm`.
  double? get _recentPaceSecPerKm {
    if (_recentSamples.length < 2) return null;
    final first = _recentSamples.first;
    final last = _recentSamples.last;
    final dDist = last.distanceM - first.distanceM;
    final dElapsed = last.elapsedS - first.elapsedS;
    if (dDist <= 0) return null;
    return dElapsed / (dDist / 1000);
  }

  /// The next-cutoff projection for the current position, or null when there's
  /// no route with cutoffs / no position yet / the runner is past the last
  /// cutoff. `stale` suppresses the verdict (the helper returns
  /// [LiveCutoffStatus.unknown]) rather than fabricating an ETA off an old fix.
  LiveCutoffEta? _cutoffEta(bool stale, int? ageMs) {
    if (_cutoffLegs.isEmpty || _latestPos == null) return null;
    final distAlong = distanceAlongRoute(_latestPos!, _routeWaypoints);
    if (distAlong == null) return null;
    final eta = nextCutoffEta(
      distAlongRouteM: distAlong,
      // `_elapsedS` only moves when a ping lands, so it freezes the moment
      // the runner drops out of signal. A cut-off deadline does not —
      // advance the race clock by the ping age so a limit that expired
      // during a dead zone actually registers. Distance is deliberately NOT
      // extrapolated: only time that has genuinely passed is added.
      elapsedS: liveElapsedS(_elapsedS, ageMs).toDouble(),
      recentPaceSecPerKm: _recentPaceSecPerKm,
      legs: _cutoffLegs,
      stale: stale,
    );
    return eta.checkpoint == null ? null : eta;
  }

  /// Course progress (0..1) along a linked route, or null when there's no
  /// route with >=2 waypoints / no position yet. Backs the live progress
  /// bar (mirror of the web spectator's `courseProgressPct`).
  double? get _courseProgressPct {
    if (_routeWaypoints.length < 2 || _latestPos == null) return null;
    final along = distanceAlongRoute(_latestPos!, _routeWaypoints);
    if (along == null) return null;
    final total = polylineLengthMetres(_routeWaypoints);
    if (total <= 0) return null;
    return (along / total).clamp(0.0, 1.0);
  }

  /// While live, re-check the run's concluded_at marker. The recorder now
  /// LEAVES the pings on stop (bounded by the 48h retention cron), so a
  /// stopped runner just goes stale — "no pings" can't be the finish
  /// signal. When concluded_at appears we freeze on the saved totals and
  /// switch to the conclusion view. Best-effort: a transient fetch error
  /// just defers to the next interval and never disturbs the live feed.
  Future<void> _maybeCheckConcluded() async {
    if (_status != 'live') return;
    try {
      final run = await widget.api.fetchPublicRunById(widget.runId);
      if (!mounted || _status != 'live' || run == null) return;
      if (run.concludedAt == null) return;
      final ch = _channel;
      if (ch != null) {
        Supabase.instance.client.removeChannel(ch);
        _channel = null;
      }
      setState(() {
        _status = 'finished';
        _distanceM = run.distanceM;
        _elapsedS = run.durationS;
      });
    } catch (_) {
      // Deferred to the next tick.
    }
  }

  void _openFullRun() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PublicRunScreen(api: widget.api, runId: widget.runId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final l10n = AppLocalizations.of(context);
    // Freshness ("Updated N ago" + the stale flag) is a *live*-tracking
    // signal; a terminal run is frozen on its saved totals, so we don't
    // surface a ping age for it (it would read as a misleading "Updated
    // 2h ago" under a "Finished"/"DNF" badge).
    final terminal = _status == 'finished' || _status == 'dnf';
    final fresh = (terminal || _lastPingAtMs == null)
        ? null
        : freshnessFor(_lastPingAtMs!, _nowMs);
    final stale = fresh?.stale ?? false;
    // Coarse is a *live*-tracking property; a terminal run is frozen on
    // its saved totals, so we never surface the approximate treatment for
    // one.
    final coarse = !terminal && _lastPingCoarse;
    // A concluded run has no "next" cut-off — the projection would be a
    // live claim about a runner who has already stopped.
    final cutoff = terminal ? null : _cutoffEta(stale, fresh?.ageMs);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.liveSpectatorTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: _StatusBadge(
                status: _status,
                stale: stale,
                coarse: coarse,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? FullBodyLoader(
              kind: ActivityLoaderKind.run,
              label: l10n.commonLoading,
            )
          : _loadError != null
              ? ErrorState(
                  message: l10n.liveSpectatorConnectError, onRetry: _hydrate)
              : Column(
                  children: [
                    Expanded(
                      child: _trace.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  l10n.liveSpectatorWaiting,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : LiveRunMap(
                              track: _trace,
                              plannedRoute: const [],
                              followRunner: true,
                              currentPosition: _trace.last,
                              coarsePosition: coarse,
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(20),
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_status == 'finished') ...[
                            _ConclusionCard(onViewFullRun: _openFullRun),
                            const SizedBox(height: 16),
                          ],
                          if (coarse) ...[
                            Text(
                              l10n.liveSpectatorApproximateSub,
                              key: const Key('coarse-sub'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: semantic.warning,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (fresh != null) ...[
                            Text(
                              _freshnessLabel(l10n, fresh),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: stale
                                    ? semantic.warning
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight:
                                    stale ? FontWeight.w700 : FontWeight.w500,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (cutoff != null) ...[
                            CutoffCard(eta: cutoff, stale: stale),
                            const SizedBox(height: 16),
                          ],
                          // Expanded, not spaceAround: an intrinsically-sized
                          // cell has no bound for its FittedBox to scale
                          // against, so a long value overflowed the row
                          // instead of shrinking.
                          Row(
                            children: [
                              Expanded(
                                child: _Metric(
                                  label: l10n.runStatDistance,
                                  value: formatDistanceForPref(_distanceM),
                                ),
                              ),
                              Expanded(
                                child: _Metric(
                                  label: l10n.runStatTime,
                                  value: formatLiveDuration(
                                      Duration(seconds: _elapsedS)),
                                ),
                              ),
                              Expanded(
                                child: _Metric(
                                  label: l10n.runStatPace,
                                  value: _distanceM > 0 && _elapsedS > 0
                                      ? formatLivePace(
                                          _elapsedS / (_distanceM / 1000))
                                      : '—',
                                ),
                              ),
                              if (_status == 'live' &&
                                  _recentPaceSecPerKm != null)
                                Expanded(
                                  child: _Metric(
                                    key: const Key('recent-pace'),
                                    label: l10n.liveSpectatorRecentPace,
                                    value: formatLivePace(_recentPaceSecPerKm!),
                                  ),
                                ),
                            ],
                          ),
                          if (_status == 'live' &&
                              _courseProgressPct != null) ...[
                            const SizedBox(height: 16),
                            _CourseProgress(
                              fraction: _courseProgressPct!,
                              label: l10n.liveSpectatorCourseProgress(
                                  (_courseProgressPct! * 100).round()),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

}

/// Live-spectator duration formatter — H:MM:SS past an hour, M:SS under.
/// Hoisted out of `_LiveSpectatorScreenState` so the widget test can
/// pin the boundary cases (the per-second realtime ingest path renders
/// this every tick; a regression to e.g. always-H:MM:SS would surface
/// `0:01:23` for a 1-minute live run).
@visibleForTesting
String formatLiveDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Live-spectator pace formatter — delegates to the canonical
/// unit-aware `formatPaceForPref` so the spectator sees pace in their
/// own unit (`/km` or `/mi`) and the seconds rounding matches every
/// other pace surface (UnitFormat truncates the fractional second).
@visibleForTesting
String formatLivePace(double secPerKm) => formatPaceForPref(secPerKm);

/// A run is treated as already finished when its saved duration places
/// its end > 2 minutes in the past. Mirror of the web `/live/[id]`
/// `runIsFinished` — the 2 min slack covers the gap between the last
/// live ping and the recorder posting the final row, plus clock skew.
/// `now` is injectable so the widget test can pin the boundary without
/// depending on wall-clock time.
@visibleForTesting
bool runIsFinished(RunRow run, {DateTime? now}) {
  if (run.durationS <= 0) return false;
  final endedMs =
      run.startedAt.millisecondsSinceEpoch + run.durationS * 1000;
  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return endedMs < nowMs - 2 * 60 * 1000;
}

String _freshnessLabel(AppLocalizations l10n, Freshness f) {
  switch (f.bucket) {
    case FreshnessBucket.now:
      return l10n.liveUpdatedNow;
    case FreshnessBucket.seconds:
      return l10n.liveUpdatedSeconds(f.value);
    case FreshnessBucket.minutes:
      return l10n.liveUpdatedMinutes(f.value);
    case FreshnessBucket.hours:
      return l10n.liveUpdatedHours(f.value);
    case FreshnessBucket.days:
      return l10n.liveUpdatedDays(f.value);
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool stale;
  final bool coarse;
  const _StatusBadge({
    required this.status,
    this.stale = false,
    this.coarse = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Terminal states win over the live/stale axis: a finished or
    // race-marked-DNF run is over, so we never show "Live"/"Delayed" for
    // it. "Delayed" (amber) is a *live* runner whose last ping went
    // stale — distinct from "Finished" (neutral) and "DNF" (danger). A
    // live coarse (privacy-zone last-seen) fix outranks the live/stale
    // label so the badge reads "Approximate", never a precise "Live".
    final semantic = AppSemanticColors.of(context);
    final (label, color) = switch (status) {
      'dnf' => (l10n.liveSpectatorBadgeDnf, theme.colorScheme.error),
      'finished' =>
        (l10n.liveSpectatorBadgeFinished, theme.colorScheme.onSurfaceVariant),
      'live' when coarse =>
        (l10n.liveSpectatorBadgeApproximate, semantic.warning),
      'live' when stale =>
        (l10n.liveSpectatorBadgeStale, semantic.warning),
      'live' => (l10n.liveSpectatorBadgeLive, semantic.success),
      'idle' => (
          l10n.liveSpectatorBadgeIdle,
          theme.colorScheme.onSurfaceVariant,
        ),
      _ => (
          l10n.liveSpectatorBadgeConnecting,
          theme.colorScheme.onSurfaceVariant,
        ),
    };
    return StatusPill(
      label: label,
      foreground: color,
      fill: color.withValues(alpha: 0.15),
      dot: true,
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // A runner 240 miles into an ultra is exactly who a spectator is
        // watching, and "104:32:11" is far wider than a 5K's "30:00", so
        // scale it down to the cell rather than overflow the row. Mirrors
        // _StatBig on run_detail_screen.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              )),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// End-of-run conclusion summary shown when a broadcast has concluded
/// (mirror of the web spectator's conclusion card). The runner stopped, so
/// instead of a stale feed the spectator sees a clear "complete" state and
/// a CTA into the full run.
class _ConclusionCard extends StatelessWidget {
  final VoidCallback onViewFullRun;
  const _ConclusionCard({required this.onViewFullRun});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final green = AppSemanticColors.of(context).success;
    return Container(
      key: const Key('conclusion-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: BorderDirectional(
          start: BorderSide(color: green, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_circle, color: green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.liveSpectatorConcludedTitle,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.liveSpectatorConcludedBody,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onViewFullRun,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10n.liveSpectatorViewFullRun),
            ),
          ),
        ],
      ),
    );
  }
}

/// A slim course-progress bar (fraction 0..1) + label, shown while live
/// when the run follows a known route — the mobile twin of the web
/// spectator's course-progress bar.
class _CourseProgress extends StatelessWidget {
  final double fraction;
  final String label;
  const _CourseProgress({required this.fraction, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: const Key('course-progress'),
      children: [
        Expanded(child: ProgressBar(value: fraction)),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
