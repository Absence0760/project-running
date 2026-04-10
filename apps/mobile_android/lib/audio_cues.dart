import 'package:flutter_tts/flutter_tts.dart';

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
  Future<void> announceSplit({
    required int distanceTicks,
    required double? paceSecondsPerKm,
    required DistanceUnit unit,
  }) async {
    await _init();
    final unitWord = unit == DistanceUnit.mi
        ? (distanceTicks == 1 ? 'mile' : 'miles')
        : (distanceTicks == 1 ? 'kilometre' : 'kilometres');
    final paceText = _formatPace(paceSecondsPerKm, unit);
    await _tts.speak('$distanceTicks $unitWord. $paceText');
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
