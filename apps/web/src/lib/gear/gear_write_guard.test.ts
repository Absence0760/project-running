// Source-level guards for the gear backfill write path. `addGearToRuns` calls
// the `supabase` singleton directly, so the data-integrity property it carries
// can't be behaviourally unit-tested without a live stack — pin it as text,
// with the reason a future editor can read before deciding it's safe to change.
//
// Runs with cwd = apps/web (the `test:unit` script), matching the convention in
// src/lib/core/data.test.ts and src/lib/privacy_guards.test.ts.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

function bodyOf(source: string, decl: string): string {
	const start = source.indexOf(decl);
	assert.ok(start >= 0, `Could not locate ${decl} — rename?`);
	const next = source.indexOf('\nexport ', start + 1);
	return source.slice(start, next > start ? next : undefined);
}

test('addGearToRuns is additive — never a delete-then-insert of the run gear set', () => {
	// Reason: backfill attaches ONE new item to runs that may already carry
	// other gear (the auto-tag trigger stamps the current pair on every run
	// insert). setRunGear REPLACES a run's whole gear set, so reusing it here
	// would silently untag every other item on each backfilled run — a
	// data-loss bug with no error and no undo. The write must stay an upsert
	// that only ever adds rows.
	const body = bodyOf(read('src/lib/core/data.ts'), 'export async function addGearToRuns');
	assert.match(
		body,
		/\.upsert\(/,
		'addGearToRuns must write via upsert — an insert alone 23505s on a run ' +
			'that already carries this gear, which is a legitimate re-run.',
	);
	assert.match(
		body,
		/ignoreDuplicates:\s*true/,
		'addGearToRuns must pass ignoreDuplicates so a repeated backfill is a ' +
			'no-op rather than a conflict error — and because run_gear has no ' +
			'UPDATE policy, so the default merge-duplicates resolution ' +
			'(ON CONFLICT DO UPDATE) has nothing to pass on a collision.',
	);
	assert.doesNotMatch(
		body,
		/\.delete\(/,
		'addGearToRuns must never delete run_gear rows — it attaches one item ' +
			'to past runs, it does not own the rest of their gear set.',
	);
});

test('the backfill modal attaches through addGearToRuns, not setRunGear', () => {
	// Reason: same data-loss failure as above, one layer up. If the modal ever
	// reaches for setRunGear to attach the new gear, each backfilled run loses
	// whatever else was on it — including the current pair the auto-tag trigger
	// stamped on it at insert.
	const modal = read('src/lib/components/GearBackfillModal.svelte');
	assert.match(
		modal,
		/addGearToRuns\(/,
		'GearBackfillModal must attach candidates via addGearToRuns.',
	);
	assert.doesNotMatch(
		modal,
		/setRunGear/,
		"GearBackfillModal must not call setRunGear — that replaces a run's whole " +
			"gear set and would untag the runner's other gear.",
	);
});

test('backfill candidates are fetched column-narrowed and windowed by the purchase date', () => {
	// Reason: the backfill window opens at `purchased_at`, which can be years
	// back. An unwindowed / unnarrowed fetchRuns() pages the ENTIRE history
	// including the metadata jsonb bag (issue #332) just to list a handful of
	// candidate rows. The prompt only ever reads id / started_at / distance_m /
	// activity_type.
	const page = read('src/routes/settings/gear/+page.svelte');
	const call = /fetchRuns\(\{[^}]*\}\)/.exec(page);
	assert.ok(call, '/settings/gear must load backfill candidates via fetchRuns.');
	assert.match(
		call[0],
		/columns:\s*\w/,
		'the backfill fetch must narrow its columns — never select(*) over the ' +
			'whole history.',
	);
	// The tuple is read out of the page rather than the call, because the call
	// names it: since § 1330 `columns` is a `satisfies RunColumns` tuple, so
	// that a projected column and the row type it is read as cannot diverge.
	// Asserting the identifier alone would let the tuple grow `metadata` back.
	const tuple = /const BACKFILL_RUN_COLUMNS = \[([^\]]*)\]/.exec(page);
	assert.ok(tuple, 'the backfill column tuple must be declared on the page — re-anchor.');
	assert.match(
		call[0],
		/columns:\s*BACKFILL_RUN_COLUMNS/,
		'the backfill fetch must project the declared tuple, not a second column list.',
	);
	assert.doesNotMatch(
		tuple[1],
		/metadata/,
		'the backfill fetch must not pull the metadata jsonb bag; activity_type ' +
			'is a real column (migration 20261207_001).',
	);
	assert.match(
		call[0],
		/startedAtFrom:/,
		'the backfill fetch must bound started_at at the purchase date rather ' +
			'than scanning the full run history.',
	);
});
