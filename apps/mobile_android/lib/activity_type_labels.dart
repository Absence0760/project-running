import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import 'l10n/gen/app_localizations.dart';

/// The one `runs.activity_type` vocabulary on mobile — the Dart mirror of
/// web's `runs/activity_type.svelte.ts#activityTypeLabel`.
///
/// Lives outside `ActivityType` so `preferences.dart` stays free of the
/// generated localisation class: everything else on the enum (stride, GPS
/// filter, split interval, calorie factor) is physics and needs no context,
/// and the label was the one member that did.
///
/// `hike` reads "Trail run" — a runner picking it means an off-road run, and a
/// user surfaced "Hike" as the reason trail runners did not see themselves in
/// the picker. Web says the same word for the same value; the enum name and the
/// database value stay `hike` (the CHECK constraint, the Strava / Health
/// Connect importers, and every stored row key on it).
String activityTypeLabel(AppLocalizations l10n, ActivityType type) {
  switch (type) {
    case ActivityType.run:
      return l10n.activityTypeRun;
    case ActivityType.walk:
      return l10n.activityTypeWalk;
    case ActivityType.cycle:
      return l10n.activityTypeCycle;
    case ActivityType.hike:
      return l10n.activityTypeHike;
    case ActivityType.stroller:
      return l10n.activityTypeStroller;
  }
}

/// Label for a raw stored value. An absent / unrecognised value resolves as
/// `run`, matching the column default and `ActivityType.fromName`.
String activityTypeLabelFor(AppLocalizations l10n, String? raw) =>
    activityTypeLabel(l10n, ActivityType.fromName(raw));

/// The Material icon per value.
///
/// An extension rather than a member because the enum lives in `core_models`,
/// which has no Flutter dependency — the same reason the label above is a
/// function rather than a getter. Both halves of "how this value is presented"
/// therefore sit in this one file.
extension ActivityTypeIcon on ActivityType {
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
      case ActivityType.stroller:
        return Icons.child_friendly;
    }
  }
}
