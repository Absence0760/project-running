import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DistanceUnit { km, mi }

/// App-wide user preferences (units, audio cues, etc.).
class Preferences extends ChangeNotifier {
  static const _kUseMiles = 'use_miles';
  static const _kAudioCues = 'audio_cues';
  static const _kAutoPause = 'auto_pause';

  late SharedPreferences _prefs;
  bool _useMiles = false;
  bool _audioCues = true;
  bool _autoPause = true;

  DistanceUnit get unit => _useMiles ? DistanceUnit.mi : DistanceUnit.km;
  bool get useMiles => _useMiles;
  bool get audioCues => _audioCues;
  bool get autoPause => _autoPause;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _useMiles = _prefs.getBool(_kUseMiles) ?? false;
    _audioCues = _prefs.getBool(_kAudioCues) ?? true;
    _autoPause = _prefs.getBool(_kAutoPause) ?? true;
  }

  Future<void> setUseMiles(bool v) async {
    _useMiles = v;
    await _prefs.setBool(_kUseMiles, v);
    notifyListeners();
  }

  Future<void> setAudioCues(bool v) async {
    _audioCues = v;
    await _prefs.setBool(_kAudioCues, v);
    notifyListeners();
  }

  Future<void> setAutoPause(bool v) async {
    _autoPause = v;
    await _prefs.setBool(_kAutoPause, v);
    notifyListeners();
  }
}

/// Distance/pace formatting helpers that respect the user's unit preference.
class UnitFormat {
  static const _metresPerMile = 1609.344;

  /// Format distance: "5.23 km" or "3.25 mi".
  static String distance(double metres, DistanceUnit unit) {
    if (unit == DistanceUnit.mi) {
      return '${(metres / _metresPerMile).toStringAsFixed(2)} mi';
    }
    return '${(metres / 1000).toStringAsFixed(2)} km';
  }

  /// Format distance value only (no unit suffix).
  static String distanceValue(double metres, DistanceUnit unit) {
    if (unit == DistanceUnit.mi) {
      return (metres / _metresPerMile).toStringAsFixed(2);
    }
    return (metres / 1000).toStringAsFixed(2);
  }

  /// Distance unit label.
  static String distanceLabel(DistanceUnit unit) =>
      unit == DistanceUnit.mi ? 'mi' : 'km';

  /// Format pace: "5:30" (per km/mi based on unit).
  static String pace(double? secondsPerKm, DistanceUnit unit) {
    if (secondsPerKm == null || secondsPerKm <= 0) return '--:--';
    final secondsPerUnit = unit == DistanceUnit.mi
        ? secondsPerKm * (_metresPerMile / 1000)
        : secondsPerKm;
    final m = secondsPerUnit ~/ 60;
    final s = (secondsPerUnit % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Pace unit label e.g. "/km" or "/mi".
  static String paceLabel(DistanceUnit unit) =>
      unit == DistanceUnit.mi ? '/mi' : '/km';

  /// How many distance "ticks" (km or mi) the runner has hit so far.
  static int distanceTicks(double metres, DistanceUnit unit) {
    if (unit == DistanceUnit.mi) {
      return (metres / _metresPerMile).floor();
    }
    return (metres / 1000).floor();
  }
}
