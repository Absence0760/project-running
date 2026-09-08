// `/terms` §6 is the BUYER-facing half of the claim `merchant_note_guard.test.ts`
// pins on the host-facing half, and it was the last document in the product still
// asserting what decisions § 769 disproved. Until 2026-09-08 it told the buyer
// "the seller (merchant of record) is the event host … not Threkir" and told the
// host "You are the merchant of record: you own refunds, chargebacks …", while
// `payouts.merchantNote` had said the opposite since § 1548 — two documents, one
// product, contradicting each other about the same fact on the same day.
//
// The third rail is the DATABASE. § 1549 corrected `20261229_001`'s header in
// place, which repaired the file a reader opens and not the comment `\d+
// event_orders` prints, because that migration never wrote one. `20270713000001`
// does, for both money ledgers.
//
// ── What this guard reads, and why it is allowed to read prose here ──────────
// The Stripe parameters come first, exactly as the sibling guard does it: what
// makes any of these sentences true is that `on_behalf_of` is absent from every
// checkout call site ("If `on_behalf_of` is omitted, the platform is the business
// of record for the payment"), so the flip that would falsify all three rails at
// once fails HERE, naming them.
//
// The sibling deliberately does not read its sentence, because six of the seven
// catalogues are not in English and a wording-keyed check would police one locale
// and be escaped in the others by translation drift. Neither rail here has that
// shape: `/terms` is one English page with no catalogue and no twin, and the
// table comments are two English string literals this repo owns. So both are read
// through a DECLARED marker rather than through their wording — `data-merchant-
// of-record` on the page, `MERCHANT OF RECORD: the PLATFORM` in the comment — and
// the prose around each marker can be rewritten or translated freely without
// touching the guard. Flipping the CLAIM means flipping the marker, which is what
// this fails on.
//
// The two sentences the page carried until 2026-09-08 are additionally pinned as
// negatives, because a reintroduced bullet needs no marker to be wrong.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, '..', '..', '..', '..', '..');
const FUNCTIONS = join(REPO_ROOT, 'apps/backend/supabase/functions');
const MIGRATIONS = join(REPO_ROOT, 'apps/backend/supabase/migrations');
const TERMS_PAGE = join(HERE, '+page.svelte');

/** Whole-line comments only — a trailing `//` after code leaves the code. */
function codeOnly(source: string): string {
	return source
		.split('\n')
		.filter((line) => {
			const t = line.trim();
			return !(t.startsWith('//') || t.startsWith('///') || t.startsWith('*') || t.startsWith('/*'));
		})
		.join('\n');
}

/**
 * Supabase applies a migration by the version its filename carries before the
 * first `_`, so a plain filename sort gets `20270708_001` vs `20270708000010`
 * backwards. The last comment written for a table is the one in the database.
 */
function migrationsInApplyOrder(): Array<{ file: string; sql: string }> {
	const version = (f: string) => (f.includes('_') ? f.slice(0, f.indexOf('_')) : f);
	return readdirSync(MIGRATIONS)
		.filter((f) => f.endsWith('.sql'))
		.sort((a, b) => (version(a) === version(b) ? a.localeCompare(b) : version(a).localeCompare(version(b))))
		.map((file) => ({ file, sql: readFileSync(join(MIGRATIONS, file), 'utf-8') }));
}

/**
 * A SQL comment body is a run of adjacent single-quoted literals that Postgres
 * concatenates, so the text the database actually holds is not any one of them.
 * Rebuild it the way the server does — join every literal, `''` back to `'` —
 * or a marker that happens to straddle a line break reads as absent.
 */
function sqlLiteralText(body: string): string {
	let text = '';
	for (const m of body.matchAll(/'((?:[^']|'')*)'/g)) text += m[1].replaceAll("''", "'");
	return text;
}

/** The body of the LAST `comment on table <t> is …;` in the tree, or null. */
function liveTableComment(table: string): { file: string; body: string } | null {
	// The literal run is matched explicitly rather than "up to the next `;`":
	// these comments contain semicolons INSIDE the text, and a non-greedy scan to
	// the statement terminator silently truncates the body it is about to read.
	const re = new RegExp(
		`comment\\s+on\\s+table\\s+(?:public\\.)?${table}\\s+is\\s+((?:'(?:[^']|'')*'\\s*)+);`,
		'gi',
	);
	let found: { file: string; body: string } | null = null;
	for (const { file, sql } of migrationsInApplyOrder()) {
		for (const m of sql.matchAll(re)) found = { file, body: sqlLiteralText(m[1]) };
	}
	return found;
}

const CHECKOUT_CALL_SITES = [
	'events-checkout/lib.ts',
	'events-checkout/index.ts',
	'donations-checkout/lib.ts',
	'donations-checkout/index.ts',
];

test('the platform stays merchant of record: no checkout call site sends on_behalf_of', () => {
	for (const file of CHECKOUT_CALL_SITES) {
		const code = codeOnly(readFileSync(join(FUNCTIONS, file), 'utf-8'));
		assert.ok(
			!code.includes('on_behalf_of'),
			`${file} sends on_behalf_of, which makes the HOST the business of record for the payment. /terms §6 tells the buyer and the host that Threkir is, the event_orders and donations table comments say so in the database, and payouts.merchantNote says so in seven locales — settle club_events.md § Refunds' sign-off item and rewrite all four before landing this.`,
		);
	}
});

test('/terms declares the merchant of record, and declares the platform', () => {
	const page = readFileSync(TERMS_PAGE, 'utf-8');
	const declared = [...page.matchAll(/data-merchant-of-record="([^"]*)"/g)].map((m) => m[1]);
	assert.ok(
		declared.length > 0,
		'/terms carries no data-merchant-of-record marker at all. The marker is what makes the claim checkable without policing the wording around it — §6 must declare who the merchant of record is, not merely happen to mention it.',
	);
	for (const value of declared) {
		assert.equal(
			value,
			'platform',
			`/terms declares data-merchant-of-record="${value}". No checkout call site sends on_behalf_of, so the platform is the business of record for the payment (decisions § 769) — the page may not tell a buyer or a host otherwise.`,
		);
	}
});

test('/terms no longer carries the two sentences § 769 disproved', () => {
	// A reintroduced bullet needs no marker to be wrong, so the exact claims the
	// page made until 2026-09-08 are pinned as negatives. This is a regression pin
	// on two sentences, not a general wording rule: everything else in §6 is free
	// to be rewritten.
	const page = readFileSync(TERMS_PAGE, 'utf-8');
	assert.doesNotMatch(
		page,
		/\(merchant of record\)\s*is the event host/i,
		'/terms tells the buyer the seller of record is the host again (decisions § 769, § 1506).',
	);
	assert.doesNotMatch(
		page,
		/You are the merchant of\s+record/i,
		'/terms tells the host they are the merchant of record again. payouts.merchantNote tells them the opposite in seven locales (decisions § 1548).',
	);
});

test('both money ledgers state the merchant of record in the database, not only in a migration header', () => {
	// `\d+ event_orders` prints the table's own comment. 20261229_001 wrote none,
	// so § 1549's in-place header correction left the schema-reader with nothing
	// (followups, closed by 20270713000001).
	for (const table of ['event_orders', 'donations']) {
		const comment = liveTableComment(table);
		assert.ok(
			comment !== null,
			`no migration writes "comment on table ${table}", so the live schema states nothing about who the merchant of record is on a money ledger.`,
		);
		assert.ok(
			comment.body.includes('MERCHANT OF RECORD: the ') && comment.body.includes('PLATFORM'),
			`${comment.file}'s comment on ${table} does not declare "MERCHANT OF RECORD: the PLATFORM". No checkout call site sends on_behalf_of, so that is what the database should say (decisions § 769, § 1549).`,
		);
	}
});
