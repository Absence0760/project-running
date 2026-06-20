import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:run_recorder/run_recorder.dart' show
    PaceDriftEvent,
    StepProgressKind,
    WorkoutStep,
    WorkoutStepKind;

import 'l10n/gen/app_localizations.dart';
import 'l10n/locale_support.dart';
import 'turn_cues.dart' show TurnDirection;
import 'preferences.dart';

/// Speaks running stats out loud (km splits, etc.) using text-to-speech.
///
/// Phrases are read from the gen-l10n catalogue for the active locale — TTS
/// is context-free (no `BuildContext`), so it resolves the catalogue via
/// [lookupAppLocalizations] keyed by [activeLocaleTag]. The TTS engine
/// language follows the same active locale through [ttsLanguageTag].

/// Resolve the gen-l10n catalogue for a BCP-47-ish [localeTag], falling back
/// to the default (English) locale for an unknown/unparseable tag.
AppLocalizations ttsL10n(String localeTag) =>
    lookupAppLocalizations(localeFromTag(localeTag) ?? defaultLocale);

/// Map an app-locale tag (`en`, `de`, `pt-BR`) to the BCP-47 language tag the
/// platform TTS engine expects (`en-US`, `de-DE`, `pt-BR`). Unknown tags fall
/// back to `en-US` so a cue always speaks in *some* voice rather than failing.
String ttsLanguageTag(String localeTag) {
  final base = localeTag.toLowerCase().split(RegExp('[-_]'))[0];
  switch (localeTag.toLowerCase()) {
    case 'pt-br':
    case 'pt_br':
      return 'pt-BR';
  }
  switch (base) {
    case 'en':
      return 'en-US';
    case 'de':
      return 'de-DE';
    case 'fr':
      return 'fr-FR';
    case 'es':
      return 'es-ES';
    case 'ja':
      return 'ja-JP';
    case 'pt':
      return 'pt-BR';
    default:
      return 'en-US';
  }
}

/// Format a speed string for TTS.
///
/// Returns the empty string when [secondsPerKm] is null or non-positive
/// — the caller appends this to a split announcement, so the empty
/// string degrades the cue to just the distance.
String formatSpeedUtterance(double? secondsPerKm, DistanceUnit unit,
    [String? localeTag]) {
  if (secondsPerKm == null || secondsPerKm <= 0) return '';
  final l10n = ttsL10n(localeTag ?? activeLocaleTag);
  final kmh = 3600 / secondsPerKm;
  if (unit == DistanceUnit.mi) {
    final mph = kmh / 1.609344;
    return l10n.ttsSpeedMi(mph.toStringAsFixed(1));
  }
  return l10n.ttsSpeedKm(kmh.toStringAsFixed(1));
}

/// Format a pace string for TTS. Mirror of [formatSpeedUtterance] —
/// empty-string on null or non-positive input.
String formatPaceUtterance(double? secondsPerKm, DistanceUnit unit,
    [String? localeTag]) {
  if (secondsPerKm == null || secondsPerKm <= 0) return '';
  final l10n = ttsL10n(localeTag ?? activeLocaleTag);
  const metresPerMile = 1609.344;
  final secondsPerUnit = unit == DistanceUnit.mi
      ? secondsPerKm * (metresPerMile / 1000)
      : secondsPerKm;
  final m = secondsPerUnit ~/ 60;
  final s = (secondsPerUnit % 60).toInt();
  return unit == DistanceUnit.mi
      ? l10n.ttsPaceMi(m, s)
      : l10n.ttsPaceKm(m, s);
}

/// Spoken distance: km/metres for metric, miles/yards for imperial.
/// Round km/mile values drop the decimal ("5 kilometres" not "5.0
/// kilometres", "1 mile" not "1.0 miles"). Imperial sub-mile values
/// render in yards (matches how runners read race distances on
/// imperial signage). Mirror of the visual `UnitFormat.distance` —
/// the spoken form replaces "km" / "mi" / "m" / "yd" with the
/// word-form a TTS engine can pronounce naturally.
String formatSpokenDistance(double metres, DistanceUnit unit,
    [String? localeTag]) {
  final l10n = ttsL10n(localeTag ?? activeLocaleTag);
  if (unit == DistanceUnit.mi) {
    const metresPerMile = 1609.344;
    final miles = metres / metresPerMile;
    if (miles >= 1) {
      if (miles == miles.roundToDouble()) {
        final n = miles.round();
        return n == 1
            ? l10n.ttsDistanceMileSingular('$n')
            : l10n.ttsDistanceMiles('$n');
      }
      return l10n.ttsDistanceMiles(miles.toStringAsFixed(1));
    }
    // Sub-mile → yards. 1 metre = 1.09361 yards.
    final yards = (metres * 1.09361).round();
    return l10n.ttsDistanceYards(yards);
  }
  if (metres >= 1000) {
    final km = metres / 1000;
    if (km == km.roundToDouble()) return l10n.ttsDistanceKm('${km.round()}');
    return l10n.ttsDistanceKm(km.toStringAsFixed(1));
  }
  return l10n.ttsDistanceMetres(metres.round());
}

/// Compose the workout-step intro line ("Warmup", "Rep 3 of 5", etc.)
/// followed by spoken distance + pace. Pure — used by the live audio
/// cues during a structured workout. The pace and distance honour
/// the user's unit pref so a mi-mode runner hears "Warmup. 1 mile
/// at 8 minutes per mile" instead of the km form.
String _spokenDuration(int sec, AppLocalizations l10n) {
  final m = sec ~/ 60;
  final s = sec % 60;
  if (m == 0) return l10n.ttsDurationSeconds(s);
  final mPart = l10n.ttsDurationMinutes(m);
  return s == 0 ? mPart : l10n.ttsDurationMinutesSeconds(mPart, s);
}

String formatWorkoutStepUtterance(WorkoutStep step, DistanceUnit unit,
    [String? localeTag]) {
  final tag = localeTag ?? activeLocaleTag;
  final l10n = ttsL10n(tag);
  const metresPerMile = 1609.344;
  final paceSecPerUnit = unit == DistanceUnit.mi
      ? (step.targetPaceSecPerKm * (metresPerMile / 1000)).round()
      : step.targetPaceSecPerKm;
  final paceM = paceSecPerUnit ~/ 60;
  final paceS = paceSecPerUnit % 60;
  final paceTail = unit == DistanceUnit.mi
      ? (paceS == 0
          ? l10n.ttsStepPaceMiWhole(paceM)
          : l10n.ttsStepPaceMi(paceM, paceS))
      : (paceS == 0
          ? l10n.ttsStepPaceKmWhole(paceM)
          : l10n.ttsStepPaceKm(paceM, paceS));
  final dist = formatSpokenDistance(step.targetDistanceMetres, unit, tag);
  // A duration-based work rep is a walk-run "Run" interval; a distance-based
  // one is an interval "Rep" (persona #22).
  final durationBased = step.isDurationBased;
  final hasIdx = step.repIndex != null && step.repTotal != null;
  final intro = switch (step.kind) {
    WorkoutStepKind.warmup => l10n.ttsStepWarmup,
    WorkoutStepKind.rep => hasIdx
        ? (durationBased
            ? l10n.ttsStepRunOf(step.repIndex!, step.repTotal!)
            : l10n.ttsStepRepOf(step.repIndex!, step.repTotal!))
        : (durationBased ? l10n.ttsStepRun : l10n.ttsStepRep),
    WorkoutStepKind.recovery => l10n.ttsStepRecovery,
    WorkoutStepKind.walk => hasIdx
        ? l10n.ttsStepWalkOf(step.repIndex!, step.repTotal!)
        : l10n.ttsStepWalk,
    WorkoutStepKind.steady => l10n.ttsStepSteady,
    WorkoutStepKind.cooldown => l10n.ttsStepCooldown,
  };
  // Time-based steps (walk-run intervals, timed warmup/cooldown) announce
  // their duration; distance-based steps announce distance + pace.
  if (durationBased) {
    return l10n.ttsStepDuration(intro, _spokenDuration(step.targetDurationSec!, l10n));
  }
  return l10n.ttsStepDistancePace(intro, dist, paceTail);
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
  String? _appliedLanguageTag;

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
      await _applyLanguage();
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

  /// Re-apply the TTS engine language to match the active locale. Resolved
  /// per-announcement (cheap, robust against a mid-session locale change) and
  /// best-effort — a setLanguage failure must NOT stop the cue (L4). Skips the
  /// platform call when the language hasn't changed since the last apply.
  Future<void> _applyLanguage() async {
    final tag = ttsLanguageTag(activeLocaleTag);
    if (tag == _appliedLanguageTag) return;
    try {
      await _tts.setLanguage(tag);
      _appliedLanguageTag = tag;
    } catch (e) {
      debugPrint('audio_cues.setLanguage($tag) failed: $e');
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
    await _applyLanguage();
    final tag = activeLocaleTag;
    final l10n = ttsL10n(tag);
    final totalUnits = (distanceTicks * tickIntervalMetres / 1000).round();
    final unitWord = unit == DistanceUnit.mi
        ? (totalUnits == 1 ? l10n.ttsSplitUnitMile : l10n.ttsSplitUnitMiles)
        : (totalUnits == 1
            ? l10n.ttsSplitUnitKilometre
            : l10n.ttsSplitUnitKilometres);
    final tail = useSpeed
        ? formatSpeedUtterance(paceSecondsPerKm, unit, tag)
        : formatPaceUtterance(paceSecondsPerKm, unit, tag);
    await _tts.speak(l10n.ttsSplit('$totalUnits', unitWord, tail));
  }

  /// Announce that the run started.
  Future<void> announceStart() async {
    await _init();
    await _applyLanguage();
    await _tts.speak(ttsL10n(activeLocaleTag).ttsRunStarted);
  }

  /// Announce that the run finished, with summary.
  Future<void> announceFinish({
    required double distanceMetres,
    required Duration elapsed,
    required DistanceUnit unit,
  }) async {
    await _init();
    await _applyLanguage();
    final l10n = ttsL10n(activeLocaleTag);
    final distance = UnitFormat.distance(distanceMetres, unit);
    final mins = elapsed.inMinutes;
    await _tts.speak(l10n.ttsRunComplete(distance, mins));
  }

  /// Warn that the runner has drifted off the selected route.
  Future<void> announceOffRoute() async {
    await _init();
    await _applyLanguage();
    await _tts.speak(ttsL10n(activeLocaleTag).ttsOffRoute);
  }

  /// Speak a turn-by-turn cue for an upcoming bend on the followed route.
  /// [direction] is the geometric turn classification from `turn_cues.dart`;
  /// [distance] is a pre-formatted, unit-aware distance string (null = the
  /// turn is here now). Best-effort like every other cue — a TTS failure
  /// never disturbs the recording (L4, wrapped by the caller's `_ttsCue`).
  Future<void> announceTurn(
    TurnDirection direction, {
    String? distance,
  }) async {
    await _init();
    await _applyLanguage();
    final l10n = ttsL10n(activeLocaleTag);
    final String phrase;
    switch (direction) {
      case TurnDirection.left:
        phrase = distance != null
            ? l10n.ttsTurnLeftIn(distance)
            : l10n.ttsTurnLeftNow;
        break;
      case TurnDirection.right:
        phrase = distance != null
            ? l10n.ttsTurnRightIn(distance)
            : l10n.ttsTurnRightNow;
        break;
      case TurnDirection.slightLeft:
        phrase = l10n.ttsSlightLeft;
        break;
      case TurnDirection.slightRight:
        phrase = l10n.ttsSlightRight;
        break;
      case TurnDirection.uturn:
        phrase = l10n.ttsUturn;
        break;
      case TurnDirection.straight:
        return;
    }
    await _tts.speak(phrase);
  }

  /// Tell the runner they're outside the target pace window.
  Future<void> announcePaceAlert({required bool tooSlow}) async {
    await _init();
    await _applyLanguage();
    final l10n = ttsL10n(activeLocaleTag);
    await _tts.speak(tooSlow ? l10n.ttsPaceAlertFast : l10n.ttsPaceAlertSlow);
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
    await _applyLanguage();
    await _tts.speak(formatWorkoutStepUtterance(step, unit, activeLocaleTag));
  }

  /// In-step progress cue ("halfway" / "fifty metres to go").
  Future<void> announceWorkoutStepProgress(
      WorkoutStep step, StepProgressKind kind) async {
    await _init();
    await _applyLanguage();
    final l10n = ttsL10n(activeLocaleTag);
    final phrase = switch (kind) {
      StepProgressKind.halfway => l10n.ttsStepHalfway,
      StepProgressKind.lastFiftyMetres => l10n.ttsStepLastFifty,
    };
    await _tts.speak(phrase);
  }

  /// Pace-drift nudge when the runner has been more than the tolerance
  /// off pace for ~45 s. Verb is signed.
  Future<void> announceWorkoutPaceDrift(PaceDriftEvent e) async {
    await _init();
    await _applyLanguage();
    final l10n = ttsL10n(activeLocaleTag);
    await _tts.speak(e.ahead
        ? l10n.ttsPaceDriftAhead(e.deltaSecPerKm)
        : l10n.ttsPaceDriftBehind(e.deltaSecPerKm));
  }

  /// Final cue when the last step's auto-advance fires.
  Future<void> announceWorkoutComplete() async {
    await _init();
    await _applyLanguage();
    await _tts.speak(ttsL10n(activeLocaleTag).ttsWorkoutComplete);
  }

  /// Speak an arbitrary guided-run cue. The TTS engine handles
  /// interruption (a new speak() call cancels the previous utterance)
  /// so back-to-back cues at the same second cleanly chain.
  Future<void> speakGuidedCue(String text) async {
    await _init();
    await _applyLanguage();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
