import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/gen/app_localizations.dart';
import '../preferences.dart' show ActivityType;
import '../tile_cache.dart';
import 'pace_segments.dart';
import 'track_decorations.dart';
import 'track_segment.dart';

const double _metresPerMile = 1609.344;

/// Apply a 1-2-3-2-1 weighted moving average to the track so GPS jitter
/// shows as a smoother line instead of a visible zig-zag. The first two
/// and last two points are preserved unchanged. Display-only — the stored
/// run keeps the raw waypoints.
///
/// This reduces noise but cannot correct systematic offset from the road
/// (i.e. when GPS reports you 5 m off the centreline). The real fix is
/// backend map matching — see docs/product/roadmap.md.
List<LatLng> smoothTrack(List<LatLng> points) {
  if (points.length < 5) return points;
  final out = List<LatLng>.from(points);
  for (int i = 2; i < points.length - 2; i++) {
    out[i] = _kernel(points, i);
  }
  return out;
}

/// One 1-2-3-2-1 weighted-average sample at index [i] of [p] — the body of
/// [smoothTrack]'s interior loop, factored out so the incremental path can
/// evaluate it at a single index. Callers guarantee `2 <= i < p.length - 2`.
LatLng _kernel(List<LatLng> p, int i) {
  final a = p[i - 2], b = p[i - 1], c = p[i], d = p[i + 1], e = p[i + 2];
  return LatLng(
    (a.latitude + b.latitude * 2 + c.latitude * 3 + d.latitude * 2 + e.latitude) / 9,
    (a.longitude + b.longitude * 2 + c.longitude * 3 + d.longitude * 2 + e.longitude) / 9,
  );
}

/// Two-pass smoothing of [raw] (== `smoothTrack(smoothTrack(raw))`) that
/// reuses [prev] — the smoothed output for raw's first [prevLen] points —
/// when the track has only grown by appended points.
///
/// Why this is exact: the kernel at index `i` reads `[i-2, i+2]`, so two
/// passes make `s2[i]` depend on `raw[i-4 .. i+4]`. Appending tail points
/// therefore cannot change `s2[i]` for `i < prevLen - 4`; that prefix is
/// copied verbatim from [prev] and only the `[prevLen-4, len)` suffix is
/// recomputed. Cost is O(appended) instead of O(n), turning the live map's
/// per-GPS-fix resmooth from O(n) (→ O(n^2) over a multi-hour ultra) into a
/// bounded tail update. Falls back to a full rebuild when [prev] can't serve
/// as a prefix (cold start, reset, shrink, or sub-5-point tracks where
/// `smoothTrack` is the identity).
@visibleForTesting
List<LatLng> smoothTrackIncremental(
  List<LatLng> raw,
  List<LatLng>? prev,
  int prevLen,
) {
  final m = raw.length;
  if (prev == null || prevLen < 5 || prev.length != prevLen || m <= prevLen) {
    return smoothTrack(smoothTrack(raw));
  }
  final from = prevLen - 4; // prevLen >= 5 ⇒ from >= 1
  final s1from = from - 2 < 0 ? 0 : from - 2;
  // First pass over just the window the suffix needs: indices [s1from, m).
  final s1 = List<LatLng>.generate(
    m - s1from,
    (k) {
      final j = s1from + k;
      return (j < 2 || j >= m - 2) ? raw[j] : _kernel(raw, j);
    },
  );
  return List<LatLng>.generate(m, (i) {
    if (i < from) return prev[i];
    if (i < 2 || i >= m - 2) return s1[i - s1from];
    final a = s1[i - 2 - s1from],
        b = s1[i - 1 - s1from],
        c = s1[i - s1from],
        d = s1[i + 1 - s1from],
        e = s1[i + 2 - s1from];
    return LatLng(
      (a.latitude + b.latitude * 2 + c.latitude * 3 + d.latitude * 2 + e.latitude) / 9,
      (a.longitude + b.longitude * 2 + c.longitude * 3 + d.longitude * 2 + e.longitude) / 9,
    );
  });
}

/// Live map shown during a run, displaying the GPS track and current position.
///
/// Inspired by Nike Run Club: dark map, bright route line, pulsing blue dot.
/// OSM-tile fallback URL. Public, free, rate-limited per OSM's
/// tile-usage policy — appropriate for the no-config dev path but
/// NOT for production. The fallback exists so the map renders
/// SOMETHING when neither MAPTILER_KEY nor TILE_URL_TEMPLATE is
/// set in `.env.local`; MissingMapTilesHint surfaces the diagnostic
/// alongside.
const _kOsmTileUrl =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Build the raster-tile URL template. Resolution precedence:
///   1. `TILE_URL_TEMPLATE` override (local Protomaps tileserver-gl
///      dev setup — see `docs/ops/protomaps_local_setup.md`)
///   2. `MAPTILER_KEY` → MapTiler streets-v2-dark
///   3. OSM tiles as a last-resort fallback so the map isn\'t blank
///      on a dev setup with neither env var configured
///
/// File-level pure helper so the env-resolution contract is
/// unit-testable without booting the widget. Reads only the keys it
/// needs from the supplied env map so tests can pass a tiny
/// `Map<String, String>` rather than poking dotenv.
///
/// Whitespace-only overrides are treated as absent — a stray space
/// after `TILE_URL_TEMPLATE=` in `.env.local` shouldn't silently
/// disable MapTiler. Matches the Kotlin `buildTileUrl` `isNotBlank`
/// semantics on the Wear OS side; see `decisions.md § 68`.
///
/// The OSM fallback (May 2026 audit) replaces a pre-existing bug
/// where the helper returned `https://api.maptiler.com/...?key=`
/// (empty key) on an unconfigured dev machine — every tile request
/// 403\'d and the map rendered blank. Callers that wanted OSM as a
/// fallback had to reimplement the check themselves; now it\'s the
/// universal contract.
@visibleForTesting
String resolveTileUrl(Map<String, String> env) {
  final override = (env['TILE_URL_TEMPLATE'] ?? '').trim();
  if (override.isNotEmpty) return override;
  final key = (env['MAPTILER_KEY'] ?? '').trim();
  if (key.isNotEmpty) {
    return 'https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}@2x.png?key=$key';
  }
  return _kOsmTileUrl;
}

/// Production-callsite convenience: read dotenv defensively (the
/// `.env` may not be loaded in widget tests) and route through
/// [resolveTileUrl]. Use this from screen build() methods instead
/// of `resolveTileUrl(dotenv.env)` — bare `dotenv.env` throws
/// `NotInitializedError` when the test harness hasn\'t called
/// `dotenv.load()`, which then propagates up and prevents the
/// screen from rendering at all (real bug found by the May 2026
/// audit when the privacy-zones + heatmap screens started reading
/// dotenv in their TileLayer URL).
String currentTileUrl() {
  try {
    return resolveTileUrl(dotenv.env);
  } catch (_) {
    return resolveTileUrl(const {});
  }
}

/// Point at a fractional [index] along [line], linearly interpolated
/// between the two adjacent vertices (clamped to the line's range).
/// The replay dot animates through this instead of tweening raw
/// lat/lng chords: every interpolated position lies exactly on the
/// polyline segment it falls in, so the dot can never leave the
/// rendered line. Returns null for an empty line.
LatLng? latLngAtFractionalIndex(List<LatLng> line, double index) {
  if (line.isEmpty) return null;
  final maxIdx = (line.length - 1).toDouble();
  final fi = index.isNaN ? 0.0 : index.clamp(0.0, maxIdx).toDouble();
  final lo = fi.floor();
  final hi = fi.ceil();
  if (lo == hi) return line[lo];
  final t = fi - lo;
  final a = line[lo];
  final b = line[hi];
  return LatLng(
    a.latitude + (b.latitude - a.latitude) * t,
    a.longitude + (b.longitude - a.longitude) * t,
  );
}

/// A course marker (aid station, cutoff, …) to paint on the map. `color`
/// is the shared hex from `routeMarkerKinds` so a pin matches the web twin
/// and the schedule list.
class MapMarkerPin {
  final String id;
  final String label;
  final String color;
  final double lat;
  final double lng;
  const MapMarkerPin({
    required this.id,
    required this.label,
    required this.color,
    required this.lat,
    required this.lng,
  });
}

class LiveRunMap extends StatefulWidget {
  /// The GPS track recorded so far.
  final List<Waypoint> track;

  /// Latest raw GPS fix. When present, drives the blue dot so it can refresh
  /// faster than the track-append threshold. Falls back to the last track
  /// point when null.
  final Waypoint? currentPosition;

  /// Authoritative index of [currentPosition] within [track]. When set,
  /// the smoothed-dot snap looks up `smoothed[currentPositionIndex]`
  /// directly instead of scanning for a lat/lng match. Required for
  /// loop routes where multiple track waypoints share the same coord
  /// (start == end) — without the explicit index the scan would
  /// snap-to-start every time the user scrubbed to the end. Pass it
  /// from the replay path; leave null for live recording (where the
  /// latest fix isn't in the track and the dot renders at raw coords).
  final int? currentPositionIndex;

  /// Optional planned route to show underneath the live track.
  final List<Waypoint>? plannedRoute;

  /// Whether to auto-follow the runner's position.
  final bool followRunner;

  /// Logical pixels at the bottom of the widget that are covered by an
  /// overlay (e.g. the run stats panel). The follow-cam shifts the dot up by
  /// half of this so it sits in the visible area above the overlay instead
  /// of behind it.
  final double bottomPadding;

  /// Activity type that produced this track. When non-null the track is
  /// drawn as a per-segment pace heatmap (NRC-style) with an age-based
  /// alpha fade; when null it falls back to the legacy single gradient
  /// polyline — used by route_detail (no pace data) and manual-entry runs.
  final ActivityType? activity;

  /// When true, decorate the recorded track with km / mile distance
  /// markers and direction chevrons (mirrors web's run-detail map).
  /// Defaults to false — the live recording surface already has a
  /// pulsing dot so direction is implicit.
  final bool showDecorations;

  /// Whether to label distance markers in miles instead of kilometres.
  final bool useMilesForDecorations;

  /// Authoritative route distance in metres. Used to scale the
  /// distance-marker positions when the polyline is sparser than the
  /// real route (legacy seed data + sparse user clicks). Mirrors the
  /// `totalDistanceM` prop on `RunMap.svelte`.
  final double? totalDistanceM;

  /// Fires when the user taps the map and the tap is close enough to
  /// the recorded track to be considered a segment selection. The
  /// callback receives a [SelectedSegment] for the ±150 m window
  /// around the nearest track point, or `null` when the tap was
  /// outside that radius (in which case the caller should clear any
  /// rendered popup). When `null`, the map disables the gesture.
  final ValueChanged<SelectedSegment?>? onSegmentSelect;

  /// Optional ghost-pacer marker — when non-null, renders a faint
  /// silhouette at the supplied position. The host (`run_screen.dart`)
  /// computes it during a structured workout step via
  /// [`ghostPacerPosition`]; when no workout is active it stays null
  /// and the marker is hidden. See `docs/features/workout_execution.md`
  /// § Ghost pacer.
  final Waypoint? ghostPosition;

  /// Linked-cursor index — when non-null AND within bounds of [track],
  /// paints a pulsing marker at `track[hoverIdx]`. Driven by the
  /// run-detail elevation chart's pointer crosshair (Nike/Strava-style
  /// brushing pattern). `null` clears the marker.
  final int? hoverIdx;

  /// Free-form "runner" marker position — when non-null, paints a
  /// pulsing dot at this lat/lng. Used by the route-detail screen's
  /// scrubber: a horizontal slider feeds an interpolated position
  /// along the planned polyline (computed by
  /// [interpolateAlongRoute] in `route_geometry.dart`) so the user
  /// can drag from start to finish and see the direction of the run.
  ///
  /// Independent of [hoverIdx] — that's an index into a recorded
  /// `track`, this is a free position along an arbitrary
  /// [plannedRoute]. Both can be set at once; both render the same
  /// `_PulsingDot` so the visual language stays consistent.
  final Waypoint? previewPosition;

  /// When true the current-position marker renders as the approximate
  /// `_CoarseDot` (a hollow amber ring) instead of the solid pulsing
  /// dot. Set by the spectator screen for the privacy-zone last-seen
  /// fix (migration 20270121_001) so it reads as a ~1 km cell, not a
  /// precise current position.
  final bool coarsePosition;

  const LiveRunMap({
    super.key,
    required this.track,
    this.currentPosition,
    this.currentPositionIndex,
    this.plannedRoute,
    this.followRunner = true,
    this.bottomPadding = 0,
    this.activity,
    this.showDecorations = false,
    this.useMilesForDecorations = false,
    this.totalDistanceM,
    this.onSegmentSelect,
    this.ghostPosition,
    this.hoverIdx,
    this.previewPosition,
    this.coarsePosition = false,
    this.courseMarkers = const [],
    this.markerPlacing = false,
    this.onMarkerPlace,
    this.onMarkerTap,
    this.offlineTileProvider,
  });

  /// Optional read-through tile provider serving a followed route's offline
  /// pack from disk first, falling through to the network/LRU cache (set by
  /// the recorder when following a route that has an offline pack pinned).
  /// Null → the normal network-cached tile path (decisions §167).
  final TileProvider? offlineTileProvider;

  /// Course markers (aid stations, cutoffs, …) painted as coloured pins
  /// with a label above the trace. Empty = no marker layer.
  final List<MapMarkerPin> courseMarkers;

  /// When true, a map tap reports its lat/lng up via [onMarkerPlace]
  /// (the marker-editor "tap to drop a pin" mode) instead of doing
  /// segment selection.
  final bool markerPlacing;
  final ValueChanged<Waypoint>? onMarkerPlace;
  final ValueChanged<String>? onMarkerTap;

  @override
  State<LiveRunMap> createState() => _LiveRunMapState();
}

class _LiveRunMapState extends State<LiveRunMap> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  bool _userPanned = false;
  bool _mapReady = false;

  // Currently-highlighted segment from the most-recent tap, when
  // segment-selection is enabled. Null when no segment is selected (or
  // the feature is disabled).
  SelectedSegment? _selectedSegment;

  // Cumulative-distance vector for the segment-selection nearest-index
  // path. Recomputed only when the track length changes — the host
  // only ever appends to the track during a recording, so a matching
  // length means the cumulative array is still valid.
  List<double>? _cachedCumulative;
  int _cachedCumulativeForLen = -1;

  // Shared disk-backed tile cache (via [TileCache.init] at app startup).
  // Survives app restarts — a previously-loaded area renders offline.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Position interpolation — tweens the dot from the previous GPS fix to the
  // next one over [_positionTweenDuration] so it glides instead of hopping.
  // The camera (when following) rides the interpolated position too.
  static const _positionTweenDuration = Duration(milliseconds: 900);
  late final AnimationController _positionController;
  LatLng? _animatedLatLng;
  LatLng? _tweenStart;
  LatLng? _tweenEnd;

  // Replay (authoritative-index) tween state. The replay path animates
  // the dot in INDEX space along the smoothed polyline instead of the
  // lat/lng chord tween above — see didUpdateWidget for the why. Null
  // whenever the caller isn't driving `currentPositionIndex`.
  double? _animatedIdx;
  double? _idxTweenStart;
  double? _idxTweenEnd;

  // Cached smoothed track polyline. The tween controller drives ~1 Hz
  // rebuilds of LiveRunMap. A naive resmooth is two O(n) passes over the
  // full track; during a recording the length grows every GPS fix, so a
  // length-keyed cache misses every time → O(n^2) over a multi-hour run.
  // `_smoothedTrackFor` therefore extends this cache incrementally
  // (`smoothTrackIncremental`): equal length → reuse, longer → recompute
  // only the suffix the kernel can reach.
  List<LatLng>? _cachedSmoothedTrack;
  int _cachedSmoothedForLength = -1;

  // Cached per-segment pace buckets, keyed by activity. A segment's speed is
  // fixed once both endpoints exist, so appending only adds tail segments —
  // we extend this list rather than re-walk the whole track (O(n) haversine)
  // every fix. Feeds `buildPaceSegments` so it skips its own classify pass.
  List<int>? _cachedPaceBuckets;
  ActivityType? _cachedPaceBucketsForActivity;

  // Cached pace-heatmap polylines. Keyed by (length, activity) so a
  // manual activity change during preload rebuilds the buckets.
  List<Polyline>? _cachedPaceSegments;
  int _cachedPaceSegmentsForLength = -1;
  ActivityType? _cachedPaceSegmentsForActivity;

  // Cached halo + dark-underline polylines for the recorded track. Without
  // this, the 45 Hz position-tween setState path re-allocates three
  // Polyline + three PolylineLayer widgets every frame even though their
  // points are unchanged. Keyed by length only — the styling is constant.
  List<Polyline>? _cachedHaloPolylines;
  int _cachedHaloForLength = -1;

  String get _tileUrl => resolveTileUrl(dotenv.env);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0.4, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _positionController = AnimationController(
      vsync: this,
      duration: _positionTweenDuration,
    )..addListener(_onPositionTick);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _positionController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onPositionTick() {
    final idxStart = _idxTweenStart;
    final idxEnd = _idxTweenEnd;
    if (idxStart != null && idxEnd != null) {
      final t = _positionController.value;
      final fi = idxStart + (idxEnd - idxStart) * t;
      _animatedIdx = fi;
      final next =
          latLngAtFractionalIndex(_smoothedTrackFor(widget.track), fi);
      if (next == null) return;
      setState(() => _animatedLatLng = next);
      if (widget.followRunner && !_userPanned) {
        _moveCamera(next);
      }
      return;
    }

    final start = _tweenStart;
    final end = _tweenEnd;
    if (start == null || end == null) return;
    final t = Curves.linear.transform(_positionController.value);
    final next = LatLng(
      start.latitude + (end.latitude - start.latitude) * t,
      start.longitude + (end.longitude - start.longitude) * t,
    );
    setState(() => _animatedLatLng = next);

    if (widget.followRunner && !_userPanned) {
      _moveCamera(next);
    }
  }

  Waypoint? get _latestPosition =>
      widget.currentPosition ??
      (widget.track.isNotEmpty ? widget.track.last : null);

  /// `_latestPosition` snapped onto the SMOOTHED polyline that the
  /// map actually draws — REPLAY ONLY. The polyline gets a two-pass
  /// weighted moving average via `smoothTrack(smoothTrack(raw))` to
  /// remove GPS jitter. On the replay path, `currentPosition`
  /// equals `run.track[replayIndex]` (an EXACT raw-track member);
  /// returning the smoothed waypoint at the same index aligns the
  /// dot with the rendered line.
  ///
  /// CRITICAL: only snap on an EXACT index match (the replay path
  /// where `pos === run.track[i]`). For live recording, the latest
  /// GPS fix isn't in `widget.track` — snapping there would lie
  /// about position (a runner 50 m off-route would visually appear
  /// on the route). The May 2026 audit caught the nearest-by-delta
  /// fallback I'd originally written + scoped it to exact match
  /// only.
  ///
  /// Returns `null` for the live-recording case so the caller falls
  /// back to the raw `_latestPosition` coords.
  LatLng? _smoothedDotLatLng() {
    final pos = _latestPosition;
    if (pos == null) return null;
    if (widget.track.length < 5) {
      // smoothTrack short-circuits below 5 points → raw === smoothed,
      // no snap needed.
      return LatLng(pos.lat, pos.lng);
    }
    // Preferred path: caller passed the authoritative index (replay,
    // hover-marker). Look it up directly in the smoothed track —
    // critical for loop routes where start == end coordinates would
    // make a coord-only scan return the wrong index.
    final idx = widget.currentPositionIndex;
    if (idx != null && idx >= 0 && idx < widget.track.length) {
      final smoothed = _smoothedTrackFor(widget.track);
      if (idx < smoothed.length) return smoothed[idx];
    }
    // Fallback: identity-on-(lat,lng) scan for callers that haven't
    // adopted the explicit index yet. Live recording (where the
    // latest GPS fix isn't in the track and no index is meaningful)
    // falls through to `return null` and the caller renders raw
    // coords unmodified. The `break` keeps replay walks at
    // O(index) for non-loop tracks; loop tracks SHOULD use the
    // explicit index path above to avoid snap-to-start.
    for (int i = 0; i < widget.track.length; i++) {
      final w = widget.track[i];
      if ((w.lat - pos.lat).abs() < 1e-9 &&
          (w.lng - pos.lng).abs() < 1e-9) {
        final smoothed = _smoothedTrackFor(widget.track);
        if (i < smoothed.length) return smoothed[i];
        return null;
      }
    }
    return null;
  }

  /// Smoothed polyline for [widget.track]. Equal length → return the cache;
  /// a grown track → extend it incrementally via [smoothTrackIncremental] so
  /// the per-GPS-fix cost is O(appended) instead of O(n) (the recorder only
  /// appends, so the prior smoothed prefix is still valid). Result is
  /// byte-identical to `smoothTrack(smoothTrack(raw))`.
  List<LatLng> _smoothedTrackFor(List<Waypoint> track) {
    if (_cachedSmoothedTrack != null &&
        _cachedSmoothedForLength == track.length) {
      return _cachedSmoothedTrack!;
    }
    final raw = track.map((w) => LatLng(w.lat, w.lng)).toList();
    final smoothed = smoothTrackIncremental(
      raw,
      _cachedSmoothedTrack,
      _cachedSmoothedForLength,
    );
    _cachedSmoothedTrack = smoothed;
    _cachedSmoothedForLength = track.length;
    return smoothed;
  }

  /// Per-segment pace buckets for [track], extended in place as the track
  /// grows. Appending a point only adds new tail segments (existing segments'
  /// endpoints don't move), so we classify just the tail rather than re-run
  /// the full O(n) haversine pass every fix.
  List<int> _paceBucketsFor(List<Waypoint> track, ActivityType activity) {
    final segCount = track.length < 2 ? 0 : track.length - 1;
    final cached = _cachedPaceBuckets;
    if (cached != null &&
        _cachedPaceBucketsForActivity == activity &&
        segCount >= cached.length) {
      if (segCount == cached.length) return cached;
      final out = List<int>.from(cached);
      for (int i = cached.length; i < segCount; i++) {
        out.add(paceBucketForSegment(track[i], track[i + 1], activity));
      }
      _cachedPaceBuckets = out;
      return out;
    }
    final buckets = computePaceBuckets(track, activity);
    _cachedPaceBuckets = buckets;
    _cachedPaceBucketsForActivity = activity;
    return buckets;
  }

  /// Pace-coloured + age-faded polylines for [widget.track], cached by
  /// (length, activity). Rebuilds at GPS rate as the track grows but
  /// coalesces consecutive same-bucket segments, so a 10 km run typically
  /// lands at a few dozen polylines rather than one-per-fix.
  List<Polyline> _pacedSegmentsFor(
    List<Waypoint> track,
    List<LatLng> rendered,
    ActivityType activity,
  ) {
    if (_cachedPaceSegments != null &&
        _cachedPaceSegmentsForLength == track.length &&
        _cachedPaceSegmentsForActivity == activity) {
      return _cachedPaceSegments!;
    }
    final segs = buildPaceSegments(
      track: track,
      rendered: rendered,
      activity: activity,
      paceBuckets: _paceBucketsFor(track, activity),
    );
    _cachedPaceSegments = segs;
    _cachedPaceSegmentsForLength = track.length;
    _cachedPaceSegmentsForActivity = activity;
    return segs;
  }

  /// Halo + dark-underline polylines for [rendered], cached by length.
  /// Three Polylines bundled into a single layer (replacing three
  /// PolylineLayers in the previous version) — fewer Layer widgets means
  /// fewer diffs per position-tween tick.
  List<Polyline> _haloPolylinesFor(List<LatLng> rendered) {
    if (_cachedHaloPolylines != null &&
        _cachedHaloForLength == rendered.length) {
      return _cachedHaloPolylines!;
    }
    final out = <Polyline>[
      Polyline(
        points: rendered,
        strokeWidth: 18,
        color: const Color(0xFF818CF8).withValues(alpha: 0.18),
      ),
      Polyline(
        points: rendered,
        strokeWidth: 10,
        color: const Color(0xFF818CF8).withValues(alpha: 0.35),
      ),
      Polyline(
        points: rendered,
        strokeWidth: 8,
        color: const Color(0xFF1E1B4B),
      ),
    ];
    _cachedHaloPolylines = out;
    _cachedHaloForLength = rendered.length;
    return out;
  }

  /// Offset (in logical pixels) to shift the camera by so the dot sits in the
  /// centre of the visible area above [LiveRunMap.bottomPadding]. flutter_map's
  /// positive dy moves the [center] down the screen, so we pass a negative
  /// value to lift the dot above the overlay.
  Offset get _cameraOffset => Offset(0, -widget.bottomPadding / 2);

  /// A tap is considered a segment selection when the nearest track point
  /// is within this distance. Beyond it, the tap clears the current
  /// selection (so a tap on empty map dismisses the popup).
  static const double _tapMatchRadiusMetres = 80;

  void _handleMapTap(TapPosition _, LatLng tap) {
    final track = widget.track;
    final cb = widget.onSegmentSelect;
    if (cb == null || track.length < 2) return;

    if (_cachedCumulative == null ||
        _cachedCumulativeForLen != track.length) {
      _cachedCumulative = buildCumulativeDistances(track);
      _cachedCumulativeForLen = track.length;
    }
    final idx = nearestTrackIdx(tap, track);
    final nearest = LatLng(track[idx].lat, track[idx].lng);
    final distanceToTrack = const Distance().as(LengthUnit.Meter, tap, nearest);
    if (distanceToTrack > _tapMatchRadiusMetres) {
      if (_selectedSegment != null) {
        setState(() => _selectedSegment = null);
        cb(null);
      }
      return;
    }
    final seg = buildSegmentAt(track, idx, cumulative: _cachedCumulative);
    setState(() => _selectedSegment = seg);
    cb(seg);
  }

  void _moveCamera(LatLng target, {double? zoom}) {
    if (!_mapReady) return;
    final z = zoom ??
        (_mapController.camera.zoom < 17 ? 19.0 : _mapController.camera.zoom);
    _mapController.move(target, z, offset: _cameraOffset);
  }

  @override
  void didUpdateWidget(covariant LiveRunMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Detect a run reset: when the parent clears its track and current
    // position (discard / finish → new run), wipe the interpolated dot,
    // the tween endpoints, and the user-panned flag. Without this, the
    // next run's first fix would tween from the previous run's location
    // and the camera would stay parked where the last run ended.
    final resetDetected = oldWidget.track.isNotEmpty &&
        widget.track.isEmpty &&
        widget.currentPosition == null;
    if (resetDetected) {
      _positionController.stop();
      _animatedLatLng = null;
      _tweenStart = null;
      _tweenEnd = null;
      _animatedIdx = null;
      _idxTweenStart = null;
      _idxTweenEnd = null;
      _userPanned = false;
      _cachedSmoothedTrack = null;
      _cachedSmoothedForLength = -1;
      _cachedPaceBuckets = null;
      _cachedPaceBucketsForActivity = null;
      _cachedPaceSegments = null;
      _cachedPaceSegmentsForLength = -1;
      _cachedPaceSegmentsForActivity = null;
      _cachedHaloPolylines = null;
      _cachedHaloForLength = -1;
    }

    // Replay path — the only caller that passes currentPositionIndex.
    // Animate in INDEX space along the smoothed polyline rather than
    // the lat/lng chord tween below: the replay controller advances
    // the index up to once per frame, so the 900 ms chord tween never
    // caught up — the dot chased a moving target across straight-line
    // chords that cut every corner, visibly off the rendered line.
    // Interpolating a fractional index between adjacent smoothed
    // vertices keeps every intermediate position ON the drawn
    // polyline by construction.
    final replayIdx = widget.currentPositionIndex;
    if (replayIdx != null && widget.track.isNotEmpty) {
      final target = replayIdx
          .toDouble()
          .clamp(0.0, (widget.track.length - 1).toDouble())
          .toDouble();
      if (_animatedIdx == null) {
        // Entering replay: snap. Tweening from the dot's resting spot
        // (usually the end of the track) would glide a chord across
        // the whole map to the start.
        _positionController.stop();
        _animatedIdx = target;
        _idxTweenStart = target;
        _idxTweenEnd = target;
        final snapped =
            latLngAtFractionalIndex(_smoothedTrackFor(widget.track), target);
        if (snapped != null) _animatedLatLng = snapped;
        return;
      }
      if (_idxTweenEnd == target) return;
      _idxTweenStart = _animatedIdx;
      _idxTweenEnd = target;
      _positionController
        ..stop()
        ..value = 0
        ..forward();
      return;
    }
    // Not (or no longer) replaying — drop the index-space state so the
    // lat/lng tween below owns the dot again.
    _animatedIdx = null;
    _idxTweenStart = null;
    _idxTweenEnd = null;

    final pos = _latestPosition;
    if (pos == null) return;
    // Snap to the smoothed polyline so the dot tween targets the
    // SAME line the user sees rendered. Without this the tween
    // walked between raw GPS points which can be ±5 m off the
    // smoothed polyline — replay dot visibly drifted off the line.
    final target = _smoothedDotLatLng() ?? LatLng(pos.lat, pos.lng);

    // First fix — snap, don't animate. Subsequent fixes tween from the
    // current interpolated position to the new target.
    if (_animatedLatLng == null) {
      _animatedLatLng = target;
      _tweenStart = target;
      _tweenEnd = target;
      if (widget.followRunner && !_userPanned) {
        _moveCamera(target);
      }
      return;
    }

    final prevEnd = _tweenEnd;
    if (prevEnd != null &&
        prevEnd.latitude == target.latitude &&
        prevEnd.longitude == target.longitude) {
      return; // same target, nothing to animate
    }

    _tweenStart = _animatedLatLng;
    _tweenEnd = target;
    _positionController
      ..stop()
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final trackLatLngs = _smoothedTrackFor(widget.track);
    final plannedLatLngs = widget.plannedRoute
            ?.map((w) => LatLng(w.lat, w.lng))
            .toList() ??
        [];
    final latest = _latestPosition;
    // Prefer the interpolated (tweened) position when available so
    // the dot glides between GPS fixes instead of hopping. Fall back
    // to the SMOOTHED snap of the latest fix so the dot stays on the
    // rendered polyline (which is also smoothed) — see
    // `_smoothedDotLatLng` for the why.
    final currentLatLng = _animatedLatLng ??
        _smoothedDotLatLng() ??
        (latest != null ? LatLng(latest.lat, latest.lng) : null);

    // No GPS fix yet and no planned route — wait for GPS
    if (currentLatLng == null && plannedLatLngs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context).liveRunMapWaitingGps),
          ],
        ),
      );
    }

    final center = currentLatLng ?? plannedLatLngs.first;

    // When not following the runner (detail screen), fit the camera to the
    // full track so the user sees the whole run at a glance.
    final allPoints = trackLatLngs.isNotEmpty ? trackLatLngs : plannedLatLngs;
    final fitBounds = !widget.followRunner &&
        allPoints.length >= 2;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: fitBounds ? allPoints.first : center,
            initialZoom: fitBounds ? 14 : 19,
            // Cap gesture zoom to what the tile layer can actually cover
            // (with up-sampling above 19). Without this, users on the
            // finished-run screen pinch past the tile layer's display
            // ceiling and see only the polyline on a white background.
            minZoom: 3,
            maxZoom: 22,
            initialCameraFit: fitBounds
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(allPoints),
                    padding: const EdgeInsets.all(32),
                  )
                : null,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
            onMapReady: () {
              _mapReady = true;
              // Apply the bottom-padding offset once we know the viewport.
              final pos = _animatedLatLng;
              if (pos != null && widget.followRunner && !_userPanned) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _moveCamera(pos));
              }
            },
            onPositionChanged: (pos, hasGesture) {
              if (hasGesture) setState(() => _userPanned = true);
            },
            onTap: (widget.onSegmentSelect == null && !widget.markerPlacing)
                ? null
                : (tapPos, latLng) {
                    if (widget.markerPlacing) {
                      widget.onMarkerPlace
                          ?.call(Waypoint(lat: latLng.latitude, lng: latLng.longitude));
                      return;
                    }
                    _handleMapTap(tapPos, latLng);
                  },
          ),
          children: [
            // Dark map tiles with HTTP cache. `maxNativeZoom` caps tile
            // fetches at 19 (MapTiler's ceiling for this style) while
            // `maxZoom` lets flutter_map keep displaying the layer at
            // gesture-zoom 20–22 by up-sampling the z=19 tiles. Without
            // the split the layer goes blank past 19 and the user sees
            // the polyline floating on a white background.
            TileLayer(
              urlTemplate: _tileUrl,
              userAgentPackageName: 'com.threkir.app',
              maxNativeZoom: 19,
              maxZoom: 22,
              tileProvider: widget.offlineTileProvider ??
                  CachedTileProvider(
                    store: TileCache.store,
                    maxStale: const Duration(days: 30),
                    dio: TileCache.dio,
                  ),
            ),

            // Planned route (underneath) — dashed-looking with lighter color
            if (plannedLatLngs.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: plannedLatLngs,
                    strokeWidth: 6,
                    color: const Color(0x80A78BFA), // Translucent violet
                  ),
                ],
              ),

            // Recorded track — Nike-Run-Club-style glowing line.
            // Stack from bottom to top:
            //   1. outer halo (soft glow)
            //   2. mid halo (denser glow)
            //   3. dark underline (provides contrast without needing a
            //      per-segment border, which would show visible seams
            //      between coalesced pace buckets)
            //   4. pace heatmap OR legacy gradient on top
            if (trackLatLngs.length >= 2) ...[
              PolylineLayer(polylines: _haloPolylinesFor(trackLatLngs)),
              if (widget.activity != null)
                PolylineLayer(
                  polylines: _pacedSegmentsFor(
                    widget.track,
                    trackLatLngs,
                    widget.activity!,
                  ),
                )
              else
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: trackLatLngs,
                      strokeWidth: 6,
                      gradientColors: const [
                        Color(0xFF4F46E5),
                        Color(0xFF818CF8),
                        Color(0xFFC7D2FE),
                      ],
                    ),
                  ],
                ),
            ],

            // Selected-segment highlight — drawn over the trace + heatmap
            // so the user sees what they tapped. The host renders the
            // stats popup; the map only owns the visual highlight.
            if (_selectedSegment != null && trackLatLngs.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: trackLatLngs.sublist(
                      _selectedSegment!.startIdx,
                      _selectedSegment!.endIdx + 1,
                    ),
                    strokeWidth: 9,
                    color: const Color(0xFFF59E0B), // amber, matches web
                  ),
                ],
              ),

            // Direction chevrons + km / mile markers — rendered only on
            // detail surfaces (followRunner = false). Live recording
            // already has a pulsing dot so direction is implicit; cluttering
            // the live map with arrows would compete with that signal.
            if (widget.showDecorations && trackLatLngs.length >= 2) ...[
              MarkerLayer(
                markers: [
                  for (final c in computeChevrons(
                    trackLatLngs,
                    stepMetres: widget.useMilesForDecorations
                        ? _metresPerMile / 2
                        : 500,
                  ))
                    Marker(
                      point: c.position,
                      width: 18,
                      height: 18,
                      child: Transform.rotate(
                        angle: c.angleRadians,
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 16,
                          color: Color(0xFF1D4ED8),
                          shadows: [Shadow(color: Colors.white, blurRadius: 3)],
                        ),
                      ),
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (final m in computeDistanceMarkers(
                    trackLatLngs,
                    useMiles: widget.useMilesForDecorations,
                    totalDistanceM: widget.totalDistanceM,
                  ))
                    Marker(
                      point: m.position,
                      width: 26,
                      height: 26,
                      child: _DistanceMarkerPin(label: m.label),
                    ),
                ],
              ),
            ],

            // Ghost-pacer marker — faint silhouette showing where a
            // runner on the workout step's target pace would be right
            // now. Rendered UNDER the blue dot so the live position
            // wins for attention; the ghost is informational. Hidden
            // when no workout is active (the host passes null).
            if (widget.ghostPosition != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(
                      widget.ghostPosition!.lat,
                      widget.ghostPosition!.lng,
                    ),
                    width: 28,
                    height: 28,
                    child: const _GhostDot(),
                  ),
                ],
              ),

            // Linked-cursor marker — pinned to the elevation chart's
            // current pointer position. Mirrors the web RunMap.svelte
            // `hover-marker` div + pulse animation. Hidden when
            // hoverIdx is null or out of range.
            if (widget.hoverIdx != null &&
                widget.hoverIdx! >= 0 &&
                widget.hoverIdx! < widget.track.length)
              MarkerLayer(
                key: const ValueKey('chart-hover-marker'),
                markers: [
                  Marker(
                    point: LatLng(
                      widget.track[widget.hoverIdx!].lat,
                      widget.track[widget.hoverIdx!].lng,
                    ),
                    width: 28,
                    height: 28,
                    child: _HoverMarkerDot(animation: _pulseAnimation),
                  ),
                ],
              ),

            // Free-form preview marker driven by the route-detail
            // scrubber. Pulsing dot rendered at an interpolated
            // position along the planned polyline so the user can
            // drag a slider from 0 → 100 % and watch the "runner"
            // glide along the route.
            if (widget.previewPosition != null)
              MarkerLayer(
                key: const ValueKey('route-preview-runner'),
                markers: [
                  Marker(
                    point: LatLng(
                      widget.previewPosition!.lat,
                      widget.previewPosition!.lng,
                    ),
                    width: 48,
                    height: 48,
                    child: _PulsingDot(animation: _pulseAnimation),
                  ),
                ],
              ),

            // Course markers (aid stations, cutoffs, …). Coloured pins
            // above the trace with a label; tapping one (in edit mode)
            // reports its id up so the host can edit / delete it.
            if (widget.courseMarkers.isNotEmpty)
              MarkerLayer(
                key: const ValueKey('course-markers'),
                markers: [
                  for (final m in widget.courseMarkers)
                    Marker(
                      point: LatLng(m.lat, m.lng),
                      width: 120,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: MergeSemantics(
                        child: Semantics(
                          button: widget.onMarkerTap != null,
                          child: GestureDetector(
                            onTap: widget.onMarkerTap == null
                                ? null
                                : () => widget.onMarkerTap!(m.id),
                            child:
                                _CourseMarkerPin(label: m.label, color: m.color),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

            // Current position marker — drawn from the interpolated tween
            // position so the dot glides smoothly between GPS fixes, with
            // the raw latest fix as a fallback on the very first frame.
            if (currentLatLng != null)
              MarkerLayer(
                key: const ValueKey('current-position-marker'),
                markers: [
                  Marker(
                    point: currentLatLng,
                    width: 48,
                    height: 48,
                    child: widget.coarsePosition
                        ? const _CoarseDot()
                        : _PulsingDot(animation: _pulseAnimation),
                  ),
                ],
              ),
          ],
        ),

        // Re-center button (appears after user pans)
        if (_userPanned && currentLatLng != null)
          Positioned(
            right: 12,
            bottom: widget.bottomPadding + 12,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              tooltip: AppLocalizations.of(context).liveRunMapRecentre,
              onPressed: () {
                setState(() => _userPanned = false);
                _moveCamera(currentLatLng, zoom: _mapController.camera.zoom);
              },
              child: const Icon(Icons.my_location),
            ),
          ),
      ],
    );
  }
}

/// Small circular pin for a km / mile distance marker. Mirrors the
/// `distance-marker-bg` + `distance-marker-text` MapLibre layers on
/// `RunMap.svelte` (white circle, indigo border, indigo digit).
class _DistanceMarkerPin extends StatelessWidget {
  final int label;
  const _DistanceMarkerPin({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF4F46E5), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 3, spreadRadius: 0.5),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$label',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }
}

/// Coloured course-marker pin + label. Mirrors the `route-marker-bg` +
/// `route-marker-label` MapLibre layers on `RunMap.svelte` (coloured
/// circle, white halo, label below).
class _CourseMarkerPin extends StatelessWidget {
  final String label;
  final String color;
  const _CourseMarkerPin({required this.label, required this.color});

  Color get _color {
    final hex = color.replaceFirst('#', '');
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return const Color(0xFF6B7280);
    return Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: _color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 3, spreadRadius: 0.5),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }
}

/// Faint marker at the ghost-pacer position. No animation — the dot
/// already pulses for the live position, so a second pulsing element
/// would compete for attention. Outline-only with a low-alpha fill so
/// it reads as "secondary signal" against the route line.
class _GhostDot extends StatelessWidget {
  const _GhostDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x55FFFFFF),
        border: Border.all(
          color: const Color(0xCC818CF8),
          width: 2,
        ),
      ),
    );
  }
}

/// Approximate last-seen marker for a privacy-zone coarse fix
/// (migration 20270121_001). A hollow amber ring with a wide soft halo,
/// deliberately distinct from the solid live `_PulsingDot` so a SAR
/// watcher reads it as a ~1 km cell, not a precise current position.
/// Mirrors the web `.runner-dot.coarse` style. No pulse — it is a
/// stale-but-retained last position, not a live fix.
class _CoarseDot extends StatelessWidget {
  const _CoarseDot();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(color: const Color(0xFFF59E0B), width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x38F59E0B),
              blurRadius: 4,
              spreadRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingDot extends StatelessWidget {
  final Animation<double> animation;
  const _PulsingDot({required this.animation});

  // Static inner dot. Moved out of the AnimatedBuilder so the 60 Hz
  // pulse rebuild only touches the outer ring instead of reallocating
  // the inner Container + BoxDecoration + BoxShadow tree on every frame.
  static final _innerDot = Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFF818CF8),
      border: Border.all(color: Colors.white, width: 2.5),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66818CF8),
          blurRadius: 8,
          spreadRadius: 2,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: _innerDot,
      builder: (context, child) {
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulse ring — only this rebuilds at 60 Hz.
              Container(
                width: 48 * (0.5 + animation.value),
                height: 48 * (0.5 + animation.value),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF818CF8).withValues(alpha: animation.value),
                ),
              ),
              if (child != null) child,
            ],
          ),
        );
      },
    );
  }
}

/// Linked-cursor marker dot — pinned at `track[hoverIdx]` when the
/// user is hovering the elevation chart. Visually distinct from the
/// blue PulsingDot (current GPS position) — uses the primary accent
/// so it reads as a "viewer pointer" rather than a recorded position.
/// Mirrors `.hover-marker` + `@keyframes hover-marker-pulse` on the
/// web RunMap.svelte.
class _HoverMarkerDot extends StatelessWidget {
  final Animation<double> animation;
  const _HoverMarkerDot({required this.animation});

  static final _innerDot = Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFFF59E0B),
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66F59E0B),
          blurRadius: 6,
          spreadRadius: 1,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: _innerDot,
      builder: (context, child) {
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 28 * (0.6 + animation.value * 0.4),
                height: 28 * (0.6 + animation.value * 0.4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF59E0B)
                      .withValues(alpha: animation.value * 0.5),
                ),
              ),
              if (child != null) child,
            ],
          ),
        );
      },
    );
  }
}
