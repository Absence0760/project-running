import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/gen/app_localizations.dart';
import '../live_cutoff_eta.dart';
import '../live_freshness.dart';
import '../preferences.dart';
import '../roadbook.dart';
import '../route_geometry.dart';
import '../widgets/error_state.dart';
import '../widgets/live_run_map.dart';

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
      if (mounted) {
        setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
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
      await _loadCutoffLegs(run?.routeId);
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
      if (run != null && runIsFinished(run)) {
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
  Future<void> _loadCutoffLegs(String? routeId) async {
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
        // Cutoff limits are goal-independent (they're absolute clock/elapsed
        // times on the markers), so a nominal goal is fine — it only shapes
        // the projected-arrival column, which the card doesn't use.
        goalSeconds: polylineLengthMetres(waypoints),
        model: PacingModel.even,
      ).legs;
      if (!legs.any((l) => l.cutoff != null)) return;
      _cutoffLegs = legs;
      _routeWaypoints = waypoints;
    } catch (_) {
      // Fail closed: keep the card hidden on any route/marker fetch error.
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
  LiveCutoffEta? _cutoffEta(bool stale) {
    if (_cutoffLegs.isEmpty || _latestPos == null) return null;
    final distAlong = distanceAlongRoute(_latestPos!, _routeWaypoints);
    if (distAlong == null) return null;
    final eta = nextCutoffEta(
      distAlongRouteM: distAlong,
      elapsedS: _elapsedS.toDouble(),
      recentPaceSecPerKm: _recentPaceSecPerKm,
      legs: _cutoffLegs,
      stale: stale,
    );
    return eta.checkpoint == null ? null : eta;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
    final cutoff = _cutoffEta(stale);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.liveSpectatorTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: _StatusBadge(status: _status, stale: stale)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(20),
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (fresh != null) ...[
                            Text(
                              _freshnessLabel(l10n, fresh),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: stale
                                    ? const Color(0xFFF59E0B)
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight:
                                    stale ? FontWeight.w700 : FontWeight.w500,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (cutoff != null) ...[
                            _CutoffCard(eta: cutoff),
                            const SizedBox(height: 16),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _Metric(
                                label: l10n.runStatDistance,
                                value: formatDistanceForPref(_distanceM),
                              ),
                              _Metric(
                                label: l10n.runStatTime,
                                value:
                                    formatLiveDuration(Duration(seconds: _elapsedS)),
                              ),
                              _Metric(
                                label: l10n.runStatPace,
                                value: _distanceM > 0 && _elapsedS > 0
                                    ? formatLivePace(_elapsedS / (_distanceM / 1000))
                                    : '—',
                              ),
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
  const _StatusBadge({required this.status, this.stale = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Terminal states win over the live/stale axis: a finished or
    // race-marked-DNF run is over, so we never show "Live"/"Delayed" for
    // it. "Delayed" (amber) is a *live* runner whose last ping went
    // stale — distinct from "Finished" (neutral) and "DNF" (danger).
    final (label, color) = switch (status) {
      'dnf' => (l10n.liveSpectatorBadgeDnf, theme.colorScheme.error),
      'finished' =>
        (l10n.liveSpectatorBadgeFinished, theme.colorScheme.outline),
      'live' when stale =>
        (l10n.liveSpectatorBadgeStale, const Color(0xFFF59E0B)),
      'live' => (l10n.liveSpectatorBadgeLive, const Color(0xFF10B981)),
      'idle' => (l10n.liveSpectatorBadgeIdle, theme.colorScheme.outline),
      _ => (l10n.liveSpectatorBadgeConnecting, theme.colorScheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Next cut-off" card — the predictive-tracking answer the ultra-spectator
/// personas actually want ("will my person make it?"). Mirror of the web
/// `/live/[id]` card: checkpoint label + distance to go, and either a
/// coloured on/tight/behind margin chip (with projected arrival) when the
/// position is fresh, or a muted "waiting for a fresh signal" line when the
/// status is `unknown` (stale / no recent pace) — never an over-claimed ETA.
class _CutoffCard extends StatelessWidget {
  final LiveCutoffEta eta;
  const _CutoffCard({required this.eta});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final unknown = eta.status == LiveCutoffStatus.unknown;
    final label = eta.checkpoint!.label.trim();
    final title = label.isEmpty ? l10n.liveCutoffTitle : label;

    final (chipColor, chipLabel) = switch (eta.status) {
      LiveCutoffStatus.behind => (
          const Color(0xFFEF4444),
          l10n.liveCutoffBehind(_marginLabel(eta.marginS!.abs())),
        ),
      LiveCutoffStatus.tight => (
          const Color(0xFFF59E0B),
          l10n.liveCutoffAhead(_marginLabel(eta.marginS!)),
        ),
      LiveCutoffStatus.on => (
          const Color(0xFF10B981),
          l10n.liveCutoffAhead(_marginLabel(eta.marginS!)),
        ),
      LiveCutoffStatus.unknown => (theme.colorScheme.outline, ''),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.liveCutoffTitle.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.liveCutoffToGo(formatDistanceForPref(eta.distanceToM)),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          if (unknown)
            Text(
              l10n.liveCutoffWaitingSignal,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    chipLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: chipColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (eta.projectedArrivalElapsedS != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.liveCutoffEta(
                        formatLiveDuration(
                          Duration(
                            seconds: eta.projectedArrivalElapsedS!.round(),
                          ),
                        ),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

/// A signed cutoff margin (seconds) rendered as `Hh Mm` / `Mm`. Always a
/// positive magnitude — the on/behind framing comes from the surrounding
/// "ahead" / "behind" copy, not a sign here.
String _marginLabel(double seconds) {
  final total = seconds.abs().round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            )),
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
