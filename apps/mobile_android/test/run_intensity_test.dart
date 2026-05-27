import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/run_intensity.dart';

Run _run({
  required DateTime startedAt,
  required int durationS,
  num? avgBpm,
}) {
  return Run(
    id: 'r-${startedAt.toIso8601String()}',
    startedAt: startedAt,
    duration: Duration(seconds: durationS),
    distanceMetres: 5000,
    source: RunSource.app,
    metadata: avgBpm == null ? null : {'avg_bpm': avgBpm},
  );
}

void main() {
  // Standard 5-zone cutoffs for a runner with ~190 max HR. Each value
  // is the upper bound of the zone (matches the web parse).
  const zones = <int>[114, 133, 152, 171, 190];
  final now = DateTime(2026, 5, 1, 12, 0, 0);

  group('computeIntensityBreakdown', () {
    test('empty when no runs', () {
      final out = computeIntensityBreakdown(
        const [],
        zones,
        windowDays: 30,
        now: now,
      );
      expect(out.totalSeconds, 0);
      expect(out.hrTrackedRuns, 0);
      expect(out.zoneSeconds, [0, 0, 0, 0, 0]);
    });

    test('skips runs older than the window', () {
      final out = computeIntensityBreakdown(
        [
          _run(
            startedAt: now.subtract(const Duration(days: 45)),
            durationS: 1800,
            avgBpm: 145,
          ),
        ],
        zones,
        windowDays: 30,
        now: now,
      );
      expect(out.hrTrackedRuns, 0);
      expect(out.totalSeconds, 0);
    });

    test('skips runs without an avg_bpm value', () {
      final out = computeIntensityBreakdown(
        [
          _run(startedAt: now.subtract(const Duration(days: 2)), durationS: 1200),
          _run(
            startedAt: now.subtract(const Duration(days: 1)),
            durationS: 600,
            avgBpm: 0, // sentinel zero — skip
          ),
        ],
        zones,
        windowDays: 30,
        now: now,
      );
      // Both runs ineligible — no HR signal.
      expect(out.hrTrackedRuns, 0);
      expect(out.totalSeconds, 0);
    });

    test('classifies each run into the right zone bucket', () {
      // avg_bpm 100 → < z1 (114) → zone 1
      // avg_bpm 120 → ≥ z1, < z2 (133) → zone 2
      // avg_bpm 140 → ≥ z2, < z3 (152) → zone 3
      // avg_bpm 160 → ≥ z3, < z4 (171) → zone 4
      // avg_bpm 180 → ≥ z4 → zone 5
      final out = computeIntensityBreakdown(
        [
          _run(startedAt: now.subtract(const Duration(days: 1)), durationS: 100, avgBpm: 100),
          _run(startedAt: now.subtract(const Duration(days: 2)), durationS: 200, avgBpm: 120),
          _run(startedAt: now.subtract(const Duration(days: 3)), durationS: 300, avgBpm: 140),
          _run(startedAt: now.subtract(const Duration(days: 4)), durationS: 400, avgBpm: 160),
          _run(startedAt: now.subtract(const Duration(days: 5)), durationS: 500, avgBpm: 180),
        ],
        zones,
        windowDays: 30,
        now: now,
      );
      expect(out.zoneSeconds, [100, 200, 300, 400, 500]);
      expect(out.totalSeconds, 1500);
      expect(out.hrTrackedRuns, 5);
    });

    test('sums durations within the same zone across multiple runs', () {
      // Two easy runs (both < z1) → zone 1 accumulates.
      final out = computeIntensityBreakdown(
        [
          _run(startedAt: now.subtract(const Duration(days: 1)), durationS: 1200, avgBpm: 105),
          _run(startedAt: now.subtract(const Duration(days: 2)), durationS: 1800, avgBpm: 110),
        ],
        zones,
        windowDays: 30,
        now: now,
      );
      expect(out.zoneSeconds, [3000, 0, 0, 0, 0]);
      expect(out.hrTrackedRuns, 2);
      expect(out.totalSeconds, 3000);
    });

    test('rejects zones list that is not strictly ascending', () {
      // A bug-day misconfiguration must not produce a misleading
      // breakdown; bailing to empty is the safest fallback the card
      // can render.
      final out = computeIntensityBreakdown(
        [
          _run(startedAt: now.subtract(const Duration(days: 1)), durationS: 600, avgBpm: 145),
        ],
        const [114, 133, 133, 171, 190], // z2 == z3 → reject
        windowDays: 30,
        now: now,
      );
      expect(out, IntensityBreakdown.empty);
    });

    test('rejects zones list with wrong length', () {
      final out = computeIntensityBreakdown(
        [
          _run(startedAt: now.subtract(const Duration(days: 1)), durationS: 600, avgBpm: 145),
        ],
        const [114, 133, 152, 171], // only 4 cutoffs
        windowDays: 30,
        now: now,
      );
      expect(out, IntensityBreakdown.empty);
    });

    test('rejects non-positive window', () {
      final out = computeIntensityBreakdown(
        [
          _run(startedAt: now.subtract(const Duration(days: 1)), durationS: 600, avgBpm: 145),
        ],
        zones,
        windowDays: 0,
        now: now,
      );
      expect(out, IntensityBreakdown.empty);
    });

    test('exact boundary HR equal to z[n] goes to the higher zone '
        '(< semantics, not <=)', () {
      // avg_bpm = 133 means "at zone 2 upper bound" → zone 3 starts
      // here per the `avg < z[n]` semantics. This matches the web
      // ladder so a runner sees the same classification in both.
      final out = computeIntensityBreakdown(
        [
          _run(startedAt: now.subtract(const Duration(days: 1)), durationS: 600, avgBpm: 133),
        ],
        zones,
        windowDays: 30,
        now: now,
      );
      expect(out.zoneSeconds[1], 0);
      expect(out.zoneSeconds[2], 600);
    });
  });

  group('parseHrZones', () {
    test('parses a valid map into the ascending 5-element list', () {
      final out = parseHrZones(
        const {'z1': 114, 'z2': 133, 'z3': 152, 'z4': 171, 'z5': 190},
      );
      expect(out, [114, 133, 152, 171, 190]);
    });

    test('rounds non-int numeric values', () {
      final out = parseHrZones(
        const {'z1': 113.6, 'z2': 133.0, 'z3': 152.2, 'z4': 171.0, 'z5': 190.0},
      );
      expect(out, [114, 133, 152, 171, 190]);
    });

    test('returns null for non-Map input', () {
      expect(parseHrZones(null), isNull);
      expect(parseHrZones('hr_zones'), isNull);
      expect(parseHrZones(42), isNull);
    });

    test('returns null when a key is missing or non-numeric', () {
      expect(
        parseHrZones(const {'z1': 114, 'z2': 133, 'z3': 152, 'z4': 171}),
        isNull,
      );
      expect(
        parseHrZones(
          const {'z1': 114, 'z2': 'oops', 'z3': 152, 'z4': 171, 'z5': 190},
        ),
        isNull,
      );
    });

    test('returns null when cutoffs are not strictly ascending', () {
      // z3 == z4 — equal is not ascending.
      expect(
        parseHrZones(
          const {'z1': 114, 'z2': 133, 'z3': 152, 'z4': 152, 'z5': 190},
        ),
        isNull,
      );
      // Out-of-order.
      expect(
        parseHrZones(
          const {'z1': 190, 'z2': 114, 'z3': 133, 'z4': 152, 'z5': 171},
        ),
        isNull,
      );
    });
  });

  // Persona-hunt Pro #4: chest-strap glitches (contact loss → sub-40
  // bpm collapse, dropped pairing → 215+ bpm spike) used to land in
  // the breakdown and shift the 30-day time-in-zone readout
  // noticeably. Sanity bounds [40, 220] treat both as "missing".
  group('computeIntensityBreakdown — HR sanity bounds (Pro #4)', () {
    final now = DateTime.utc(2026, 4, 30);
    final zones = [114, 133, 152, 171, 190];

    test('rejects spike: avg_bpm = 225 (above sensor ceiling)', () {
      final out = computeIntensityBreakdown(
        [
          _run(
            startedAt: now.subtract(const Duration(days: 1)),
            durationS: 3600,
            avgBpm: 225,
          ),
        ],
        zones,
        windowDays: 30,
        now: now,
      );
      expect(out.hrTrackedRuns, 0,
          reason: '225 bpm is a sensor glitch — must not tag the run');
      expect(out.totalSeconds, 0);
    });

    test('rejects collapse: avg_bpm = 35 (below sensor floor)', () {
      final out = computeIntensityBreakdown(
        [
          _run(
            startedAt: now.subtract(const Duration(days: 1)),
            durationS: 3600,
            avgBpm: 35,
          ),
        ],
        zones,
        windowDays: 30,
        now: now,
      );
      expect(out.hrTrackedRuns, 0,
          reason: '35 bpm is contact-loss noise — must not tag Z1');
      expect(out.totalSeconds, 0);
    });

    test('accepts boundary: avg_bpm = 40 (exact sensor floor)', () {
      final out = computeIntensityBreakdown(
        [
          _run(
            startedAt: now.subtract(const Duration(days: 1)),
            durationS: 600,
            avgBpm: 40,
          ),
        ],
        zones,
        windowDays: 30,
        now: now,
      );
      expect(out.hrTrackedRuns, 1);
      expect(out.totalSeconds, 600);
    });

    test('accepts boundary: avg_bpm = 220 (exact sensor ceiling)', () {
      final out = computeIntensityBreakdown(
        [
          _run(
            startedAt: now.subtract(const Duration(days: 1)),
            durationS: 600,
            avgBpm: 220,
          ),
        ],
        zones,
        windowDays: 30,
        now: now,
      );
      expect(out.hrTrackedRuns, 1);
      expect(out.totalSeconds, 600);
    });

    test('rejects 221 (just above ceiling)', () {
      final out = computeIntensityBreakdown(
        [
          _run(
            startedAt: now.subtract(const Duration(days: 1)),
            durationS: 600,
            avgBpm: 221,
          ),
        ],
        zones,
        windowDays: 30,
        now: now,
      );
      expect(out.hrTrackedRuns, 0);
    });

    test('rejects 39 (just below floor)', () {
      final out = computeIntensityBreakdown(
        [
          _run(
            startedAt: now.subtract(const Duration(days: 1)),
            durationS: 600,
            avgBpm: 39,
          ),
        ],
        zones,
        windowDays: 30,
        now: now,
      );
      expect(out.hrTrackedRuns, 0);
    });
  });
}
