// Source-level guards on the off-route → auto-notify-contact deploy gate.
// Invocation:
//   npx tsx --test src/lib/safety/off_route_flag.test.ts
//
// `off_route_flag` is a registered parity pair that had no mirror suite on
// EITHER side, which is the thin end of the § 641 failure: the registration
// makes divergence detectable, but nothing was pinning what either half is
// supposed to do. The instrument is the one `adaptive_fitness_gate_guard`
// already uses for a two-line env binding — SOURCE guards on the gate rather
// than value tests, because the accepted-affirmative set itself belongs to
// `core/env_flag.ts` and is pinned there.
//
// `isOffRouteEscalationEnabled` reads `$env/dynamic/public`, so the module
// cannot be imported under `tsx --test`. What matters more than the parse is
// the half nothing covered: that the escalation surface is UNREACHABLE while
// the flag is off. The flag exists so no runner's off-route departure can
// auto-notify a trusted contact before owner + CISO + counsel sign it off
// (decisions § 150), and a surface that renders is a surface that arms.
//
// The Dart mirror is `apps/mobile_android/test/off_route_flag_test.dart`.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const FLAG = 'src/lib/safety/off_route_flag.ts';
const SAFETY = 'src/routes/settings/safety/+page.svelte';

function read(path: string): string {
	return readFileSync(resolve(path), 'utf-8');
}

/// The text inside `{#if <cond>}` … `{/if}`, matched by nesting depth so a
/// `{#each}` inside the block cannot close it early. Returns null when the
/// block is absent, which a substring search would report as "found nothing
/// to complain about".
export function ifBlock(template: string, condition: string): string | null {
	const open = `{#if ${condition}}`;
	const start = template.indexOf(open);
	if (start < 0) return null;
	let depth = 1;
	const token = /\{#(?:if|each|await|key|snippet)\b|\{\/(?:if|each|await|key|snippet)\}/g;
	token.lastIndex = start + open.length;
	for (let m = token.exec(template); m; m = token.exec(template)) {
		depth += m[0].startsWith('{#') ? 1 : -1;
		if (depth === 0) return template.slice(start + open.length, m.index);
	}
	return null;
}

test('the gate is fail-closed and routed through the canonical parse', () => {
	const source = read(FLAG);
	assert.match(source, /PUBLIC_OFF_ROUTE_ESCALATION_ENABLED/);
	assert.match(
		source,
		/from\s+'\$env\/dynamic\/public'/,
		'the gate must read the deploy-time public env, not a build-time constant baked at build',
	);
	// Delegating is what keeps web and mobile from accepting different values
	// for the same documented flag (decisions § 709). The named function is
	// `off_route_alert`'s, which delegates in turn to `env_flag`.
	assert.match(
		source,
		/offRouteEscalationEnabled\(env\.PUBLIC_OFF_ROUTE_ESCALATION_ENABLED\)/,
		'the gate must delegate to offRouteEscalationEnabled rather than carry a parse',
	);
	assert.doesNotMatch(source, /\?\?\s*(true|'1'|'true')/, 'the gate must not default to on');
});

test('the block scanner finds a nested block and reports an absent one', () => {
	// Fixtures, so a scanner that stopped matching the template's shape cannot
	// pass this file by finding nothing (decisions § 762).
	assert.equal(ifBlock('{#if g}{#each xs as x}<A/>{/each}{/if}', 'g'), '{#each xs as x}<A/>{/each}');
	assert.equal(ifBlock('{#if other}<A/>{/if}', 'g'), null);
	assert.equal(ifBlock('{#if g}<A/>', 'g'), null);
});

test('every off-route escalation affordance on /settings/safety is behind the gate', () => {
	const page = read(SAFETY);
	assert.match(
		page,
		/const offRouteEnabled = isOffRouteEscalationEnabled\(\);/,
		'the page must resolve the gate',
	);
	const template = page.slice(page.indexOf('</script>'));
	const block = ifBlock(template, 'offRouteEnabled');
	assert.ok(block, 'the off-route section is no longer inside {#if offRouteEnabled} — guard is stale');

	for (const needle of [
		'safety-off-route-card',
		'safety-off-route-toggle',
		'safety.offRouteTitle',
		'saveOffRoute',
	]) {
		assert.ok(template.includes(needle), `the page no longer renders ${needle} — guard is stale`);
		assert.ok(
			block.includes(needle),
			`${needle} renders with PUBLIC_OFF_ROUTE_ESCALATION_ENABLED off`,
		);
		assert.equal(
			template.split(needle).length - 1,
			block.split(needle).length - 1,
			`${needle} also appears outside the gated block`,
		);
	}
});
