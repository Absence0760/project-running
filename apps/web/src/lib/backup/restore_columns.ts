// Which keys of an archived row this build's schema can actually accept.
//
// A restore reads rows out of a ZIP the user supplied, so the column set is
// whatever build wrote the archive — and PostgREST refuses a payload naming a
// column the table does not have (PGRST204) for the WHOLE row. An archive
// written before `runs.kind` was dropped (migration 20261206_001) therefore
// fails every run it carries, one 400 at a time, after each run's track blob
// has already been uploaded to Storage: a restore that imports nothing and
// leaves an orphaned object per run behind. Dropping the unknown key instead
// lands the rest of the row, which is the same call
// `stripServerManagedProfileFields` already makes for its three.
//
// Each record is `satisfies Record<keyof Insertable<T>, true>`, which checks
// both directions at once: a name the table has dropped fails as an excess
// property, and a column a migration ADDS fails as a missing one — so a new
// column has to be admitted here deliberately rather than being silently
// discarded off every archive that carries it.
//
// The moderation and derived-cache columns stay in the sets on purpose. They
// are frozen server-side by 20270704000003, which REVERTS a non-service-role
// write rather than raising, so listing them costs nothing and re-spelling the
// freeze list here would be a second copy of it to drift.

import type { Insertable } from '../core/database';
import type { JsonObject } from '../types';

export const RUN_RESTORE_COLUMNS = {
	activity_type: true,
	concluded_at: true,
	created_at: true,
	distance_m: true,
	duration_s: true,
	elevation_gain_m: true,
	event_id: true,
	external_id: true,
	fastest_10k_s: true,
	fastest_5k_s: true,
	fastest_half_marathon_s: true,
	fastest_marathon_s: true,
	hr_series_url: true,
	id: true,
	is_dnf: true,
	is_public: true,
	metadata: true,
	race_listing_id: true,
	route_id: true,
	source: true,
	started_at: true,
	track_url: true,
	updated_at: true,
	user_id: true,
} as const satisfies Record<keyof Insertable<'runs'>, true>;

export const ROUTE_RESTORE_COLUMNS = {
	club_id: true,
	created_at: true,
	description: true,
	distance_m: true,
	elevation_m: true,
	featured_at: true,
	geom: true,
	geom_public: true,
	id: true,
	is_featured: true,
	is_public: true,
	is_starred: true,
	name: true,
	run_count: true,
	shadow_hidden: true,
	slug: true,
	start_point: true,
	surface: true,
	tags: true,
	updated_at: true,
	user_id: true,
	waypoints: true,
} as const satisfies Record<keyof Insertable<'routes'>, true>;

export const PROFILE_RESTORE_COLUMNS = {
	age_confirmed_at: true,
	ai_disclosure_version: true,
	avatar_url: true,
	billing_issue_at: true,
	coach_consent_at: true,
	created_at: true,
	date_of_birth: true,
	display_name: true,
	gender: true,
	handle: true,
	health_data_consent_at: true,
	height_cm: true,
	id: true,
	onboarded_at: true,
	parkrun_number: true,
	preferred_unit: true,
	shadow_hidden: true,
	subscription_at: true,
	subscription_tier: true,
	terms_accepted_at: true,
	tier_updated_event_ts: true,
} as const satisfies Record<keyof Insertable<'user_profiles'>, true>;

/**
 * The row as this build's schema can accept it, plus the names that were not
 * columns of it.
 *
 * Membership is tested with `Object.hasOwn`, not `in`: the row is parsed from
 * a user-supplied JSON file, so `constructor` / `toString` / `__proto__` are
 * all keys an archive can carry and all of them answer true on the prototype
 * chain of any object. `in` would wave them through as columns.
 */
export function keepKnownColumns(
	row: JsonObject,
	columns: Readonly<Record<string, true>>,
): { row: JsonObject; dropped: string[] } {
	const kept: JsonObject = {};
	const dropped: string[] = [];
	for (const key of Object.keys(row)) {
		if (Object.hasOwn(columns, key)) kept[key] = row[key];
		else dropped.push(key);
	}
	return { row: kept, dropped };
}
