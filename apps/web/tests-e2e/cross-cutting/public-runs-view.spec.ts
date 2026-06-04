import { expect, test } from '@playwright/test';

import { createClient } from '@supabase/supabase-js';

import { loadSupabaseEnv } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * `public_runs` view contract — the privacy boundary between owner-
 * accessible `runs` and anon-readable `public_runs`. The view strips
 * a long list of metadata keys (Strava IDs, Health Connect IDs, plan
 * linkage, sync internals, race identity, RPE, …) before exposing
 * the row. Three migrations have widened the strip list as new keys
 * landed (`20260626_001`, `20260714_001`, `20260724_001`); each was
 * a privacy fix.
 *
 * The seed has a SQL assertion that pins the strip list against
 * pgtap. This test pins it END-TO-END through the wire — plant a
 * public run with every strip-listed metadata key, read it as anon
 * via supabase-js, assert each key is absent from the returned row.
 * A regression that re-exposed any key would surface here as the
 * first place a real client hits.
 */

// Keys the public_runs view subtracts from `metadata` before
// returning. Source of truth: the most recent
// `create or replace view public_runs` migration. Keep this list in
// sync with the migration; if a new strip lands, add a key here.
const STRIPPED_METADATA_KEYS = [
	'strava_id',
	'garmin_id',
	'imported_from',
	'imported_at',
	'health_connect_type',
	'strava_activity_type',
	'source_file',
	'max_bpm',
	'plan_workout_id',
	'workout_step_results',
	'workout_adherence',
	'last_modified_at',
	'recovered_from_crash',
	'in_progress_saved_at',
	'in_progress',
	'manual_entry',
	'indoor_estimated',
	'distance_source',
	'race_name',
	'bib',
	'overall_place',
	'chip_time',
	'perceived_effort',
	'run_number',
] as const;

// Keys the view DOES expose in the metadata bag (so a public viewer can
// render the run usefully). Pin these so a regression that over-stripped
// breaks here too. `activity_type` is NOT here — migration 20261207_001
// promoted it to a real `runs.activity_type` column, so the view exposes
// it as a top-level column (asserted separately below), not a bag key.
const RETAINED_METADATA_KEYS = [
	'avg_bpm',
] as const;

test.describe('public_runs view — privacy strip contract', () => {
	test('anon reading public_runs gets none of the strip-listed metadata keys', async () => {
		// Plant a public run with every strippable key set to a marker
		// value. Also set the retained keys so we can confirm the view
		// kept them.
		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true,
			activity_type: 'run',
			metadata: {
				// strip-list — these MUST disappear
				strava_id: 'STRAVA_LEAK',
				garmin_id: 'GARMIN_LEAK',
				imported_from: 'STRAVA_ZIP',
				imported_at: '2026-01-01T00:00:00Z',
				health_connect_type: 'RUNNING',
				strava_activity_type: 'Run',
				source_file: 'leak.gpx',
				max_bpm: 198,
				plan_workout_id: 'PLAN_LEAK',
				workout_step_results: [{ leak: true }],
				workout_adherence: 'on',
				last_modified_at: '2026-01-01T00:00:00Z',
				recovered_from_crash: true,
				in_progress_saved_at: '2026-01-01T00:00:00Z',
				in_progress: false,
				manual_entry: true,
				indoor_estimated: true,
				distance_source: 'leak',
				race_name: 'LEAK_RACE',
				bib: '999',
				overall_place: 1,
				chip_time: 1499,
				perceived_effort: 7,
				run_number: 42,
				// retained — these MUST remain
				activity_type: 'run',
				avg_bpm: 150,
			} as Record<string, unknown>,
		});

		try {
			// Anon client — the only thing /share/run sees.
			const { url, anonKey } = loadSupabaseEnv();
			const anon = createClient(url, anonKey, {
				auth: { persistSession: false }
			});
			const { data, error } = await anon
				.from('public_runs')
				.select('activity_type, metadata')
				.eq('id', planted)
				.single();

			expect(error, 'anon must be able to read its own public_runs row')
				.toBeNull();
			const row = data as { activity_type: string; metadata: Record<string, unknown> };
			const meta = row.metadata;

			// activity_type is a real column on the view (20261207_001), not a
			// metadata bag key — a public viewer reads it for the activity badge.
			expect(row.activity_type).toBe('run');

			// Every strip-listed key must be absent.
			for (const key of STRIPPED_METADATA_KEYS) {
				expect(
					meta,
					`metadata key '${key}' leaked through the public_runs view; ` +
						`a recent migration must have dropped it from the strip list`
				).not.toHaveProperty(key);
			}

			// Every retained key must be present (over-stripping
			// regression guard).
			for (const key of RETAINED_METADATA_KEYS) {
				expect(
					meta,
					`metadata key '${key}' is supposed to survive the strip ` +
						`(public viewers need it for activity badges + HR display)`
				).toHaveProperty(key);
			}
		} finally {
			await deleteRun(planted);
		}
	});

	test('anon CANNOT read public_runs rows where is_public=false', async () => {
		// Defence in depth: the view's WHERE clause filters
		// is_public=true. A regression that dropped the WHERE would
		// expose private runs to anon through the view. Pin it.
		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 4_000,
			duration_s: 1_200,
			is_public: false,
		});

		try {
			const { url, anonKey } = loadSupabaseEnv();
			const anon = createClient(url, anonKey, {
				auth: { persistSession: false }
			});
			const { data } = await anon
				.from('public_runs')
				.select('id')
				.eq('id', planted)
				.maybeSingle();
			expect(data).toBeNull();
		} finally {
			await deleteRun(planted);
		}
	});
});
