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
	// 24 entries matches the Go worker's spec list (May 2026 +
	// reports_against_me); a regression that drops one of these is a
	// silent Art 15 completeness gap.
	assertEquals(specs.length, 24, `expected 24 specs, got ${specs.length}`);
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
		'user_device_settings.json',
		'user_coach_usage.json',
		'reports.json',
		'reports_against_me.json',
	]) {
		assertEquals(entries.has(expected), true, `missing entry: ${expected}`);
	}
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
