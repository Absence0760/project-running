import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:run_recorder/run_recorder.dart' show
    PaceDriftEvent,
    StepProgressKind,
    WorkoutStep,
    WorkoutStepKind;

import 'preferences.dart';

/// Speaks running stats out loud (km splits, etc.) using text-to-speech.
/// Format a speed string for TTS.
///
/// Returns the empty string when [secondsPerKm] is null or non-positive
/// — the caller appends this to a split announcement, so the empty
/// string degrades the cue to just the distance.
String formatSpeedUtterance(double? secondsPerKm, DistanceUnit unit) {
  if (secondsPerKm == null || secondsPerKm <= 0) return '';
  final kmh = 3600 / secondsPerKm;
  if (unit == DistanceUnit.mi) {
    final mph = kmh / 1.609344;
    return 'Speed, ${mph.toStringAsFixed(1)} miles per hour';
  }
  return 'Speed, ${kmh.toStringAsFixed(1)} kilometres per hour';
}

/// Format a pace string for TTS. Mirror of [formatSpeedUtterance] —
/// empty-string on null or non-positive input.
String formatPaceUtterance(double? secondsPerKm, DistanceUnit unit) {
  if (secondsPerKm == null || secondsPerKm <= 0) return '';
  const metresPerMile = 1609.344;
  final secondsPerUnit = unit == DistanceUnit.mi
      ? secondsPerKm * (metresPerMile / 1000)
      : secondsPerKm;
  final m = secondsPerUnit ~/ 60;
  final s = (secondsPerUnit % 60).toInt();
  final unitWord = unit == DistanceUnit.mi ? 'per mile' : 'per kilometre';
  return 'Pace, $m minutes $s seconds $unitWord';
}

/// Spoken distance: km/metres for metric, miles/yards for imperial.
/// Round km/mile values drop the decimal ("5 kilometres" not "5.0
/// kilometres", "1 mile" not "1.0 miles"). Imperial sub-mile values
/// render in yards (matches how runners read race distances on
/// imperial signage). Mirror of the visual `UnitFormat.distance` —
/// the spoken form replaces "km" / "mi" / "m" / "yd" with the
/// word-form a TTS engine can pronounce naturally.
String formatSpokenDistance(double metres, DistanceUnit unit) {
  if (unit == DistanceUnit.mi) {
    const metresPerMile = 1609.344;
    final miles = metres / metresPerMile;
    if (miles >= 1) {
      if (miles == miles.roundToDouble()) {
        final n = miles.round();
        return '$n ${n == 1 ? 'mile' : 'miles'}';
      }
      return '${miles.toStringAsFixed(1)} miles';
    }
    // Sub-mile → yards. 1 metre = 1.09361 yards.
    final yards = (metres * 1.09361).round();
    return '$yards yards';
  }
  if (metres >= 1000) {
    final km = metres / 1000;
    if (km == km.roundToDouble()) return '${km.round()} kilometres';
    return '${km.toStringAsFixed(1)} kilometres';
  }
  return '${metres.round()} metres';
}

/// Compose the workout-step intro line ("Warmup", "Rep 3 of 5", etc.)
/// followed by spoken distance + pace. Pure — used by the live audio
/// cues during a structured workout. The pace and distance honour
/// the user's unit pref so a mi-mode runner hears "Warmup. 1 mile
/// at 8 minutes per mile" instead of the km form.
String _spokenDuration(int sec) {
  final m = sec ~/ 60;
  final s = sec % 60;
  if (m == 0) return '$s seconds';
  final mPart = m == 1 ? '1 minute' : '$m minutes';
  return s == 0 ? mPart : '$mPart $s seconds';
}

String formatWorkoutStepUtterance(WorkoutStep step, DistanceUnit unit) {
  const metresPerMile = 1609.344;
  final paceSecPerUnit = unit == DistanceUnit.mi
      ? (step.targetPaceSecPerKm * (metresPerMile / 1000)).round()
      : step.targetPaceSecPerKm;
  final paceM = paceSecPerUnit ~/ 60;
  final paceS = paceSecPerUnit % 60;
  final unitTail = unit == DistanceUnit.mi ? 'per mile' : 'per kilometre';
  final paceTail = paceS == 0
      ? '$paceM minutes $unitTail'
      : '$paceM minutes $paceS seconds $unitTail';
  final dist = formatSpokenDistance(step.targetDistanceMetres, unit);
  // A duration-based work rep is a walk-run "Run" interval; a distance-based
  // one is an interval "Rep" (persona #22).
  final durationBased = step.isDurationBased;
  final intro = switch (step.kind) {
    WorkoutStepKind.warmup => 'Warmup',
    WorkoutStepKind.rep => step.repIndex != null && step.repTotal != null
        ? '${durationBased ? 'Run' : 'Rep'} ${step.repIndex} of ${step.repTotal}'
        : (durationBased ? 'Run' : 'Rep'),
    WorkoutStepKind.recovery => 'Recovery',
    WorkoutStepKind.walk => step.repIndex != null && step.repTotal != null
        ? 'Walk ${step.repIndex} of ${step.repTotal}'
        : 'Walk',
    WorkoutStepKind.steady => 'Steady',
    WorkoutStepKind.cooldown => 'Cooldown',
  };
  // Time-based steps (walk-run intervals, timed warmup/cooldown) announce
  // their duration; distance-based steps announce distance + pace.
  if (durationBased) {
    return '$intro. ${_spokenDuration(step.targetDurationSec!)}.';
  }
  return '$intro. $dist at $paceTail.';
}

/// Which audio-focus ducking strategy a platform gets for TTS cues.
/// Android requests navigation-guidance focus (transient-may-duck);
/// iOS uses the playback category with duckOthers; every other platform
/// gets none (no native ducking path). Persona android + samsung #12.
enum TtsDuckingStrategy { androidNavigation, iosDuck, none }

TtsDuckingStrategy ttsDuckingStrategyFor({
  required bool isAndroid,
  required bool isIOS,
}) {
  if (isAndroid) return TtsDuckingStrategy.androidNavigation;
  if (isIOS) return TtsDuckingStrategy.iosDuck;
  return TtsDuckingStrategy.none;
}

class AudioCues {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    // Latch _initialized BEFORE the platform calls so a partial
    // failure (e.g. setLanguage rejects on a fresh install where the
    // TTS engine hasn't downloaded en-US data yet) doesn't trap every
    // future announceX in a re-init loop. The plugin keeps whatever
    // settings landed; subsequent announceX may speak in the default
    // voice / rate / volume, which is preferable to silent retries.
    _initialized = true;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      // Request transient ducking so a cue lowers the runner's music /
      // podcast instead of talking over it (Android) or hard-pausing it
      // (iOS). Persona-hunt android + samsung #12. Each platform call is
      // best-effort: a failure here must not stop the cue from speaking,
      // so it stays inside the same L4 try/catch as the voice settings.
      switch (ttsDuckingStrategyFor(
        isAndroid: Platform.isAndroid,
        isIOS: Platform.isIOS,
      )) {
        case TtsDuckingStrategy.androidNavigation:
          // USAGE_ASSISTANCE_NAVIGATION_GUIDANCE → AUDIOFOCUS_GAIN_
          // TRANSIENT_MAY_DUCK, the nav-app ducking behaviour.
          await _tts.setAudioAttributesForNavigation();
        case TtsDuckingStrategy.iosDuck:
          await _tts.setIosAudioCategory(
            IosTextToSpeechAudioCategory.playback,
            [
              IosTextToSpeechAudioCategoryOptions.mixWithOthers,
              IosTextToSpeechAudioCategoryOptions.duckOthers,
            ],
            IosTextToSpeechAudioMode.voicePrompt,
          );
        case TtsDuckingStrategy.none:
          break;
      }
    } catch (e) {
      debugPrint('audio_cues._init partial failure: $e');
    }
  }

  /// Announce a split, e.g. "1 kilometre, pace 5 minutes 30 seconds".
  ///
  /// If [useSpeed] is true, announces speed in km/h or mph instead of pace.
  /// [tickIntervalMetres] lets the cue describe non-1km intervals (e.g. 5km
  /// for cycling): "5 kilometres" instead of "1 kilometre".
  Future<void> announceSplit({
    required int distanceTicks,
    required double? paceSecondsPerKm,
    required DistanceUnit unit,
    bool useSpeed = false,
    double tickIntervalMetres = 1000,
  }) async {
    await _init();
    final totalUnits = (distanceTicks * tickIntervalMetres / 1000).round();
    final unitWord = unit == DistanceUnit.mi
        ? (totalUnits == 1 ? 'mile' : 'miles')
        : (totalUnits == 1 ? 'kilometre' : 'kilometres');
    final tail = useSpeed
        ? _formatSpeed(paceSecondsPerKm, unit)
        : _formatPace(paceSecondsPerKm, unit);
    await _tts.speak('$totalUnits $unitWord. $tail');
  }

  String _formatSpeed(double? secondsPerKm, DistanceUnit unit) =>
      formatSpeedUtterance(secondsPerKm, unit);

  /// Announce that the run started.
  Future<void> announceStart() async {
    await _init();
    await _tts.speak('Run started');
  }

  /// Announce that the run finished, with summary.
  Future<void> announceFinish({
    required double distanceMetres,
    required Duration elapsed,
    required DistanceUnit unit,
  }) async {
    await _init();
    final distance = UnitFormat.distance(distanceMetres, unit);
    final mins = elapsed.inMinutes;
    await _tts.speak('Run complete. $distance in $mins minutes.');
  }

  /// Warn that the runner has drifted off the selected route.
  Future<void> announceOffRoute() async {
    await _init();
    await _tts.speak('Off route');
  }

  /// Tell the runner they're outside the target pace window.
  Future<void> announcePaceAlert({required bool tooSlow}) async {
    await _init();
    await _tts.speak(tooSlow ? 'Pick up the pace' : 'Slow down');
  }

  /// Announce a structured-workout step transition. Reuses the same
  /// TTS engine the splits cues use; failures are swallowed by the
  /// caller's try/catch (layered-resilience contract). [unit] is the
  /// user's distance preference so the spoken distance + pace match
  /// what they see on screen ("Warmup. 1 mile at 8 minutes per mile"
  /// vs "Warmup. 1.6 kilometres at 5 minutes per kilometre").
  Future<void> announceWorkoutStepTransition(
    WorkoutStep step,
    DistanceUnit unit,
  ) async {
    await _init();
    await _tts.speak(_workoutStepUtterance(step, unit));
  }

  /// In-step progress cue ("halfway" / "fifty metres to go").
  Future<void> announceWorkoutStepProgress(
      WorkoutStep step, StepProgressKind kind) async {
    await _init();
    final phrase = switch (kind) {
      StepProgressKind.halfway => 'Halfway through this rep',
      StepProgressKind.lastFiftyMetres => 'Fifty metres to go',
    };
    await _tts.speak(phrase);
  }

  /// Pace-drift nudge when the runner has been more than the tolerance
  /// off pace for ~45 s. Verb is signed.
  Future<void> announceWorkoutPaceDrift(PaceDriftEvent e) async {
    await _init();
    final verb = e.ahead ? 'Ease up' : 'Pick it up';
    final delta = e.deltaSecPerKm;
    final dir = e.ahead ? 'ahead' : 'behind';
    await _tts.speak('$verb — $delta seconds $dir pace.');
  }

  /// Final cue when the last step's auto-advance fires.
  Future<void> announceWorkoutComplete() async {
    await _init();
    await _tts.speak('Workout complete. Nice work.');
  }

  /// Speak an arbitrary guided-run cue. The TTS engine handles
  /// interruption (a new speak() call cancels the previous utterance)
  /// so back-to-back cues at the same second cleanly chain.
  Future<void> speakGuidedCue(String text) async {
    await _init();
    await _tts.speak(text);
  }

  String _workoutStepUtterance(WorkoutStep step, DistanceUnit unit) =>
      formatWorkoutStepUtterance(step, unit);

  Future<void> stop() async {
    await _tts.stop();
  }

  String _formatPace(double? secondsPerKm, DistanceUnit unit) =>
      formatPaceUtterance(secondsPerKm, unit);
}
