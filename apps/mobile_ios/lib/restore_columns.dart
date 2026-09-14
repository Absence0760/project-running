// Which keys of an archived row this build's schema can actually accept.
//
// A restore reads rows out of a ZIP the user supplied, so the column set is
// whatever build wrote the archive — and PostgREST refuses a payload naming a
// column the table does not have (PGRST204) for the WHOLE row. An archive
// written before `runs.kind` was dropped (migration `20261206_001`) therefore
// failed every run it carried, one 400 at a time, after each run's track blob
// had already been uploaded to Storage: a restore that imports nothing and
// leaves an orphaned object per run behind. Dropping the unknown key instead
// lands the rest of the row, which is the same call the profile's own
// `subscription_tier` / `subscription_at` / `parkrun_number` removes make.
//
// The three sets are stated here rather than derived at runtime because
// stating them is what makes a column a migration ADDS fail:
// `restore_columns_test.dart` reads the `col*` constants out of the generated
// `db_rows.dart` and demands set EQUALITY, so a new column has to be admitted
// here deliberately instead of being silently discarded off every archive
// that carries it. That is the same both-directions check the web side gets
// from `satisfies Record<keyof Insertable<T>, true>`, which Dart has no
// structural analogue for.
//
// The moderation and derived-cache columns stay in the sets on purpose. They
// are frozen server-side by `20270704000003`, which REVERTS a non-service-role
// write rather than raising, so listing them costs nothing and re-spelling the
// freeze list here would be a second copy of it to drift.
const Set<String> kRunRestoreColumns = <String>{
  'activity_type',
  'concluded_at',
  'created_at',
  'distance_m',
  'duration_s',
  'elevation_gain_m',
  'event_id',
  'external_id',
  'fastest_10k_s',
  'fastest_5k_s',
  'fastest_half_marathon_s',
  'fastest_marathon_s',
  'hr_series_url',
  'id',
  'is_dnf',
  'is_public',
  'metadata',
  'race_listing_id',
  'route_id',
  'source',
  'started_at',
  'track_url',
  'updated_at',
  'user_id',
};

const Set<String> kRouteRestoreColumns = <String>{
  'club_id',
  'created_at',
  'description',
  'distance_m',
  'elevation_m',
  'featured_at',
  'geom',
  'geom_public',
  'id',
  'is_featured',
  'is_public',
  'is_starred',
  'name',
  'run_count',
  'shadow_hidden',
  'slug',
  'start_point',
  'surface',
  'tags',
  'updated_at',
  'user_id',
  'waypoints',
};

const Set<String> kProfileRestoreColumns = <String>{
  'age_confirmed_at',
  'ai_disclosure_version',
  'avatar_url',
  'billing_issue_at',
  'coach_consent_at',
  'created_at',
  'date_of_birth',
  'display_name',
  'gender',
  'handle',
  'health_data_consent_at',
  'height_cm',
  'id',
  'onboarded_at',
  'parkrun_number',
  'preferred_unit',
  'shadow_hidden',
  'subscription_at',
  'subscription_tier',
  'terms_accepted_at',
  'tier_updated_event_ts',
};

/// The row as this build's schema can accept it, plus the names that were not
/// columns of it.
class KeptColumns {
  const KeptColumns(this.row, this.dropped);

  final Map<String, dynamic> row;
  final List<String> dropped;
}

/// Filter [row] down to [columns], reporting what was left behind.
///
/// A `Set.contains` is an exact membership test on a decoded JSON map, so the
/// prototype-chain hazard the web half has to spell `Object.hasOwn` for —
/// `constructor` / `toString` / `__proto__` all answering true through `in` —
/// does not arise here.
KeptColumns keepKnownColumns(
  Map<String, dynamic> row,
  Set<String> columns,
) {
  final kept = <String, dynamic>{};
  final dropped = <String>[];
  for (final key in row.keys) {
    if (columns.contains(key)) {
      kept[key] = row[key];
    } else {
      dropped.add(key);
    }
  }
  return KeptColumns(kept, dropped);
}
