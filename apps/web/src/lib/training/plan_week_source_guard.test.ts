// Source-level guard pinning the single "which plan week is it" source across
// the plan surfaces. `/plans/[id]` has always bucketed through
// `currentPlanWeekIndex` (whole UTC epoch-days); `/plans` rolled its own
// `Math.floor((today - start) / (7 * 86_400_000))` over two LOCAL midnights.
//
// A local-midnight span that crosses a spring-forward is 7*24h - 1h, so the
// floor lands a week short on every week-rollover day for the whole of DST.
// Measured in Europe/London for a plan starting 2026-03-23: on 2026-03-30 the
// list card said "Week 1" while the detail page said "Week 2", and again on
// 2026-04-06 (Week 2 vs Week 3). Two surfaces of the same plan, disagreeing.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const PLAN_SURFACES = ['src/routes/plans/+page.svelte', 'src/routes/plans/[id]/+page.svelte'];

test('every plan surface derives its week index from plan_week.ts', () => {
	for (const rel of PLAN_SURFACES) {
		const source = readFileSync(resolve(rel), 'utf-8');
		assert.match(
			source,
			/import \{ currentPlanWeekIndex \} from '\$lib\/training\/plan_week'/,
			`${rel} must import currentPlanWeekIndex`,
		);
		assert.match(source, /currentPlanWeekIndex\(/, `${rel} must call currentPlanWeekIndex`);
	}
});

test('no plan surface divides an elapsed span by a week of milliseconds', () => {
	for (const rel of PLAN_SURFACES) {
		const source = readFileSync(resolve(rel), 'utf-8');
		assert.doesNotMatch(
			source,
			/\/\s*\(?\s*7\s*\*\s*86_?400_?000/,
			`${rel} must not derive a week index by dividing elapsed milliseconds - ` +
				'a DST-crossing local-midnight span is 167 or 169 hours',
		);
	}
});
