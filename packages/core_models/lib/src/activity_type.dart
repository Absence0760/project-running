/// The `runs.activity_type` value domain.
///
/// Authoritative source is the SQL CHECK constraint `runs_activity_type_check`
/// (migration `20261207_001`); this enum is one of the rails
/// `apps/web/scripts/check_constraint_unions.mjs` reads against it, so the
/// vocabulary and the CHECK move together.
///
/// A LEAF, mirroring web's `apps/web/src/lib/runs/activity_type.ts`, and it
/// lives in `core_models` rather than in `preferences.dart` because a pure
/// parser must be able to reach the vocabulary. `csv_run_importer.dart` needed
/// it and had to import a file that also holds a `SharedPreferences` cache and
/// `package:flutter/material.dart` — retyping the five values instead would
/// have created a second unregistered rail against the CHECK, which is the
/// drift the constraint-union guard exists to prevent (decisions § 1013).
///
/// `core_models` has no Flutter dependency, so the `IconData get icon` getter
/// could not travel with it; it is an extension in
/// `apps/mobile_android/lib/activity_type_labels.dart`, beside the label the
/// enum deliberately does not carry either.

enum ActivityType {
  run,
  walk,
  cycle,
  hike,
  stroller;

  /// The user-facing name is NOT here: it needs an [AppLocalizations], and
  /// keeping it as a hardcoded getter printed five English words in all six
  /// non-English locales. Resolve it through
  /// `activity_type_labels.dart#activityTypeLabel`.

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
      case ActivityType.stroller:
        // Running while pushing a stroller — a touch above open running.
        return 1.1;
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

  /// Average stride / step length in metres. Used as a fallback distance
  /// estimate for indoor / treadmill runs where GPS never produces a fix —
  /// the pedometer still counts steps, so `steps × strideMetres` gives a
  /// rough distance that's better than the `0.00 km` we'd otherwise show.
  /// Values are average-adult estimates; individual stride varies with
  /// height, cadence, and fatigue. Cycling has no pedometer so its value
  /// is unused.
  double get strideMetres {
    switch (this) {
      case ActivityType.run:
        return 1.1; // ~2000 steps/km at a moderate pace
      case ActivityType.walk:
        return 0.73; // ~1370 steps/km
      case ActivityType.cycle:
        return 0.0; // pedometer not meaningful for cycling
      case ActivityType.hike:
        return 0.85; // shorter than running, longer than walking
      case ActivityType.stroller:
        return 1.1; // running stride
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
      case ActivityType.stroller:
        return 9; // running with a pram — a touch under open-run peak
    }
  }

  static ActivityType fromName(String? name) {
    return ActivityType.values.firstWhere(
      (a) => a.name == name,
      orElse: () => ActivityType.run,
    );
  }
}
