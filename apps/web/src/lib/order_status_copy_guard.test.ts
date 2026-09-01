// Source-level guard that the paid-registration surfaces can only ever name a
// status the ledger can actually hold.
//
// The copy is the reason this matters. § 789 gave a bank-reversed refund its
// own terminal status, `refund_failed`, and § 825 gave it a banner that tells
// the buyer their money is still with us. A banner is a sentence about a state:
// rename the state in SQL, or narrow the CHECK, and the sentence keeps
// rendering for a row that can no longer exist — or, worse, silently stops
// rendering for one that does, which is the exact invisibility § 825 closed.
//
// So both directions are pinned: every status literal the surface compares
// against must be in the live CHECK, and `refund_failed` must survive in the
// CHECK for as long as the banner reads it.
//
// The CHECK is read from the LAST migration that restates it, not from a fixed
// filename — a later migration that widens or narrows either ledger is exactly
// what this must follow.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS = resolve(__dirname, '../../../backend/supabase/migrations');
const EVENT_PAGE = resolve(__dirname, '../routes/clubs/[slug]/events/[id]/+page.svelte');

/** The status vocabulary the newest migration to restate `<table>_status_check` allows. */
function liveStatusSet(table: string): Set<string> {
	const re = new RegExp(
		`add\\s+constraint\\s+${table}_status_check\\s+check\\s*\\(\\s*status\\s+in\\s*\\(([^)]*)\\)`,
		'i'
	);
	let latest: string[] | null = null;
	for (const file of readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort()) {
		const m = re.exec(readFileSync(join(MIGRATIONS, file), 'utf-8'));
		if (m) latest = [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]);
	}
	assert.ok(latest, `no migration restates ${table}_status_check`);
	return new Set(latest);
}

/** Every literal the source compares an order's `status` against. */
function orderStatusLiterals(source: string): string[] {
	return [...source.matchAll(/\b(?:myOrder|order)\??\.status\s*[!=]==\s*'([a-z_]+)'/g)].map(
		(m) => m[1]
	);
}

test('every order status the event page names is one the ledger can hold', () => {
	const allowed = liveStatusSet('event_orders');
	const source = readFileSync(EVENT_PAGE, 'utf-8');
	const named = orderStatusLiterals(source);
	assert.ok(named.length >= 3, 'the status comparisons stopped matching — the regex is stale');
	for (const status of named) {
		assert.ok(
			allowed.has(status),
			`/clubs/[slug]/events/[id] compares status against '${status}', which event_orders_status_check does not allow`
		);
	}
});

test('the reversed-refund banner reads a status the ledger still has', () => {
	const source = readFileSync(EVENT_PAGE, 'utf-8');
	assert.ok(
		source.includes("data-testid=\"refund-failed-banner\""),
		'the reversed-refund banner is gone — a buyer whose refund the bank rejected sees nothing again (§ 789, § 825)'
	);
	assert.ok(
		orderStatusLiterals(source).includes('refund_failed'),
		'the banner no longer derives off refund_failed'
	);
	assert.ok(
		liveStatusSet('event_orders').has('refund_failed'),
		'event_orders can no longer hold refund_failed, but the page still renders copy about it'
	);
	assert.ok(
		liveStatusSet('donations').has('refund_failed'),
		'donations can no longer hold refund_failed, but the notification copy still names it'
	);
});
