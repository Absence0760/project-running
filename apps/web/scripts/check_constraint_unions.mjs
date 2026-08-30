// Guardrail: verify every set-shaped CHECK constraint in the Supabase
// migrations matches the client enumerations of that value set — on BOTH
// rails, TypeScript and Dart — and that every such constraint is accounted
// for by name.
//
// Why this exists: Supabase's gen-types pass doesn't read CHECK constraints,
// so the narrow client types are hand-maintained. If a migration adds a new
// value to the CHECK and nobody updates the union (or vice versa), one client
// can write a value the other rejects (postgres 23514 `check_violation`) and
// we don't notice until production. The April 2026 cross-client audit caught
// this happening with `runsignup` — the IntegrationProvider TS union had it,
// the CHECK constraint didn't.
//
// Three things this guard learned the hard way (decisions § 791):
//
//   * A rail registered in no registry drifts with nothing able to notice.
//     § 641's `turn_cues` is the exact precedent — one helper diverged in all
//     three implementations at once because the pair appeared in neither
//     registry. This guard read `apps/web/src/lib/types.ts` and nothing else,
//     so eleven columns whose client union lives in another file were
//     structurally unreachable, and the entire Dart rail was unguarded.
//
//   * Coverage has to be DERIVED, not asserted. The old suite checked
//     `checks.size >= PAIRS.length`, which is true of any registry and says
//     nothing about the columns missing from it. `auditCoverage` below
//     compares the registry against the constraints the migrations actually
//     define, in both directions, so a new CHECK column fails the PR until
//     somebody files it as paired or as deliberately unenumerated.
//
//   * The replay has to honour drops. `runs.kind` was dropped in migration
//     20261206_001 and this script still reported a live CHECK on it, because
//     a walk that only ever ADDS cannot represent a column going away.
//
// Run: `npm run check:check-constraints --workspace=apps/web`
// CI:  invoked from the parity-types job alongside gen:types:check.
// Unit tests: `node --test apps/web/scripts/check_constraint_unions.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { splitSqlStatements } from '../../backend/scripts/sql_lex.mjs';
import { extractClientEnum } from './client_enum_extract.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = join(__dirname, '..', '..', '..');
export const MIGRATIONS_DIR = join(REPO_ROOT, 'apps/backend/supabase/migrations');

const TYPES = 'apps/web/src/lib/types.ts';
const DATA = 'apps/web/src/lib/core/data.ts';

/**
 * A client enumeration of one CHECK set.
 *
 * `shape` names how the values are spelled — see `client_enum_extract.mjs`.
 * `extra` declares the values the client carries that the column does NOT,
 * which makes the pair a SUPERSET rather than an equality. That is a real
 * and legitimate shape, not a loophole: `data_export_jobs.status` has five
 * stored states, while both clients additionally model `none` (a subject who
 * never asked) and `stalled` (derived at read time from how long the row has
 * gone untouched). Declaring them keeps the guard able to catch a stored
 * status the client cannot represent, which is the direction that breaks.
 *
 * @typedef {{ file: string, shape: 'union'|'list'|'keyed'|'keys'|'enum',
 *   name: string, field?: string, extra?: readonly string[] }} ClientEnum
 */

/**
 * Every set-shaped CHECK column that a client enumerates, and where.
 * `parity-types` fails the PR when a column is missing from both this and
 * `UNENUMERATED`, so a new constraint cannot land unexamined.
 *
 * @type {readonly { tableColumn: string, ts: readonly ClientEnum[], dart: readonly ClientEnum[] }[]}
 */
export const PAIRS = [
	{
		tableColumn: 'runs.source',
		ts: [
			{ file: TYPES, shape: 'union', name: 'RunSource' },
			{ file: 'apps/web/src/lib/runs/source_badge.ts', shape: 'list', name: 'RUN_SOURCES' },
		],
		dart: [
			{ file: 'packages/core_models/lib/src/run_source.dart', shape: 'enum', name: 'RunSource' },
		],
	},
	{
		tableColumn: 'runs.activity_type',
		ts: [
			{ file: TYPES, shape: 'union', name: 'ActivityType' },
			{ file: 'apps/web/src/lib/runs/activity_type.ts', shape: 'list', name: 'ACTIVITY_TYPES' },
		],
		dart: [{ file: 'apps/mobile_android/lib/preferences.dart', shape: 'enum', name: 'ActivityType' }],
	},
	{
		tableColumn: 'challenges.activity_type',
		ts: [{ file: TYPES, shape: 'union', name: 'ActivityType' }],
		dart: [{ file: 'apps/mobile_android/lib/preferences.dart', shape: 'enum', name: 'ActivityType' }],
	},
	{
		tableColumn: 'routes.surface',
		ts: [{ file: TYPES, shape: 'union', name: 'RouteSurface' }],
		dart: [
			{
				file: 'apps/mobile_android/lib/catalogue_browse.dart',
				shape: 'list',
				name: 'kRouteSurfaceVocabulary',
			},
		],
	},
	{
		tableColumn: 'route_markers.kind',
		ts: [
			{ file: TYPES, shape: 'union', name: 'RouteMarkerKind' },
			{
				file: 'apps/web/src/lib/routes/route_markers.ts',
				shape: 'keyed',
				name: 'ROUTE_MARKER_KINDS',
				field: 'kind',
			},
		],
		dart: [
			{
				file: 'apps/mobile_android/lib/route_markers.dart',
				shape: 'keyed',
				name: 'routeMarkerKinds',
				field: 'kind',
			},
		],
	},
	{
		tableColumn: 'route_conditions.condition',
		ts: [{ file: TYPES, shape: 'union', name: 'RouteConditionKind' }],
		dart: [
			{
				file: 'apps/mobile_android/lib/widgets/route_conditions.dart',
				shape: 'list',
				name: 'kRouteConditionKinds',
			},
		],
	},
	{
		tableColumn: 'route_conditions.severity',
		ts: [{ file: TYPES, shape: 'union', name: 'RouteConditionSeverity' }],
		dart: [
			{
				file: 'apps/mobile_android/lib/widgets/route_conditions.dart',
				shape: 'list',
				name: 'kRouteConditionSeverities',
			},
		],
	},
	{
		tableColumn: 'integrations.provider',
		ts: [{ file: TYPES, shape: 'union', name: 'IntegrationProvider' }],
		dart: [],
	},
	{
		tableColumn: 'user_profiles.gender',
		ts: [{ file: TYPES, shape: 'union', name: 'Gender' }],
		dart: [],
	},
	{
		tableColumn: 'user_profiles.preferred_unit',
		ts: [{ file: TYPES, shape: 'union', name: 'PreferredUnit' }],
		dart: [
			{ file: 'apps/mobile_android/lib/preferences.dart', shape: 'enum', name: 'DistanceUnit' },
		],
	},
	{
		tableColumn: 'user_profiles.subscription_tier',
		ts: [{ file: TYPES, shape: 'union', name: 'SubscriptionTier' }],
		dart: [],
	},
	{
		tableColumn: 'club_members.role',
		ts: [{ file: TYPES, shape: 'union', name: 'ClubRole' }],
		dart: [],
	},
	{
		tableColumn: 'club_members.status',
		ts: [{ file: TYPES, shape: 'union', name: 'MembershipStatus' }],
		dart: [],
	},
	{
		tableColumn: 'clubs.join_policy',
		ts: [{ file: TYPES, shape: 'union', name: 'JoinPolicy' }],
		dart: [],
	},
	{
		tableColumn: 'coach_athletes.status',
		ts: [{ file: TYPES, shape: 'union', name: 'CoachAthleteStatus' }],
		dart: [],
	},
	{
		tableColumn: 'training_plans.status',
		ts: [{ file: TYPES, shape: 'union', name: 'PlanStatus' }],
		dart: [],
	},
	{
		tableColumn: 'events.recurrence_freq',
		ts: [{ file: TYPES, shape: 'union', name: 'RecurrenceFreq' }],
		dart: [
			{ file: 'apps/mobile_android/lib/recurrence.dart', shape: 'enum', name: 'RecurrenceFreq' },
		],
	},
	{
		tableColumn: 'events.category',
		ts: [
			{ file: TYPES, shape: 'union', name: 'EventCategory' },
			{
				file: 'apps/web/src/lib/social/event_category.ts',
				shape: 'list',
				name: 'EVENT_CATEGORIES',
			},
		],
		dart: [
			{
				file: 'apps/mobile_android/lib/event_category.dart',
				shape: 'list',
				name: 'kEventCategories',
			},
		],
	},
	{
		tableColumn: 'event_attendees.status',
		ts: [{ file: TYPES, shape: 'union', name: 'RsvpStatus' }],
		dart: [],
	},
	{
		tableColumn: 'event_attendees.attendance',
		ts: [{ file: TYPES, shape: 'union', name: 'EventAttendance' }],
		dart: [],
	},
	{
		tableColumn: 'notifications.kind',
		ts: [{ file: TYPES, shape: 'union', name: 'NotificationKind' }],
		dart: [],
	},
	{
		tableColumn: 'event_orders.status',
		ts: [{ file: TYPES, shape: 'union', name: 'OrderStatus' }],
		dart: [],
	},
	{
		tableColumn: 'event_pricing.refund_policy',
		ts: [{ file: TYPES, shape: 'union', name: 'RefundPolicy' }],
		dart: [],
	},
	{
		tableColumn: 'event_pricing.modality',
		ts: [{ file: TYPES, shape: 'union', name: 'EventModality' }],
		dart: [],
	},
	{
		tableColumn: 'fundraisers.status',
		ts: [{ file: TYPES, shape: 'union', name: 'FundraiserStatus' }],
		dart: [],
	},
	{
		tableColumn: 'donations.status',
		ts: [{ file: TYPES, shape: 'union', name: 'DonationStatus' }],
		dart: [],
	},
	{
		tableColumn: 'session_plan_items.kind',
		ts: [
			{ file: TYPES, shape: 'union', name: 'SessionItemKind' },
			{ file: 'apps/web/src/lib/social/session_steps.ts', shape: 'union', name: 'SessionItemKind' },
		],
		dart: [
			{
				file: 'apps/mobile_android/lib/session_steps.dart',
				shape: 'enum',
				name: 'SessionItemKind',
			},
		],
	},
	{
		tableColumn: 'gym_routines.periodisation',
		ts: [{ file: TYPES, shape: 'union', name: 'GymPeriodisation' }],
		dart: [],
	},
	{
		tableColumn: 'gym_routine_exercises.modality',
		ts: [{ file: TYPES, shape: 'union', name: 'GymExerciseModality' }],
		dart: [
			{
				file: 'apps/mobile_android/lib/widgets/routine_builder_sheet.dart',
				shape: 'list',
				name: '_modalities',
			},
		],
	},
	{
		tableColumn: 'exercises.modality',
		ts: [{ file: TYPES, shape: 'union', name: 'GymExerciseModality' }],
		dart: [
			{
				file: 'apps/mobile_android/lib/widgets/routine_builder_sheet.dart',
				shape: 'list',
				name: '_modalities',
			},
		],
	},
	{
		tableColumn: 'gym_routine_exercises.progression',
		ts: [
			{ file: TYPES, shape: 'union', name: 'GymProgressionScheme' },
			{ file: 'apps/web/src/lib/gym/gym_progression.ts', shape: 'union', name: 'ProgressionScheme' },
		],
		dart: [
			{
				file: 'apps/mobile_android/lib/gym_progression.dart',
				shape: 'enum',
				name: 'ProgressionScheme',
			},
			{
				file: 'apps/mobile_android/lib/widgets/routine_builder_sheet.dart',
				shape: 'list',
				name: '_schemes',
			},
		],
	},
	{
		tableColumn: 'gym_routine_sets.set_type',
		ts: [{ file: TYPES, shape: 'union', name: 'GymSetType' }],
		dart: [
			{
				file: 'apps/mobile_android/lib/widgets/routine_builder_sheet.dart',
				shape: 'list',
				name: '_setTypes',
			},
			{
				file: 'apps/mobile_android/lib/widgets/gym_compose_sheet.dart',
				shape: 'list',
				name: '_gymSetTypes',
			},
		],
	},
	{
		tableColumn: 'gym_sets.set_type',
		ts: [{ file: TYPES, shape: 'union', name: 'GymSetType' }],
		dart: [
			{
				file: 'apps/mobile_android/lib/widgets/gym_compose_sheet.dart',
				shape: 'list',
				name: '_gymSetTypes',
			},
		],
	},
	{
		tableColumn: 'exercises.category',
		ts: [{ file: TYPES, shape: 'union', name: 'ExerciseCategory' }],
		dart: [
			{
				file: 'apps/mobile_android/lib/widgets/exercise_catalogue_picker.dart',
				shape: 'list',
				name: '_kCategories',
			},
		],
	},
	{
		tableColumn: 'reports.target_kind',
		ts: [{ file: TYPES, shape: 'union', name: 'ReportTargetKind' }],
		dart: [],
	},
	{
		tableColumn: 'public_recaps.period_kind',
		ts: [{ file: TYPES, shape: 'union', name: 'RecapPeriodKind' }],
		dart: [
			{ file: 'apps/mobile_android/lib/screens/recap_screen.dart', shape: 'enum', name: 'RecapPeriod' },
		],
	},
	{
		tableColumn: 'achievements.tier',
		ts: [
			{ file: TYPES, shape: 'union', name: 'AchievementTier' },
			{ file: 'apps/web/src/lib/social/badges.ts', shape: 'list', name: 'TIER_ORDER' },
		],
		dart: [{ file: 'apps/mobile_android/lib/badges.dart', shape: 'list', name: 'kTierOrder' }],
	},
	{
		tableColumn: 'achievements.source_kind',
		ts: [{ file: TYPES, shape: 'union', name: 'AchievementSourceKind' }],
		dart: [],
	},
	{
		tableColumn: 'challenges.metric',
		ts: [
			{ file: TYPES, shape: 'union', name: 'ChallengeMetric' },
			{
				file: 'apps/web/src/lib/social/challenge_progress.ts',
				shape: 'union',
				name: 'ChallengeMetric',
			},
		],
		dart: [
			{
				file: 'apps/mobile_android/lib/challenge_progress.dart',
				shape: 'enum',
				name: 'ChallengeMetric',
			},
			{
				file: 'apps/mobile_android/lib/widgets/challenge_form_sheet.dart',
				shape: 'list',
				name: 'kChallengeMetrics',
			},
		],
	},
	{
		tableColumn: 'challenges.scope',
		ts: [{ file: TYPES, shape: 'union', name: 'ChallengeScope' }],
		dart: [
			{
				file: 'apps/mobile_android/lib/widgets/challenge_form_sheet.dart',
				shape: 'list',
				name: 'kChallengeScopes',
			},
		],
	},
	{
		tableColumn: 'race_listings.provider',
		ts: [{ file: TYPES, shape: 'union', name: 'RaceProvider' }],
		dart: [],
	},

	// ── Reachable only since § 791 widened the guard past `types.ts` ──

	{
		tableColumn: 'data_export_jobs.status',
		ts: [
			{
				file: 'apps/web/src/lib/backup/cloud_export_helpers.ts',
				shape: 'union',
				name: 'CloudExportJobStatus',
				extra: ['none', 'stalled'],
			},
			{
				file: 'apps/web/src/lib/backup/cloud_export_helpers.ts',
				shape: 'list',
				name: 'KNOWN_JOB_STATUSES',
				extra: ['none', 'stalled'],
			},
		],
		dart: [
			{
				file: 'apps/mobile_android/lib/export_job.dart',
				shape: 'enum',
				name: 'ExportJobStatus',
				extra: ['none', 'stalled'],
			},
			{
				file: 'apps/mobile_android/lib/export_job.dart',
				shape: 'keys',
				name: '_statusTokens',
				extra: ['none', 'stalled'],
			},
		],
	},
	{
		tableColumn: 'data_export_jobs.format',
		ts: [
			{
				file: 'apps/web/src/lib/backup/cloud_export_helpers.ts',
				shape: 'union',
				name: 'CloudExportFormat',
			},
		],
		dart: [],
	},
	{
		tableColumn: 'gear.kind',
		ts: [{ file: DATA, shape: 'union', name: 'GearKind' }],
		dart: [],
	},
	{
		tableColumn: 'gear_wear_logs.area',
		ts: [
			{ file: DATA, shape: 'union', name: 'GearWearArea' },
			{
				file: 'apps/web/src/routes/settings/gear/+page.svelte',
				shape: 'list',
				name: 'WEAR_AREAS',
			},
		],
		dart: [
			{
				file: 'apps/mobile_android/lib/widgets/gear_form_sheet.dart',
				shape: 'list',
				name: '_wearAreas',
			},
		],
	},
	{
		tableColumn: 'food_log.meal_slot',
		ts: [
			{ file: DATA, shape: 'union', name: 'MealSlot' },
			{ file: 'apps/web/src/lib/nutrition/nutrition_totals.ts', shape: 'union', name: 'MealSlot' },
			{ file: 'apps/web/src/lib/nutrition/nutrition_totals.ts', shape: 'list', name: 'MEAL_SLOTS' },
		],
		dart: [
			{ file: 'apps/mobile_android/lib/nutrition_totals.dart', shape: 'list', name: 'mealSlots' },
		],
	},
	{
		tableColumn: 'meal_templates.meal_slot',
		ts: [
			{ file: 'apps/web/src/lib/nutrition/meal_template.ts', shape: 'union', name: 'MealSlot' },
			{ file: 'apps/web/src/lib/nutrition/meal_template.ts', shape: 'list', name: 'SLOTS' },
		],
		dart: [{ file: 'apps/mobile_android/lib/meal_template.dart', shape: 'list', name: '_slots' }],
	},
	{
		tableColumn: 'meal_template_items.meal_slot',
		ts: [{ file: 'apps/web/src/lib/nutrition/meal_template.ts', shape: 'union', name: 'MealSlot' }],
		dart: [{ file: 'apps/mobile_android/lib/meal_template.dart', shape: 'list', name: '_slots' }],
	},
	{
		tableColumn: 'recipes.meal_slot',
		ts: [
			{ file: 'apps/web/src/lib/nutrition/recipe.ts', shape: 'union', name: 'MealSlot' },
			{ file: 'apps/web/src/lib/nutrition/recipe.ts', shape: 'list', name: 'SLOTS' },
		],
		dart: [{ file: 'apps/mobile_android/lib/recipe.dart', shape: 'list', name: '_slots' }],
	},
	{
		tableColumn: 'run_matched_tracks.status',
		ts: [{ file: DATA, shape: 'union', name: 'MatchStatus' }],
		dart: [
			{
				file: 'packages/core_models/lib/src/run_match_info.dart',
				shape: 'enum',
				name: 'MatchStatus',
			},
		],
	},
	{
		tableColumn: 'reports.reason',
		ts: [{ file: DATA, shape: 'union', name: 'ReportReason' }],
		dart: [
			{
				file: 'apps/mobile_android/lib/widgets/report_sheet.dart',
				shape: 'list',
				name: '_reasonKeys',
			},
		],
	},
	{
		tableColumn: 'personal_records.distance',
		ts: [
			{ file: DATA, shape: 'keys', name: 'order' },
			{
				file: 'apps/web/src/routes/dashboard/+page.svelte',
				shape: 'keys',
				name: 'PR_KEY_DISTANCE_M',
			},
		],
		dart: [
			{ file: 'apps/mobile_android/lib/run_stats.dart', shape: 'keys', name: '_pbBracketLabels' },
			{ file: 'apps/mobile_android/lib/run_stats.dart', shape: 'keys', name: '_pbBracketOrder' },
		],
	},
];

/**
 * Set-shaped CHECK columns no client enumerates, and why. Being on this list
 * is a claim, not an exemption: it says a reader looked and found no declared
 * client enumeration of this value set. If one is later written, move the
 * column to `PAIRS` — leaving it here re-creates exactly the § 641 hole.
 *
 * @type {Readonly<Record<string, string>>}
 */
export const UNENUMERATED = {
	'app_quota.window_kind': 'server-side quota bookkeeping; no client reads the column',
	'coach_messages.reaction': 'thumb up/down written as inline literals at the two call sites',
	'coach_messages.role': 'transcript role; the coach core types it structurally, not as a set',
	'deletion_audit_log.result': 'server-only erasure audit codes',
	'device_tokens.platform': 'each client writes its own platform; none enumerates the three',
	'email_suppressions.reason': 'server-only SMTP bounce/complaint bookkeeping',
	'event_result_claims.status': 'organiser moderation state; no client enumerates it',
	'event_results.finisher_status': 'no client enumerates it; read as a raw token per row',
	'fitness_snapshots.source': 'client/server provenance tag; written, never enumerated',
	'jobs.kind': 'server-only job queue; the allowlist lives in the migration and the worker',
	'jobs.status': 'server-only job queue lifecycle',
	'notifications.activity_kind': 'activities-view modality tag; no client declares the set',
	'race_sessions.status': 'race-director session lifecycle; no client enumerates it',
	'reports.status': 'moderation-side state; no client enumerates it',
	'training_plans.source': 'plan provenance tag; written, never enumerated',
};

/**
 * Walk a SQL file and emit `(table, column) -> values` for every set-shaped
 * `check (<col> in (...))` clause that is still LIVE at the end of the file —
 * including the nullable `check (<col> is null or <col> in (...))` form.
 *
 * "Still live" is the part that needs a replay rather than a scan. A constraint
 * dropped and immediately re-added (how every widening is written) must end up
 * at its new value set, and a column dropped outright must end up at nothing.
 * `runs.kind` is the case that proved it: 20261204_001 added it with a CHECK,
 * 20261206_001 dropped the column, and a walk that only ever adds reported a
 * live constraint on a column that no longer exists.
 *
 * @param {string} sql
 * @returns {Map<string, Set<string>>}
 */
export function parseChecks(sql) {
	// Comments removed by the lexer, literals kept whole: the values this
	// script reads ARE literals, so blanking them would empty every set.
	const stripped = splitSqlStatements(sql).join(';');

	const tableRe =
		/\b(?:create\s+table|alter\s+table)\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-z_][a-z0-9_]*)/gi;
	const checkRe =
		/(?:constraint\s+([a-z_][a-z0-9_]*)\s+)?check\s*\(\s*(?:[a-z_][a-z0-9_]*\s+is\s+null\s+or\s+)?([a-z_][a-z0-9_]*)\s+in\s*\(([^)]*)\)\s*\)/gi;
	const dropColumnRe = /\bdrop\s+column\s+(?:if\s+exists\s+)?([a-z_][a-z0-9_]*)/gi;
	const dropConstraintRe = /\bdrop\s+constraint\s+(?:if\s+exists\s+)?([a-z_][a-z0-9_]*)/gi;

	/**
	 * @type {({ kind: 'table', index: number, table: string }
	 *   | { kind: 'check', index: number, constraint: string | undefined, column: string, valuesRaw: string }
	 *   | { kind: 'dropColumn', index: number, column: string }
	 *   | { kind: 'dropConstraint', index: number, constraint: string })[]}
	 */
	const hits = [];
	/** @type {RegExpExecArray | null} */
	let m;
	while ((m = tableRe.exec(stripped)) !== null)
		hits.push({ kind: 'table', index: m.index, table: m[1].toLowerCase() });
	while ((m = checkRe.exec(stripped)) !== null)
		hits.push({
			kind: 'check',
			index: m.index,
			constraint: m[1]?.toLowerCase(),
			column: m[2].toLowerCase(),
			valuesRaw: m[3],
		});
	while ((m = dropColumnRe.exec(stripped)) !== null)
		hits.push({ kind: 'dropColumn', index: m.index, column: m[1].toLowerCase() });
	while ((m = dropConstraintRe.exec(stripped)) !== null)
		hits.push({ kind: 'dropConstraint', index: m.index, constraint: m[1].toLowerCase() });
	hits.sort((a, b) => a.index - b.index);

	/** @type {Map<string, Set<string>>} */
	const out = new Map();
	/** @type {Map<string, string>} */
	const definedBy = new Map();
	/** @type {string | null} */
	let currentTable = null;
	for (const h of hits) {
		if (h.kind === 'table') {
			currentTable = h.table;
			continue;
		}
		if (!currentTable) continue;
		if (h.kind === 'dropColumn') {
			out.delete(`${currentTable}.${h.column}`);
			continue;
		}
		if (h.kind === 'dropConstraint') {
			const key = definedBy.get(h.constraint);
			if (key !== undefined) {
				out.delete(key);
				definedBy.delete(h.constraint);
			}
			continue;
		}
		const values = new Set();
		const valueRe = /'([^']*)'/g;
		let v;
		while ((v = valueRe.exec(h.valuesRaw)) !== null) values.add(v[1]);
		const key = `${currentTable}.${h.column}`;
		out.set(key, values);
		if (h.constraint !== undefined) definedBy.set(h.constraint, key);
	}
	return out;
}

/** @returns {Map<string, Set<string>>} */
export function loadAllMigrationChecks() {
	/** @type {Map<string, Set<string>>} */
	const merged = new Map();
	/** @type {Set<string>} */
	const dropped = new Set();
	const files = readdirSync(MIGRATIONS_DIR)
		.filter((f) => f.endsWith('.sql'))
		.sort();
	for (const f of files) {
		const sql = readFileSync(join(MIGRATIONS_DIR, f), 'utf-8');
		let local;
		try {
			local = parseChecks(sql);
		} catch (err) {
			// SQL the lexer cannot read is SQL this guard must not report a
			// verdict about — say which file, rather than skipping it.
			throw new Error(`${f}: ${err instanceof Error ? err.message : String(err)}`);
		}
		// A migration that drops a column says nothing about it afterwards, so
		// the absence has to be carried forward across files explicitly.
		for (const key of droppedColumnsIn(sql)) {
			dropped.add(key);
			merged.delete(key);
		}
		for (const [key, values] of local) {
			dropped.delete(key);
			merged.set(key, values);
		}
	}
	return merged;
}

/**
 * The `<table>.<column>` keys a single migration drops outright.
 *
 * Same ordered walk `parseChecks` uses — a `drop column` belongs to whichever
 * `alter table` header most recently preceded it, which no span regex can be
 * told without also being told where a statement ends. The last statement in a
 * file need not carry a trailing semicolon, and `runs.kind`'s drop is exactly
 * that statement.
 *
 * @param {string} sql
 * @returns {string[]}
 */
export function droppedColumnsIn(sql) {
	const stripped = splitSqlStatements(sql).join(';');
	const tableRe =
		/\b(?:create\s+table|alter\s+table)\s+(?:if\s+not\s+exists\s+)?(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?([a-z_][a-z0-9_]*)/gi;
	const dropRe = /\bdrop\s+column\s+(?:if\s+exists\s+)?([a-z_][a-z0-9_]*)/gi;

	/** @type {({ index: number, table: string } | { index: number, column: string })[]} */
	const hits = [];
	/** @type {RegExpExecArray | null} */
	let m;
	while ((m = tableRe.exec(stripped)) !== null)
		hits.push({ index: m.index, table: m[1].toLowerCase() });
	while ((m = dropRe.exec(stripped)) !== null)
		hits.push({ index: m.index, column: m[1].toLowerCase() });
	hits.sort((a, b) => a.index - b.index);

	/** @type {string[]} */
	const out = [];
	/** @type {string | null} */
	let currentTable = null;
	for (const h of hits) {
		if ('table' in h) currentTable = h.table;
		else if (currentTable) out.push(`${currentTable}.${h.column}`);
	}
	return out;
}

/**
 * @param {Set<string>} a
 * @param {Set<string>} b
 */
function diff(a, b) {
	return {
		onlyA: [...a].filter((x) => !b.has(x)),
		onlyB: [...b].filter((x) => !a.has(x)),
	};
}

/**
 * Compare every registered client enumeration against its CHECK.
 *
 * @param {Map<string, Set<string>>} checks
 * @param {(relPath: string) => string} readSource
 * @param {readonly { tableColumn: string, ts: readonly ClientEnum[], dart: readonly ClientEnum[] }[]} [pairs]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function audit(checks, readSource, pairs = PAIRS) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];

	if (pairs.length === 0) {
		errors.push(
			'the PAIRS list is empty, so this guard compares nothing. Either the narrow ' +
				'unions were retired — in which case delete this script with them — or the ' +
				'list was lost.',
		);
		return { errors, ok };
	}

	for (const pair of pairs) {
		const checkValues = checks.get(pair.tableColumn);
		if (!checkValues) {
			errors.push(
				`no live CHECK constraint on "${pair.tableColumn}" in the migrations — ` +
					`remove the entry from PAIRS, or restore the constraint.`,
			);
			continue;
		}
		if (pair.ts.length === 0 && pair.dart.length === 0) {
			errors.push(
				`${pair.tableColumn} is in PAIRS with no client enumeration on either rail. ` +
					`Move it to UNENUMERATED with a reason, or name the declaration.`,
			);
			continue;
		}

		for (const [rail, decls] of /** @type {const} */ ([
			['TS', pair.ts],
			['Dart', pair.dart],
		])) {
			for (const decl of decls) {
				let src;
				try {
					src = readSource(decl.file);
				} catch {
					errors.push(`${pair.tableColumn} [${rail}]: cannot read ${decl.file}.`);
					continue;
				}
				let values;
				try {
					values = extractClientEnum(src, decl);
				} catch (err) {
					errors.push(
						`${pair.tableColumn} [${rail}]: ${decl.file}#${decl.name} — ` +
							`${err instanceof Error ? err.message : String(err)}`,
					);
					continue;
				}
				if (!values) {
					errors.push(
						`${pair.tableColumn} [${rail}]: no ${decl.shape} named "${decl.name}" in ${decl.file}.`,
					);
					continue;
				}
				const expected = new Set([...checkValues, ...(decl.extra ?? [])]);
				const { onlyA: missingFromClient, onlyB: notInCheck } = diff(expected, values);
				if (missingFromClient.length || notInCheck.length) {
					errors.push(
						`${pair.tableColumn} [${rail}] drift in ${decl.file}#${decl.name}:\n` +
							`  in the CHECK but not the client: ${missingFromClient.join(', ') || '(none)'}\n` +
							`  in the client but not the CHECK: ${notInCheck.join(', ') || '(none)'}\n` +
							`  Fix: update the migration AND every client enumeration together. A value the\n` +
							`  client alone carries needs an \`extra: [...]\` on the entry to be legitimate.`,
					);
					continue;
				}
				ok.push(
					`${pair.tableColumn} [${rail}] ${decl.file}#${decl.name}: ${[...values].sort().join(', ')}`,
				);
			}
		}
	}

	return { errors, ok };
}

/**
 * Every live set-shaped CHECK column must be filed exactly once — as a pair or
 * as deliberately unenumerated — and nothing may be filed that no longer
 * exists. Derived from the migrations, so a new constraint is never invisible.
 *
 * @param {Map<string, Set<string>>} checks
 * @param {readonly { tableColumn: string }[]} [pairs]
 * @param {Readonly<Record<string, string>>} [unenumerated]
 * @returns {string[]}
 */
export function auditCoverage(checks, pairs = PAIRS, unenumerated = UNENUMERATED) {
	/** @type {string[]} */
	const errors = [];
	const paired = new Set(pairs.map((p) => p.tableColumn));
	const excused = new Set(Object.keys(unenumerated));

	for (const key of excused) {
		if (paired.has(key))
			errors.push(`${key} is filed BOTH in PAIRS and in UNENUMERATED; it must be one or the other.`);
	}
	for (const key of [...checks.keys()].sort()) {
		if (!paired.has(key) && !excused.has(key))
			errors.push(
				`${key} has a set-shaped CHECK constraint that nothing accounts for. Add it to ` +
					`PAIRS naming the client enumerations of its value set, or to UNENUMERATED ` +
					`with the reason no client enumerates it.`,
			);
	}
	for (const key of [...excused].sort()) {
		if (!checks.has(key))
			errors.push(`${key} is in UNENUMERATED but has no live CHECK constraint; delete the entry.`);
	}
	return errors;
}

function main() {
	const checks = loadAllMigrationChecks();
	/** @param {string} rel */
	const readSource = (rel) => readFileSync(join(REPO_ROOT, rel), 'utf-8');

	const { errors, ok } = audit(checks, readSource);
	const coverage = auditCoverage(checks);

	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of coverage) console.error(`[FAIL] coverage: ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);
	console.log(
		`[INFO] ${checks.size} live set-shaped CHECK columns; ` +
			`${PAIRS.length} paired, ${Object.keys(UNENUMERATED).length} unenumerated; ` +
			`${ok.length} client enumerations verified.`,
	);
	return errors.length + coverage.length > 0 ? 1 : 0;
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit(main());
