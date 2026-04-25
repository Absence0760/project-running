import 'package:flutter_tts/flutter_tts.dart';
import 'package:run_recorder/run_recorder.dart' show
    PaceDriftEvent,
    StepProgressKind,
    WorkoutStep,
    WorkoutStepKind;

import 'preferences.dart';

/// Speaks running stats out loud (km splits, etc.) using text-to-speech.
class AudioCues {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    _initialized = true;
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

  String _formatSpeed(double? secondsPerKm, DistanceUnit unit) {
    if (secondsPerKm == null || secondsPerKm <= 0) return '';
    final kmh = 3600 / secondsPerKm;
    if (unit == DistanceUnit.mi) {
      final mph = kmh / 1.609344;
      return 'Speed, ${mph.toStringAsFixed(1)} miles per hour';
    }
    return 'Speed, ${kmh.toStringAsFixed(1)} kilometres per hour';
  }

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
  /// caller's try/catch (layered-resilience contract).
  Future<void> announceWorkoutStepTransition(WorkoutStep step) async {
    await _init();
    await _tts.speak(_workoutStepUtterance(step));
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

  String _workoutStepUtterance(WorkoutStep step) {
    final paceM = step.targetPaceSecPerKm ~/ 60;
    final paceS = step.targetPaceSecPerKm % 60;
    final paceTail = paceS == 0
        ? '$paceM minutes per kilometre'
        : '$paceM minutes $paceS seconds per kilometre';
    final dist = _spokenDistance(step.targetDistanceMetres);
    final intro = switch (step.kind) {
      WorkoutStepKind.warmup => 'Warmup',
      WorkoutStepKind.rep => step.repIndex != null && step.repTotal != null
          ? 'Rep ${step.repIndex} of ${step.repTotal}'
          : 'Rep',
      WorkoutStepKind.recovery => 'Recovery',
      WorkoutStepKind.steady => 'Steady',
      WorkoutStepKind.cooldown => 'Cooldown',
    };
    return '$intro. $dist at $paceTail.';
  }

  String _spokenDistance(double metres) {
    if (metres >= 1000) {
      final km = metres / 1000;
      if (km == km.roundToDouble()) return '${km.round()} kilometres';
      return '${km.toStringAsFixed(1)} kilometres';
    }
    return '${metres.round()} metres';
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  String _formatPace(double? secondsPerKm, DistanceUnit unit) {
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
}
