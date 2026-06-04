// Pins the `backup` format's table-spec list + jobs summary helper
// added per audit/data-export-completeness May 2026 High. The wiring
// in index.ts is hard to test without a Supabase + Storage stack;
// the pure spec list is easy.

import {
	assertEquals,
	assertExists,
	assertMatch,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { buildBackupSpecs, summariseJobsByKind } from './backup_spec.ts';

const TEST_UID = '00000000-0000-0000-0000-000000000abc';

Deno.test('buildBackupSpecs covers the Go worker table set', () => {
	const specs = buildBackupSpecs(TEST_UID);
	// 36 entries matches the Go worker's spec list (May 2026 +
	// reports_against_me + the 2026-05-30 Critical batch:
	// direct_messages × 2 directions, coach_athletes × 2 directions,
	// event_results + the 2026-05-30 High batch: event_result_claims,
	// user_blocks, club_posts, event_exceptions + the persona round-5
	// addition: user_settings + the Phase 4 multi-modal gym/nutrition
	// pair: gym_workouts, food_log + the nutrition body_metrics weight
	// series); a regression that drops one of these is a silent Art 20
	// completeness gap. Keep in lockstep with the Go worker's
	// `FetchExportPersonalDataTables` spec list.
	assertEquals(specs.length, 37, `expected 37 specs, got ${specs.length}`);
	const entries = new Set(specs.map((s) => s.entry));
	for (const expected of [
		'coach_messages.json',
		'notifications.json',
		'training_plans.json',
		'integrations.json',
		'run_kudos.json',
		'run_comments.json',
		'run_photos.json',
		'segment_efforts.json',
		'gear.json',
		'fitness_snapshots.json',
		'personal_records.json',
		'device_tokens.json',
		'live_run_pings.json',
		'following.json',
		'followers.json',
		'event_attendees.json',
		'club_members.json',
		'saved_routes.json',
		'route_reviews.json',
		'race_pings.json',
		'user_settings.json',
		'user_device_settings.json',
		'user_coach_usage.json',
		'reports.json',
		'reports_against_me.json',
		'direct_messages_sent.json',
		'direct_messages_received.json',
		'coaching_as_coach.json',
		'coaching_as_athlete.json',
		'event_results.json',
		'event_result_claims.json',
		'user_blocks.json',
		'club_posts.json',
		'event_exceptions.json',
		'gym_workouts.json',
		'food_log.json',
		'body_metrics.json',
	]) {
		assertEquals(entries.has(expected), true, `missing entry: ${expected}`);
	}
});

Deno.test('gym + nutrition logs exported for the subject (Phase 4 multi-modal, GDPR Art 20)', () => {
	// audit/data-export-completeness gym/nutrition gap. The Phase 4
	// strength + nutrition logs (migration 20261204_001) are the
	// subject's own health-adjacent data and must ship in the Art 20
	// export. gym_sets has no user_id of its own — it cascades from the
	// parent gym_workouts row — so the workout spec nests its sets via
	// the same embed shape training_plans uses, rather than a separate
	// owner-less top-level table.
	const specs = buildBackupSpecs(TEST_UID);
	const gym = specs.find((s) => s.entry === 'gym_workouts.json');
	const food = specs.find((s) => s.entry === 'food_log.json');
	assertExists(gym);
	assertExists(food);
	assertEquals(gym.table, 'gym_workouts');
	assertEquals(gym.filter, `user_id=eq.${TEST_UID}`);
	// The nested embed pulls the child sets (gym_sets) with the workout
	// so the owner-less child table still ships.
	assertEquals(gym.select.includes('gym_sets'), true);
	assertEquals(food.table, 'food_log');
	assertEquals(food.filter, `user_id=eq.${TEST_UID}`);
	assertEquals(food.select, '*');
});

Deno.test('direct_messages exported in both directions (GDPR Art 20)', () => {
	// audit/data-export-completeness (2026-05-30) Critical. Private 1:1
	// message bodies are the densest comms PII in the app; an export
	// that omitted them would be a wilful Art 20 failure. Both the
	// sent (sender_id) and received (recipient_id) sides are the
	// subject's own correspondence and must ship.
	const specs = buildBackupSpecs(TEST_UID);
	const sent = specs.find((s) => s.entry === 'direct_messages_sent.json');
	const received = specs.find((s) => s.entry === 'direct_messages_received.json');
	assertExists(sent);
	assertExists(received);
	assertEquals(sent.table, 'direct_messages');
	assertEquals(received.table, 'direct_messages');
	assertEquals(sent.filter, `sender_id=eq.${TEST_UID}`);
	assertEquals(received.filter, `recipient_id=eq.${TEST_UID}`);
});

Deno.test('coach_athletes exported both ways without the invite_token credential', () => {
	// audit/data-export-completeness (2026-05-30) Critical. The
	// subject's coaching links (as coach and as athlete) are their own
	// data and must ship, but `invite_token` is a redeemable credential
	// — anyone holding it can claim the link — so the narrow select
	// must omit it, mirroring the integrations vault-column exclusion.
	const specs = buildBackupSpecs(TEST_UID);
	const asCoach = specs.find((s) => s.entry === 'coaching_as_coach.json');
	const asAthlete = specs.find((s) => s.entry === 'coaching_as_athlete.json');
	assertExists(asCoach);
	assertExists(asAthlete);
	assertEquals(asCoach.filter, `coach_id=eq.${TEST_UID}`);
	assertEquals(asAthlete.filter, `athlete_id=eq.${TEST_UID}`);
	for (const spec of [asCoach, asAthlete]) {
		assertEquals(spec.table, 'coach_athletes');
		assertEquals(
			spec.select.includes('invite_token'),
			false,
			'invite_token is a redeemable credential and must never ship in the export',
		);
		assertEquals(spec.select.includes('status'), true);
		assertEquals(spec.select.includes('accepted_at'), true);
	}
});

Deno.test('event_results exported for the subject (GDPR Art 20)', () => {
	// audit/data-export-completeness (2026-05-30) Critical. Per-user
	// race finish times, ranks, DNF/DNS flags, and age-grade are
	// health-adjacent performance records the subject is entitled to.
	const results = buildBackupSpecs(TEST_UID).find((s) => s.entry === 'event_results.json');
	assertExists(results);
	assertEquals(results.table, 'event_results');
	assertEquals(results.filter, `user_id=eq.${TEST_UID}`);
});

Deno.test('user_settings exported for the subject, owner-scoped, unredacted (GDPR Art 20)', () => {
	// persona round-5 privacy / GDPR Art 20. The universal per-user
	// prefs bag (privacy zones, HR settings, date-of-birth, week-start,
	// units, …) is the subject's own data and must ship in full. The
	// Go worker also folds it into profile.json's settings_prefs, but
	// the EF rollback path has no profile.json — so the spec entry is
	// what gets it into the EF export. Scoped to user_id, select '*',
	// no redactor (only cross-user identifiers get projected out, and
	// user_settings has none).
	const us = buildBackupSpecs(TEST_UID).find((s) => s.entry === 'user_settings.json');
	assertExists(us);
	assertEquals(us.table, 'user_settings');
	assertEquals(us.filter, `user_id=eq.${TEST_UID}`);
	assertEquals(us.select, '*');
	assertEquals(us.redact, undefined);
});

Deno.test('integrations spec redacts vault columns via narrow select', () => {
	const integ = buildBackupSpecs(TEST_UID).find((s) => s.entry === 'integrations.json');
	assertExists(integ);
	// access_token + refresh_token must NEVER ship in the export —
	// they're vault-stored secrets, not user-portable data. The select
	// projects a deliberate narrow column set instead of `*`.
	assertEquals(integ.select.includes('access_token'), false);
	assertEquals(integ.select.includes('refresh_token'), false);
	assertMatch(
		integ.select,
		/id,provider,external_id,scope,last_sync_at,sync_cursor/,
	);
});

Deno.test('integrations spec includes disconnect timestamps (GDPR Art 15)', () => {
	// Persona-hunt Round 3 finding Privacy #2. Migration 20261004_001
	// added `disconnected_at` + `disconnected_reason` columns; these
	// are personal data and must surface in the right-of-access
	// export. A regression that narrowed the select back to the
	// pre-fix column list would silently strip this from every
	// future export.
	const integ = buildBackupSpecs(TEST_UID).find((s) => s.entry === 'integrations.json');
	assertExists(integ);
	assertEquals(integ.select.includes('disconnected_at'), true);
	assertEquals(integ.select.includes('disconnected_reason'), true);
});

Deno.test('device_tokens spec carries a token-redactor', () => {
	const dt = buildBackupSpecs(TEST_UID).find((s) => s.entry === 'device_tokens.json');
	assertExists(dt);
	assertExists(dt.redact);
	const redacted = dt.redact!({
		token: 'real-fcm-token-bytes',
		platform: 'android',
		last_seen_at: '2026-05-26T00:00:00Z',
	});
	assertEquals(redacted.token, '<redacted>');
	// `platform` + `last_seen_at` MUST survive — the audit Low pinned
	// that the export was missing those (it actually wasn't, given
	// `select: '*'`, but the redactor shouldn't be the regression
	// vector either).
	assertEquals(redacted.platform, 'android');
	assertEquals(redacted.last_seen_at, '2026-05-26T00:00:00Z');
});

Deno.test('reports_against_me spec uses two-param filter + narrow projection', () => {
	const rep = buildBackupSpecs(TEST_UID).find(
		(s) => s.entry === 'reports_against_me.json',
	);
	assertExists(rep);
	// Two-param filter (`target_kind=eq.user&target_id=eq.<uid>`) is
	// the postgrest shape that the EF's fetchBackupTable expects. A
	// single-param `filter` would silently drop the qualifier.
	assertEquals(rep.filter.includes('target_kind=eq.user'), true);
	assertEquals(rep.filter.includes(`target_id=eq.${TEST_UID}`), true);
	// reporter_id is intentionally excluded (Art 15(4) competing rights).
	assertEquals(rep.select.includes('reporter_id'), false);
});

Deno.test('no reports-target (against-me) spec leaks reporter_id in its select', () => {
	// audit-findings 2026-05-30 Medium [security/edge-functions]: the
	// only redaction backstop for the other party's reporter_id is the
	// select column list. Guard that EVERY spec which targets the user as
	// a report SUBJECT (target_kind=eq.user) omits reporter_id — so a
	// future copy-paste that adds another against-me table can't leak it.
	const offenders = buildBackupSpecs(TEST_UID)
		.filter((s) => s.table === 'reports' && s.filter.includes('target_kind=eq.user'))
		.filter((s) => s.select === '*' || s.select.includes('reporter_id'));
	assertEquals(offenders.length, 0, `against-me reports spec leaks reporter_id: ${offenders.map((o) => o.entry).join(', ')}`);
});

Deno.test('filter values are URL-encoded (raw filter is interpolated into the REST URL)', () => {
	// index.ts builds the PostgREST URL as `...?select=...&${spec.filter}`,
	// so any non-URL-safe character in the id must already be encoded in
	// the filter. UUIDs encode to themselves; a value with a reserved char
	// must come back percent-encoded. audit-findings 2026-05-30 Medium.
	const specs = buildBackupSpecs('a b&c#d');
	const sent = specs.find((s) => s.entry === 'direct_messages_sent.json');
	assertExists(sent);
	assertEquals(sent.filter, 'sender_id=eq.a%20b%26c%23d');
});

Deno.test('summariseJobsByKind aggregates raw rows', () => {
	const rows = [
		{ kind: 'map_match' },
		{ kind: 'map_match' },
		{ kind: 'token_refresh' },
		{ kind: 'map_match' },
		{ kind: 'strava_event' },
		{ kind: 'token_refresh' },
	];
	const summary = summariseJobsByKind(rows);
	const sorted = [...summary].sort((a, b) => a.kind.localeCompare(b.kind));
	assertEquals(sorted, [
		{ kind: 'map_match', count: 3 },
		{ kind: 'strava_event', count: 1 },
		{ kind: 'token_refresh', count: 2 },
	]);
});

Deno.test('summariseJobsByKind empty input → empty output', () => {
	assertEquals(summariseJobsByKind([]), []);
});

Deno.test('summariseJobsByKind never leaks raw payload', () => {
	// Defence-in-depth: the audit prefers the count-by-kind shape
	// over the raw payload (which would leak internal retry state).
	// The summary's only keys are `kind` + `count`.
	const summary = summariseJobsByKind([
		{ kind: 'map_match' },
	]);
	for (const row of summary) {
		assertEquals(Object.keys(row).sort(), ['count', 'kind']);
	}
});
