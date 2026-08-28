// Guardrail: verify every CHECK-constraint enum in the Supabase migrations
// matches the corresponding narrow TypeScript union in `src/lib/types.ts`.
//
// Why this exists: Supabase's gen-types pass doesn't read CHECK constraints,
// so the narrow TS unions in `types.ts` are hand-maintained. If a migration
// adds a new value to the CHECK and nobody updates the union (or vice
// versa), one client can write a value the other rejects (postgres 23514
// `check_violation`) and we don't notice until production. The April 2026
// cross-client audit caught this happening with `runsignup` — the
// IntegrationProvider TS union had it, the CHECK constraint didn't.
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
const REPO_ROOT = join(__dirname, '..', '..', '..');
export const MIGRATIONS_DIR = join(REPO_ROOT, 'apps/backend/supabase/migrations');
export const TYPES_FILE = join(REPO_ROOT, 'apps/web/src/lib/types.ts');

// Each entry pairs a Supabase column with its hand-maintained TS union.
// If you add a new CHECK ... IN (...) constraint AND a TS union for it,
// append here so the script verifies they stay in lockstep. Key by
// `<table>.<column>` because some columns share names across tables
// (e.g. `runs.source` vs `fitness_snapshots.source`).
export const PAIRS = [
	{ tableColumn: 'runs.source', tsUnion: 'RunSource' },
	{ tableColumn: 'runs.activity_type', tsUnion: 'ActivityType' },
	{ tableColumn: 'routes.surface', tsUnion: 'RouteSurface' },
	{ tableColumn: 'route_markers.kind', tsUnion: 'RouteMarkerKind' },
	{ tableColumn: 'route_conditions.condition', tsUnion: 'RouteConditionKind' },
	{ tableColumn: 'route_conditions.severity', tsUnion: 'RouteConditionSeverity' },
	{ tableColumn: 'integrations.provider', tsUnion: 'IntegrationProvider' },
	{ tableColumn: 'user_profiles.gender', tsUnion: 'Gender' },
	{ tableColumn: 'user_profiles.preferred_unit', tsUnion: 'PreferredUnit' },
	{ tableColumn: 'user_profiles.subscription_tier', tsUnion: 'SubscriptionTier' },
	{ tableColumn: 'club_members.role', tsUnion: 'ClubRole' },
	{ tableColumn: 'notifications.kind', tsUnion: 'NotificationKind' },
	{ tableColumn: 'events.category', tsUnion: 'EventCategory' },
	{ tableColumn: 'event_orders.status', tsUnion: 'OrderStatus' },
	{ tableColumn: 'event_pricing.refund_policy', tsUnion: 'RefundPolicy' },
	{ tableColumn: 'event_pricing.modality', tsUnion: 'EventModality' },
	{ tableColumn: 'fundraisers.status', tsUnion: 'FundraiserStatus' },
	{ tableColumn: 'donations.status', tsUnion: 'DonationStatus' },
	{ tableColumn: 'event_attendees.attendance', tsUnion: 'EventAttendance' },
	{ tableColumn: 'session_plan_items.kind', tsUnion: 'SessionItemKind' },
	{ tableColumn: 'gym_routines.periodisation', tsUnion: 'GymPeriodisation' },
	{ tableColumn: 'gym_routine_exercises.modality', tsUnion: 'GymExerciseModality' },
	{ tableColumn: 'gym_routine_exercises.progression', tsUnion: 'GymProgressionScheme' },
	{ tableColumn: 'gym_routine_sets.set_type', tsUnion: 'GymSetType' },
	{ tableColumn: 'gym_sets.set_type', tsUnion: 'GymSetType' },
	{ tableColumn: 'exercises.category', tsUnion: 'ExerciseCategory' },
	{ tableColumn: 'exercises.modality', tsUnion: 'GymExerciseModality' },
	{ tableColumn: 'reports.target_kind', tsUnion: 'ReportTargetKind' },
	{ tableColumn: 'public_recaps.period_kind', tsUnion: 'RecapPeriodKind' },
	{ tableColumn: 'achievements.tier', tsUnion: 'AchievementTier' },
	{ tableColumn: 'achievements.source_kind', tsUnion: 'AchievementSourceKind' },
	{ tableColumn: 'challenges.metric', tsUnion: 'ChallengeMetric' },
	{ tableColumn: 'challenges.scope', tsUnion: 'ChallengeScope' },
	{ tableColumn: 'race_listings.provider', tsUnion: 'RaceProvider' },
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

// Extract the literal-string members of an exported TS union. Handles
// both single-line (`= 'a' | 'b';`) and multi-line forms.
/**
 * @param {string} types
 * @param {string} name
 * @returns {Set<string> | null}
 */
export function parseTsUnion(types, name) {
	const re = new RegExp(`export\\s+type\\s+${name}\\s*=([^;]+);`, 'm');
	const m = types.match(re);
	if (!m) return null;
	/** @type {Set<string>} */
	const out = new Set();
	const valueRe = /'([^']+)'/g;
	let v;
	while ((v = valueRe.exec(m[1])) !== null) out.add(v[1]);
	return out.size === 0 ? null : out;
}

/**
 * @param {Set<string>} a
 * @param {Set<string>} b
 */
function setsEqual(a, b) {
	if (a.size !== b.size) return false;
	for (const x of a) if (!b.has(x)) return false;
	return true;
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
 * @param {Map<string, Set<string>>} checks
 * @param {string} types
 * @param {readonly { tableColumn: string, tsUnion: string }[]} [pairs]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function audit(checks, types, pairs = PAIRS) {
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

	for (const { tableColumn, tsUnion } of pairs) {
		const checkValues = checks.get(tableColumn);
		const tsValues = parseTsUnion(types, tsUnion);

		if (!checkValues) {
			errors.push(`${tsUnion}: no CHECK constraint found on "${tableColumn}" in migrations.`);
			continue;
		}
		if (!tsValues) {
			errors.push(`${tsUnion}: TS union not found in apps/web/src/lib/types.ts.`);
			continue;
		}
		if (!setsEqual(checkValues, tsValues)) {
			const { onlyA: onlyInCheck, onlyB: onlyInTs } = diff(checkValues, tsValues);
			errors.push(
				`${tsUnion} drift on ${tableColumn}:\n` +
					`  CHECK only: ${onlyInCheck.length ? onlyInCheck.join(', ') : '(none)'}\n` +
					`  TS only:    ${onlyInTs.length ? onlyInTs.join(', ') : '(none)'}\n` +
					`  Fix: update the migration AND the TS union so both list the same values.`,
			);
			continue;
		}
		ok.push(`${tsUnion} (${tableColumn}): ${[...tsValues].sort().join(', ')}`);
	}

	return { errors, ok };
}

function main() {
	const { errors, ok } = audit(loadAllMigrationChecks(), readFileSync(TYPES_FILE, 'utf-8'));
	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);
	return errors.length > 0 ? 1 : 0;
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit(main());
