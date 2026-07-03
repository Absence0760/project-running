// Pins the `backup` format's table-spec list + jobs summary helper
// added per audit/data-export-completeness May 2026 High. The wiring
// in index.ts is hard to test without a Supabase + Storage stack;
// the pure spec list is easy.

import {
	assertEquals,
	assertExists,
	assertMatch,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	avatarCandidatePaths,
	BACKUP_FORMAT,
	BACKUP_VERSION,
	buildBackupManifest,
	buildBackupSpecs,
	isSafeStoragePath,
	orphanStorageEntries,
	PROFILE_SELECT,
	shapeExportRoute,
	stripProfileId,
	summariseJobsByKind,
} from './backup_spec.ts';

const TEST_UID = '00000000-0000-0000-0000-000000000abc';

Deno.test('buildBackupSpecs covers the Go worker table set', () => {
	const specs = buildBackupSpecs(TEST_UID);
	// Entry count tracks the Go worker's exportPersonalDataSpecs list (May
	// 2026 base + reports_against_me + the 2026-05-30 Critical/High batches
	// + user_settings + the Phase 4 gym/nutrition pair + body_metrics +
	// safety_contacts × 2 + instructor_payout_accounts). The 2026-06-20
	// GDPR Art 20 batch added the four owner-FK tables missing from BOTH
	// export paths — session_plans, route_photos, event_orders (× 2: buyer
	// + host), event_pricing_as_host — plus the four pre-existing user_id
	// gaps the widened completeness guard then surfaced (achievements,
	// challenge_participants, challenge_badges, public_recaps). A regression
	// that drops one is a silent Art 20 completeness gap. route_markers +
	// checkpoint_crossings were added to the Go worker in 8d16f665 (June
	// 2026) without this twin — an unintentional drift, not a design
	// choice — and were wired in per audit/data-export-completeness
	// 2026-07-02 High, so the two lists carry the same table set again.
	// The 2026-06-20 widened-guard pass then surfaced route_conditions
	// (migration 20270215_001) as a further user_id gap and wired it in.
	// The 2026-06-20 nutrition saved-meals batch added meal_templates
	// (+ nested items) as a further owner-scoped Art 20 table; the recipe
	// builder (migration 20270221_001) then added recipes (+ nested
	// ingredients), and the exercise-catalogue batch (migration
	// 20270222_001) added exercises filtered to the subject's OWN custom
	// entries (author_id = uid) — seeded global rows are shared reference
	// data, not personal data.
	assertEquals(specs.length, 59, `expected 59 specs, got ${specs.length}`);
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
		'gear_wear_logs.json',
		'gear_rotations.json',
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
		'route_markers.json',
		'route_conditions.json',
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
		'checkpoint_crossings.json',
		'event_result_claims.json',
		'user_blocks.json',
		'club_posts.json',
		'event_exceptions.json',
		'gym_workouts.json',
		'gym_routines.json',
		'exercises.json',
		'food_log.json',
		'meal_templates.json',
		'recipes.json',
		'body_metrics.json',
		'instructor_payout_accounts.json',
		'safety_contacts_owned.json',
		'safety_contacts_as_contact.json',
		'session_plans.json',
		'route_photos.json',
		'club_photos.json',
		'event_orders_as_buyer.json',
		'event_orders_as_host.json',
		'event_pricing_as_host.json',
		'achievements.json',
		'challenge_participants.json',
		'challenge_badges.json',
		'public_recaps.json',
	]) {
		assertEquals(entries.has(expected), true, `missing entry: ${expected}`);
	}
});

Deno.test('session_plans exported author-scoped with blocks + items nested (GDPR Art 20)', () => {
	// 2026-06-20 Art 20 batch. The yoga/pilates session-planner P1 authored
	// content (migration 20270103_001) was missing from both export paths.
	// It is keyed by author_id (NOT user_id), so the Go completeness guard's
	// user_id-column scan never flagged it — the blind spot this batch
	// closed. session_plan_blocks / session_plan_items have no owner column
	// of their own (they cascade from the parent plan), so the spec nests
	// them, mirroring the gym_routines embed.
	const specs = buildBackupSpecs(TEST_UID);
	const plans = specs.find((s) => s.entry === 'session_plans.json');
	assertExists(plans);
	assertEquals(plans.table, 'session_plans');
	assertEquals(plans.filter, `author_id=eq.${TEST_UID}`);
	assertEquals(plans.select.includes('session_plan_blocks'), true);
	assertEquals(plans.select.includes('session_plan_items'), true);
});

Deno.test('recipes exported user-scoped with ingredients nested (GDPR Art 20)', () => {
	// Recipe builder (migration 20270221_001). Owner-scoped (user_id);
	// recipe_ingredients have no user_id of their own (they cascade from the
	// parent recipe), so the spec nests them, mirroring the meal_templates +
	// gym_routines embeds. A regression that drops the nested ingredients
	// silently strips them from every DSAR.
	const specs = buildBackupSpecs(TEST_UID);
	const recipes = specs.find((s) => s.entry === 'recipes.json');
	assertExists(recipes);
	assertEquals(recipes.table, 'recipes');
	assertEquals(recipes.filter, `user_id=eq.${TEST_UID}`);
	assertEquals(recipes.select.includes('recipe_ingredients'), true);
});

Deno.test('route_photos exported owner-scoped (GDPR Art 20)', () => {
	// 2026-06-20 Art 20 batch. Route-photo metadata (migration 20270114_001)
	// is keyed by owner_id (the uploader), so the user_id-column guard never
	// saw it. The metadata row (caption, ordering, storage paths, timestamps)
	// is the subject's own data; the image bytes live in Storage.
	const photos = buildBackupSpecs(TEST_UID).find((s) => s.entry === 'route_photos.json');
	assertExists(photos);
	assertEquals(photos.table, 'route_photos');
	assertEquals(photos.filter, `owner_id=eq.${TEST_UID}`);
	assertEquals(photos.select, '*');
});

Deno.test('event_orders exported both legs: as buyer and as host (GDPR Art 20)', () => {
	// 2026-06-20 Art 20 batch. The paid-registration ledger (migration
	// 20261229_001) is keyed by buyer_user_id / host_user_id, neither of
	// which the user_id-column guard saw. The subject is party to a row on
	// both legs — orders they placed (buyer) and orders for their events
	// (host) — and the financial record is their own Art 15/20 data.
	const specs = buildBackupSpecs(TEST_UID);
	const asBuyer = specs.find((s) => s.entry === 'event_orders_as_buyer.json');
	const asHost = specs.find((s) => s.entry === 'event_orders_as_host.json');
	assertExists(asBuyer);
	assertExists(asHost);
	assertEquals(asBuyer.table, 'event_orders');
	assertEquals(asHost.table, 'event_orders');
	assertEquals(asBuyer.filter, `buyer_user_id=eq.${TEST_UID}`);
	assertEquals(asHost.filter, `host_user_id=eq.${TEST_UID}`);
});

Deno.test('event_pricing exported host-scoped via embedded event inner-join (GDPR Art 20)', () => {
	// 2026-06-20 Art 20 batch. event_pricing (migration 20261229_001) has no
	// owner column of its own — the host link is event_id → events.host_user_id.
	// The spec inner-joins the parent event and filters on its host_user_id,
	// so only the subject's own events' pricing ships. The embedded events
	// object must project ONLY host_user_id (the subject's own id) so no
	// third-party event data leaks alongside it.
	const pricing = buildBackupSpecs(TEST_UID).find((s) => s.entry === 'event_pricing_as_host.json');
	assertExists(pricing);
	assertEquals(pricing.table, 'event_pricing');
	assertEquals(pricing.filter, `events.host_user_id=eq.${TEST_UID}`);
	assertEquals(pricing.select, '*,events!inner(host_user_id)');
});

Deno.test('achievements / challenges / recaps exported owner-scoped (GDPR Art 20)', () => {
	// 2026-06-20 Art 20 batch. These four carry a plain user_id FK to
	// auth.users and were genuine pre-existing gaps in the export — earned
	// achievements, challenge enrolments, challenge-completion badges, and
	// published recap snapshots are all the subject's own Art 20 data. The
	// widened completeness guard surfaced them; they ship owner-scoped, `*`.
	const specs = buildBackupSpecs(TEST_UID);
	for (const entry of [
		'achievements.json',
		'challenge_participants.json',
		'challenge_badges.json',
		'public_recaps.json',
	]) {
		const spec = specs.find((s) => s.entry === entry);
		assertExists(spec);
		assertEquals(spec.filter, `user_id=eq.${TEST_UID}`);
		assertEquals(spec.select, '*');
	}
});

Deno.test('safety_contacts exported both ways without the confirm_token credential (GDPR Art 20)', () => {
	// followups.md G1 + safety_contacts Art 20 sub-item. The subject is on
	// both legs of a safety-contact relationship: rows they OWN (owner_id —
	// the contacts they designated) and rows where they ARE the confirmed
	// contact (contact_user_id). Both are the subject's own personal data.
	// The Go guard's user_id-keyed scan can't see this table (owner_id /
	// contact_user_id), so it is wired explicitly. `confirm_token` is a
	// redeemable capability — anyone holding it can confirm the contact via
	// confirm_safety_contact_by_token — so the narrow select must omit it.
	const specs = buildBackupSpecs(TEST_UID);
	const owned = specs.find((s) => s.entry === 'safety_contacts_owned.json');
	const asContact = specs.find((s) => s.entry === 'safety_contacts_as_contact.json');
	assertExists(owned);
	assertExists(asContact);
	assertEquals(owned.filter, `owner_id=eq.${TEST_UID}`);
	assertEquals(asContact.filter, `contact_user_id=eq.${TEST_UID}`);
	for (const spec of [owned, asContact]) {
		assertEquals(spec.table, 'safety_contacts');
		assertEquals(
			spec.select.includes('confirm_token'),
			false,
			'confirm_token is a redeemable capability and must never ship in the export',
		);
		assertEquals(spec.select.includes('contact_email'), true);
		assertEquals(spec.select.includes('confirmed_at'), true);
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

Deno.test('gym_routines exported author-scoped with exercises + planned sets nested (GDPR Art 20)', () => {
	// gym_programming.md § DSAR export. The P1 reusable plan (migration
	// 20270101_001) is the subject's own authored content. It is keyed by
	// author_id (not user_id), and gym_routine_exercises / gym_routine_sets
	// have no owner column of their own — they cascade from the parent
	// routine — so the spec nests them two levels deep, mirroring the
	// gym_workouts → gym_sets embed, rather than separate owner-less tables.
	const specs = buildBackupSpecs(TEST_UID);
	const routines = specs.find((s) => s.entry === 'gym_routines.json');
	assertExists(routines);
	assertEquals(routines.table, 'gym_routines');
	assertEquals(routines.filter, `author_id=eq.${TEST_UID}`);
	// The nested embed pulls the child exercises and their planned sets so
	// the owner-less child tables still ship in full.
	assertEquals(routines.select.includes('gym_routine_exercises'), true);
	assertEquals(routines.select.includes('gym_routine_sets'), true);
});

Deno.test('meal_templates exported owner-scoped with items nested (GDPR Art 20)', () => {
	// multi_modal.md Nutrition mid tier. Saved meals (migration 20270218_001)
	// are the subject's own authored content. meal_templates is keyed by
	// user_id; meal_template_items have no owner column of their own — they
	// cascade from the parent template — so the spec nests them, mirroring the
	// gym_routines → exercises → sets embed.
	const specs = buildBackupSpecs(TEST_UID);
	const templates = specs.find((s) => s.entry === 'meal_templates.json');
	assertExists(templates);
	assertEquals(templates.table, 'meal_templates');
	assertEquals(templates.filter, `user_id=eq.${TEST_UID}`);
	assertEquals(templates.select.includes('meal_template_items'), true);
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

Deno.test('route_markers exported for the subject (GDPR Art 20)', () => {
	// audit/data-export-completeness 2026-07-02 High. Added to the Go
	// worker in 8d16f665 without this twin — the two-table drift the
	// audit re-flagged. The subject's own course annotations ship in
	// full: every column is their own input or geometry-derived.
	const markers = buildBackupSpecs(TEST_UID).find((s) => s.entry === 'route_markers.json');
	assertExists(markers);
	assertEquals(markers.table, 'route_markers');
	assertEquals(markers.filter, `user_id=eq.${TEST_UID}`);
	assertEquals(markers.select, '*');
});

Deno.test('checkpoint_crossings exported without recorded_by (GDPR Art 20 / Art 9)', () => {
	// audit/data-export-completeness 2026-07-02 High. The subject's own
	// race-checkpoint timing plus Art 9 weigh-in body weight + medical
	// hold/note — data they are unconditionally entitled to. The
	// projection must match the Go worker's: `recorded_by` (the
	// official who logged the crossing, a third-party uid) never ships.
	const crossings = buildBackupSpecs(TEST_UID).find(
		(s) => s.entry === 'checkpoint_crossings.json',
	);
	assertExists(crossings);
	assertEquals(crossings.table, 'checkpoint_crossings');
	assertEquals(crossings.filter, `user_id=eq.${TEST_UID}`);
	assertEquals(crossings.select.includes('recorded_by'), false);
	for (const col of ['in_time', 'out_time', 'body_weight_kg', 'medical_hold', 'medical_note']) {
		assertEquals(
			crossings.select.includes(col),
			true,
			`checkpoint_crossings select must carry ${col}`,
		);
	}
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

Deno.test('PROFILE_SELECT carries the subscription columns and matches the Go projection', () => {
	// audit/data-export-completeness 2026-07-02 High: subscription_tier /
	// subscription_at / billing_issue_at are commercial data the business
	// holds about the subject (Art 15(1) / CCPA right-to-know) and were
	// missing from BOTH export paths. Must stay in lockstep with the Go
	// worker's FetchExportProfile select.
	for (
		const col of [
			'subscription_tier',
			'subscription_at',
			'billing_issue_at',
			'display_name',
			'date_of_birth',
			'parkrun_number',
			'hr_zones',
			'gender',
			'activity_default',
			'privacy_default',
		]
	) {
		assertEquals(PROFILE_SELECT.includes(col), true, `PROFILE_SELECT must carry ${col}`);
	}
});

Deno.test('stripProfileId removes id, keeps everything else, passes null through', () => {
	assertEquals(stripProfileId(null), null);
	const stripped = stripProfileId({
		id: TEST_UID,
		display_name: 'Jared',
		subscription_tier: 'pro',
	});
	assertEquals(stripped, { display_name: 'Jared', subscription_tier: 'pro' });
});

Deno.test('shapeExportRoute keeps required columns, drops nulls and user_id', () => {
	const shaped = shapeExportRoute({
		id: 'r1',
		user_id: TEST_UID,
		name: 'River loop',
		waypoints: [[0, 0], [1, 1]],
		distance_m: 5000,
		elevation_m: null,
		surface: 'trail',
		slug: null,
		geom: 'SRID=4326;LINESTRING(...)',
	});
	assertEquals(shaped, {
		id: 'r1',
		name: 'River loop',
		waypoints: [[0, 0], [1, 1]],
		distance_m: 5000,
		surface: 'trail',
	});
});

Deno.test('isSafeStoragePath rejects traversal and absolute paths', () => {
	assertEquals(isSafeStoragePath(`${TEST_UID}/photo-1.jpg`), true);
	assertEquals(isSafeStoragePath(''), false);
	assertEquals(isSafeStoragePath('/etc/passwd'), false);
	assertEquals(isSafeStoragePath('a/../b.jpg'), false);
	assertEquals(isSafeStoragePath('a//b.jpg'), false);
	assertEquals(isSafeStoragePath('a/./b.jpg'), false);
	assertEquals(isSafeStoragePath('a\\b.jpg'), false);
});

Deno.test('buildBackupManifest matches the run-app-backup v1 shape', () => {
	const manifest = buildBackupManifest({
		userId: TEST_UID,
		counts: { runs: 2, routes: 1, tracks: 2, hr_series: 0, photos: 1 },
		exportedAt: '2026-07-03T00:00:00.000Z',
	});
	assertEquals(manifest, {
		format: BACKUP_FORMAT,
		version: BACKUP_VERSION,
		exported_at: '2026-07-03T00:00:00.000Z',
		exported_by_user_id: TEST_UID,
		exported_from: 'edge-function',
		counts: { runs: 2, routes: 1, tracks: 2, hr_series: 0, photos: 1 },
	});
	assertEquals(BACKUP_FORMAT, 'run-app-backup');
	assertEquals(BACKUP_VERSION, 1);
});

Deno.test('avatarCandidatePaths enumerates the stable per-extension avatar set', () => {
	// Mirrors the Go builder's avatarExts probe order and the web
	// uploader's avatarPathsFor — the export probes exactly these
	// paths, nothing else, so a hostile uid can't widen the fetch.
	assertEquals(avatarCandidatePaths(TEST_UID), [
		`${TEST_UID}/avatar.jpg`,
		`${TEST_UID}/avatar.png`,
		`${TEST_UID}/avatar.webp`,
	]);
});

Deno.test('orphanStorageEntries sweeps unarchived objects, dedupes, and skips exports + traversal', () => {
	const archived = new Set([`${TEST_UID}/run-1.json.gz`, `${TEST_UID}/run-1.hr.json.gz`]);
	const entries = orphanStorageEntries({
		bucket: 'runs',
		userId: TEST_UID,
		archived,
		keys: [
			`${TEST_UID}/run-1.json.gz`, // archived row-driven → deduped
			`${TEST_UID}/run-1.hr.json.gz`, // archived row-driven → deduped
			`${TEST_UID}/run-1.matched.json.gz`, // CAS orphan → swept
			`${TEST_UID}/exports/2026-01-01.zip`, // prior export artifact → skipped
			`${TEST_UID}/../etc/passwd`, // traversal → skipped
			'other-user/run-9.json.gz', // outside the prefix → skipped
		],
	});
	assertEquals(entries, [
		{
			key: `${TEST_UID}/run-1.matched.json.gz`,
			entry: `storage/runs/run-1.matched.json.gz`,
		},
	]);
});

Deno.test('orphanStorageEntries only skips exports/ in the runs bucket', () => {
	// run-photos has no exports/ convention; an object under that name
	// there is still the subject's data and must be swept.
	const entries = orphanStorageEntries({
		bucket: 'run-photos',
		userId: TEST_UID,
		archived: new Set<string>(),
		keys: [`${TEST_UID}/photo-1_512.jpg`, `${TEST_UID}/exports/x.jpg`],
	});
	assertEquals(entries, [
		{ key: `${TEST_UID}/photo-1_512.jpg`, entry: 'storage/run-photos/photo-1_512.jpg' },
		{ key: `${TEST_UID}/exports/x.jpg`, entry: 'storage/run-photos/exports/x.jpg' },
	]);
});
