import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
	AI_DISCLOSURE_CURRENT_VERSION,
	AI_DISCLOSURE_ERROR,
	AI_DISCLOSURE_VERSION_COACH,
	AI_DISCLOSURE_VERSION_ROUTE_AI,
	aiDisclosureDenialBody,
	aiDisclosureFromProfileRow,
	checkAiDisclosure,
	gateAiDisclosure,
} from './ai_disclosure';

async function captureConsoleError(fn: () => Promise<unknown>): Promise<string[]> {
	const lines: string[] = [];
	const original = console.error;
	console.error = (...args: unknown[]) => {
		lines.push(args.map((a) => String(a)).join(' '));
	};
	try {
		await fn();
	} finally {
		console.error = original;
	}
	return lines;
}

const ACCEPTED = '2026-01-01T00:00:00Z';

// ─────────────── checkAiDisclosure ───────────────

test('a v1 Coach acceptance does NOT satisfy the widened route-AI scope', () => {
	// Reason: issue #734. This is the whole point of versioning the record.
	// Treating the Coach stamp as covering the route endpoints retroactively
	// broadens what an existing user agreed to.
	const record = { version: AI_DISCLOSURE_VERSION_COACH, acceptedAt: ACCEPTED };
	assert.deepEqual(checkAiDisclosure(record, AI_DISCLOSURE_VERSION_COACH), {
		ok: true,
		version: 1,
	});
	assert.deepEqual(checkAiDisclosure(record, AI_DISCLOSURE_VERSION_ROUTE_AI), {
		ok: false,
		reason: 'stale',
	});
});

test('the widened acceptance satisfies both scopes', () => {
	const record = { version: AI_DISCLOSURE_VERSION_ROUTE_AI, acceptedAt: ACCEPTED };
	assert.equal(checkAiDisclosure(record, AI_DISCLOSURE_VERSION_COACH).ok, true);
	assert.equal(checkAiDisclosure(record, AI_DISCLOSURE_VERSION_ROUTE_AI).ok, true);
});

test('no record at all denies as missing', () => {
	assert.deepEqual(checkAiDisclosure({ version: null, acceptedAt: null }, 1), {
		ok: false,
		reason: 'missing',
	});
	assert.deepEqual(checkAiDisclosure({ version: undefined, acceptedAt: undefined }, 1), {
		ok: false,
		reason: 'missing',
	});
});

test('half a record is not a record — either half missing denies', () => {
	// The DB CHECK forbids this pairing, so reaching it means a corrupt row
	// or a caller reading a partial projection. Deny either way.
	assert.deepEqual(checkAiDisclosure({ version: 2, acceptedAt: null }, 1), {
		ok: false,
		reason: 'missing',
	});
	assert.deepEqual(checkAiDisclosure({ version: null, acceptedAt: ACCEPTED }, 1), {
		ok: false,
		reason: 'missing',
	});
	assert.deepEqual(checkAiDisclosure({ version: 2, acceptedAt: '' }, 1), {
		ok: false,
		reason: 'missing',
	});
});

test('a version outside this build’s ladder denies as unknown, never grants', () => {
	// A disclosure this build cannot render is one it cannot prove was made.
	assert.deepEqual(
		checkAiDisclosure({ version: AI_DISCLOSURE_CURRENT_VERSION + 1, acceptedAt: ACCEPTED }, 1),
		{ ok: false, reason: 'unknown' },
	);
	assert.deepEqual(checkAiDisclosure({ version: 0, acceptedAt: ACCEPTED }, 1), {
		ok: false,
		reason: 'unknown',
	});
	assert.deepEqual(checkAiDisclosure({ version: -3, acceptedAt: ACCEPTED }, 1), {
		ok: false,
		reason: 'unknown',
	});
});

test('a non-integer / non-numeric version denies as unknown', () => {
	for (const version of ['2', 2.5, true, {}, [], NaN, Infinity]) {
		assert.deepEqual(
			checkAiDisclosure({ version, acceptedAt: ACCEPTED }, 1),
			{ ok: false, reason: 'unknown' },
			`version ${String(version)} must not be trusted`,
		);
	}
});

test('a non-string acceptance timestamp denies as missing', () => {
	for (const acceptedAt of [0, 1735689600000, true, {}]) {
		assert.deepEqual(checkAiDisclosure({ version: 2, acceptedAt }, 1), {
			ok: false,
			reason: 'missing',
		});
	}
});

// ─────────────── aiDisclosureFromProfileRow ───────────────

test('aiDisclosureFromProfileRow reads both halves off a profile row', () => {
	assert.deepEqual(
		aiDisclosureFromProfileRow({
			ai_disclosure_version: 2,
			coach_consent_at: ACCEPTED,
			display_name: 'Test Runner',
		}),
		{ version: 2, acceptedAt: ACCEPTED },
	);
});

test('aiDisclosureFromProfileRow on a null / non-object row yields an empty record', () => {
	for (const row of [null, undefined, 'nope', 7]) {
		assert.deepEqual(aiDisclosureFromProfileRow(row), { version: null, acceptedAt: null });
		assert.equal(checkAiDisclosure(aiDisclosureFromProfileRow(row), 1).ok, false);
	}
});

// ─────────────── gateAiDisclosure ───────────────

test('gateAiDisclosure passes a sufficient record through', async () => {
	const gate = await gateAiDisclosure(
		async () => ({
			data: { ai_disclosure_version: 2, coach_consent_at: ACCEPTED },
			error: null,
		}),
		AI_DISCLOSURE_VERSION_ROUTE_AI,
		'route-describe',
	);
	assert.deepEqual(gate, { ok: true, version: 2 });
});

test('gateAiDisclosure denies a stale record with 403 and names the reason in the log', async () => {
	let gate: Awaited<ReturnType<typeof gateAiDisclosure>> | undefined;
	const lines = await captureConsoleError(async () => {
		gate = await gateAiDisclosure(
			async () => ({
				data: { ai_disclosure_version: 1, coach_consent_at: ACCEPTED },
				error: null,
			}),
			AI_DISCLOSURE_VERSION_ROUTE_AI,
			'route-request',
		);
	});
	assert.deepEqual(gate, { ok: false, status: 403, reason: 'stale' });
	assert.ok(
		lines.some((l) => l.includes('[route-request] ai disclosure denied')),
		'a denial must be operationally visible',
	);
});

test('gateAiDisclosure fails closed with 500 when the lookup errors or throws', async () => {
	// Reason: an unreadable consent record is not consent. Defaulting to
	// "no version" would be indistinguishable from a genuine denial, so the
	// caller gets a transient 500 rather than a permanent-looking 403.
	await captureConsoleError(async () => {
		const errored = await gateAiDisclosure(
			async () => ({ data: null, error: { code: '42501', message: 'permission denied' } }),
			1,
			'coach',
		);
		assert.deepEqual(errored, { ok: false, status: 500, reason: 'lookup_failed' });

		const threw = await gateAiDisclosure(
			async () => {
				throw new Error('network down');
			},
			1,
			'coach',
		);
		assert.deepEqual(threw, { ok: false, status: 500, reason: 'lookup_failed' });
	});
});

test('gateAiDisclosure never logs the raw Supabase error object', async () => {
	// Mirrors the supabaseErrorFields discipline — `.details` / `.hint` can
	// echo row fragments, and this row carries consent + profile data.
	const lines = await captureConsoleError(async () => {
		await gateAiDisclosure(
			async () => ({
				data: null,
				error: {
					code: '42501',
					message: 'permission denied',
					details: 'row: display_name=Ada',
					hint: 'grant select',
				} as { code?: string; message?: string },
			}),
			1,
			'coach',
		);
	});
	assert.ok(lines.length > 0);
	assert.ok(
		!lines.some((l) => l.includes('Ada')),
		'the log line must carry only code + message',
	);
});

// ─────────────── wire shape + SQL parity ───────────────

test('the denial body carries the machine-readable code and the required version', () => {
	// `code`, not `error`: each endpoint keeps its own `error` string, so a
	// client that wants to prompt for consent has one field to branch on.
	assert.deepEqual(aiDisclosureDenialBody(AI_DISCLOSURE_VERSION_ROUTE_AI), {
		code: AI_DISCLOSURE_ERROR,
		required_version: 2,
	});
});

test('AI_DISCLOSURE_CURRENT_VERSION matches ai_disclosure_current_version() in SQL', () => {
	// Reason: the DB refuses to record a version above its own maximum and
	// the gate refuses to trust one above the build's. If the two drift, a
	// user can be asked to accept a version that cannot be stored, or a
	// stored version stops being honoured. Same class of guard as the
	// CHECK-constraint ↔ TS-union parity check.
	const sql = readFileSync(
		resolve('../backend/supabase/migrations/20270511_001_ai_disclosure_consent_version.sql'),
		'utf-8',
	);
	const match = sql.match(
		/create or replace function ai_disclosure_current_version\(\)[\s\S]*?select\s+(\d+)::smallint/,
	);
	assert.ok(match, 'ai_disclosure_current_version() must be defined in the migration');
	assert.equal(
		Number(match[1]),
		AI_DISCLOSURE_CURRENT_VERSION,
		'the SQL and TS disclosure versions must stay in lockstep',
	);
});

test('the version ladder is ordered and the current version is its top rung', () => {
	assert.ok(AI_DISCLOSURE_VERSION_COACH < AI_DISCLOSURE_VERSION_ROUTE_AI);
	assert.equal(AI_DISCLOSURE_CURRENT_VERSION, AI_DISCLOSURE_VERSION_ROUTE_AI);
});
