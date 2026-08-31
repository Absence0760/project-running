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

// The ban above names ONE spelling of the arithmetic. decisions.md § 738 is
// the standing lesson that a guard which lists shapes rots into a guard that
// passes the defect wearing a different sentence, so the scan below covers the
// family: a week of milliseconds written any of the ways JavaScript spells it,
// and a FLOORED millisecond division of any kind on these surfaces.
//
// The floor is the discriminator, not the division. Both surfaces legitimately
// divide by a day of milliseconds to count days — but they `Math.round`, which
// absorbs the ±1 h a DST-crossing local-midnight span carries. `Math.floor` of
// the same span is what lands a day (and, over seven, a week) short.

/** Line-numbered source with `//` and block comments blanked, so a ban cannot fire on prose. */
function scannableLines(rel: string): { line: number; text: string }[] {
	const raw = readFileSync(resolve(rel), 'utf-8');
	let out = '';
	let i = 0;
	let inBlock = false;
	while (i < raw.length) {
		if (inBlock) {
			if (raw.startsWith('*/', i)) {
				inBlock = false;
				out += '  ';
				i += 2;
			} else {
				out += raw[i] === '\n' ? '\n' : ' ';
				i++;
			}
			continue;
		}
		if (raw.startsWith('/*', i)) {
			inBlock = true;
			out += '  ';
			i += 2;
			continue;
		}
		if (raw.startsWith('//', i)) {
			while (i < raw.length && raw[i] !== '\n') {
				out += ' ';
				i++;
			}
			continue;
		}
		out += raw[i];
		i++;
	}
	return out.split('\n').map((text, idx) => ({ line: idx + 1, text }));
}

/** A week of milliseconds, however it is spelled. */
const WEEK_MS_SPELLINGS = [
	/604_?800_?000/,
	/7\s*\*\s*86_?400_?000/,
	/86_?400_?000\s*\*\s*7/,
	/7\s*\*\s*24\s*\*\s*60\s*\*\s*60\s*\*\s*1000/,
	/24\s*\*\s*7\s*\*\s*60\s*\*\s*60\s*\*\s*1000/,
];

test('no plan surface spells a week of milliseconds at all', () => {
	for (const rel of PLAN_SURFACES) {
		for (const { line, text } of scannableLines(rel)) {
			for (const pattern of WEEK_MS_SPELLINGS) {
				assert.doesNotMatch(
					text,
					pattern,
					`${rel}:${line} spells a week in milliseconds. A plan week is seven ` +
						'calendar days, and a calendar span is not a duration — bucket ' +
						'through currentPlanWeekIndex instead.\n  ' +
						text.trim(),
				);
			}
		}
	}
});

test('no plan surface floors a millisecond span into a day or week count', () => {
	// `Math.round(ms / 86_400_000)` is fine and both surfaces use it: a
	// 167 h or 169 h span still rounds to the right number of days. The
	// floored form is the one that silently loses the hour.
	const FLOORED_MS_DIVISION = /Math\.floor\([^;]*?\/\s*\(?\s*(?:day(?:Ms|MS)|86_?400_?000|604_?800_?000|1000\s*\*\s*60)/;
	for (const rel of PLAN_SURFACES) {
		for (const { line, text } of scannableLines(rel)) {
			assert.doesNotMatch(
				text,
				FLOORED_MS_DIVISION,
				`${rel}:${line} floors an elapsed-millisecond division. Across a DST ` +
					'transition the span is 23 or 25 hours per day and the floor lands ' +
					'short — count whole UTC epoch-days instead.\n  ' + text.trim(),
			);
		}
	}
});

test('the scan sees the shapes it bans, and spares the ones it must not', () => {
	// § 738: a scan is the only instrument that can see this defect, so a
	// shape it misses is a shape that returns. Probe both directions rather
	// than trusting the regexes by reading them.
	const banned = [
		'const w = Math.floor(ms / 604800000);',
		'const w = Math.floor(ms / (7 * 86_400_000));',
		'const w = Math.floor(ms / (86400000 * 7));',
		'const w = Math.floor(ms / (7 * 24 * 60 * 60 * 1000));',
		'const d = Math.floor((end - start) / dayMs);',
		'const d = Math.floor((end - start) / 86_400_000);',
	];
	for (const probe of banned) {
		const hitsWeek = WEEK_MS_SPELLINGS.some((p) => p.test(probe));
		const hitsFloor =
			/Math\.floor\([^;]*?\/\s*\(?\s*(?:day(?:Ms|MS)|86_?400_?000|604_?800_?000|1000\s*\*\s*60)/.test(
				probe,
			);
		assert.ok(hitsWeek || hitsFloor, `the scan misses: ${probe}`);
	}
	const allowed = [
		'const days = Math.max(1, Math.round(ms / 86_400_000) + 1);',
		'const d = Math.round((end.getTime() - today.getTime()) / dayMs);',
		'const idx = currentPlanWeekIndex(p.start_date, todayISO(), totalWeeks(p));',
	];
	for (const probe of allowed) {
		const hitsWeek = WEEK_MS_SPELLINGS.some((p) => p.test(probe));
		const hitsFloor =
			/Math\.floor\([^;]*?\/\s*\(?\s*(?:day(?:Ms|MS)|86_?400_?000|604_?800_?000|1000\s*\*\s*60)/.test(
				probe,
			);
		assert.ok(!hitsWeek && !hitsFloor, `the scan wrongly accuses: ${probe}`);
	}
});
