// The Art 9 weigh-in gate, and whether the surface it gates is actually
// behind it. Invocation:
//   npx tsx --test src/lib/runs/weigh_in_flag.test.ts
//
// `isWeighInEnabled` reads `$env/dynamic/public`, so the module cannot be
// imported under `tsx --test`; its parse is pinned in `core/env_flag.test
// .ts` (which walks every `*_flag.ts`). What has no coverage anywhere is
// the half that matters: that body weight, the medical-hold flag and the
// organiser consent action are UNREACHABLE while the flag is off. The
// flag exists so no Art 9 health data can be collected before owner +
// CISO + counsel sign it off (decisions § 150), and the DB is only the
// other half of the pair — a surface that renders is a surface that asks.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const FLAG = 'src/lib/runs/weigh_in_flag.ts';
const BOARD = 'src/routes/clubs/[slug]/events/[id]/board/+page.svelte';

function read(path: string): string {
	return readFileSync(resolve(path), 'utf-8');
}

test('the gate is fail-closed and routed through the canonical parse', () => {
	const source = read(FLAG);
	assert.match(source, /PUBLIC_WEIGH_IN_ENABLED/);
	// Unset -> undefined -> off. The affirmative set itself lives in
	// core/env_flag.ts and is pinned there; what this asserts is that the
	// gate delegates rather than carrying a copy (decisions § 709).
	assert.match(
		source,
		/isTruthyFlagValue\(env\.PUBLIC_WEIGH_IN_ENABLED\)/,
		'the gate must delegate to isTruthyFlagValue',
	);
	assert.doesNotMatch(
		source,
		/\?\?\s*(true|'1'|'true')/,
		'the gate must not default to on',
	);
});

/// Svelte block nesting, resolved far enough to answer "is this character
/// inside an `{#if}` whose condition names the flag". A token guarded by
/// `{#if weighInEnabled}` two levels up is what the template actually
/// relies on, and a substring search cannot see it.
function guardedRanges(template: string, flagName: string): (i: number) => boolean {
	type Frame = { close: string; guarded: boolean };
	const stack: Frame[] = [];
	const marks: { at: number; depth: number }[] = [];
	const token = /\{#(if|each|await|key|snippet)\b([^}]*)\}|\{:else([^}]*)\}|\{\/(if|each|await|key|snippet)\}/g;
	const flag = new RegExp(`\\b${flagName}\\b`);
	let guardedDepth = 0;
	let last = 0;
	const push = (at: number) => {
		marks.push({ at, depth: guardedDepth });
		last = at;
	};
	push(0);
	for (const m of template.matchAll(token)) {
		const at = m.index ?? 0;
		if (m[1]) {
			const guarded = m[1] === 'if' && flag.test(m[2] ?? '');
			stack.push({ close: m[1], guarded });
			if (guarded) guardedDepth++;
			push(at + m[0].length);
		} else if (m[3] !== undefined) {
			// `{:else}` leaves the guarded branch; `{:else if flag}` re-enters.
			const top = stack[stack.length - 1];
			if (top && top.close === 'if') {
				if (top.guarded) guardedDepth--;
				top.guarded = flag.test(m[3]);
				if (top.guarded) guardedDepth++;
			}
			push(at + m[0].length);
		} else {
			const top = stack.pop();
			if (top?.guarded) guardedDepth--;
			push(at + m[0].length);
		}
	}
	void last;
	return (i: number) => {
		let depth = 0;
		for (const mark of marks) {
			if (mark.at > i) break;
			depth = mark.depth;
		}
		return depth > 0;
	};
}

test('the block scanner sees a nested guard and refuses an unguarded sibling', () => {
	// Fixtures, so a scanner that stopped matching the template's shape
	// cannot pass this file by finding nothing (decisions § 762).
	const inside = guardedRanges('{#if weighInEnabled}{#each rows as r}<X/>{/each}{/if}', 'weighInEnabled');
	assert.equal(inside('{#if weighInEnabled}{#each rows as r}'.length + 1), true);

	const after = guardedRanges('{#if weighInEnabled}<A/>{/if}<B/>', 'weighInEnabled');
	assert.equal(after('{#if weighInEnabled}<A/>{/if}'.length + 1), false);

	const other = guardedRanges('{#if somethingElse}<A/>{/if}', 'weighInEnabled');
	assert.equal(other('{#if somethingElse}'.length + 1), false);

	const elseBranch = guardedRanges('{#if weighInEnabled}<A/>{:else}<B/>{/if}', 'weighInEnabled');
	assert.equal(elseBranch('{#if weighInEnabled}<A/>{:else}'.length + 1), false);
});

test('every Art 9 weigh-in affordance on the board is behind the flag', () => {
	const page = read(BOARD);
	assert.match(
		page,
		/const weighInEnabled = isWeighInEnabled\(\);/,
		'the board must resolve the gate',
	);
	const templateAt = page.indexOf('</script>');
	assert.ok(templateAt > 0, 'no template found on the board page');
	const template = page.slice(templateAt);
	const guarded = guardedRanges(template, 'weighInEnabled');

	// Every rendered trace of the health surface: the column, the badge,
	// the entry affordance, the modal, the consent checkbox, and the stored
	// weight itself.
	const affordances = [
		'checkpoint.weighInTitle',
		'checkpoint.recordWeighIn',
		'checkpoint.medicalHoldBadge',
		'weigh-in-modal',
		'weigh-in-consent',
		'openWeighIn(',
		'body_weight_kg',
	];
	let found = 0;
	for (const needle of affordances) {
		let from = template.indexOf(needle);
		assert.notEqual(from, -1, `the board no longer renders ${needle} — guard is stale`);
		while (from !== -1) {
			found++;
			assert.ok(
				guarded(from),
				`${needle} at template offset ${from} renders with PUBLIC_WEIGH_IN_ENABLED off`,
			);
			from = template.indexOf(needle, from + needle.length);
		}
	}
	assert.ok(found >= affordances.length, 'expected at least one site per affordance');
});

test('the organiser consent flag is only sent from behind an explicit tick', () => {
	const page = read(BOARD);
	const save = page.slice(
		page.indexOf('async function saveWeighIn'),
		page.indexOf('</script>'),
	);
	assert.ok(save.length > 0, 'saveWeighIn not found — did it move?');
	assert.match(
		save,
		/if\s*\(!wConsent\)\s*\{[\s\S]*?return;/,
		'saveWeighIn must refuse without an explicit consent tick',
	);
	const consentAt = save.indexOf('healthConsent: true');
	assert.notEqual(consentAt, -1, 'the upsert must still pass the consent term');
	assert.ok(
		save.indexOf('if (!wConsent)') < consentAt,
		'the consent refusal must precede the upsert that carries p_health_consent',
	);
});
