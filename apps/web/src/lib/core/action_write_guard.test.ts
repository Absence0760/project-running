// Source-level guard pinning the issue #236 fix on the web side.
// supabase-js resolves errors instead of rejecting, so a bare-awaited
// write on an action path swallows the failure: linkRunToRoute showed
// the "Linked to route" toast and flipped route_id locally while the
// write failed (route_id feeds plan progress + segment auto-compute),
// replaceSessionPlanChildren could duplicate every block/item after a
// resolved-with-error delete, and a resolved-error decrement_coach_usage
// silently kept a failed generation's daily-cap slot consumed. Action
// writes must destructure { error } and throw.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const data = readFileSync(resolve('src/lib/core/data.ts'), 'utf-8');
const handler = readFileSync(resolve('src/lib/coach/handler.ts'), 'utf-8');

function fnBody(source: string, decl: string): string {
	const start = source.indexOf(decl);
	assert.notEqual(start, -1, `${decl} missing`);
	const next = source.indexOf('\nasync function ', start + 1);
	const nextExport = source.indexOf('\nexport ', start + 1);
	const boundaries = [next, nextExport].filter((i) => i !== -1);
	return boundaries.length === 0 ? source.slice(start) : source.slice(start, Math.min(...boundaries));
}

test('linkRunToRoute error-checks the runs.route_id update (#236)', () => {
	const body = fnBody(data, 'export async function linkRunToRoute(');
	assert.match(body, /const \{ error \}/, 'must destructure { error } from the update');
	assert.match(body, /if \(error\) throw error;/, 'must throw on a resolved error');
});

test('replaceSessionPlanChildren error-checks both child deletes (#236)', () => {
	const body = fnBody(data, 'async function replaceSessionPlanChildren(');
	assert.match(body, /itemsError\) throw itemsError/, 'items delete must throw on error');
	assert.match(body, /blocksError\) throw blocksError/, 'blocks delete must throw on error');
	assert.doesNotMatch(
		body,
		/^\s*await supabase\.from\('session_plan_(items|blocks)'\)\.delete\(\)/m,
		'no bare-awaited child delete — a resolved error would duplicate children',
	);
});

test('coach refundCapSlot surfaces a resolved rpc error (#236)', () => {
	const start = handler.indexOf('async function refundCapSlot(');
	assert.notEqual(start, -1, 'refundCapSlot missing from coach/handler.ts');
	const body = handler.slice(start, handler.indexOf('\n\t}', start));
	assert.match(
		body,
		/const \{ error \} = await supabase\.rpc\('decrement_coach_usage'/,
		'the refund rpc must destructure { error }',
	);
	assert.match(body, /if \(error\) throw error;/, 'a resolved error must reach the catch/log');
});
