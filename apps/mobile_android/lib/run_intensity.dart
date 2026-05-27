import 'package:core_models/core_models.dart';

/// Per-zone time + sample-count breakdown of how a runner has been
/// training over a fixed window. Mirrors the inline `intensityBreakdown`
/// derived value on web's `/dashboard/+page.svelte` so the time-in-zone
/// readout reads the same way on both surfaces.
///
/// MVP classifies each run by `metadata.avg_bpm` against the supplied
/// HR-zone cutoffs (z1..z5, ascending bpm). Per-point analysis would
/// be more accurate but requires a per-run track fetch — out of scope
/// for the dashboard card, which is meant as an at-a-glance summary.
class IntensityBreakdown {
  /// Five-element list — seconds in zone 1 .. zone 5 in order.
  final List<int> zoneSeconds;
  /// Total of [zoneSeconds]. Convenient for the "x of total" readout.
  final int totalSeconds;
  /// Number of runs in the window that had an `avg_bpm` we could
  /// classify. Drives the helper text — "based on N HR-tracked runs"
  /// — and gates the empty state when nothing in the window carried HR.
  final int hrTrackedRuns;

  const IntensityBreakdown({
    required this.zoneSeconds,
    required this.totalSeconds,
    required this.hrTrackedRuns,
  });

  static const IntensityBreakdown empty = IntensityBreakdown(
    zoneSeconds: [0, 0, 0, 0, 0],
    totalSeconds: 0,
    hrTrackedRuns: 0,
  );
}

/// Out-of-band HR sentinel bounds — anything outside [40, 220] BPM is
/// treated as sensor noise rather than data. Pros' max HR rarely
/// exceeds 210, and Polar / Wahoo contact-loss commonly drops to
/// 30-50 (Z1 false-easy). 40 is below any realistic resting HR for a
/// trained adult; 220 is the standard age-based theoretical maximum
/// (220 − age = 200 at age 20). Persona-hunt finding Pro #4.
const int kHrSanityFloorBpm = 40;
const int kHrSanityCeilingBpm = 220;

/// HR-zone bpm cutoffs (z1..z5 = upper bound of each zone). Five
/// strictly-ascending integers; callers parse this off the
/// `hr_zones` map in the universal settings bag.
typedef HrZones = List<int>;

/// Parse the universal-bag `hr_zones` value into a 5-element ascending
/// list. Returns null when the map is missing, malformed, or contains
/// out-of-order cutoffs. Shared by the dashboard intensity card and
/// `run_detail_screen`'s per-run HR-zone panel so both surfaces agree
/// on what "configured" means.
HrZones? parseHrZones(Object? raw) {
  if (raw is! Map) return null;
  final out = <int>[];
  for (final k in const ['z1', 'z2', 'z3', 'z4', 'z5']) {
    final v = raw[k];
    if (v is! num) return null;
    out.add(v.round());
  }
  if (out.length != 5) return null;
  for (var i = 1; i < out.length; i++) {
    if (out[i] <= out[i - 1]) return null;
  }
  return out;
}

/// Classify every run that started within the last [windowDays]
/// against the supplied [zones] and sum the per-zone seconds. Runs
/// without an `avg_bpm` are skipped (not counted as "easy" — we don't
/// know).
///
/// [now] is parameterised so tests can pin the time window. In
/// production callers pass `DateTime.now()`.
IntensityBreakdown computeIntensityBreakdown(
  List<Run> runs,
  HrZones zones, {
  required int windowDays,
  required DateTime now,
}) {
  if (zones.length != 5) return IntensityBreakdown.empty;
  // Cutoffs must be strictly increasing or the zone-index math is
  // meaningless. Mirrors the parse guard in run_detail_screen.
  for (var i = 1; i < zones.length; i++) {
    if (zones[i] <= zones[i - 1]) return IntensityBreakdown.empty;
  }
  if (windowDays <= 0) return IntensityBreakdown.empty;

  final cutoff = now.subtract(Duration(days: windowDays));
  final zoneSeconds = <int>[0, 0, 0, 0, 0];
  var hrTracked = 0;
  for (final r in runs) {
    if (r.startedAt.isBefore(cutoff)) continue;
    final avgRaw = r.metadata?['avg_bpm'];
    if (avgRaw is! num) continue;
    final avg = avgRaw.toDouble();
    // Persona-hunt Pro #4: sensor glitches (chest-strap contact loss,
    // dropped pairing) commonly produce avg_bpm spikes (215+) or
    // collapses (sub-40). Either tags a whole workout into the wrong
    // zone and shifts the 30-day breakdown noticeably. Treat values
    // outside [40, 220] as "missing" — same disposition as `avg <= 0`.
    if (avg < kHrSanityFloorBpm || avg > kHrSanityCeilingBpm) continue;
    hrTracked += 1;
    int idx;
    if (avg < zones[0]) {
      idx = 0;
    } else if (avg < zones[1]) {
      idx = 1;
    } else if (avg < zones[2]) {
      idx = 2;
    } else if (avg < zones[3]) {
      idx = 3;
    } else {
      idx = 4;
    }
    zoneSeconds[idx] += r.duration.inSeconds;
  }
  final total = zoneSeconds.fold<int>(0, (a, b) => a + b);
  return IntensityBreakdown(
    zoneSeconds: List.unmodifiable(zoneSeconds),
    totalSeconds: total,
    hrTrackedRuns: hrTracked,
  );
}
