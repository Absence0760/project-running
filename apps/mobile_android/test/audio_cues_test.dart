// Unit tests for the pure TTS-format helpers in `lib/audio_cues.dart`.
//
// The `AudioCues` class itself wraps `FlutterTts` (platform plugin) so
// the announceX methods need real platform bindings. This file scopes
// to the four pure top-level format functions exposed for direct
// testing:
//
//   - `formatSpeedUtterance(secsPerKm, unit)` — km/h or mph string
//   - `formatPaceUtterance(secsPerKm, unit)` — "Pace, M minutes S
//     seconds per X" string
//   - `formatSpokenDistance(metres)` — "N kilometres" / "N metres"
//   - `formatWorkoutStepUtterance(step)` — composite intro for
//     structured-workout step transitions
//
// These strings ARE the audio cue the runner hears at every split,
// off-route, workout-step transition, and end-of-run summary. A
// regression in any of them silently mangles the user's audio
// experience without any visual signal — exactly the kind of bug
// that's hard to catch in production.

import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart' show WorkoutStep, WorkoutStepKind;

import '../lib/audio_cues.dart';
import '../lib/preferences.dart';

void main() {
  group('formatSpeedUtterance', () {
    test('null secondsPerKm returns the empty string (suppress cue)', () {
      // The split-cue caller appends the speed to a distance line.
      // Empty-string degrades to "5 kilometres." with no trailing
      // speed — preferable to "5 kilometres. Speed, NaN km/h".
      expect(formatSpeedUtterance(null, DistanceUnit.km), '');
    });

    test('zero or negative secondsPerKm returns empty string', () {
      // Division by zero would otherwise produce Infinity → "Speed,
      // Infinity km/h". The <=0 guard is the only thing preventing
      // that — a regression to `secondsPerKm == null || secondsPerKm
      // == 0` (loosening to allow negative) would surface as
      // "Speed, -3.0 km/h" on a sensor jitter sample.
      expect(formatSpeedUtterance(0, DistanceUnit.km), '');
      expect(formatSpeedUtterance(-100, DistanceUnit.km), '');
    });

    test('km mode renders km/h to one decimal', () {
      // 360 sec/km → 3600/360 = 10 km/h
      expect(formatSpeedUtterance(360, DistanceUnit.km),
          'Speed, 10.0 kilometres per hour');
      // 300 sec/km → 12 km/h
      expect(formatSpeedUtterance(300, DistanceUnit.km),
          'Speed, 12.0 kilometres per hour');
    });

    test('mi mode converts km/h to mph via 1.609344 factor', () {
      // 360 sec/km = 10 km/h = 10 / 1.609344 = 6.21 mph → 6.2
      expect(formatSpeedUtterance(360, DistanceUnit.mi),
          'Speed, 6.2 miles per hour');
    });
  });

  group('formatPaceUtterance', () {
    test('null / non-positive secondsPerKm returns empty string', () {
      // Same suppression contract as formatSpeedUtterance — empty
      // degrades the cue rather than speaking junk.
      expect(formatPaceUtterance(null, DistanceUnit.km), '');
      expect(formatPaceUtterance(0, DistanceUnit.km), '');
      expect(formatPaceUtterance(-30, DistanceUnit.km), '');
    });

    test('km mode renders M:SS as "M minutes S seconds per kilometre"', () {
      // 330 sec/km = 5 min 30 sec
      expect(formatPaceUtterance(330, DistanceUnit.km),
          'Pace, 5 minutes 30 seconds per kilometre');
    });

    test('exact-minute pace renders "0 seconds" (not omitted)', () {
      // 300 sec/km = 5:00. The cue includes "0 seconds" so the
      // structure is consistent — a regression that suppressed the
      // zero would emit "Pace, 5 minutes per kilometre" which is
      // shorter but breaks the M:SS audio rhythm.
      expect(formatPaceUtterance(300, DistanceUnit.km),
          'Pace, 5 minutes 0 seconds per kilometre');
    });

    test('mi mode converts sec/km to sec/mi via 1.609344 km/mi factor', () {
      // 300 sec/km × 1.609344 km/mi = 482.8 sec/mi = 8 min 2 sec
      // (482 // 60 = 8, 482 % 60 = 2 — the trailing 0.8 is truncated
      // by `.toInt()` on the seconds).
      final r = formatPaceUtterance(300, DistanceUnit.mi);
      // M = 8, S = 2 (truncated from 2.8). Pin the literal so a
      // refactor to `.round()` (which would yield S=3) fails loud.
      expect(r, 'Pace, 8 minutes 2 seconds per mile');
    });

    test('mi mode includes "per mile" suffix, not "per kilometre"', () {
      // Suffix is the unit-label — a regression that hardcoded
      // "per kilometre" would silently render mph paces with the
      // wrong unit.
      expect(formatPaceUtterance(330, DistanceUnit.mi),
          contains('per mile'));
      expect(formatPaceUtterance(330, DistanceUnit.mi),
          isNot(contains('per kilometre')));
    });
  });

  group('formatSpokenDistance', () {
    test('sub-1km renders as metres (no decimal)', () {
      expect(formatSpokenDistance(500), '500 metres');
      expect(formatSpokenDistance(999), '999 metres');
      expect(formatSpokenDistance(50), '50 metres');
    });

    test('exactly 1km drops decimal — "1 kilometres" not "1.0 kilometres"', () {
      // The km == km.roundToDouble() check catches integer km values
      // and renders them without the decimal. A regression that
      // always emitted .1f would speak "1.0 kilometres" — accurate
      // but unnatural.
      expect(formatSpokenDistance(1000), '1 kilometres');
      expect(formatSpokenDistance(5000), '5 kilometres');
    });

    test('non-integer km renders with one decimal', () {
      // 5500 m → 5.5 km
      expect(formatSpokenDistance(5500), '5.5 kilometres');
      // 1234 m → 1.234 km → "1.2" (toStringAsFixed rounds)
      expect(formatSpokenDistance(1234), '1.2 kilometres');
    });

    test('999.5 metres rounds to 1000 m (renders as metres, not km)', () {
      // metres.round() floors-half-to-even-by-default in Dart's
      // num.round(); 999.5 → 1000 actually. Then the check is
      // `metres >= 1000`. So 999.5 → 1000 m → renders as
      // "1000 metres" via the round, OR enters the km branch and
      // renders as "1 kilometres". Let's pin the actual behaviour.
      //
      // Looking at the source: line 44 checks `metres >= 1000`, then
      // line 49 does `metres.round()`. 999.5 < 1000 → metres branch.
      // 999.5.round() = 1000 → "1000 metres".
      //
      // So the >= 1000 check uses the RAW metres, not the rounded.
      // This is the kind of edge case that could surprise a refactor.
      expect(formatSpokenDistance(999.5), '1000 metres');
    });

    test('exactly 1000 m boundary enters the km branch', () {
      expect(formatSpokenDistance(1000.0), '1 kilometres');
    });
  });

  group('formatWorkoutStepUtterance', () {
    WorkoutStep step({
      required WorkoutStepKind kind,
      int? repIndex,
      int? repTotal,
      double targetDistanceMetres = 1000,
      int targetPaceSecPerKm = 300,
    }) =>
        WorkoutStep(
          kind: kind,
          repIndex: repIndex,
          repTotal: repTotal,
          targetDistanceMetres: targetDistanceMetres,
          targetPaceSecPerKm: targetPaceSecPerKm,
          toleranceSecPerKm: 10,
          label: 'test',
        );

    test('warmup intro reads "Warmup."', () {
      final r = formatWorkoutStepUtterance(step(kind: WorkoutStepKind.warmup));
      expect(r, startsWith('Warmup.'));
    });

    test('rep with repIndex+repTotal reads "Rep N of M"', () {
      final r = formatWorkoutStepUtterance(
        step(kind: WorkoutStepKind.rep, repIndex: 3, repTotal: 5),
      );
      expect(r, startsWith('Rep 3 of 5.'));
    });

    test('rep WITHOUT repIndex/repTotal degrades to bare "Rep"', () {
      // Defensive: a non-rep refactor that wired generic intervals
      // through with null indices must not speak "Rep null of null".
      final r = formatWorkoutStepUtterance(step(kind: WorkoutStepKind.rep));
      expect(r, startsWith('Rep.'));
      expect(r, isNot(contains('null')));
    });

    test('recovery + steady + cooldown intros pinned', () {
      // Each enum value gets its own intro. A per-value regression
      // (e.g. recovery → "Recovery rep") wouldn't fail other tests.
      expect(
        formatWorkoutStepUtterance(step(kind: WorkoutStepKind.recovery)),
        startsWith('Recovery.'),
      );
      expect(
        formatWorkoutStepUtterance(step(kind: WorkoutStepKind.steady)),
        startsWith('Steady.'),
      );
      expect(
        formatWorkoutStepUtterance(step(kind: WorkoutStepKind.cooldown)),
        startsWith('Cooldown.'),
      );
    });

    test('exact-minute pace renders without "0 seconds"', () {
      // The intra-step pace formatter omits "0 seconds" — the cue
      // is composed inline and reads more naturally as "5 minutes
      // per kilometre" than "5 minutes 0 seconds per kilometre" in
      // the mid-step context. Pin the asymmetry vs
      // formatPaceUtterance (which DOES include "0 seconds").
      final r = formatWorkoutStepUtterance(
        step(kind: WorkoutStepKind.warmup, targetPaceSecPerKm: 300),
      );
      expect(r, contains('5 minutes per kilometre'));
      expect(r, isNot(contains('5 minutes 0 seconds')));
    });

    test('non-zero seconds in pace renders "M minutes S seconds"', () {
      final r = formatWorkoutStepUtterance(
        step(kind: WorkoutStepKind.rep,
            repIndex: 1, repTotal: 3,
            targetPaceSecPerKm: 330),
      );
      expect(r, contains('5 minutes 30 seconds per kilometre'));
    });

    test('distance is in spoken-distance form, NOT metres always', () {
      // 1000m step → "1 kilometres", 200m step → "200 metres"
      final long = formatWorkoutStepUtterance(
        step(kind: WorkoutStepKind.rep,
            repIndex: 1, repTotal: 1,
            targetDistanceMetres: 1000),
      );
      expect(long, contains('1 kilometres'));
      final short = formatWorkoutStepUtterance(
        step(kind: WorkoutStepKind.recovery, targetDistanceMetres: 200),
      );
      expect(short, contains('200 metres'));
    });
  });
}
