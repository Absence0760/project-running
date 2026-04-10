import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DistanceUnit { km, mi }

enum ActivityType {
  run,
  walk,
  cycle,
  hike;

  String get label {
    switch (this) {
      case ActivityType.run:
        return 'Run';
      case ActivityType.walk:
        return 'Walk';
      case ActivityType.cycle:
        return 'Cycle';
      case ActivityType.hike:
        return 'Hike';
    }
  }

  IconData get icon {
    switch (this) {
      case ActivityType.run:
        return Icons.directions_run;
      case ActivityType.walk:
        return Icons.directions_walk;
      case ActivityType.cycle:
        return Icons.directions_bike;
      case ActivityType.hike:
        return Icons.terrain;
    }
  }

  static ActivityType fromName(String? name) {
    return ActivityType.values.firstWhere(
      (a) => a.name == name,
      orElse: () => ActivityType.run,
    );
  }
}

/// App-wide user preferences (units, audio cues, etc.).
class Preferences extends ChangeNotifier {
  static const _kUseMiles = 'use_miles';
  static const _kAudioCues = 'audio_cues';
  static const _kAutoPause = 'auto_pause';
  static const _kOnboarded = 'onboarded';
  static const _kWeeklyGoalKm = 'weekly_goal_km';
  static const _kTargetPaceSecPerKm = 'target_pace_sec_per_km';

  late SharedPreferences _prefs;
  bool _useMiles = false;
  bool _audioCues = true;
  bool _autoPause = true;
  bool _onboarded = false;
  double _weeklyGoalKm = 0;
  int _targetPaceSecPerKm = 0;

  DistanceUnit get unit => _useMiles ? DistanceUnit.mi : DistanceUnit.km;
  bool get useMiles => _useMiles;
  bool get audioCues => _audioCues;
  bool get autoPause => _autoPause;
  bool get onboarded => _onboarded;

  /// Weekly distance goal stored in kilometres (0 means not set).
  double get weeklyGoalKm => _weeklyGoalKm;

  /// Target pace in seconds per km (0 means no target). Audio cue triggers
  /// when current pace is more than 30s off in either direction.
  int get targetPaceSecPerKm => _targetPaceSecPerKm;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _useMiles = _prefs.getBool(_kUseMiles) ?? false;
    _audioCues = _prefs.getBool(_kAudioCues) ?? true;
    _autoPause = _prefs.getBool(_kAutoPause) ?? true;
    _onboarded = _prefs.getBool(_kOnboarded) ?? false;
    _weeklyGoalKm = _prefs.getDouble(_kWeeklyGoalKm) ?? 0;
    _targetPaceSecPerKm = _prefs.getInt(_kTargetPaceSecPerKm) ?? 0;
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

  Future<void> setOnboarded(bool v) async {
    _onboarded = v;
    await _prefs.setBool(_kOnboarded, v);
    notifyListeners();
  }

  Future<void> setWeeklyGoalKm(double v) async {
    _weeklyGoalKm = v;
    await _prefs.setDouble(_kWeeklyGoalKm, v);
    notifyListeners();
  }

  Future<void> setTargetPaceSecPerKm(int v) async {
    _targetPaceSecPerKm = v;
    await _prefs.setInt(_kTargetPaceSecPerKm, v);
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
