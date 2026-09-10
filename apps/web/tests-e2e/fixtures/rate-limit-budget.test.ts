import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { stripComments } from '../../src/lib/core/strip_comments';

/*
 * A spec that creates a rate-limited entity has to state its budget.
 *
 * `public.rate_limits` is keyed (user_id, bucket, window_start) on the clock
 * hour, so a spec that creates a club or a route as one of the three SEEDED
 * users is spending a budget every other spec in the run — and every run
 * started in the same hour — is spending too. `docs/testing/testing.md § 7`
 * spells the rule out and decisions § 1554 fixed the route side, but the rule
 * was prose: the next spec to drive a create without a `resetRateLimit` in its
 * `beforeEach` re-opens the ordering dependence that produced the round-43
 * report, and it passes in isolation and on CI's fresh-per-job stack while
 * failing locally an hour after someone ran a cap test.
 *
 * The population is DERIVED rather than listed, in three steps, so a create
 * surface nobody thought about still lands in it:
 *
 *   1. the buckets come from the migrations — every `enforce_create_rate_limit`
 *      call site — so a new bucket is undeclared until someone declares it;
 *   2. each bucket names the `core/data.ts` functions that spend it, and each
 *      is checked to still insert into the bucket's own table;
 *   3. the SURFACES come from the app: every `.svelte` that calls one of those
 *      functions must be registered, so a second create page fails the guard
 *      rather than quietly widening the rule's blind spot.
 *
 * What a spec is matched on is the submit control itself, resolved through the
 * component — an i18n key read out of `locales/en.ts`, or a `data-testid`.
 * Keying the scan on a literal `'Create club'` would fail correct code the day
 * the copy changes and pass a re-spelled violation; keying it on the key means
 * the matcher moves with the button, and a key the component no longer renders
 * fails as a stale registry entry rather than as a silently empty scan.
 */

const HERE = dirname(fileURLToPath(import.meta.url));
const E2E_ROOT = join(HERE, '..');
const WEB_SRC = join(HERE, '..', '..', 'src');
const DATA_TS = join(WEB_SRC, 'lib', 'core', 'data.ts');
const EN_LOCALE = join(WEB_SRC, 'lib', 'i18n', 'locales', 'en.ts');
const MIGRATIONS = join(HERE, '..', '..', '..', 'backend', 'supabase', 'migrations');

type Control = { message: string } | { testid: string };
type Surface = { component: string; controls: Control[] };
type Budget = {
	bucket: string;
	/** The table whose BEFORE INSERT trigger spends the bucket. */
	table: string;
	/** `core/data.ts` exports that insert into it from a client. */
	dataFns: string[];
	surfaces: Surface[];
};

/**
 * Buckets a Playwright spec can spend as a seeded user, and the surfaces that
 * spend them. Every field is re-derived below, so an entry cannot outlive what
 * it was written about.
 */
const SHARED_BUDGETS: Budget[] = [
	{
		bucket: 'create_club',
		table: 'clubs',
		dataFns: ['createClub'],
		surfaces: [
			{
				component: 'lib/components/ClubEditor.svelte',
				controls: [{ message: 'clubEditor.createClub' }]
			}
		]
	},
	{
		bucket: 'create_route',
		table: 'routes',
		dataFns: ['saveRoute', 'saveRunAsRoute'],
		surfaces: [
			{
				component: 'lib/components/ImportRoute.svelte',
				controls: [{ message: 'importRoute.saveRoute' }]
			},
			{
				component: 'routes/routes/new/+page.svelte',
				controls: [
					{ message: 'routeNew.saveRoute' },
					{ message: 'routeNew.saveRouteModal' }
				]
			},
			{
				// The save-as-route modal's confirm is addressed by testid, not by
				// copy — `runs/save-as-route.spec.ts` drives it that way, and a
				// label-only scan would have missed the whole surface.
				component: 'routes/runs/[id]/+page.svelte',
				controls: [{ testid: 'name-route-save' }]
			}
		]
	}
];

/**
 * Buckets no Playwright spec spends as a seeded user, with why. The reason is
 * prose and cannot be machine-checked, but the claim is checked in the one
 * direction that matters: if a spec resets the bucket, someone found a way to
 * spend it and the entry is wrong.
 */
const NOT_SPENT_BY_SPECS: Record<string, string> = {
	create_report:
		'admin/admin-moderation-journey.spec.ts files reports through the real submit_report ' +
		'RPC, but only ever as an ephemeral saga user whose id is minted per test and never ' +
		'reused, so the bucket it spends is its own and cannot reach another spec.',
	create_challenge:
		'No spec creates a challenge through the UI; challenges/*.spec.ts seed rows with the ' +
		'service-role client, which migration 20260616_001 exempts from the limit outright.',
	send_direct_message:
		'The messaging specs send as saga users, and the burst budget below is the same rail.',
	send_direct_message_burst:
		'The per-minute companion to send_direct_message, spent by the same saga-user sends.',
	clone_plan_template:
		'Plan and routine cloning is exercised in pgtap (clone_plan_template_test.sql and ' +
		'siblings), where each file runs in its own rolled-back transaction.',
	clone_public_plan: 'Same as clone_plan_template — pgtap only.',
	clone_session_template: 'Same as clone_plan_template — pgtap only.',
	clone_gym_routine_template: 'Same as clone_plan_template — pgtap only.',
	publish_gym_routine_as_template: 'Same as clone_plan_template — pgtap only.'
};

function walk(dir: string, ext: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules' || entry === '.auth' || entry === '.svelte-kit') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) walk(full, ext, out);
		else if (full.endsWith(ext)) out.push(full);
	}
	return out;
}

/** Every bucket name the migrations pass to `enforce_create_rate_limit`. */
function enforcedBuckets(): Set<string> {
	const out = new Set<string>();
	for (const file of walk(MIGRATIONS, '.sql')) {
		const sql = readFileSync(file, 'utf8');
		for (const m of sql.matchAll(/enforce_create_rate_limit\s*\(\s*'([a-z_]+)'/g)) out.add(m[1]);
	}
	return out;
}

/** The body of `export async function <name>` in data.ts, up to the next export. */
function exportedBody(source: string, name: string): string | null {
	const start = source.indexOf(`export async function ${name}(`);
	if (start === -1) return null;
	const next = source.indexOf('\nexport ', start + 1);
	return source.slice(start, next === -1 ? source.length : next);
}

function englishLabel(key: string): string | null {
	const locale = readFileSync(EN_LOCALE, 'utf8');
	const line = locale
		.split('\n')
		.find((l) => l.trimStart().startsWith(`"${key}":`));
	if (line === undefined) return null;
	return /:\s*"((?:[^"\\]|\\.)*)"/.exec(line)?.[1] ?? null;
}

/** The literal strings a spec would address each surface's submit control by. */
function markersFor(budget: Budget): string[] {
	const out: string[] = [];
	for (const surface of budget.surfaces) {
		for (const control of surface.controls) {
			if ('testid' in control) out.push(control.testid);
			else {
				const label = englishLabel(control.message);
				if (label !== null) out.push(label);
			}
		}
	}
	return out;
}

/** The span of every `test.beforeEach(...)` callback in a spec. */
function beforeEachBodies(source: string): string[] {
	const out: string[] = [];
	const hook = /\btest\s*\.\s*beforeEach\s*\(/g;
	// The match itself is never read — `hook.lastIndex` is what the scan walks
	// from — so nothing binds it.
	while (hook.exec(source) !== null) {
		let depth = 1;
		let i = hook.lastIndex;
		while (i < source.length && depth > 0) {
			if (source[i] === '(') depth++;
			else if (source[i] === ')') depth--;
			i++;
		}
		out.push(source.slice(hook.lastIndex, i - 1));
	}
	return out;
}

/**
 * Whether the spec drives one of [markers] to a click or a keyboard submit.
 * Two shapes reach the same control: the marker and the `.click()` in one
 * statement, and a marker bound to a local that is clicked later — which is
 * how `routes/new.spec.ts` and `routes/generate-loop.spec.ts` both address the
 * save button, and only one of them submits.
 */
function drivesControl(source: string, markers: string[]): boolean {
	if (markers.length === 0) return false;
	const bound = new Set<string>();
	const declaration = /(?:const|let)\s+([A-Za-z_$][\w$]*)\s*=\s*([^;]*);/g;
	let match: RegExpExecArray | null;
	while ((match = declaration.exec(source))) {
		if (markers.some((marker) => match![2].includes(marker))) bound.add(match[1]);
	}
	for (const statement of source.split(';')) {
		if (!/\.\s*(click|press|dispatchEvent)\s*\(/.test(statement)) continue;
		if (markers.some((marker) => statement.includes(marker))) return true;
		for (const binding of bound) {
			if (new RegExp(`\\b${binding}\\s*\\.\\s*(click|press|dispatchEvent)\\s*\\(`).test(statement)) {
				return true;
			}
		}
	}
	return false;
}

/** Spec files that drive [budget]'s controls as one of the seeded users. */
/**
 * The specs that drive one of `budget`'s create controls AS A SEEDED USER.
 *
 * The seeded-user filter is the scope of the whole rule, not an optimisation:
 * `rate_limits` is keyed on the user, so a spec creating as an ephemeral saga
 * user (`createSagaUsers` mints a fresh uuid per test) spends a bucket no
 * other spec has heard of and can leak nothing. `cross-user/sagas/*` is out
 * of scope for that reason and needs no exemption — which is what an
 * exemption list here got wrong, listing a saga spec this filter had already
 * excluded.
 */
function driversOf(budget: Budget): string[] {
	const markers = markersFor(budget);
	const out: string[] = [];
	for (const file of walk(E2E_ROOT, '.spec.ts')) {
		const source = stripComments(readFileSync(file, 'utf8'));
		if (!/\bUSER_[A-Z][A-Z_]*\b/.test(source)) continue;
		if (!drivesControl(source, markers)) continue;
		out.push(relative(E2E_ROOT, file).split('\\').join('/'));
	}
	return out;
}

function statesBudget(file: string, bucket: string): boolean {
	const source = stripComments(readFileSync(join(E2E_ROOT, file), 'utf8'));
	const spends = new RegExp(`resetRateLimit\\s*\\([^)]*'${bucket}'`);
	return beforeEachBodies(source).some((body) => spends.test(body));
}

test('every rate-limit bucket the migrations enforce is declared', () => {
	const enforced = enforcedBuckets();
	assert.ok(enforced.size >= 8, `only ${enforced.size} buckets parsed out of the migrations`);
	const declared = new Set([
		...SHARED_BUDGETS.map((b) => b.bucket),
		...Object.keys(NOT_SPENT_BY_SPECS)
	]);
	assert.deepEqual(
		[...enforced].filter((b) => !declared.has(b)).sort(),
		[],
		'A new rate-limit bucket is enforced and nothing says whether a Playwright spec can ' +
			'spend it. Add it to SHARED_BUDGETS with its surfaces, or to NOT_SPENT_BY_SPECS with why.'
	);
	assert.deepEqual(
		[...declared].filter((b) => !enforced.has(b)).sort(),
		[],
		'A declared bucket is no longer enforced by any migration — drop the entry.'
	);
	for (const [bucket, reason] of Object.entries(NOT_SPENT_BY_SPECS)) {
		assert.ok(reason.trim().length > 40, `${bucket} is declared unspent with no real reason`);
	}
});

test('each budget still names the data-layer functions that spend it', () => {
	const data = readFileSync(DATA_TS, 'utf8');
	for (const budget of SHARED_BUDGETS) {
		assert.ok(budget.dataFns.length > 0, `${budget.bucket} names no data-layer function`);
		for (const fn of budget.dataFns) {
			const body = exportedBody(data, fn);
			assert.ok(body !== null, `core/data.ts no longer exports ${fn} (${budget.bucket})`);
			assert.match(
				body,
				new RegExp(`from\\(\\s*'${budget.table}'\\s*\\)[\\s\\S]{0,400}?\\.insert\\(`),
				`${fn} no longer inserts into ${budget.table}, so it no longer spends ${budget.bucket}`
			);
		}
	}
});

test('every component that creates through one of those functions is a registered surface', () => {
	const registered = new Set(
		SHARED_BUDGETS.flatMap((b) => b.surfaces.map((s) => s.component))
	);
	const found = new Set<string>();
	for (const file of walk(WEB_SRC, '.svelte')) {
		const source = readFileSync(file, 'utf8');
		for (const budget of SHARED_BUDGETS) {
			if (!budget.dataFns.some((fn) => new RegExp(`\\bawait\\s+${fn}\\s*\\(`).test(source))) {
				continue;
			}
			found.add(relative(WEB_SRC, file).split('\\').join('/'));
		}
	}
	assert.deepEqual(
		[...found].filter((c) => !registered.has(c)).sort(),
		[],
		'A component creates a rate-limited row and is not a registered surface, so the spec ' +
			'scan below cannot see the control it submits through. Register it in SHARED_BUDGETS.'
	);
	assert.deepEqual(
		[...registered].filter((c) => !found.has(c)).sort(),
		[],
		'A registered surface no longer creates anything — drop it, or the scan is matching a ' +
			'control that costs nothing.'
	);
});

test('every registered control still resolves in its own component', () => {
	for (const budget of SHARED_BUDGETS) {
		for (const surface of budget.surfaces) {
			const source = readFileSync(join(WEB_SRC, surface.component), 'utf8');
			assert.ok(surface.controls.length > 0, `${surface.component} names no control`);
			for (const control of surface.controls) {
				if ('testid' in control) {
					assert.ok(
						source.includes(`data-testid="${control.testid}"`),
						`${surface.component} no longer carries data-testid="${control.testid}"`
					);
					continue;
				}
				assert.ok(
					source.includes(`'${control.message}'`),
					`${surface.component} no longer renders m('${control.message}')`
				);
				const label = englishLabel(control.message);
				assert.ok(
					label !== null && label.length > 0,
					`locales/en.ts no longer carries "${control.message}", so the scan for the ` +
						'control it names silently matches nothing'
				);
			}
		}
	}
});

test('a spec that creates as a seeded user states its rate-limit budget in beforeEach', () => {
	const offenders: string[] = [];
	for (const budget of SHARED_BUDGETS) {
		const drivers = driversOf(budget);
		assert.ok(
			drivers.length > 0,
			`no spec drives ${budget.bucket}'s controls — the scan has stopped matching anything`
		);
		for (const file of drivers) {
			if (statesBudget(file, budget.bucket)) continue;
			offenders.push(`${file} (${budget.bucket})`);
		}
	}
	assert.deepEqual(
		offenders,
		[],
		'These specs drive a create control as one of the seeded users without resetting the ' +
			'bucket in a test.beforeEach. `rate_limits` is one row per (user, bucket, clock hour) ' +
			'shared by the whole run, so the budget they get is whatever the last spec left — and ' +
			'a cap test that leaked its plant makes every create in the suite fail for the rest of ' +
			'the hour (docs/testing/testing.md § 7, decisions § 1554). Add ' +
			`resetRateLimit(USER_A.id, '<bucket>') to a test.beforeEach: ${offenders.join(', ')}`
	);
});
