import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Every surface that turns the runner's age into a health inference reads the
// date through `healthUseDob` (decisions § 722). The rule is mechanical and
// the drift is silent — a new `.date_of_birth` read compiles, renders, and
// looks right, and nothing about it says it just spent the ungated child-safety
// record on an Art 9 purpose. So it is pinned here rather than remembered.
//
// This list is health-USE surfaces only. `/settings/preferences` and
// `/settings/account` read the column directly on purpose: they edit the age
// record itself, and gating the editor is what produced § 718's deadlock (a
// runner whose consent lapsed could neither save nor clear their own date).
const HEALTH_USE_SURFACES = [
	'../../routes/dashboard/+page.svelte',
	'../../routes/nutrition/+page.svelte',
	'../../routes/nutrition/targets/+page.svelte',
	'../components/PlanEditor.svelte',
];

for (const rel of HEALTH_USE_SURFACES) {
	test(`${rel} takes the age for health use through healthUseDob`, () => {
		const src = readFileSync(resolve(import.meta.dirname, rel), 'utf8');
		assert.ok(
			src.includes('healthUseDob'),
			`${rel} derives age for a health inference — it must go through healthUseDob`,
		);
		assert.ok(
			!src.includes('date_of_birth'),
			`${rel} reads date_of_birth directly; the age record carries no consent term, ` +
				'so a health use must resolve it through healthUseDob instead',
		);
	});
}
