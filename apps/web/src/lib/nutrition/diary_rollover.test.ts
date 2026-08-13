// Source-grep guards on /nutrition's local-midnight rollover wiring. The
// arithmetic is unit-tested (`msUntilNextLocalMidnight` in diary_day.test.ts +
// diary_day.dst.test.ts); what cannot be unit-tested without a browser is the
// wiring, so pin it in the source the way core/dashboard_load.test.ts pins the
// dashboard's mount sequence.
//
// The bug: `todayIso` / `yesterdayIso` were recomputed only inside the `$effect`,
// which fires on a `$page.url` or `authReady` change and never on the clock. A
// tab left open past local midnight kept labelling the previous day "Today" and
// kept the Next-day step disabled. No write path was affected — every write
// resolves `entryTimestampFor(viewDate, new Date())` at save time (decisions
// § 591) — so this is a stale-label bug, and the fix is sized to that.
//
// Two triggers, each costing ONE wakeup a day:
//   - a single timeout armed for the next local midnight, the only thing that
//     reaches a tab that stays visible across it (a kitchen screen);
//   - a visibility check for the tab that was backgrounded across it, where the
//     browser throttled that timer or the machine slept through it.
// A polling interval is the thing this must never become: a per-minute tick
// burns 1440 wakeups on every open tab to catch an edge that happens once.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SRC = readFileSync(
	resolve(import.meta.dirname, '../../routes/nutrition/+page.svelte'),
	'utf8',
);

test('/nutrition arms a single timeout for the next local midnight', () => {
	assert.match(
		SRC,
		/setTimeout\(syncDay,\s*msUntilNextLocalMidnight\(/,
		'the rollover must be scheduled from the calendar-stepped helper, not a fixed delay.',
	);
	assert.doesNotMatch(
		SRC,
		/86_?400_?000/,
		'a day is 23 or 25 hours across a DST transition — never a fixed 86 400 000 (decisions § 589).',
	);
	// One timer at a time, and it does not outlive the page.
	assert.match(SRC, /clearTimeout\(rolloverTimer\)/);
	assert.equal(
		(SRC.match(/clearTimeout\(rolloverTimer\)/g) ?? []).length,
		2,
		'the timer is cleared both when re-armed and when the page is destroyed.',
	);
});

test('/nutrition also re-checks the day when the tab regains visibility', () => {
	assert.match(
		SRC,
		/addEventListener\('visibilitychange',\s*onVisibility\)/,
		'a backgrounded tab has its timer throttled, or the machine slept — visibility is the second trigger.',
	);
	assert.match(
		SRC,
		/removeEventListener\('visibilitychange',\s*onVisibility\)/,
		'the listener must be torn down with the page.',
	);
	assert.match(
		SRC,
		/document\.visibilityState === 'visible'/,
		'only a tab that became visible needs the check; going hidden is not a rollover.',
	);
});

test('/nutrition does not poll for the rollover', () => {
	assert.doesNotMatch(
		SRC,
		/setInterval\(/,
		'a per-minute interval burns a wakeup on every open tab to catch a once-a-day edge.',
	);
});

test('the rollover re-resolves the day from the URL, and cannot re-arm the URL effect', () => {
	const start = SRC.indexOf('function syncDay()');
	assert.ok(start >= 0, 'Could not locate syncDay — rename?');
	const body = SRC.slice(start, SRC.indexOf('\n\tonMount(() => {', start));
	assert.match(
		body,
		/resolveDiaryDate\(\$page\.url\.searchParams\.get\(DIARY_DATE_PARAM\), now\)/,
		'a bare /nutrition must follow the clock onto the new day; an explicit past ?date= must stay put.',
	);
	// The $effect that owns the URL reads `$page.url` and `authReady`. The
	// rollover writes neither, which is what keeps it from re-arming the effect
	// that the § 591 round already had to wrap in `untrack`.
	assert.doesNotMatch(body, /\bauthReady\s*=/, 'syncDay must not write authReady — the URL effect reads it.');
	assert.doesNotMatch(body, /\bgoto\(/, 'the rollover changes the day in place; navigating would push history at midnight.');
});
