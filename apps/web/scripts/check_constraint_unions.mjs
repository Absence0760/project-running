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
// Run: `npm run check:check-constraints --workspace=apps/web`
// CI:  invoked from the parity-types job alongside gen:types:check.

import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..', '..');
const MIGRATIONS_DIR = join(REPO_ROOT, 'apps/backend/supabase/migrations');
const TYPES_FILE = join(REPO_ROOT, 'apps/web/src/lib/types.ts');

// Each entry pairs a Supabase column with its hand-maintained TS union.
// If you add a new CHECK ... IN (...) constraint AND a TS union for it,
// append here so the script verifies they stay in lockstep. Key by
// `<table>.<column>` because some columns share names across tables
// (e.g. `runs.source` vs `fitness_snapshots.source`).
const PAIRS = [
	{ tableColumn: 'runs.source', tsUnion: 'RunSource' },
	{ tableColumn: 'runs.activity_type', tsUnion: 'ActivityType' },
	{ tableColumn: 'routes.surface', tsUnion: 'RouteSurface' },
	{ tableColumn: 'route_markers.kind', tsUnion: 'RouteMarkerKind' },
	{ tableColumn: 'route_conditions.condition', tsUnion: 'RouteConditionKind' },
	{ tableColumn: 'route_conditions.severity', tsUnion: 'RouteConditionSeverity' },
	{ tableColumn: 'integrations.provider', tsUnion: 'IntegrationProvider' },
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
// `check (<col> in (...))` clause encountered. Returns the LAST occurrence
// per `<table>.<column>` (later migrations win).
function parseChecks(sql) {
	const out = new Map();

	const stripped = sql
		.replace(/--[^\n]*/g, '')
		.replace(/\/\*[\s\S]*?\*\//g, '');

	const tableRe = /\b(?:create\s+table|alter\s+table)\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-z_][a-z0-9_]*)/gi;
	const checkRe = /check\s*\(\s*([a-z_][a-z0-9_]*)\s+in\s*\(([^)]*)\)\s*\)/gi;

	const hits = [];
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

function loadAllMigrationChecks() {
	const merged = new Map();
	const files = readdirSync(MIGRATIONS_DIR)
		.filter((f) => f.endsWith('.sql'))
		.sort();
	for (const f of files) {
		const sql = readFileSync(join(MIGRATIONS_DIR, f), 'utf-8');
		const local = parseChecks(sql);
		for (const [key, values] of local) merged.set(key, values);
	}
	return merged;
}

// Extract the literal-string members of an exported TS union. Handles
// both single-line (`= 'a' | 'b';`) and multi-line forms.
function parseTsUnion(types, name) {
	const re = new RegExp(`export\\s+type\\s+${name}\\s*=([^;]+);`, 'm');
	const m = types.match(re);
	if (!m) return null;
	const out = new Set();
	const valueRe = /'([^']+)'/g;
	let v;
	while ((v = valueRe.exec(m[1])) !== null) out.add(v[1]);
	return out.size === 0 ? null : out;
}

function setsEqual(a, b) {
	if (a.size !== b.size) return false;
	for (const x of a) if (!b.has(x)) return false;
	return true;
}

function diff(a, b) {
	const onlyA = [...a].filter((x) => !b.has(x));
	const onlyB = [...b].filter((x) => !a.has(x));
	return { onlyA, onlyB };
}

function main() {
	const checks = loadAllMigrationChecks();
	const types = readFileSync(TYPES_FILE, 'utf-8');

	let failed = false;
	for (const { tableColumn, tsUnion } of PAIRS) {
		const checkValues = checks.get(tableColumn);
		const tsValues = parseTsUnion(types, tsUnion);

		if (!checkValues) {
			console.error(
				`[FAIL] ${tsUnion}: no CHECK constraint found on "${tableColumn}" in migrations.`,
			);
			failed = true;
			continue;
		}
		if (!tsValues) {
			console.error(
				`[FAIL] ${tsUnion}: TS union not found in apps/web/src/lib/types.ts.`,
			);
			failed = true;
			continue;
		}
		if (!setsEqual(checkValues, tsValues)) {
			const { onlyA: onlyInCheck, onlyB: onlyInTs } = diff(checkValues, tsValues);
			console.error(
				`[FAIL] ${tsUnion} drift on ${tableColumn}:\n` +
					`  CHECK only: ${onlyInCheck.length ? onlyInCheck.join(', ') : '(none)'}\n` +
					`  TS only:    ${onlyInTs.length ? onlyInTs.join(', ') : '(none)'}\n` +
					`  Fix: update the migration AND the TS union so both list the same values.`,
			);
			failed = true;
			continue;
		}
		console.log(
			`[OK] ${tsUnion} (${tableColumn}): ${[...tsValues].sort().join(', ')}`,
		);
	}

	return failed ? 1 : 0;
}

process.exit(main());
