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
//   switch   — `case 'a':` / `'a' =>` labels              (Dart only)
//
// `switch` exists because § 791's carve-out does not carry over. Web's
// icon/label `Record<Union, X>` maps are deliberately unregistered — `tsc`
// makes them exhaustive — and Dart has no analogue: a `switch` over a `String`
// cannot be exhaustive, so every one of those lookups degrades SILENTLY to its
// `default:` / `_` branch the day its CHECK gains a value. The rail reads the
// switch ITSELF rather than a const list beside it, because a list is a second
// declaration nothing checks against the switch — the § 641 shape, a copy whose
// divergence is undetectable. decisions § 818.
//
// A `switch` rail's `allowMissing` is normally the one value its `default:` /
// `_` branch was written FOR: a `_slotLabel` naming breakfast / lunch / dinner
// and falling through to "Snack" omits `snack` on purpose. The exemption is
// staleness-checked like every other, so a FIFTH meal slot still fails here.
export const SHAPES = ['union', 'strings', 'keys', 'records', 'enum', 'switch'];

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
			{
				file: 'apps/mobile_android/lib/widgets/badge_grid.dart',
				decl: 'badgeTierColor',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/widgets/badge_grid.dart',
				decl: 'badgeTierLabel',
				shape: 'switch',
			},
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
			{ file: 'packages/core_models/lib/src/activity_type.dart', decl: 'ActivityType', shape: 'enum' },
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
			{
				file: 'apps/mobile_android/lib/challenge_goal.dart',
				decl: 'challengeGoalUnit',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/widgets/challenge_progress_bar.dart',
				decl: 'challengeMetricLabel',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/widgets/challenge_progress_bar.dart',
				decl: 'challengeValueLabel',
				shape: 'switch',
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
			{
				file: 'apps/mobile_android/lib/widgets/challenge_form_sheet.dart',
				decl: '_scopeLabel',
				shape: 'switch',
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
			{
				file: 'apps/mobile_android/lib/screens/discover_screen.dart',
				decl: '_categoryLabel',
				shape: 'switch',
			},
		],
	},
	{
		tableColumn: 'events.recurrence_freq',
		clients: [
			{ file: TS_TYPES, decl: 'RecurrenceFreq', shape: 'union' },
			{ file: 'apps/mobile_android/lib/recurrence.dart', decl: 'RecurrenceFreq', shape: 'enum' },
			{
				file: 'apps/mobile_android/lib/recurrence.dart',
				decl: 'recurrenceFromString',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/screens/discover_screen.dart',
				decl: 'freq',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/widgets/event_form_sheet.dart',
				decl: '_submit',
				shape: 'switch',
			},
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
			{
				file: 'apps/mobile_android/lib/screens/nutrition_screen.dart',
				decl: '_slotLabel',
				shape: 'switch',
				allowMissing: ['snack'],
			},
			{
				file: 'apps/mobile_android/lib/screens/nutrition_meal_detail_screen.dart',
				decl: '_slotLabel',
				shape: 'switch',
				allowMissing: ['snack'],
			},
			{
				file: 'apps/mobile_android/lib/widgets/nutrition_log_sheet.dart',
				decl: '_slotLabel',
				shape: 'switch',
				allowMissing: ['snack'],
			},
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
			{
				file: 'apps/mobile_android/lib/widgets/gear_form_sheet.dart',
				decl: '_wearAreaLabel',
				shape: 'switch',
				allowMissing: ['other'],
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
			{
				file: 'apps/mobile_android/lib/widgets/routine_builder_sheet.dart',
				decl: '_modalityLabel',
				shape: 'switch',
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
			{
				file: 'apps/mobile_android/lib/widgets/routine_builder_sheet.dart',
				decl: '_schemeLabel',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/screens/routine_detail_screen.dart',
				decl: '_schemeLabel',
				shape: 'switch',
				allowMissing: ['none'],
			},
			{
				file: 'apps/mobile_android/lib/screens/gym_detail_screen.dart',
				decl: '_schemeFromString',
				shape: 'switch',
				allowMissing: ['none'],
			},
			{
				file: 'apps/mobile_android/lib/screens/gym_session_screen.dart',
				decl: '_schemeFromString',
				shape: 'switch',
				allowMissing: ['none'],
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
			{
				file: 'apps/mobile_android/lib/widgets/routine_builder_sheet.dart',
				decl: '_setTypeLabel',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/screens/routine_detail_screen.dart',
				decl: '_setTypeLabel',
				shape: 'switch',
			},
		],
	},
	{
		tableColumn: 'gym_routines.periodisation',
		clients: [{ file: TS_TYPES, decl: 'GymPeriodisation', shape: 'union' }],
	},
	{
		// `_setTypeChip` returns null for `working` BEFORE its switch — the common
		// set carries no chip, so the switch never names the value.
		tableColumn: 'gym_sets.set_type',
		clients: [
			{ file: TS_TYPES, decl: 'GymSetType', shape: 'union' },
			{ file: 'apps/web/src/lib/components/GymEditor.svelte', decl: 'SET_TYPES', shape: 'strings' },
			{
				file: 'apps/mobile_android/lib/widgets/gym_compose_sheet.dart',
				decl: '_gymSetTypes',
				shape: 'strings',
			},
			{
				file: 'apps/mobile_android/lib/widgets/gym_compose_sheet.dart',
				decl: '_gymSetTypeLabel',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/screens/gym_detail_screen.dart',
				decl: '_setTypeChip',
				shape: 'switch',
				allowMissing: ['working'],
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
		// `_targetKeyFor` omits the three kinds that point at no shared entity,
		// so they take a per-row `solo:` key and can never collapse into each
		// other; that is the grouping contract, not an oversight. `refund_failed`
		// is deliberately among them: two reversed refunds are two sums of money
		// owed, and "and 1 other" would hide one of them.
		tableColumn: 'notifications.kind',
		clients: [
			{ file: TS_TYPES, decl: 'NotificationKind', shape: 'union' },
			{
				file: 'apps/mobile_android/lib/notification_groups.dart',
				decl: '_targetKeyFor',
				shape: 'switch',
				allowMissing: ['content_hidden', 'data_export_ready', 'refund_failed'],
			},
			{
				file: 'apps/mobile_android/lib/screens/profile_screen.dart',
				decl: '_verbFor',
				shape: 'switch',
			},
		],
	},
	{
		tableColumn: 'payment_refunds.status',
		clients: [
			{ file: TS_TYPES, decl: 'PaymentRefundStatus', shape: 'union' },
			{
				file: 'apps/backend/supabase/functions/stripe-events-webhook/lib.ts',
				decl: 'REFUND_STATUSES',
				shape: 'strings',
			},
		],
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
		clients: [
			{ file: TS_TYPES, decl: 'RaceSessionStatus', shape: 'union' },
			{
				file: 'apps/mobile_android/lib/screens/event_detail_screen.dart',
				decl: 'banner',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/screens/event_detail_screen.dart',
				decl: 'bannerColour',
				shape: 'switch',
			},
		],
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
			{
				file: 'apps/mobile_android/lib/widgets/report_sheet.dart',
				decl: '_reasonLabel',
				shape: 'switch',
				allowMissing: ['other'],
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
		clients: [
			{ file: TS_TYPES, decl: 'ReportTargetKind', shape: 'union' },
			{
				file: 'apps/mobile_android/lib/widgets/report_sheet.dart',
				decl: '_title',
				shape: 'switch',
			},
		],
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
			{
				file: 'apps/mobile_android/lib/widgets/route_conditions.dart',
				decl: 'routeConditionKindLabel',
				shape: 'switch',
				allowMissing: ['other'],
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
			{
				file: 'apps/mobile_android/lib/widgets/route_conditions.dart',
				decl: 'routeConditionSeverityLabel',
				shape: 'switch',
				allowMissing: ['info'],
			},
			{
				file: 'apps/mobile_android/lib/widgets/route_conditions.dart',
				decl: 'routeConditionSeverityColor',
				shape: 'switch',
				allowMissing: ['info'],
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
			{
				file: 'apps/mobile_android/lib/screens/run_screen.dart',
				decl: '_markerKindLabel',
				shape: 'switch',
				allowMissing: ['custom'],
			},
			{
				file: 'apps/mobile_android/lib/widgets/route_markers_panel.dart',
				decl: 'RouteMarkersPanelState._kindLabel',
				shape: 'switch',
				allowMissing: ['custom'],
			},
			{
				file: 'apps/mobile_android/lib/widgets/route_markers_panel.dart',
				decl: '_MarkerEditorSheetState._kindLabel',
				shape: 'switch',
				allowMissing: ['custom'],
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
			{
				file: 'apps/mobile_android/lib/screens/global_segments_screen.dart',
				decl: 'catalogueSurfaceLabel',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/screens/route_detail_screen.dart',
				decl: 'surface',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/screens/route_detail_screen.dart',
				decl: '_surfaceIcon',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/screens/route_detail_screen.dart',
				decl: '_surfaceLabel',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/screens/explore_routes_screen.dart',
				decl: '_surfaceIcon',
				shape: 'switch',
				allowMissing: ['road'],
			},
			{
				file: 'apps/mobile_android/lib/screens/explore_routes_screen.dart',
				decl: '_surfaceLabel',
				shape: 'switch',
				allowMissing: ['road'],
			},
		],
	},
	{
		tableColumn: 'run_matched_tracks.status',
		clients: [{ file: DATA_TS, decl: 'MatchStatus', shape: 'union' }],
	},
	{
		// `_activityIcon` lets `stroller` fall to the running icon deliberately: a
		// stroller run is foot-powered, which is the same mapping the
		// `auto_tag_default_gear` trigger and `gear_backfill` make (decisions § 598).
		tableColumn: 'runs.activity_type',
		clients: [
			{ file: TS_TYPES, decl: 'ActivityType', shape: 'union' },
			{ file: 'apps/web/src/lib/runs/activity_type.ts', decl: 'ACTIVITY_TYPES', shape: 'strings' },
			{ file: 'packages/core_models/lib/src/activity_type.dart', decl: 'ActivityType', shape: 'enum' },
			{
				file: 'apps/mobile_android/lib/health_connect_exporter.dart',
				decl: 'healthWorkoutTypeForActivity',
				shape: 'switch',
			},
			{
				file: 'apps/mobile_android/lib/widgets/gear_backfill_sheet.dart',
				decl: '_activityIcon',
				shape: 'switch',
				allowMissing: ['stroller'],
			},
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
			{
				file: 'apps/mobile_android/lib/screens/session_detail_screen.dart',
				decl: 'sessionKindFromString',
				shape: 'switch',
				allowMissing: ['hold'],
			},
			{
				file: 'apps/mobile_android/lib/screens/event_detail_screen.dart',
				decl: '_sessionKindFromString',
				shape: 'switch',
				allowMissing: ['hold'],
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
			{
				file: 'apps/mobile_android/lib/screens/nutrition_targets_screen.dart',
				decl: '_metricsCard',
				shape: 'switch',
				allowMissing: ['prefer_not_to_say'],
			},
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

/**
 * A copy of `src` with every comment replaced by spaces of the same length, so
 * index-based scanning still maps 1:1 onto the original. String literals —
 * including Dart's triple-quoted form — are left whole: the values this script
 * reads ARE literals.
 *
 * Length-preserving rather than reusing `stripComments`, which deletes: the
 * switch reader compares positions, and a commented-out declaration must not
 * become the anchor of the switch below it (a `/// String _oldLabel(String s)
 * {` doc line is exactly that shape).
 * @param {string} src
 */
export function blankComments(src) {
	let out = '';
	let i = 0;
	while (i < src.length) {
		const c = src[i];
		if (c === "'" || c === '"') {
			const triple = src.slice(i, i + 3);
			if (triple === "'".repeat(3) || triple === '"'.repeat(3)) {
				const end = src.indexOf(triple, i + 3);
				const stop = end < 0 ? src.length : end + 3;
				out += src.slice(i, stop);
				i = stop;
				continue;
			}
			const end = skipString(src, i);
			out += src.slice(i, end);
			i = end;
			continue;
		}
		if (c === '/' && src[i + 1] === '/') {
			const nl = src.indexOf('\n', i);
			const stop = nl < 0 ? src.length : nl;
			out += ' '.repeat(stop - i);
			i = stop;
			continue;
		}
		if (c === '/' && src[i + 1] === '*') {
			const end = src.indexOf('*/', i + 2);
			const stop = end < 0 ? src.length : end + 2;
			out += src.slice(i, stop).replace(/[^\n]/g, ' ');
			i = stop;
			continue;
		}
		out += c;
		i += 1;
	}
	return out;
}

// A getter or a variable with an initialiser. A method / function is found by
// scan rather than by pattern (`dartDeclarations`): a Dart parameter list can
// carry `{named}` / `[optional]` groups, which no bounded character class can
// cross — `_verbFor(l10n, item, {String? nameOverride})` was invisible to one
// that tried, and its 16-value switch with it.
const DART_DECLS = [
	/\bget\s+([A-Za-z_$][\w$]*)\s*(?:\{|=>)/g,
	/\b(?:final|const|var|late)\s+(?:[\w$<>,?[\]]+\s+)?([A-Za-z_$][\w$]*)\s*=(?!=)/g,
];
const DART_SCOPES = /\b(?:class|mixin|extension|enum)\s+([A-Za-z_$][\w$]*)/g;
// `if (…) {` is an identifier followed by a parenthesised group and a block —
// structurally a method declaration. A control-flow word winning the
// innermost-enclosing race would move every anchor onto the nearest `if`.
const DART_NON_DECL = new Set([
	'if',
	'for',
	'while',
	'switch',
	'catch',
	'do',
	'else',
	'return',
	'assert',
	'await',
	'yield',
	'new',
	'super',
	'this',
]);

/**
 * The index one past the end of the declaration body that starts at `from`.
 * A block body is its balanced braces; an arrow or assignment body runs to the
 * next `;` outside any bracket or string.
 * @param {string} src
 * @param {number} from index of the `{`, or just past the `=>` / `=`
 * @param {boolean} block
 */
function declBodyEnd(src, from, block) {
	let depth = 0;
	let i = from;
	while (i < src.length) {
		const c = src[i];
		if (c === "'" || c === '"') {
			i = skipString(src, i);
			continue;
		}
		if (c === '(' || c === '[' || c === '{') depth += 1;
		else if (c === ')' || c === ']' || c === '}') {
			depth -= 1;
			if (block && depth === 0) return i + 1;
			if (depth < 0) return i;
		} else if (!block && c === ';' && depth === 0) return i + 1;
		i += 1;
	}
	return src.length;
}

/**
 * Every declaration in a comment-blanked Dart source that can hold a switch,
 * with the span its body occupies.
 * @param {string} blanked
 * @returns {{ start: number, end: number, name: string }[]}
 */
function dartDeclarations(blanked) {
	/** @type {{ start: number, end: number, name: string }[]} */
	const out = [];
	for (const re of DART_DECLS) {
		re.lastIndex = 0;
		/** @type {RegExpExecArray | null} */
		let d;
		while ((d = re.exec(blanked)) !== null) {
			const after = d.index + d[0].length;
			const block = d[0].endsWith('{');
			out.push({
				start: d.index,
				end: declBodyEnd(blanked, block ? after - 1 : after, block),
				name: d[1],
			});
		}
	}
	const nameRe = /([A-Za-z_$][\w$]*)\s*(?:<[^<>()]*>)?\s*\(/g;
	/** @type {RegExpExecArray | null} */
	let n;
	while ((n = nameRe.exec(blanked)) !== null) {
		if (DART_NON_DECL.has(n[1])) continue;
		let i = n.index + n[0].length - 1;
		let depth = 0;
		for (; i < blanked.length; i += 1) {
			const c = blanked[i];
			if (c === "'" || c === '"') {
				i = skipString(blanked, i) - 1;
				continue;
			}
			if (c === '(') depth += 1;
			else if (c === ')') {
				depth -= 1;
				if (depth === 0) {
					i += 1;
					break;
				}
			}
		}
		const tail = blanked.slice(i).match(/^\s*(?:async\s*\*?\s*|sync\s*\*\s*)?(\{|=>)/);
		if (!tail) continue;
		const bodyAt = i + tail[0].length - tail[1].length;
		out.push({
			start: n.index,
			end: declBodyEnd(blanked, tail[1] === '{' ? bodyAt : bodyAt + 2, tail[1] === '{'),
			name: n[1],
		});
	}
	out.sort((a, b) => a.start - b.start);
	return out;
}

/**
 * Every `switch (…) { … }` in a Dart source, with the path the registry
 * addresses it by: the name of the innermost declaration whose body ENCLOSES
 * it, qualified by the nearest preceding class / mixin / extension.
 *
 * Innermost-enclosing rather than nearest-preceding, which conflates two very
 * different declarations: `final banner = switch (status) {…}` is the switch's
 * own initialiser and names it exactly, while `final t = row['set_type'] …`
 * sitting a line above one merely precedes it — addressing by that would let an
 * unrelated local rename move a rail off its switch.
 *
 * Addressed by declaration rather than by subject expression because two
 * switches in one method routinely share a subject: the race banner and its
 * colour on `event_detail_screen` both switch on `status`.
 * @param {string} src
 * @returns {{ path: string, member: string, body: string }[]}
 */
export function dartSwitches(src) {
	const blanked = blankComments(src);
	const decls = dartDeclarations(blanked);
	/** @type {{ index: number, name: string }[]} */
	const scopes = [];
	DART_SCOPES.lastIndex = 0;
	/** @type {RegExpExecArray | null} */
	let sc;
	while ((sc = DART_SCOPES.exec(blanked)) !== null) scopes.push({ index: sc.index, name: sc[1] });

	/** @type {{ path: string, member: string, body: string }[]} */
	const out = [];
	const switchRe = /\bswitch\s*\(/g;
	/** @type {RegExpExecArray | null} */
	let m;
	while ((m = switchRe.exec(blanked)) !== null) {
		let i = blanked.indexOf('(', m.index);
		let depth = 0;
		for (; i < blanked.length; i += 1) {
			if (blanked[i] === '(') depth += 1;
			else if (blanked[i] === ')') {
				depth -= 1;
				if (depth === 0) {
					i += 1;
					break;
				}
			}
		}
		while (i < blanked.length && /\s/.test(blanked[i])) i += 1;
		if (blanked[i] !== '{') continue;
		const end = declBodyEnd(blanked, i, true);
		/** @type {string | null} */
		let member = null;
		for (const d of decls) {
			if (d.start >= m.index) break;
			if (d.end > m.index) member = d.name;
		}
		if (member === null) continue;
		/** @type {string | null} */
		let scope = null;
		for (const sp of scopes) {
			if (sp.index >= m.index) break;
			scope = sp.name;
		}
		out.push({
			path: scope === null ? member : `${scope}.${member}`,
			member,
			body: blanked.slice(i, end),
		});
	}
	return out;
}

/**
 * The string literals a Dart switch's case labels enumerate — `case 'x':`,
 * `case 'x' || 'y':`, `'x' =>` and `'x' || 'y' =>`. The `default:` / `_` branch
 * contributes nothing, which is the point: it is where an unhandled value
 * lands, not a value the switch names.
 * @param {string} body
 */
function switchLabels(body) {
	/** @type {Set<string>} */
	const out = new Set();
	for (const m of body.matchAll(/\bcase\s+('[^']*'(?:\s*\|\|\s*'[^']*')*)/g)) {
		for (const v of m[1].matchAll(/'([^']*)'/g)) out.add(v[1]);
	}
	for (const m of body.matchAll(/(?:^|[{,;])\s*('[^']*'(?:\s*\|\|\s*'[^']*')*)\s*=>/gm)) {
		for (const v of m[1].matchAll(/'([^']*)'/g)) out.add(v[1]);
	}
	return out;
}

/**
 * The value set the switch addressed by `decl` enumerates. `decl` is either a
 * bare declaration name or `Scope.name`; a bare name matching two switches
 * throws rather than reading the first, the same refusal `findInitializers`
 * makes one shape over.
 * @param {string} src
 * @param {string} decl
 * @returns {Set<string> | null}
 */
export function extractSwitchValues(src, decl) {
	const matches = dartSwitches(src).filter((s) => s.path === decl || s.member === decl);
	if (matches.length === 0) return null;
	if (matches.length > 1) {
		throw new Error(
			`${matches.length} switches addressed by "${decl}" (${matches
				.map((s) => s.path)
				.join(', ')}) — the registry cannot say which one it means. Qualify it as Scope.name.`,
		);
	}
	const values = switchLabels(matches[0].body);
	return values.size === 0 ? null : values;
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

	if (shape === 'switch') return extractSwitchValues(src, decl);

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
