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
//   - `formatSpokenDistance(metres, unit)` — "N kilometres"/"N metres" or "N miles"/"N yards"
//   - `formatWorkoutStepUtterance(step, unit)` — composite intro for
//     structured-workout step transitions
//
// These strings ARE the audio cue the runner hears at every split,
// off-route, workout-step transition, and end-of-run summary. A
// regression in any of them silently mangles the user's audio
// experience without any visual signal — exactly the kind of bug
// that's hard to catch in production.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart' show WorkoutStep, WorkoutStepKind;

import '../lib/audio_cues.dart';
import '../lib/preferences.dart';

void main() {
  group('SplitPaceMode.coerce', () {
    test('known values pass through', () {
      expect(SplitPaceMode.coerce('split'), SplitPaceMode.split);
      expect(SplitPaceMode.coerce('average'), SplitPaceMode.average);
      expect(SplitPaceMode.coerce('both'), SplitPaceMode.both);
    });
    test('null / unknown falls back to split (never disables the cue)', () {
      expect(SplitPaceMode.coerce(null), SplitPaceMode.split);
      expect(SplitPaceMode.coerce(''), SplitPaceMode.split);
      expect(SplitPaceMode.coerce('nonsense'), SplitPaceMode.split);
    });
  });

  group('splitCueDistance', () {
    test('metric default interval counts whole kilometres', () {
      final one = splitCueDistance(1, 1000, DistanceUnit.km);
      expect(one.count, '1');
      expect(one.singular, isTrue);
      final five = splitCueDistance(5, 1000, DistanceUnit.km);
      expect(five.count, '5');
      expect(five.singular, isFalse);
    });

    test('the 500 m interval speaks halves, not a rounded-up whole', () {
      // Regression: the count was `round(ticks * interval / 1000)`, so the
      // first 500 m split announced "1 kilometre" — the runner is told they
      // have run twice as far as they have.
      expect(splitCueDistance(1, 500, DistanceUnit.km).count, '0.5');
      expect(splitCueDistance(1, 500, DistanceUnit.km).singular, isFalse);
      expect(splitCueDistance(3, 500, DistanceUnit.km).count, '1.5');
      expect(splitCueDistance(4, 500, DistanceUnit.km).count, '2');
    });

    test('imperial on the default 1 km interval speaks real miles', () {
      // Regression: the kilometre count was read out with the word "miles",
      // so 1 km announced as "1 mile" while the on-screen banner said 0.6 mi.
      expect(splitCueDistance(1, 1000, DistanceUnit.mi).count, '0.6');
      expect(splitCueDistance(1, 1000, DistanceUnit.mi).singular, isFalse);
      expect(splitCueDistance(5, 1000, DistanceUnit.mi).count, '3.1');
    });

    test('the 1 mi preset (1609 m) reads as a whole mile, not "1.0"', () {
      final one = splitCueDistance(1, 1609, DistanceUnit.mi);
      expect(one.count, '1');
      expect(one.singular, isTrue);
      final three = splitCueDistance(3, 1609, DistanceUnit.mi);
      expect(three.count, '3');
      expect(three.singular, isFalse);
      // Still whole deep into an ultra, where the 0.344 m/mile the preset
      // drops would otherwise accumulate past a tenth.
      expect(splitCueDistance(50, 1609, DistanceUnit.mi).count, '50');
    });

    test("cycling's 5 km interval converts for an imperial rider", () {
      expect(splitCueDistance(1, 5000, DistanceUnit.km).count, '5');
      expect(splitCueDistance(1, 5000, DistanceUnit.mi).count, '3.1');
    });
  });

  group('splitCueUtterance', () {
    final en = ttsL10n('en');
    const splitTail = 'Pace, 5 minutes 30 seconds per kilometre';
    const avgTail = 'Pace, 5 minutes 45 seconds per kilometre';

    test('split mode speaks only the split tail', () {
      final s = splitCueUtterance(en,
          count: '1',
          unitWord: 'kilometre',
          splitTail: splitTail,
          avgTail: avgTail,
          paceMode: SplitPaceMode.split);
      expect(s, '1 kilometre. $splitTail');
      expect(s.contains('Average'), isFalse);
    });

    test('average mode speaks the cumulative-average tail', () {
      final s = splitCueUtterance(en,
          count: '1',
          unitWord: 'kilometre',
          splitTail: splitTail,
          avgTail: avgTail,
          paceMode: SplitPaceMode.average);
      expect(s, '1 kilometre. Average $avgTail');
    });

    test('both mode speaks the split tail then the average', () {
      final s = splitCueUtterance(en,
          count: '2',
          unitWord: 'kilometres',
          splitTail: splitTail,
          avgTail: avgTail,
          paceMode: SplitPaceMode.both);
      expect(s, '2 kilometres. $splitTail. Average $avgTail');
    });

    test('average mode degrades to split-only when the average is missing', () {
      final s = splitCueUtterance(en,
          count: '1',
          unitWord: 'kilometre',
          splitTail: splitTail,
          avgTail: '',
          paceMode: SplitPaceMode.average);
      expect(s, '1 kilometre. $splitTail');
    });

    test('both mode degrades to split-only when the average is missing', () {
      final s = splitCueUtterance(en,
          count: '1',
          unitWord: 'kilometre',
          splitTail: splitTail,
          avgTail: '',
          paceMode: SplitPaceMode.both);
      expect(s, '1 kilometre. $splitTail');
    });
  });

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

  group('formatPaceTailUtterance', () {
    test('null / non-positive secondsPerKm returns empty string', () {
      expect(formatPaceTailUtterance(null, DistanceUnit.km), '');
      expect(formatPaceTailUtterance(0, DistanceUnit.km), '');
      expect(formatPaceTailUtterance(-30, DistanceUnit.km), '');
    });

    test('km mode renders the bare pace with no "Pace," prefix', () {
      expect(formatPaceTailUtterance(341, DistanceUnit.km),
          '5 minutes 41 seconds per kilometre');
    });

    test('exact-minute pace drops the zero-seconds tail', () {
      expect(formatPaceTailUtterance(300, DistanceUnit.km),
          '5 minutes per kilometre');
    });

    test('mi mode converts sec/km to sec/mi before formatting', () {
      // 300 sec/km * 1.609344 = 482.8 → 483 s = 8:03 per mile.
      expect(formatPaceTailUtterance(300, DistanceUnit.mi),
          '8 minutes 3 seconds per mile');
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

  group('formatSpokenDistance (km mode)', () {
    test('sub-1km renders as metres (no decimal)', () {
      expect(formatSpokenDistance(500, DistanceUnit.km), '500 metres');
      expect(formatSpokenDistance(999, DistanceUnit.km), '999 metres');
      expect(formatSpokenDistance(50, DistanceUnit.km), '50 metres');
    });

    test('exactly 1km drops decimal — "1 kilometres" not "1.0 kilometres"', () {
      // The km == km.roundToDouble() check catches integer km values
      // and renders them without the decimal. A regression that
      // always emitted .1f would speak "1.0 kilometres" — accurate
      // but unnatural.
      expect(formatSpokenDistance(1000, DistanceUnit.km), '1 kilometres');
      expect(formatSpokenDistance(5000, DistanceUnit.km), '5 kilometres');
    });

    test('non-integer km renders with one decimal', () {
      // 5500 m → 5.5 km
      expect(formatSpokenDistance(5500, DistanceUnit.km), '5.5 kilometres');
      // 1234 m → 1.234 km → "1.2" (toStringAsFixed rounds)
      expect(formatSpokenDistance(1234, DistanceUnit.km), '1.2 kilometres');
    });

    test('999.5 metres rounds to 1000 m (renders as metres, not km)', () {
      // metres.round() floors-half-to-even-by-default in Dart's
      // num.round(); 999.5 → 1000 actually. The km/metres branch
      // checks `metres >= 1000` BEFORE rounding, so 999.5 enters the
      // metres branch and `999.5.round()` yields "1000 metres".
      // Edge case worth pinning.
      expect(formatSpokenDistance(999.5, DistanceUnit.km), '1000 metres');
    });

    test('exactly 1000 m boundary enters the km branch', () {
      expect(formatSpokenDistance(1000.0, DistanceUnit.km), '1 kilometres');
    });
  });

  group('formatSpokenDistance (mi mode)', () {
    // Regression net for the unit-aware TTS path. A user with mi-pref
    // who heard "5 kilometres" while their on-screen distance read
    // "3.11 mi" is the headline bug this guards against.
    test('integer miles uses singular/plural correctly', () {
      // 1 mile = 1609.344 m → "1 mile" (NOT "1 miles")
      expect(formatSpokenDistance(1609.344, DistanceUnit.mi), '1 mile');
      // 5 miles → "5 miles"
      expect(formatSpokenDistance(5 * 1609.344, DistanceUnit.mi), '5 miles');
    });

    test('non-integer miles uses one decimal — "3.1 miles"', () {
      // 5000 m / 1609.344 ≈ 3.107 → "3.1 miles"
      expect(formatSpokenDistance(5000, DistanceUnit.mi), '3.1 miles');
    });

    test('sub-1-mile renders in yards', () {
      // 800 m × 1.09361 ≈ 875 yards
      expect(formatSpokenDistance(800, DistanceUnit.mi), '875 yards');
      expect(formatSpokenDistance(0, DistanceUnit.mi), '0 yards');
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
      final r = formatWorkoutStepUtterance(
          step(kind: WorkoutStepKind.warmup), DistanceUnit.km);
      expect(r, startsWith('Warmup.'));
    });

    test('rep with repIndex+repTotal reads "Rep N of M"', () {
      final r = formatWorkoutStepUtterance(
        step(kind: WorkoutStepKind.rep, repIndex: 3, repTotal: 5),
        DistanceUnit.km,
      );
      expect(r, startsWith('Rep 3 of 5.'));
    });

    test('rep WITHOUT repIndex/repTotal degrades to bare "Rep"', () {
      // Defensive: a non-rep refactor that wired generic intervals
      // through with null indices must not speak "Rep null of null".
      final r = formatWorkoutStepUtterance(
          step(kind: WorkoutStepKind.rep), DistanceUnit.km);
      expect(r, startsWith('Rep.'));
      expect(r, isNot(contains('null')));
    });

    test('recovery + steady + cooldown intros pinned', () {
      // Each enum value gets its own intro. A per-value regression
      // (e.g. recovery → "Recovery rep") wouldn't fail other tests.
      expect(
        formatWorkoutStepUtterance(
            step(kind: WorkoutStepKind.recovery), DistanceUnit.km),
        startsWith('Recovery.'),
      );
      expect(
        formatWorkoutStepUtterance(
            step(kind: WorkoutStepKind.steady), DistanceUnit.km),
        startsWith('Steady.'),
      );
      expect(
        formatWorkoutStepUtterance(
            step(kind: WorkoutStepKind.cooldown), DistanceUnit.km),
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
        DistanceUnit.km,
      );
      expect(r, contains('5 minutes per kilometre'));
      expect(r, isNot(contains('5 minutes 0 seconds')));
    });

    test('non-zero seconds in pace renders "M minutes S seconds"', () {
      final r = formatWorkoutStepUtterance(
        step(kind: WorkoutStepKind.rep,
            repIndex: 1, repTotal: 3,
            targetPaceSecPerKm: 330),
        DistanceUnit.km,
      );
      expect(r, contains('5 minutes 30 seconds per kilometre'));
    });

    test('distance is in spoken-distance form, NOT metres always', () {
      // 1000m step → "1 kilometres", 200m step → "200 metres"
      final long = formatWorkoutStepUtterance(
        step(kind: WorkoutStepKind.rep,
            repIndex: 1, repTotal: 1,
            targetDistanceMetres: 1000),
        DistanceUnit.km,
      );
      expect(long, contains('1 kilometres'));
      final short = formatWorkoutStepUtterance(
        step(kind: WorkoutStepKind.recovery, targetDistanceMetres: 200),
        DistanceUnit.km,
      );
      expect(short, contains('200 metres'));
    });

    test('mi-mode: distance + pace both render imperial', () {
      // Regression net for the unit-aware workout-step utterance.
      // A bug that left only distance unit-aware would speak
      // "1 mile at 5 minutes per kilometre" — confusing for an
      // imperial runner.
      final r = formatWorkoutStepUtterance(
        step(
          kind: WorkoutStepKind.rep,
          repIndex: 1,
          repTotal: 3,
          targetDistanceMetres: 1609.344,
          targetPaceSecPerKm: 300,
        ),
        DistanceUnit.mi,
      );
      expect(r, contains('1 mile'));
      expect(r, contains('per mile'));
      expect(r, isNot(contains('per kilometre')));
      expect(r, isNot(contains('kilometres')));
    });
  });

  group('localized utterances (de)', () {
    WorkoutStep deStep() => WorkoutStep(
          kind: WorkoutStepKind.warmup,
          targetDistanceMetres: 1000,
          targetPaceSecPerKm: 300,
          toleranceSecPerKm: 10,
          label: 'test',
        );

    // The same pure helpers read from the gen-l10n catalogue for the
    // passed locale tag — a German runner hears German cues, not English.
    test('pace utterance renders the German wording', () {
      expect(formatPaceUtterance(330, DistanceUnit.km, 'de'),
          'Pace, 5 Minuten 30 Sekunden pro Kilometer');
    });

    test('spoken distance renders the German unit word', () {
      expect(formatSpokenDistance(5000, DistanceUnit.km, 'de'), '5 Kilometer');
    });

    test('workout-step intro is translated', () {
      final r = formatWorkoutStepUtterance(deStep(), DistanceUnit.km, 'de');
      expect(r, startsWith('Aufwärmen.'));
      expect(r, contains('pro Kilometer'));
    });
  });

  group('AudioCues wiring (source guard)', () {
    test('announceFinish speaks the distance, never UnitFormat abbreviations',
        () {
      final src = File('lib/audio_cues.dart').readAsStringSync();
      final start = src.indexOf('Future<void> announceFinish(');
      expect(start, isNonNegative);
      final body = src.substring(start, src.indexOf('/// Warn that', start));
      expect(body, contains('formatSpokenDistance(distanceMetres, unit, tag)'));
      expect(
        body.contains('UnitFormat.distance('),
        isFalse,
        reason: 'UnitFormat renders "5.2 km" — an engine reads that '
            'abbreviation out as letters, and it is not the right word in a '
            'non-English voice.',
      );
    });
  });

  group('ttsDuckingStrategyFor (persona #12)', () {
    test('Android → navigation-guidance ducking', () {
      expect(ttsDuckingStrategyFor(isAndroid: true, isIOS: false),
          TtsDuckingStrategy.androidNavigation);
    });

    test('iOS → playback duckOthers', () {
      expect(ttsDuckingStrategyFor(isAndroid: false, isIOS: true),
          TtsDuckingStrategy.iosDuck);
    });

    test('any other platform → no native ducking path', () {
      expect(ttsDuckingStrategyFor(isAndroid: false, isIOS: false),
          TtsDuckingStrategy.none);
    });
  });
}
