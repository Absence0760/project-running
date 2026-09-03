/// The `user_profiles.preferred_unit` value domain.
///
/// Authoritative source is the SQL CHECK constraint
/// `user_profiles_preferred_unit_check` (migration `20260505_001`); this enum
/// is one of the rails `apps/web/scripts/check_constraint_unions.mjs` reads
/// against it, so the vocabulary and the CHECK move together.
///
/// A LEAF, for the reason `activity_type.dart` is one (decisions § 1013): it
/// used to live in `preferences.dart`, which also holds a `SharedPreferences`
/// cache and imports `package:flutter/material.dart`, so nothing outside the
/// Flutter app could name the unit a value is expressed in. It is also what
/// stranded `ActivityType.splitIntervalMetresFor` behind as an extension when
/// the activity vocabulary moved — the method takes a unit, and a leaf that
/// imported `preferences.dart` to reach one would have inverted the dependency
/// the move existed to remove.
library;

enum DistanceUnit { km, mi }

/// Metres in one statute mile. The single definition — `UnitFormat`, the
/// split-interval defaults and the course-marker panel all read it, and the
/// panel used to keep a second copy of the same number.
///
/// It travels with the enum rather than staying in `preferences.dart`: it is
/// what [DistanceUnit.mi] MEANS, and a leaf that can name the unit but not
/// convert it is half a vocabulary.
const double kMetresPerMile = 1609.344;
