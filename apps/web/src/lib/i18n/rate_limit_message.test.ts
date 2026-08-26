// Renders the rate-limit refusal out of the real catalogues, in every
// locale. Run via
//   npx tsx --test apps/web/src/lib/i18n/rate_limit_message.test.ts
//
// The English assertions are the pre-§744 strings verbatim: moving the
// prose out of the parity pair and into the catalogue must not change a
// single character of what an English reader sees (three Playwright
// specs match on that wording).

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { interpolate } from './interpolate';
import { CATALOGUE_LOADERS } from './catalogues';
import { SUPPORTED_LOCALES, type Locale } from './locale';
import { rateLimitErrorMessage, rateLimitMessage, type Translate } from './rate_limit_message';

const BUCKETS = [
	'create_club',
	'create_route',
	'create_report',
	'clone_plan_template',
	'clone_public_plan',
	'clone_session_template',
	'clone_gym_routine_template',
	'publish_gym_routine_as_template',
	'send_direct_message',
	'send_direct_message_burst',
] as const;

async function translatorFor(loc: Locale): Promise<Translate> {
	const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
	return (key, params) => interpolate(dict[key], params, loc);
}

function err(bucket: string, seconds: number) {
	return { code: 'P0001', message: `rate limit exceeded for ${bucket}, retry in ${seconds}s` };
}

test('en: every bucket keeps the exact sentence it had before the copy moved', async () => {
	const t = await translatorFor('en');
	assert.equal(
		rateLimitErrorMessage(t, err('create_club', 42)),
		"You're creating clubs too quickly — please wait 42 seconds and try again.",
	);
	assert.equal(
		rateLimitErrorMessage(t, err('create_route', 1234)),
		"You're creating routes too quickly — please wait 21 minutes and try again.",
	);
	assert.equal(
		rateLimitErrorMessage(t, err('create_report', 600)),
		"You're filing reports too quickly — please wait 10 minutes and try again.",
	);
	assert.equal(
		rateLimitErrorMessage(t, err('clone_plan_template', 300)),
		"You're adopting plans too quickly — please wait 5 minutes and try again.",
	);
	assert.equal(
		rateLimitErrorMessage(t, err('clone_public_plan', 45)),
		"You're adopting plans too quickly — please wait 45 seconds and try again.",
	);
	assert.equal(
		rateLimitErrorMessage(t, err('clone_session_template', 30)),
		"You're adopting session plans too quickly — please wait 30 seconds and try again.",
	);
	assert.equal(
		rateLimitErrorMessage(t, err('clone_gym_routine_template', 30)),
		"You're adopting gym routines too quickly — please wait 30 seconds and try again.",
	);
	assert.equal(
		rateLimitErrorMessage(t, err('publish_gym_routine_as_template', 120)),
		"You're publishing routines too quickly — please wait 2 minutes and try again.",
	);
});

test('en: both direct-message buckets read as "sending messages", not "doing that"', async () => {
	// The live defect § 744 was opened on: neither platform mapped the two
	// buckets migration 20270608_001 added, so a throttled sender was told
	// "You're doing that too quickly" about a message.
	const t = await translatorFor('en');
	assert.equal(
		rateLimitErrorMessage(t, err('send_direct_message', 1800)),
		"You're sending messages too quickly — please wait 30 minutes and try again.",
	);
	assert.equal(
		rateLimitErrorMessage(t, err('send_direct_message_burst', 41)),
		"You're sending messages too quickly — please wait 41 seconds and try again.",
	);
});

test('en: an unrecognised bucket degrades to the generic sentence', async () => {
	const t = await translatorFor('en');
	assert.equal(
		rateLimitErrorMessage(t, err('create_widget', 30)),
		"You're doing that too quickly — please wait 30 seconds and try again.",
	);
});

test('en: the wait pluralises and rounds at the 90-second cutoff', async () => {
	const t = await translatorFor('en');
	const wait = (seconds: number) =>
		rateLimitErrorMessage(t, err('create_club', seconds))!
			.replace("You're creating clubs too quickly — please wait ", '')
			.replace(' and try again.', '');
	assert.equal(wait(1), '1 second');
	assert.equal(wait(42), '42 seconds');
	assert.equal(wait(89), '89 seconds');
	assert.equal(wait(90), '2 minutes');
	assert.equal(wait(120), '2 minutes');
	assert.equal(wait(3540), '59 minutes');
	assert.equal(wait(3600), '60 minutes');
});

test('en: a non-positive wait reads as "a few seconds", never "0 seconds"', async () => {
	const t = await translatorFor('en');
	assert.equal(
		rateLimitErrorMessage(t, err('create_club', 0)),
		"You're creating clubs too quickly — please wait a few seconds and try again.",
	);
});

test('a non-rate-limit error renders nothing, so the caller rethrows it', async () => {
	const t = await translatorFor('en');
	assert.equal(rateLimitErrorMessage(t, { code: '42501', message: 'permission denied' }), null);
	assert.equal(rateLimitErrorMessage(t, null), null);
});

for (const loc of SUPPORTED_LOCALES) {
	test(`${loc}: every bucket and every wait shape renders complete copy`, async () => {
		const t = await translatorFor(loc);
		const soon = rateLimitMessage(t, { bucket: 'create_club', seconds: null });
		for (const bucket of [...BUCKETS, 'create_widget']) {
			for (const seconds of [null, 1, 42, 90, 3600] as (number | null)[]) {
				const rendered = rateLimitMessage(t, { bucket, seconds });
				assert.ok(rendered.trim().length > 0, `${loc}/${bucket}/${seconds} is empty`);
				assert.ok(
					!rendered.includes('{'),
					`${loc}/${bucket}/${seconds} left an unsubstituted slot: ${rendered}`,
				);
				assert.ok(
					!/rateLimit\./.test(rendered),
					`${loc}/${bucket}/${seconds} fell through to a raw key: ${rendered}`,
				);
			}
		}
		// The wait is a slot, so a locale that dropped {wait} would render
		// the same sentence for a 1-second and a 1-hour refusal.
		assert.notEqual(
			rateLimitMessage(t, { bucket: 'create_club', seconds: 1 }),
			rateLimitMessage(t, { bucket: 'create_club', seconds: 3600 }),
			`${loc} renders the same sentence for a 1 s and a 1 h wait — {wait} was dropped`,
		);
		assert.notEqual(
			soon,
			rateLimitMessage(t, { bucket: 'create_club', seconds: 42 }),
			`${loc} does not distinguish the non-positive wait`,
		);
	});

	test(`${loc}: each distinct activity gets its own sentence`, async () => {
		// The two plan-adopt buckets deliberately share one; the two DM
		// buckets likewise. Everything else must be distinguishable, or a
		// locale has pasted one translation over several keys.
		const t = await translatorFor(loc);
		const distinct = new Set(
			[
				'create_club',
				'create_route',
				'create_report',
				'clone_plan_template',
				'clone_session_template',
				'clone_gym_routine_template',
				'publish_gym_routine_as_template',
				'send_direct_message',
				'create_widget',
			].map((bucket) => rateLimitMessage(t, { bucket, seconds: 42 })),
		);
		assert.equal(distinct.size, 9, `${loc} reuses one sentence for two different activities`);
		assert.equal(
			rateLimitMessage(t, { bucket: 'clone_plan_template', seconds: 42 }),
			rateLimitMessage(t, { bucket: 'clone_public_plan', seconds: 42 }),
			`${loc}: the two plan-adopt buckets are one act and share a sentence`,
		);
		assert.equal(
			rateLimitMessage(t, { bucket: 'send_direct_message', seconds: 42 }),
			rateLimitMessage(t, { bucket: 'send_direct_message_burst', seconds: 42 }),
			`${loc}: which of the two send windows refused is our accounting, not the sender's`,
		);
	});
}
