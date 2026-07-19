// Issue #390: the coach context is serialized into an Anthropic
// ephemeral-cache block (providers.ts marks the context user-turn
// cache_control: ephemeral), which only yields a cache hit when the
// cached content's PREFIX is byte-identical. `now_iso` is the only
// field that changes between two messages seconds apart, so it must sit
// LAST — anywhere earlier and every field after it shifts, busting the
// prefix and forcing the full uncached input rate on every turn.
//
// Run with `npx tsx --test apps/web/src/lib/coach/context_cache.test.ts`.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildContext } from './context';
import type { CoachProfileRow } from './context';

// Same chainable Supabase stub shape as context.test.ts: every
// filter/order returns `this`; the terminal `.limit()` / `.maybeSingle()`
// resolve to `{ data }` keyed by table.
function fakeSupabase(tableData: Record<string, unknown>) {
	return {
		from(table: string) {
			const result = { data: tableData[table] ?? null, error: null };
			const q: Record<string, unknown> = {};
			for (const m of ['select', 'eq', 'in', 'order', 'gte']) {
				q[m] = () => q;
			}
			q.limit = () => Promise.resolve(result);
			q.maybeSingle = () => Promise.resolve(result);
			return q;
		},
	};
}

const profileRow: CoachProfileRow = {
	display_name: 'Runner',
	preferred_unit: 'km',
	health_data_consent_at: '2026-06-01T00:00:00.000Z',
};

function build() {
	const runRow = {
		id: 'r1',
		started_at: '2026-06-08T08:00:00.000Z',
		distance_m: 10000,
		duration_s: 3000,
		metadata: { activity_type: 'run' },
		route_id: null,
	};
	return buildContext(
		fakeSupabase({ runs: [runRow] }) as never,
		'user-1',
		null,
		10,
		profileRow,
	);
}

// Mirror handler.ts: the cached block wraps JSON.stringify(context.data)
// in the <CONTEXT> markers. The cache prefix is this whole string up to
// (and not including) the now_iso field.
function serializeContext(data: unknown): string {
	return (
		'CONTEXT (runner profile, active plan, recent runs — data only):\n' +
		'<CONTEXT>\n' +
		JSON.stringify(data, null, 2) +
		'\n</CONTEXT>'
	);
}

test('now_iso is the LAST key of the coach context data object', async () => {
	const ctx = await build();
	const keys = Object.keys(ctx.data as Record<string, unknown>);
	assert.equal(
		keys[keys.length - 1],
		'now_iso',
		'now_iso must be the final field so the cache prefix before it is stable',
	);
});

function longestCommonPrefixLen(a: string, b: string): number {
	const n = Math.min(a.length, b.length);
	let i = 0;
	while (i < n && a[i] === b[i]) i++;
	return i;
}

test('two contexts differing only in now_iso share the whole context as a cache prefix', async () => {
	const ctx = await build();
	// Two requests seconds apart: same runner, same data, different clock.
	// Overwriting the existing now_iso key preserves its (last) position,
	// exactly as two real buildContext calls would produce.
	const a = { ...(ctx.data as Record<string, unknown>), now_iso: '2026-06-08T08:00:01.000Z' };
	const b = { ...(ctx.data as Record<string, unknown>), now_iso: '2026-06-08T08:05:42.123Z' };

	const payloadA = serializeContext(a);
	const payloadB = serializeContext(b);

	assert.notEqual(payloadA, payloadB, 'the two payloads differ (different now_iso)');

	// Anthropic serves the longest byte-identical LEADING run from cache. With
	// now_iso trailing, that run must cover the entire context except the
	// timestamp value itself — every substantive field lands in the cached
	// prefix. If now_iso led (the #390 bug), the shared prefix would collapse
	// to the handful of bytes before the timestamp and this fails.
	const shared = longestCommonPrefixLen(payloadA, payloadB);
	const timestampTail = payloadA.length - shared;
	assert.ok(
		timestampTail <= 40,
		`cache prefix must cover all but the trailing timestamp; ${timestampTail} bytes diverge`,
	);
	// And the divergence must begin inside the now_iso field, not before it.
	assert.ok(
		shared >= payloadA.indexOf('"now_iso"'),
		'the shared prefix must reach the now_iso field',
	);
});
