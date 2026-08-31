// Guardrail: verify every set-shaped CHECK constraint in the Supabase
// migrations matches every client vocabulary that enumerates the same values —
// TypeScript unions and const arrays on web, enums and const lists in the
// Flutter tree.
//
// Why this exists: Supabase's gen-types pass doesn't read CHECK constraints,
// so the narrow unions on both clients are hand-maintained. If a migration
// adds a new value to the CHECK and nobody updates a client (or vice versa),
// one client can write a value the other rejects (postgres 23514
// `check_violation`) and we don't notice until production. The April 2026
// cross-client audit caught this happening with `runsignup` — the
// IntegrationProvider TS union had it, the CHECK constraint didn't.
//
// Two things this guard did NOT read until § 791, and both were load-bearing.
// It opened `src/lib/types.ts` and nothing else, so a vocabulary living in
// `core/data.ts`, in a `.svelte` option list or in a feature module was
// invisible; and it named no Dart path at all, so a widened CHECK failed only
// the web union while the mobile dropdown silently lacked the value. The
// registry below therefore keys on the COLUMN, not on a union name, and each
// entry lists every client rail that enumerates it.
//
// The registry is also the coverage obligation: `audit` fails when a
// set-shaped CHECK column in the migrations has no entry here, and when an
// entry names a column no live migration defines. A column with no client
// vocabulary is registered with an empty `clients` list and a `note` saying
// why — the decision is recorded, not skipped. That is what makes a NEW
// CHECK column fail this guard until someone has looked at it, instead of
// passing silently the way 26 of them did before § 791.
//
// The migrations are read through the Postgres statement lexer in
// `apps/backend/scripts/sql_lex.mjs` rather than a regex strip. Eating `--` to
// end of line before knowing whether it is a comment is wrong in two
// directions at once, and both were live here: a `--` inside a string literal
// deletes the rest of that line, which can be the `check (col in (…))` clause
// this script exists to read (reported as "no CHECK constraint found" — a
// false accusation), or the `alter table <t>` header that says which table the
// NEXT line's clause belongs to (the clause is then filed under the previous
// table, so one registered pair is certified against another table's
// constraint). § 770 built the lexer for exactly this defect one directory
// over; decisions § 774.
//
// Run: `npm run check:check-constraints --workspace=apps/web`
// CI:  invoked from the parity-types job alongside gen:types:check.
// Unit tests: `node --test apps/web/scripts/check_constraint_unions.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { splitSqlStatements } from '../../backend/scripts/sql_lex.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = join(__dirname, '..', '..', '..');
export const MIGRATIONS_DIR = join(REPO_ROOT, 'apps/backend/supabase/migrations');
export const TYPES_FILE = join(REPO_ROOT, 'apps/web/src/lib/types.ts');
export const DB_TYPES_FILE = 'apps/web/src/lib/database.types.ts';

const TS_TYPES = 'apps/web/src/lib/types.ts';
const DATA_TS = 'apps/web/src/lib/core/data.ts';

// Shapes a client rail can take. Declared, never inferred: a declaration that
// changes shape should fail loudly rather than be re-read as something else.
//   union    — `type X = 'a' | 'b';`                      (TS only)
//   strings  — `const X = ['a', 'b'];`                    (both)
//   keys     — `const X = { a: …, b: … };` object keys    (both)
//   records  — `const X = [{ f: 'a' }, …];` + `field`     (both)
//   enum     — `enum X { a, bCd }` → a, b_cd              (Dart only)
export const SHAPES = ['union', 'strings', 'keys', 'records', 'enum'];

// Each entry is one set-shaped CHECK column and every client vocabulary that
// enumerates it. `clients: []` + `note` records a column no client spells out.
//
// A rail may declare `allowExtra` (values the client carries that the column
// does not) or `allowMissing` (column values the client deliberately omits).
// Both are checked for staleness: an exemption that no longer applies is an
// error, so a tolerated delta cannot quietly widen into an untolerated one.
//
// Dart rails name the `mobile_android` path only. `lib/` is byte-identical to
// `mobile_ios` (decisions § 39) and the twin-parity guard enforces that, so a
// second path here would be a copy of a copy.
export const PAIRS = [
	{
		tableColumn: 'achievements.source_kind',
		clients: [{ file: TS_TYPES, decl: 'AchievementSourceKind', shape: 'union' }],
	},
	{
		tableColumn: 'achievements.tier',
		clients: [
			{ file: TS_TYPES, decl: 'AchievementTier', shape: 'union' },
			{ file: 'apps/web/src/lib/social/badges.ts', decl: 'TIER_ORDER', shape: 'strings' },
			{ file: 'apps/mobile_android/lib/badges.dart', decl: 'kTierOrder', shape: 'strings' },
		],
	},
	{
		tableColumn: 'app_quota.window_kind',
		clients: [],
		note: 'server-side quota bookkeeping; the two values are written by SQL and never named by a client.',
	},
	{
		tableColumn: 'challenges.activity_type',
		clients: [
			{ file: TS_TYPES, decl: 'ActivityType', shape: 'union' },
			{ file: 'apps/web/src/lib/runs/activity_type.ts', decl: 'ACTIVITY_TYPES', shape: 'strings' },
			{ file: 'apps/mobile_android/lib/preferences.dart', decl: 'ActivityType', shape: 'enum' },
		],
	},
	{
		tableColumn: 'challenges.metric',
		clients: [
			{ file: TS_TYPES, decl: 'ChallengeMetric', shape: 'union' },
			{
				file: 'apps/web/src/lib/social/challenge_progress.ts',
				decl: 'ChallengeMetric',
				shape: 'union',
			},
			{
				file: 'apps/mobile_android/lib/challenge_progress.dart',
				decl: 'ChallengeMetric',
				shape: 'enum',
			},
			{
				file: 'apps/mobile_android/lib/widgets/challenge_form_sheet.dart',
				decl: 'kChallengeMetrics',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'challenges.scope',
		clients: [
			{ file: TS_TYPES, decl: 'ChallengeScope', shape: 'union' },
			{
				file: 'apps/mobile_android/lib/widgets/challenge_form_sheet.dart',
				decl: 'kChallengeScopes',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'club_members.role',
		clients: [{ file: TS_TYPES, decl: 'ClubRole', shape: 'union' }],
	},
	{
		tableColumn: 'club_members.status',
		clients: [{ file: TS_TYPES, decl: 'MembershipStatus', shape: 'union' }],
	},
	{
		tableColumn: 'clubs.join_policy',
		clients: [{ file: TS_TYPES, decl: 'JoinPolicy', shape: 'union' }],
	},
	{
		tableColumn: 'coach_athletes.status',
		clients: [{ file: TS_TYPES, decl: 'CoachAthleteStatus', shape: 'union' }],
	},
	{
		tableColumn: 'coach_messages.reaction',
		clients: [],
		note: 'the thumb up/down control writes the two literals inline; there is no named vocabulary to read.',
	},
	{
		tableColumn: 'coach_messages.role',
		clients: [{ file: 'apps/web/src/lib/coach/types.ts', decl: 'CoachMessageRole', shape: 'union' }],
	},
	{
		tableColumn: 'data_export_jobs.format',
		clients: [
			{
				file: 'apps/web/src/lib/backup/cloud_export_helpers.ts',
				decl: 'CloudExportFormat',
				shape: 'union',
			},
		],
	},
	{
		tableColumn: 'data_export_jobs.status',
		// `none` (no job on record) and `stalled` (a running job past its own
		// deadline) are CLIENT states, not column values — the row cannot hold
		// either. Both clients carry the same two, and the exemption is checked
		// for staleness, so a THIRD client-only status still fails here.
		clients: [
			{
				file: 'apps/web/src/lib/backup/cloud_export_helpers.ts',
				decl: 'CloudExportJobStatus',
				shape: 'union',
				allowExtra: ['none', 'stalled'],
			},
			{
				file: 'apps/web/src/lib/backup/cloud_export_helpers.ts',
				decl: 'KNOWN_JOB_STATUSES',
				shape: 'strings',
				allowExtra: ['none', 'stalled'],
			},
			{
				file: 'apps/mobile_android/lib/export_job.dart',
				decl: 'ExportJobStatus',
				shape: 'enum',
				allowExtra: ['none', 'stalled'],
			},
			{
				file: 'apps/mobile_android/lib/export_job.dart',
				decl: '_statusTokens',
				shape: 'keys',
				allowExtra: ['none', 'stalled'],
			},
		],
	},
	{
		tableColumn: 'deletion_audit_log.result',
		clients: [],
		note: 'per-stage erasure outcome written only by the delete-account SQL; no client reads or enumerates it.',
	},
	{
		tableColumn: 'device_tokens.platform',
		clients: [],
		note: 'each client writes its own single literal at registration; none enumerates the other two.',
	},
	{
		tableColumn: 'donations.status',
		clients: [{ file: TS_TYPES, decl: 'DonationStatus', shape: 'union' }],
	},
	{
		tableColumn: 'email_suppressions.reason',
		clients: [],
		note: 'written by the bounce/complaint webhook and the unsubscribe RPC; no client surface enumerates it.',
	},
	{
		tableColumn: 'event_attendees.attendance',
		clients: [{ file: TS_TYPES, decl: 'EventAttendance', shape: 'union' }],
	},
	{
		tableColumn: 'event_attendees.status',
		clients: [{ file: TS_TYPES, decl: 'RsvpStatus', shape: 'union' }],
	},
	{
		tableColumn: 'event_orders.status',
		clients: [{ file: TS_TYPES, decl: 'OrderStatus', shape: 'union' }],
	},
	{
		tableColumn: 'event_pricing.modality',
		clients: [{ file: TS_TYPES, decl: 'EventModality', shape: 'union' }],
	},
	{
		tableColumn: 'event_pricing.refund_policy',
		clients: [{ file: TS_TYPES, decl: 'RefundPolicy', shape: 'union' }],
	},
	{
		tableColumn: 'event_result_claims.status',
		clients: [],
		note: 'the organiser approve/reject buttons write their literal inline; no named vocabulary on either client.',
	},
	{
		tableColumn: 'event_results.finisher_status',
		clients: [{ file: TS_TYPES, decl: 'FinisherStatus', shape: 'union' }],
	},
	{
		tableColumn: 'events.category',
		clients: [
			{ file: TS_TYPES, decl: 'EventCategory', shape: 'union' },
			{
				file: 'apps/web/src/lib/social/event_category.ts',
				decl: 'EVENT_CATEGORIES',
				shape: 'strings',
			},
			{
				file: 'apps/mobile_android/lib/event_category.dart',
				decl: 'kEventCategories',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'events.recurrence_freq',
		clients: [
			{ file: TS_TYPES, decl: 'RecurrenceFreq', shape: 'union' },
			{ file: 'apps/mobile_android/lib/recurrence.dart', decl: 'RecurrenceFreq', shape: 'enum' },
		],
	},
	{
		tableColumn: 'exercises.category',
		clients: [
			{ file: TS_TYPES, decl: 'ExerciseCategory', shape: 'union' },
			{
				file: 'apps/web/src/lib/components/ExerciseCataloguePicker.svelte',
				decl: 'CATEGORIES',
				shape: 'strings',
			},
			{
				file: 'apps/mobile_android/lib/widgets/exercise_catalogue_picker.dart',
				decl: '_kCategories',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'exercises.modality',
		clients: [
			{ file: TS_TYPES, decl: 'GymExerciseModality', shape: 'union' },
			{
				file: 'apps/web/src/lib/components/RoutineEditor.svelte',
				decl: 'MODALITIES',
				shape: 'strings',
			},
			{
				file: 'apps/mobile_android/lib/widgets/routine_builder_sheet.dart',
				decl: '_modalities',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'fitness_snapshots.source',
		clients: [],
		note: 'each writer stamps its own side; neither client enumerates the pair.',
	},
	{
		tableColumn: 'food_log.meal_slot',
		clients: [
			{ file: DATA_TS, decl: 'MealSlot', shape: 'union' },
			{
				file: 'apps/web/src/lib/nutrition/nutrition_totals.ts',
				decl: 'MealSlot',
				shape: 'union',
			},
			{
				file: 'apps/web/src/lib/nutrition/nutrition_totals.ts',
				decl: 'MEAL_SLOTS',
				shape: 'strings',
			},
			{ file: 'apps/web/src/lib/nutrition/meal_template.ts', decl: 'MealSlot', shape: 'union' },
			{ file: 'apps/web/src/lib/nutrition/meal_template.ts', decl: 'SLOTS', shape: 'strings' },
			{ file: 'apps/web/src/lib/nutrition/recipe.ts', decl: 'MealSlot', shape: 'union' },
			{ file: 'apps/web/src/lib/nutrition/recipe.ts', decl: 'SLOTS', shape: 'strings' },
			{ file: 'apps/mobile_android/lib/nutrition_totals.dart', decl: 'mealSlots', shape: 'strings' },
			{ file: 'apps/mobile_android/lib/meal_template.dart', decl: '_slots', shape: 'strings' },
			{ file: 'apps/mobile_android/lib/recipe.dart', decl: '_slots', shape: 'strings' },
		],
	},
	{
		tableColumn: 'fundraisers.status',
		clients: [{ file: TS_TYPES, decl: 'FundraiserStatus', shape: 'union' }],
	},
	{
		tableColumn: 'gear.kind',
		clients: [{ file: DATA_TS, decl: 'GearKind', shape: 'union' }],
	},
	{
		tableColumn: 'gear_wear_logs.area',
		clients: [
			{ file: DATA_TS, decl: 'GearWearArea', shape: 'union' },
			{
				file: 'apps/web/src/routes/settings/gear/+page.svelte',
				decl: 'WEAR_AREAS',
				shape: 'strings',
			},
			{
				file: 'apps/mobile_android/lib/widgets/gear_form_sheet.dart',
				decl: '_wearAreas',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'gym_routine_exercises.modality',
		clients: [
			{ file: TS_TYPES, decl: 'GymExerciseModality', shape: 'union' },
			{
				file: 'apps/web/src/lib/components/RoutineEditor.svelte',
				decl: 'MODALITIES',
				shape: 'strings',
			},
			{
				file: 'apps/mobile_android/lib/widgets/routine_builder_sheet.dart',
				decl: '_modalities',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'gym_routine_exercises.progression',
		clients: [
			{ file: TS_TYPES, decl: 'GymProgressionScheme', shape: 'union' },
			{
				file: 'apps/web/src/lib/gym/gym_progression.ts',
				decl: 'ProgressionScheme',
				shape: 'union',
			},
			{ file: 'apps/web/src/lib/components/RoutineEditor.svelte', decl: 'SCHEMES', shape: 'strings' },
			{
				file: 'apps/mobile_android/lib/gym_progression.dart',
				decl: 'ProgressionScheme',
				shape: 'enum',
			},
			{
				file: 'apps/mobile_android/lib/widgets/routine_builder_sheet.dart',
				decl: '_schemes',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'gym_routine_sets.set_type',
		clients: [
			{ file: TS_TYPES, decl: 'GymSetType', shape: 'union' },
			{
				file: 'apps/web/src/lib/components/RoutineEditor.svelte',
				decl: 'SET_TYPES',
				shape: 'strings',
			},
			{
				file: 'apps/mobile_android/lib/widgets/routine_builder_sheet.dart',
				decl: '_setTypes',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'gym_routines.periodisation',
		clients: [{ file: TS_TYPES, decl: 'GymPeriodisation', shape: 'union' }],
	},
	{
		tableColumn: 'gym_sets.set_type',
		clients: [
			{ file: TS_TYPES, decl: 'GymSetType', shape: 'union' },
			{ file: 'apps/web/src/lib/components/GymEditor.svelte', decl: 'SET_TYPES', shape: 'strings' },
			{
				file: 'apps/mobile_android/lib/widgets/gym_compose_sheet.dart',
				decl: '_gymSetTypes',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'integrations.provider',
		clients: [{ file: TS_TYPES, decl: 'IntegrationProvider', shape: 'union' }],
	},
	{
		tableColumn: 'jobs.kind',
		clients: [],
		note: 'the queue vocabulary: enqueued by SQL triggers and drained by the Go worker and the Edge Functions, never enumerated by a client.',
	},
	{
		tableColumn: 'jobs.status',
		clients: [],
		note: 'queue lifecycle owned by the Go worker; no client surface enumerates it.',
	},
	{
		tableColumn: 'meal_template_items.meal_slot',
		clients: [
			{ file: DATA_TS, decl: 'MealSlot', shape: 'union' },
			{ file: 'apps/web/src/lib/nutrition/meal_template.ts', decl: 'MealSlot', shape: 'union' },
			{ file: 'apps/web/src/lib/nutrition/meal_template.ts', decl: 'SLOTS', shape: 'strings' },
			{ file: 'apps/mobile_android/lib/meal_template.dart', decl: '_slots', shape: 'strings' },
		],
	},
	{
		tableColumn: 'meal_templates.meal_slot',
		clients: [
			{ file: DATA_TS, decl: 'MealSlot', shape: 'union' },
			{ file: 'apps/web/src/lib/nutrition/meal_template.ts', decl: 'MealSlot', shape: 'union' },
			{ file: 'apps/mobile_android/lib/meal_template.dart', decl: '_slots', shape: 'strings' },
		],
	},
	{
		tableColumn: 'notifications.activity_kind',
		clients: [],
		note: 'stamped by the notify triggers from the activity that fired them; no client enumerates the three.',
	},
	{
		tableColumn: 'notifications.kind',
		clients: [{ file: TS_TYPES, decl: 'NotificationKind', shape: 'union' }],
	},
	{
		tableColumn: 'personal_records.distance',
		// The three maps are keyed `Record<string, …>` / `<String, …>`, so
		// neither compiler checks them: a new bracket sorts to the fallback
		// rank and renders its raw key. They are the only enumeration of this
		// column on either client.
		clients: [
			{ file: DATA_TS, decl: 'PR_BRACKET_LABELS', shape: 'keys' },
			{ file: DATA_TS, decl: 'PR_BRACKET_ORDER', shape: 'keys' },
			{
				file: 'apps/web/src/routes/dashboard/+page.svelte',
				decl: 'PR_KEY_DISTANCE_M',
				shape: 'keys',
			},
			{ file: 'apps/mobile_android/lib/run_stats.dart', decl: '_pbBracketLabels', shape: 'keys' },
			{ file: 'apps/mobile_android/lib/run_stats.dart', decl: '_pbBracketOrder', shape: 'keys' },
		],
	},
	{
		tableColumn: 'public_recaps.period_kind',
		clients: [
			{ file: TS_TYPES, decl: 'RecapPeriodKind', shape: 'union' },
			{
				file: 'apps/mobile_android/lib/screens/recap_screen.dart',
				decl: 'RecapPeriod',
				shape: 'enum',
			},
		],
	},
	{
		tableColumn: 'race_listings.provider',
		clients: [{ file: TS_TYPES, decl: 'RaceProvider', shape: 'union' }],
	},
	{
		tableColumn: 'race_sessions.status',
		clients: [{ file: TS_TYPES, decl: 'RaceSessionStatus', shape: 'union' }],
	},
	{
		tableColumn: 'recipes.meal_slot',
		clients: [
			{ file: DATA_TS, decl: 'MealSlot', shape: 'union' },
			{ file: 'apps/web/src/lib/nutrition/recipe.ts', decl: 'MealSlot', shape: 'union' },
			{ file: 'apps/mobile_android/lib/recipe.dart', decl: '_slots', shape: 'strings' },
		],
	},
	{
		tableColumn: 'reports.reason',
		clients: [
			{ file: DATA_TS, decl: 'ReportReason', shape: 'union' },
			{
				file: 'apps/web/src/lib/components/ReportDialog.svelte',
				decl: 'REASONS',
				shape: 'records',
				field: 'value',
			},
			{
				file: 'apps/mobile_android/lib/widgets/report_sheet.dart',
				decl: '_reasonKeys',
				shape: 'strings',
			},
		],
	},
	{
		// `pending` is the insert default every report starts at, and the
		// moderation queue only ever writes a RESOLUTION — so the vocabulary is
		// named for the half it can write rather than widened to a value the
		// resolve RPC would reject. The exemption is staleness-checked, so a
		// FOURTH status still fails here.
		tableColumn: 'reports.status',
		clients: [
			{ file: DATA_TS, decl: 'ReportResolution', shape: 'union', allowMissing: ['pending'] },
		],
	},
	{
		tableColumn: 'reports.target_kind',
		clients: [{ file: TS_TYPES, decl: 'ReportTargetKind', shape: 'union' }],
	},
	{
		tableColumn: 'route_conditions.condition',
		clients: [
			{ file: TS_TYPES, decl: 'RouteConditionKind', shape: 'union' },
			{
				file: 'apps/web/src/lib/components/RouteConditions.svelte',
				decl: 'CONDITION_KINDS',
				shape: 'strings',
			},
			{
				file: 'apps/mobile_android/lib/widgets/route_conditions.dart',
				decl: 'kRouteConditionKinds',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'route_conditions.severity',
		clients: [
			{ file: TS_TYPES, decl: 'RouteConditionSeverity', shape: 'union' },
			{
				file: 'apps/web/src/lib/components/RouteConditions.svelte',
				decl: 'SEVERITIES',
				shape: 'strings',
			},
			{
				file: 'apps/mobile_android/lib/widgets/route_conditions.dart',
				decl: 'kRouteConditionSeverities',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'route_markers.kind',
		clients: [
			{ file: TS_TYPES, decl: 'RouteMarkerKind', shape: 'union' },
			{
				file: 'apps/web/src/lib/routes/route_markers.ts',
				decl: 'ROUTE_MARKER_KINDS',
				shape: 'records',
				field: 'kind',
			},
			{
				file: 'apps/mobile_android/lib/route_markers.dart',
				decl: 'routeMarkerKinds',
				shape: 'records',
				field: 'kind',
			},
		],
	},
	{
		tableColumn: 'routes.surface',
		clients: [
			{ file: TS_TYPES, decl: 'RouteSurface', shape: 'union' },
			{
				file: 'apps/web/src/lib/routes/route_request/constraints.ts',
				decl: 'RouteRequestSurface',
				shape: 'union',
			},
			{
				file: 'apps/mobile_android/lib/catalogue_browse.dart',
				decl: 'kRouteSurfaceVocabulary',
				shape: 'strings',
			},
		],
	},
	{
		tableColumn: 'run_matched_tracks.status',
		clients: [{ file: DATA_TS, decl: 'MatchStatus', shape: 'union' }],
	},
	{
		tableColumn: 'runs.activity_type',
		clients: [
			{ file: TS_TYPES, decl: 'ActivityType', shape: 'union' },
			{ file: 'apps/web/src/lib/runs/activity_type.ts', decl: 'ACTIVITY_TYPES', shape: 'strings' },
			{ file: 'apps/mobile_android/lib/preferences.dart', decl: 'ActivityType', shape: 'enum' },
		],
	},
	{
		tableColumn: 'runs.source',
		clients: [
			{ file: TS_TYPES, decl: 'RunSource', shape: 'union' },
			{ file: 'apps/web/src/lib/runs/source_badge.ts', decl: 'RUN_SOURCES', shape: 'strings' },
		],
	},
	{
		tableColumn: 'session_plan_items.kind',
		clients: [
			{ file: TS_TYPES, decl: 'SessionItemKind', shape: 'union' },
			{
				file: 'apps/web/src/lib/social/session_steps.ts',
				decl: 'SessionItemKind',
				shape: 'union',
			},
			{
				file: 'apps/mobile_android/lib/session_steps.dart',
				decl: 'SessionItemKind',
				shape: 'enum',
			},
		],
	},
	{
		tableColumn: 'training_plans.source',
		clients: [],
		note: 'each creation path stamps its own literal (`generated` from the wizard, `manual` otherwise); no client enumerates the three.',
	},
	{
		tableColumn: 'training_plans.status',
		clients: [{ file: TS_TYPES, decl: 'PlanStatus', shape: 'union' }],
	},
	{
		tableColumn: 'user_profiles.gender',
		// The two feature-local copies are narrower on purpose: an age-grade or
		// a BMR formula has no coefficient for `prefer_not_to_say`, so those
		// take a nullable two-value input and the caller resolves the third to
		// null. `CalorieGender` and `TrainingGender` carry all three because
		// they are read straight off the profile row.
		clients: [
			{ file: TS_TYPES, decl: 'Gender', shape: 'union' },
			{ file: 'apps/web/src/lib/runs/calories.ts', decl: 'CalorieGender', shape: 'union' },
			{ file: 'apps/web/src/lib/training/training.ts', decl: 'TrainingGender', shape: 'union' },
		],
	},
	{
		tableColumn: 'user_profiles.preferred_unit',
		clients: [
			{ file: TS_TYPES, decl: 'PreferredUnit', shape: 'union' },
			{ file: 'apps/mobile_android/lib/preferences.dart', decl: 'DistanceUnit', shape: 'enum' },
		],
	},
	{
		tableColumn: 'user_profiles.subscription_tier',
		clients: [{ file: TS_TYPES, decl: 'SubscriptionTier', shape: 'union' }],
	},
];

// Walk a SQL file, track the "current table" set by `create table <t>` or
// `alter table <t>`, and emit `(table, column, values)` for every
// `check (<col> in (...))` clause encountered — including the nullable form
// `check (<col> is null or <col> in (...))`. Returns the LAST occurrence
// per `<table>.<column>` (later migrations win).
/**
 * @param {string} sql
 * @returns {Map<string, Set<string>>}
 */
export function parseChecks(sql) {
	/** @type {Map<string, Set<string>>} */
	const out = new Map();

	// Comments removed by the lexer, literals kept whole: the values this
	// script reads ARE literals, so blanking them would empty every set.
	const stripped = splitSqlStatements(sql).join(';');

	const tableRe = /\b(?:create\s+table|alter\s+table)\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-z_][a-z0-9_]*)/gi;
	const checkRe =
		/check\s*\(\s*(?:[a-z_][a-z0-9_]*\s+is\s+null\s+or\s+)?([a-z_][a-z0-9_]*)\s+in\s*\(([^)]*)\)\s*\)/gi;

	/**
	 * A discriminated union, spelled out because an inferred evolving array
	 * widens `kind` to `string` and then nothing narrows `valuesRaw`.
	 * @type {({ kind: 'table', index: number, table: string }
	 *   | { kind: 'check', index: number, column: string, valuesRaw: string })[]}
	 */
	const hits = [];
	/** @type {RegExpExecArray | null} */
	let m;
	while ((m = tableRe.exec(stripped)) !== null) {
		hits.push({ kind: 'table', index: m.index, table: m[1].toLowerCase() });
	}
	while ((m = checkRe.exec(stripped)) !== null) {
		hits.push({
			kind: 'check',
			index: m.index,
			column: m[1].toLowerCase(),
			valuesRaw: m[2],
		});
	}
	hits.sort((a, b) => a.index - b.index);

	/** @type {string | null} */
	let currentTable = null;
	for (const h of hits) {
		if (h.kind === 'table') {
			currentTable = h.table;
			continue;
		}
		if (!currentTable) continue;
		const values = new Set();
		const valueRe = /'([^']*)'/g;
		let v;
		while ((v = valueRe.exec(h.valuesRaw)) !== null) values.add(v[1]);
		out.set(`${currentTable}.${h.column}`, values);
	}
	return out;
}

export function loadAllMigrationChecks() {
	const merged = new Map();
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
		for (const [key, values] of local) merged.set(key, values);
	}
	return merged;
}

// The columns the CURRENT schema actually has, read off the generated
// `database.types.ts`. A CHECK whose column was later dropped leaves a
// phantom entry in the migration replay — `runs.kind` (`20261204_001`, dropped
// by `20261206_001`) is one — and a coverage rule that counted phantoms would
// demand a registry entry for a column no client can ever write.
/**
 * @param {string} dbTypes
 * @returns {Map<string, Set<string>>}
 */
export function parseLiveColumns(dbTypes) {
	/** @type {Map<string, Set<string>>} */
	const out = new Map();
	const publicIdx = dbTypes.indexOf('\n  public: {');
	if (publicIdx < 0) throw new Error('database.types.ts: no public schema block found');
	const tablesIdx = dbTypes.indexOf('Tables: {', publicIdx);
	if (tablesIdx < 0) throw new Error('database.types.ts: no Tables block in the public schema');

	/** @type {string | null} */
	let table = null;
	let inRow = false;
	for (const line of dbTypes.slice(tablesIdx).split('\n')) {
		if (/^ {4}Views: \{/.test(line)) break;
		const t = line.match(/^ {6}([a-z_][a-z0-9_]*): \{\s*$/);
		if (t) {
			table = t[1];
			inRow = false;
			continue;
		}
		if (/^ {8}Row: \{/.test(line)) {
			inRow = true;
			continue;
		}
		if (inRow && /^ {8}\}/.test(line)) {
			inRow = false;
			continue;
		}
		if (!inRow || !table) continue;
		const c = line.match(/^ {10}([a-z_][a-z0-9_]*)\??:/);
		if (!c) continue;
		if (!out.has(table)) out.set(table, new Set());
		out.get(table)?.add(c[1]);
	}
	if (out.size === 0) throw new Error('database.types.ts: parsed no tables');
	return out;
}

// --- client-source readers -------------------------------------------------

/**
 * Advance past a string literal starting at `i`. Handles backslash escapes;
 * the delimiter itself is whatever `src[i]` is.
 * @param {string} src
 * @param {number} i
 */
function skipString(src, i) {
	const quote = src[i];
	i += 1;
	while (i < src.length) {
		if (src[i] === '\\') {
			i += 2;
			continue;
		}
		if (src[i] === quote) return i + 1;
		i += 1;
	}
	return i;
}

/**
 * Split the inside of a balanced `[...]` / `{...}` slice into its top-level
 * comma-separated chunks, skipping string literals and comments so a comma
 * inside either can't split an entry.
 * @param {string} slice the slice INCLUDING its outer delimiters
 * @returns {string[]}
 */
export function topLevelChunks(slice) {
	const inner = slice.slice(1, -1);
	/** @type {string[]} */
	const chunks = [];
	let depth = 0;
	let start = 0;
	let i = 0;
	while (i < inner.length) {
		const c = inner[i];
		if (c === "'" || c === '"' || c === '`') {
			i = skipString(inner, i);
			continue;
		}
		if (c === '/' && inner[i + 1] === '/') {
			const nl = inner.indexOf('\n', i);
			i = nl < 0 ? inner.length : nl;
			continue;
		}
		if (c === '/' && inner[i + 1] === '*') {
			const end = inner.indexOf('*/', i + 2);
			i = end < 0 ? inner.length : end + 2;
			continue;
		}
		if (c === '(' || c === '[' || c === '{') depth += 1;
		else if (c === ')' || c === ']' || c === '}') depth -= 1;
		else if (c === ',' && depth === 0) {
			chunks.push(inner.slice(start, i));
			start = i + 1;
		}
		i += 1;
	}
	chunks.push(inner.slice(start));
	return chunks.map((s) => s.trim()).filter((s) => s.length > 0);
}

/**
 * Every balanced `[...]` / `{...}` initialiser belonging to a `const` /
 * `final` / `let` declaration named `decl`. More than one means the registry
 * cannot say which it meant — `data.ts` is ten thousand lines and a name like
 * `order` is not unique by construction — so the caller fails rather than
 * reading the first and certifying the wrong list.
 * @param {string} src
 * @param {string} decl
 * @returns {string[]}
 */
export function findInitializers(src, decl) {
	// A registered declaration name is an identifier on both rails, and anything
	// else reaching the regex would be a registry typo silently changing what the
	// guard matches -- a `.` would match any character and an unbalanced `(` would
	// throw from inside a loop. Refuse it here, then escape the whole
	// metacharacter set anyway rather than the `$` an identifier may legally
	// carry: a partial escape is the defect, not a shorter one.
	if (!/^[A-Za-z_$][\w$]*$/.test(decl)) {
		throw new Error(`findInitializers: ${JSON.stringify(decl)} is not an identifier`);
	}
	const declRe = new RegExp(
		String.raw`(?:^|[\n;{}])[ \t]*(?:export\s+)?(?:static\s+)?(?:const|final|let|var)\s+` +
			String.raw`(?:[A-Za-z_$][\w$]*(?:<[^>=;]*>)?\s+)?` +
			decl.replace(/[\\^$.*+?()[\]{}|/-]/g, '\\$&') +
			String.raw`\b`,
		'gm',
	);
	/** @type {string[]} */
	const found = [];
	/** @type {RegExpExecArray | null} */
	let m;
	while ((m = declRe.exec(src)) !== null) {
		const slice = initializerAt(src, m.index + m[0].length);
		if (slice !== null) found.push(slice);
	}
	return found;
}

/**
 * @param {string} src
 * @param {number} from index just past the declaration's name
 * @returns {string | null}
 */
function initializerAt(src, from) {
	let i = from;
	// Skip the type annotation to the assignment. `[^=]` would do for a Dart
	// declaration but not for a TS inline record type, whose `;` field
	// separators would read as the end of the statement — so walk, and only
	// treat a `;` at depth 0 as the end.
	let annotationDepth = 0;
	while (i < src.length) {
		const c = src[i];
		if (c === "'" || c === '"' || c === '`') {
			i = skipString(src, i);
			continue;
		}
		if (c === '(' || c === '[' || c === '{') annotationDepth += 1;
		else if (c === ')' || c === ']' || c === '}') annotationDepth -= 1;
		else if (annotationDepth === 0) {
			if (c === '=' && src[i + 1] !== '=' && src[i + 1] !== '>') break;
			if (c === ';') return null;
		}
		i += 1;
	}
	if (i >= src.length) return null;
	i += 1;
	// The first bracket after the `=` opens the literal.
	while (i < src.length && src[i] !== '[' && src[i] !== '{') {
		if (src[i] === ';') return null;
		i += 1;
	}
	if (i >= src.length) return null;
	const open = src[i];
	const close = open === '[' ? ']' : '}';
	let depth = 0;
	let j = i;
	while (j < src.length) {
		const c = src[j];
		if (c === "'" || c === '"' || c === '`') {
			j = skipString(src, j);
			continue;
		}
		if (c === '/' && src[j + 1] === '/') {
			const nl = src.indexOf('\n', j);
			j = nl < 0 ? src.length : nl;
			continue;
		}
		if (c === '/' && src[j + 1] === '*') {
			const end = src.indexOf('*/', j + 2);
			j = end < 0 ? src.length : end + 2;
			continue;
		}
		if (c === open) depth += 1;
		else if (c === close) {
			depth -= 1;
			if (depth === 0) return src.slice(i, j + 1);
		}
		j += 1;
	}
	return null;
}

/**
 * Blank out `//` and comment blocks, leaving string literals alone.
 *
 * `topLevelChunks` already skips comments when it decides where to SPLIT, but
 * the chunk it hands back still contains them — so a list carrying
 * `// 'ghost' was removed` above its last entry read `ghost` as a member and
 * lost the entry underneath it. That is worse than a miss in both directions
 * at once: the guard would certify a value the CHECK has never admitted, and
 * report a value the client really carries as absent. Applied to the
 * extracted region only, never to a whole file — a `//` inside a regex
 * literal is not a comment, and this walker cannot tell.
 * @param {string} region
 */
function stripComments(region) {
	let out = '';
	let i = 0;
	while (i < region.length) {
		const c = region[i];
		if (c === "'" || c === '"' || c === '`') {
			const end = skipString(region, i);
			out += region.slice(i, end);
			i = end;
			continue;
		}
		if (c === '/' && region[i + 1] === '/') {
			const nl = region.indexOf('\n', i);
			i = nl < 0 ? region.length : nl;
			continue;
		}
		if (c === '/' && region[i + 1] === '*') {
			const end = region.indexOf('*/', i + 2);
			i = end < 0 ? region.length : end + 2;
			continue;
		}
		out += c;
		i += 1;
	}
	return out;
}

/** @param {string} chunk */
function firstStringLiteral(chunk) {
	const m = chunk.match(/'([^']*)'|"([^"]*)"/);
	if (!m) return null;
	return m[1] ?? m[2];
}

const SNAKE = /([a-z0-9])([A-Z])/g;
/** @param {string} id */
const toSnake = (id) => id.replace(SNAKE, '$1_$2').toLowerCase();

/**
 * Extract the value set a client rail enumerates. Returns null when the
 * declaration isn't there at all — a renamed or deleted vocabulary must fail
 * loudly rather than compare as empty — and THROWS when the file holds more
 * than one declaration of that name, which is the same refusal one step
 * earlier: reading the first of two is how a guard certifies the wrong list.
 * @param {string} src
 * @param {{ decl: string, shape: string, field?: string }} rail
 * @returns {Set<string> | null}
 */
export function extractClientValues(src, rail) {
	const { decl, shape, field } = rail;
	/** @type {Set<string>} */
	const out = new Set();

	if (shape === 'union') {
		const m = src.match(new RegExp(String.raw`(?:export\s+)?type\s+${decl}\s*=([^;]+);`, 'm'));
		if (!m) return null;
		for (const v of stripComments(m[1]).matchAll(/'([^']*)'|"([^"]*)"/g)) out.add(v[1] ?? v[2]);
		return out.size === 0 ? null : out;
	}

	if (shape === 'enum') {
		const m = src.match(new RegExp(String.raw`\benum\s+${decl}\s*\{([^}]*)\}`, 'm'));
		if (!m) return null;
		for (const raw of stripComments(m[1]).split(';')[0].split(',')) {
			const id = raw.trim().match(/^([a-z][A-Za-z0-9_]*)/);
			if (id) out.add(toSnake(id[1]));
		}
		return out.size === 0 ? null : out;
	}

	const slices = findInitializers(src, decl);
	if (slices.length === 0) return null;
	if (slices.length > 1) {
		throw new Error(
			`${slices.length} declarations named "${decl}" — the registry cannot say which ` +
				'one it means. Rename the one that is not the vocabulary.',
		);
	}
	const chunks = topLevelChunks(slices[0]).map(stripComments).map((c) => c.trim());

	if (shape === 'strings') {
		for (const chunk of chunks) {
			const v = firstStringLiteral(chunk);
			if (v !== null) out.add(v);
		}
	} else if (shape === 'keys') {
		for (const chunk of chunks) {
			const colon = chunk.indexOf(':');
			if (colon < 0) continue;
			const key = chunk.slice(0, colon).trim();
			const quoted = firstStringLiteral(key);
			if (quoted !== null) out.add(quoted);
			else if (/^[A-Za-z_$][\w$]*$/.test(key)) out.add(key);
		}
	} else if (shape === 'records') {
		if (!field) return null;
		const fieldRe = new RegExp(String.raw`\b${field}\s*:\s*(?:'([^']*)'|"([^"]*)")`);
		for (const chunk of chunks) {
			const m = chunk.match(fieldRe);
			if (m) out.add(m[1] ?? m[2]);
		}
	} else {
		return null;
	}
	return out.size === 0 ? null : out;
}

// Kept for the migration-coordinator agent and the guard's own suite: the
// single-declaration TS reader, now a thin wrapper over the shared extractor.
/**
 * @param {string} types
 * @param {string} name
 * @returns {Set<string> | null}
 */
export function parseTsUnion(types, name) {
	return extractClientValues(types, { decl: name, shape: 'union' });
}

/**
 * @param {Set<string>} a
 * @param {Set<string>} b
 */
function diff(a, b) {
	const onlyA = [...a].filter((x) => !b.has(x));
	const onlyB = [...b].filter((x) => !a.has(x));
	return { onlyA, onlyB };
}

/**
 * @typedef {object} ClientRail
 * @property {string} file
 * @property {string} decl
 * @property {string} shape
 * @property {string} [field]
 * @property {string[]} [allowExtra]
 * @property {string[]} [allowMissing]
 */

/**
 * @typedef {object} RegistryEntry
 * @property {string} tableColumn
 * @property {ClientRail[]} clients
 * @property {string} [note]
 */

/**
 * @param {Map<string, Set<string>>} checks
 * @param {(relPath: string) => string} readSource
 * @param {readonly RegistryEntry[]} [pairs]
 * @param {Map<string, Set<string>> | null} [liveColumns]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function audit(checks, readSource, pairs = PAIRS, liveColumns = null) {
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

	// Coverage, both directions. This is what makes a new CHECK column fail
	// until somebody registers it — including registering that no client
	// enumerates it.
	const registered = new Set();
	for (const entry of pairs) {
		if (registered.has(entry.tableColumn)) {
			errors.push(`${entry.tableColumn}: registered twice; one column gets one entry.`);
		}
		registered.add(entry.tableColumn);
		if (entry.clients.length === 0 && !entry.note) {
			errors.push(
				`${entry.tableColumn}: registered with no client vocabulary and no note. ` +
					'Say in a `note` why no client enumerates it, so the next reader knows it ' +
					'was decided rather than forgotten.',
			);
		}
		for (const rail of entry.clients) {
			if (!SHAPES.includes(rail.shape)) {
				errors.push(
					`${entry.tableColumn} → ${rail.decl}: unknown shape "${rail.shape}" ` +
						`(expected one of ${SHAPES.join(', ')}).`,
				);
			}
		}
	}
	for (const [tableColumn] of checks) {
		const [table, column] = tableColumn.split('.');
		const live = liveColumns ? liveColumns.get(table)?.has(column) !== false : true;
		if (!live) {
			if (registered.has(tableColumn)) {
				errors.push(
					`${tableColumn}: registered, but the column is not in database.types.ts — ` +
						'it was dropped by a later migration. Delete the entry.',
				);
			}
			continue;
		}
		if (!registered.has(tableColumn)) {
			errors.push(
				`${tableColumn}: a set-shaped CHECK constraint with no entry in PAIRS. ` +
					'Add one naming every client vocabulary that enumerates it (TS union, ' +
					'const list, Svelte option list, Dart enum or const list) — or an empty ' +
					'`clients` list plus a `note` saying no client does.',
			);
		}
	}

	for (const entry of pairs) {
		const checkValues = checks.get(entry.tableColumn);
		if (!checkValues) {
			errors.push(
				`${entry.tableColumn}: no set-shaped CHECK constraint found on this column in the migrations.`,
			);
			continue;
		}
		if (entry.clients.length === 0) {
			ok.push(`${entry.tableColumn}: no client vocabulary (${entry.note ?? ''})`);
			continue;
		}
		for (const rail of entry.clients) {
			/** @type {string} */
			let src;
			try {
				src = readSource(rail.file);
			} catch {
				errors.push(`${entry.tableColumn} → ${rail.decl}: cannot read ${rail.file}.`);
				continue;
			}
			/** @type {Set<string> | null} */
			let values;
			try {
				values = extractClientValues(src, rail);
			} catch (err) {
				errors.push(
					`${entry.tableColumn} → ${rail.decl} (${rail.file}): ` +
						`${err instanceof Error ? err.message : String(err)}`,
				);
				continue;
			}
			if (!values) {
				errors.push(
					`${entry.tableColumn} → ${rail.decl}: no ${rail.shape} declaration named ` +
						`"${rail.decl}" in ${rail.file}. It was renamed, deleted, or its shape changed.`,
				);
				continue;
			}
			const allowExtra = new Set(rail.allowExtra ?? []);
			const allowMissing = new Set(rail.allowMissing ?? []);
			for (const x of allowExtra) {
				if (!values.has(x)) {
					errors.push(
						`${entry.tableColumn} → ${rail.decl}: allowExtra lists "${x}" but the ` +
							'declaration no longer carries it. Drop the exemption.',
					);
				}
				if (checkValues.has(x)) {
					errors.push(
						`${entry.tableColumn} → ${rail.decl}: allowExtra lists "${x}" but the ` +
							'CHECK now admits it, so it is no longer client-only. Drop the exemption.',
					);
				}
			}
			for (const x of allowMissing) {
				if (values.has(x)) {
					errors.push(
						`${entry.tableColumn} → ${rail.decl}: allowMissing lists "${x}" but the ` +
							'declaration carries it. Drop the exemption.',
					);
				}
				if (!checkValues.has(x)) {
					errors.push(
						`${entry.tableColumn} → ${rail.decl}: allowMissing lists "${x}" but the ` +
							'CHECK no longer admits it. Drop the exemption.',
					);
				}
			}
			const { onlyA: onlyInCheck, onlyB: onlyInClient } = diff(checkValues, values);
			const unexplainedMissing = onlyInCheck.filter((x) => !allowMissing.has(x));
			const unexplainedExtra = onlyInClient.filter((x) => !allowExtra.has(x));
			if (unexplainedMissing.length || unexplainedExtra.length) {
				errors.push(
					`${entry.tableColumn} drift vs ${rail.decl} (${rail.file}):\n` +
						`  CHECK only:  ${unexplainedMissing.length ? unexplainedMissing.join(', ') : '(none)'}\n` +
						`  client only: ${unexplainedExtra.length ? unexplainedExtra.join(', ') : '(none)'}\n` +
						'  Fix: the CHECK is what the database enforces. A client missing a value ' +
						'rejects rows the database would accept; a client carrying an extra one ' +
						'produces a 23514 the user cannot act on. Decide which side is right and ' +
						'change that one — or declare the delta with allowExtra / allowMissing ' +
						'and say why.',
				);
				continue;
			}
			ok.push(`${entry.tableColumn} → ${rail.decl}: ${[...values].sort().join(', ')}`);
		}
	}

	return { errors, ok };
}

/** @param {string} relPath */
function readRepoFile(relPath) {
	return readFileSync(join(REPO_ROOT, relPath), 'utf-8');
}

export function loadLiveColumns() {
	return parseLiveColumns(readRepoFile(DB_TYPES_FILE));
}

function main() {
	const { errors, ok } = audit(
		loadAllMigrationChecks(),
		readRepoFile,
		PAIRS,
		loadLiveColumns(),
	);
	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);
	return errors.length > 0 ? 1 : 0;
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit(main());
