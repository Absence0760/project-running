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

  /// Cycling shows speed (km/h, mph) instead of pace (min/km, min/mi).
  bool get usesSpeed => this == ActivityType.cycle;

  /// Calories burned per kilogram of body weight per kilometre travelled.
  /// Approximate metabolic equivalents.
  double get kcalPerKgPerKm {
    switch (this) {
      case ActivityType.run:
        return 1.0;
      case ActivityType.walk:
        return 0.5;
      case ActivityType.cycle:
        return 0.4;
      case ActivityType.hike:
        return 0.7;
    }
  }

  /// Distance interval (metres) for split notifications. Larger for cycling
  /// so a 30 km ride doesn't fire 30 announcements.
  double get splitIntervalMetres {
    switch (this) {
      case ActivityType.cycle:
        return 5000;
      default:
        return 1000;
    }
  }

  /// GPS distance filter in metres — how far the runner must move before
  /// the next position update is fired. Larger for cycling.
  int get gpsDistanceFilter {
    switch (this) {
      case ActivityType.cycle:
        return 5;
      default:
        return 3;
    }
  }

  /// Minimum movement (metres) between GPS samples that counts as real
  /// motion. Anything below this is treated as GPS jitter.
  double get minMovementMetres {
    switch (this) {
      case ActivityType.cycle:
        return 4;
      default:
        return 2;
    }
  }

  /// Maximum plausible speed (metres/second). Position deltas implying
  /// anything faster than this are discarded as GPS corruption — the line
  /// shouldn't teleport across town because of one bad fix.
  ///
  /// Values are deliberately generous (faster than realistic peak) to avoid
  /// dropping genuine fast segments, while still catching outright glitches.
  double get maxSpeedMps {
    switch (this) {
      case ActivityType.run:
        return 10; // ~2:45/km, faster than world records — pure corruption above this
      case ActivityType.walk:
        return 5; // brisk walk ~1.7 m/s; 5 gives headroom
      case ActivityType.cycle:
        return 25; // 90 km/h — higher than any sane cyclist
      case ActivityType.hike:
        return 6; // slow running overlap for scrambling / downhill
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
  static const _kOnboarded = 'onboarded';
  static const _kWeeklyGoalKm = 'weekly_goal_km';
  static const _kTargetPaceSecPerKm = 'target_pace_sec_per_km';

  late SharedPreferences _prefs;
  bool _useMiles = false;
  bool _audioCues = true;
  bool _onboarded = false;
  double _weeklyGoalKm = 0;
  int _targetPaceSecPerKm = 0;

  DistanceUnit get unit => _useMiles ? DistanceUnit.mi : DistanceUnit.km;
  bool get useMiles => _useMiles;
  bool get audioCues => _audioCues;
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

  /// Number of activity-aware split ticks hit so far (e.g. 5km splits for cycle).
  static int activityTicks(double metres, double intervalMetres) {
    return (metres / intervalMetres).floor();
  }

  /// Format speed: "12.5 km/h" or "7.8 mph".
  static String speed(double? secondsPerKm, DistanceUnit unit) {
    if (secondsPerKm == null || secondsPerKm <= 0) return '--';
    final kmh = 3600 / secondsPerKm;
    if (unit == DistanceUnit.mi) {
      final mph = kmh / 1.609344;
      return mph.toStringAsFixed(1);
    }
    return kmh.toStringAsFixed(1);
  }

  /// Speed unit label e.g. "km/h" or "mph".
  static String speedLabel(DistanceUnit unit) =>
      unit == DistanceUnit.mi ? 'mph' : 'km/h';
}
