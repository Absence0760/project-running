import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { buildShareBadgeMeta } from './share_badge_meta';
import { buildShareClubHead } from './share_club_meta';
import { buildShareEventHead } from './share_event_meta';
import { buildShareProfileHead } from './share_profile_meta';
import { buildShareRaceHead } from './share_race_meta';
import { buildShareRecapMeta } from './share_recap_meta';
import { buildShareRouteHead } from './share_route_meta';
import { buildShareRunMeta } from './share_run_meta';
import { buildShareSessionHead } from './share_session_meta';
import { buildShareWorkoutHead } from './share_workout_meta';

/**
 * The clipping half of the `<head>` census, and the sibling of
 * `share_head_escaping.test.ts`: that one proves a hostile field cannot break
 * out of the markup, this one proves an ENORMOUS field cannot get in at all.
 *
 * `clubs.description` holds 2,000 characters against a 160-character
 * `og:description`, so a builder that forgets `collapseAndClip` does not fail
 * anything — it emits the whole column into a meta tag every crawler reads,
 * and the only visible sign is a very long unfurl. Nothing was measuring it;
 * the escape had a census since § 1476 and the clip had none.
 *
 * The probe is a run of one letter far longer than any budget in the tree.
 * The largest is the 160 of `og:description`, so a surviving run past
 * MAX_RUN means some field reached the head unclipped, whatever its own
 * budget was.
 */
const MARK = 'Z';
const HUGE = MARK.repeat(5000);
const MAX_RUN = 200;
const SITE = 'https://threkir.com';

const builders: Array<{ name: string; head: () => Record<string, unknown> }> = [
	{
		name: 'buildShareRunMeta',
		head: () =>
			buildShareRunMeta({
				id: 'r-1',
				run: {
					id: 'r-1',
					user_id: 'u-1',
					distance_m: 10_000,
					duration_s: 3000,
					started_at: '2026-05-01T08:00:00.000Z',
					source: 'manual',
					metadata: null,
					concluded_at: null,
				},
				displayName: HUGE,
				siteUrl: SITE,
			}) as unknown as Record<string, unknown>,
	},
	{
		name: 'buildShareBadgeMeta',
		head: () =>
			buildShareBadgeMeta({
				id: 'b-1',
				badge: {
					id: 'b-1',
					user_id: 'u-1',
					badge_key: 'distance_total',
					tier: 'gold',
					value_num: 1000,
					earned_at: '2026-05-01T08:00:00.000Z',
				},
				displayName: HUGE,
				siteUrl: SITE,
			}) as unknown as Record<string, unknown>,
	},
	{
		name: 'buildShareClubHead',
		head: () =>
			buildShareClubHead({
				slug: 'hampstead-runners',
				club: {
					id: 'c-1',
					slug: 'hampstead-runners',
					name: HUGE,
					description: HUGE,
					avatar_url: null,
					location_label: HUGE,
				},
				siteUrl: SITE,
			}) as unknown as Record<string, unknown>,
	},
	{
		name: 'buildShareEventHead',
		head: () =>
			buildShareEventHead({
				id: 'e-1',
				event: {
					id: 'e-1',
					club_id: 'c-1',
					title: HUGE,
					description: HUGE,
					starts_at: '2026-05-01T08:00:00.000Z',
					duration_min: 60,
					distance_m: 10_000,
					category: null,
					discipline: null,
					club_name: HUGE,
					club_slug: 'hampstead-runners',
					club_location: HUGE,
				},
				siteUrl: SITE,
			}) as unknown as Record<string, unknown>,
	},
	{
		name: 'buildShareProfileHead',
		head: () =>
			buildShareProfileHead({
				id: 'u-1',
				profile: { id: 'u-1', display_name: HUGE, avatar_url: null },
				siteUrl: SITE,
			}) as unknown as Record<string, unknown>,
	},
	{
		name: 'buildShareRaceHead',
		head: () =>
			buildShareRaceHead({
				id: 'ra-1',
				race: {
					id: 'ra-1',
					name: HUGE,
					race_date: '2026-05-01',
					distance_m: 42_195,
					location_label: HUGE,
					entry_url: null,
					is_verified: true,
				},
				siteUrl: SITE,
			}) as unknown as Record<string, unknown>,
	},
	{
		name: 'buildShareRouteHead',
		head: () =>
			buildShareRouteHead({
				id: 'ro-1',
				route: { name: HUGE, distance_m: 10_000, surface: 'road', elevation_m: 100 },
				siteUrl: SITE,
			}) as unknown as Record<string, unknown>,
	},
	{
		name: 'buildShareRecapMeta',
		head: () =>
			buildShareRecapMeta({
				id: 'rc-1',
				recap: {
					id: 'rc-1',
					periodKind: 'year',
					periodKey: '2026',
					snapshot: { year: 2026, totalDistanceM: 1_000_000, runCount: 200 },
					displayName: HUGE,
				},
				siteUrl: SITE,
			}) as unknown as Record<string, unknown>,
	},
	{
		name: 'buildShareSessionHead',
		head: () =>
			buildShareSessionHead({
				id: 's-1',
				session: {
					id: 's-1',
					author_id: 'u-1',
					title: HUGE,
					discipline: HUGE,
					equipment: HUGE,
					est_duration_min: 45,
					blocks: [{ id: 'bl-1', position: 0, name: HUGE }],
					items: [
						{
							id: 'it-1',
							block_id: 'bl-1',
							position: 0,
							movement_name: HUGE,
							kind: 'hold',
							duration_s: 60,
							reps: null,
							per_side: false,
							tempo: null,
							cue: HUGE,
						},
					],
				},
				displayName: HUGE,
				siteUrl: SITE,
			}) as unknown as Record<string, unknown>,
	},
	{
		name: 'buildShareWorkoutHead',
		head: () =>
			buildShareWorkoutHead({
				id: 'w-1',
				workout: {
					id: 'w-1',
					user_id: 'u-1',
					title: HUGE,
					started_at: '2026-05-01T08:00:00.000Z',
					set_count: 12,
					volume_kg: 4000,
					sets: [
						{ set_index: 0, exercise_name: HUGE, reps: 5, weight_kg: 100, duration_s: null },
					],
				},
				displayName: HUGE,
				siteUrl: SITE,
			}) as unknown as Record<string, unknown>,
	},
];

const RUN_PAST_BUDGET = new RegExp(`${MARK}{${MAX_RUN + 1},}`);

for (const b of builders) {
	test(`${b.name} — no field reaches the head unclipped`, () => {
		// Every field, not the first bad one: an unclipped title used to hide an
		// unclipped description behind it on the same builder.
		const unclipped = Object.entries(b.head())
			.filter(([, v]) => typeof v === 'string' && RUN_PAST_BUDGET.test(v))
			.map(([field]) => field);
		assert.deepEqual(
			unclipped,
			[],
			`${b.name} emitted more than ${MAX_RUN} consecutive input characters in: ${unclipped.join(', ')}`,
		);
	});
}

/// A builder added without a row here would be censused by nothing, which is
/// the failure this file exists to make impossible rather than to describe.
///
/// The scan reads the DECLARATION rather than the `function` keyword, matching
/// `share_head_escaping.test.ts`' own census: an
/// `export const buildShareX = (…) =>` is the same builder spelled
/// differently, and a census keyed on the keyword would miss it silently — the
/// direction a census must never fail in.
const BUILDER_DECL =
	/^export\s+(?:async\s+)?(?:function\s+(buildShare\w+)\s*[<(]|(?:const|let|var)\s+(buildShare\w+)\s*[:=])/gm;

test('every buildShare* entity builder is censused above', () => {
	const dir = dirname(fileURLToPath(import.meta.url));
	const declared = new Set<string>();
	for (const file of readdirSync(dir)) {
		if (!file.endsWith('.ts') || file.endsWith('.test.ts')) continue;
		const src = readFileSync(join(dir, file), 'utf-8');
		for (const m of src.matchAll(BUILDER_DECL)) declared.add(m[1] ?? m[2]);
	}
	const censused = new Set(builders.map((b) => b.name));
	assert.ok(declared.size > 0, 'the scan found no buildShare* builders at all');
	for (const name of declared) {
		assert.ok(censused.has(name), `${name} is exported but not censused in share_head_clipping.test.ts`);
	}
	for (const name of censused) {
		assert.ok(declared.has(name), `${name} is censused but no longer exported`);
	}
});
