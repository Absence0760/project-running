// `payouts.merchantNote` is the only host-facing sentence on a money surface,
// and until 2026-09-07 it told an instructor they were the merchant of record
// and owned refunds and chargebacks. The platform is all three (decisions
// § 769, § 1506). It said the reverse for as long as it existed because
// nothing tied the copy to the code it describes.
//
// This guard is that tie. It deliberately does not read the sentence — six of
// the seven catalogues are not in English, and a guard keyed on wording is
// escaped by rewording. It reads the two Stripe parameters that MAKE the
// sentence true, so the flip that would falsify the copy fails here and names
// the keys to change:
//
//   - `on_behalf_of` absent from the Checkout Session params. Stripe: "If
//     `on_behalf_of` is omitted, the platform is the business of record for the
//     payment" — its absence is what makes us, not the host, the merchant of
//     record, and what puts our name on the buyer's statement. Sending it is a
//     live pre-deploy sign-off question (club_events.md § Refunds), which is
//     exactly why it must not flip silently.
//   - `refund_application_fee: true` in the refund params, which "push[es] the
//     application fee funds back to the connected account" — the clause saying
//     the platform fee comes back to the host when an order is refunded.
//
// The chargeback clause is not checkable from this repo and does not need to
// be: Stripe debits dispute amounts from the platform account for a destination
// charge with or without `on_behalf_of`, so it survives the sign-off either way.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPPORTED_LOCALES } from '../../../lib/i18n/locale';
import { CATALOGUE_LOADERS } from '../../../lib/i18n/catalogues';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, '..', '..', '..', '..', '..', '..');
const FUNCTIONS = join(REPO_ROOT, 'apps/backend/supabase/functions');

/** Whole-line comments only — a trailing `//` after code leaves the code. */
function codeOnly(source: string): string {
	return source
		.split('\n')
		.filter((line) => {
			const t = line.trim();
			return !(t.startsWith('//') || t.startsWith('*') || t.startsWith('/*'));
		})
		.join('\n');
}

function edgeFunctionCode(relative: string): string {
	return codeOnly(readFileSync(join(FUNCTIONS, relative), 'utf-8'));
}

test('the platform stays merchant of record: no checkout call site sends on_behalf_of', () => {
	for (const file of ['events-checkout/lib.ts', 'events-checkout/index.ts']) {
		assert.ok(
			!edgeFunctionCode(file).includes('on_behalf_of'),
			`${file} sends on_behalf_of, which makes the HOST the business of record for the payment. payouts.merchantNote tells the host the opposite in all seven locales, and /terms §6 tells the buyer the opposite again — settle club_events.md § Refunds' sign-off item and rewrite both before landing this.`,
		);
	}
});

test('a refund still returns the platform fee to the host', () => {
	const refundLib = edgeFunctionCode('events-cancel/lib.ts');
	assert.match(
		refundLib,
		/refund_application_fee:\s*true/,
		"buildRefundParams no longer pushes the application fee back to the connected account, so payouts.merchantNote's closing clause is false in all seven locales.",
	);
	assert.match(
		refundLib,
		/reverse_transfer:\s*true/,
		'buildRefundParams no longer reverses the destination transfer. Stripe couples the two flags; sending the fee refund alone pays the host our cut on top of the ticket they keep (decisions § 769).',
	);
});

test('the refund the note promises is issued by us, under the policy the host set', () => {
	const cancel = edgeFunctionCode('events-cancel/index.ts');
	assert.ok(
		cancel.includes('refund_policy'),
		"events-cancel no longer resolves event_pricing.refund_policy, so the note's claim that refunds follow the policy the host set on the event is unsourced.",
	);
	assert.match(
		cancel,
		/refunds\.create/,
		"events-cancel no longer creates the refund itself, so the note's claim that we issue refunds is unsourced.",
	);
});

test('the payouts page renders the note rather than an inline literal', () => {
	const page = readFileSync(join(HERE, '+page.svelte'), 'utf-8');
	assert.match(page, /m\('payouts\.merchantNote'\)/);
});

test('every locale carries the note', async () => {
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const note = dict['payouts.merchantNote'];
		assert.ok(
			note !== undefined && note.trim().length > 0,
			`${loc} has no payouts.merchantNote — the host would read the English one, or nothing`,
		);
	}
});
