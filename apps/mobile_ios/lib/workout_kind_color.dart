import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show ChartPalette;

import 'training.dart';

// The one home for the workout-kind marker hue, read by `plan_calendar` and
// `current_week_strip`. Mirrors apps/web/src/lib/training/workout_kind_color.ts;
// the VALUES live once per brightness in ui_kit's ChartPalette.kinds and their
// CSS twins are asserted from the web suite by scale name.
//
// The colour is a MARK — the 3 px cell edge — and never type. Nine kinds share
// six marks, so the hue alone cannot name a kind even to a runner with full
// colour vision; the localized kind word beside the mark is what identifies it.

/// Index into [ChartPalette.kinds] for [k]. The six groups are the ladder order
/// the scale is listed in, so a greyscale reader gets a stable ordering.
int workoutKindMarkIndex(WorkoutKind k) => switch (k) {
      WorkoutKind.easy || WorkoutKind.recovery => 0,
      WorkoutKind.long || WorkoutKind.race => 1,
      WorkoutKind.tempo => 2,
      WorkoutKind.marathonPace => 3,
      WorkoutKind.interval || WorkoutKind.walkRun => 4,
      WorkoutKind.rest => 5,
    };

Color workoutKindMarkColor(ThemeData theme, WorkoutKind k) =>
    ChartPalette.ofTheme(theme).kinds[workoutKindMarkIndex(k)];
