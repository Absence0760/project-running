// The rate-limit refusal, rendered out of every catalogue we ship.
//
// decisions.md § 744 cut the parity pair at the parse so the sentence could
// be translated at all: `rate_limit_errors.ts` returns `{bucket, seconds}`
// and holds no prose, and the wording lives in the six web catalogues plus
// English. `rate_limit_message.test.ts` pins the English strings verbatim
// (three Playwright specs match on them). Nothing pinned the other six, and
// the whole point of the split was that they can now differ — so this file
// asserts what must be true of ALL of them: every bucket resolves to a
// translated sentence, the wait is the only slot, and no reader is told
// "you're doing that too quickly" about an activity we can name.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { interpolate } from './interpolate';
import { CATALOGUE_LOADERS } from './catalogues';
import { SUPPORTED_LOCALES, type Locale } from './locale';
import {
	rateLimitErrorMessage,
	rateLimitMessage,
	rateLimitWait,
	type Translate,
} from './rate_limit_message';

/// Every bucket `enforce_create_rate_limit` is called with. The two DM
/// buckets and the two plan-adopt paths deliberately share a sentence.
const BUCKETS = [
	'create_club',
	'create_route',
	'create_report',
	'create_challenge',
	'clone_plan_template',
	'clone_public_plan',
	'clone_session_template',
	'clone_gym_routine_template',
	'publish_gym_routine_as_template',
	'send_direct_message',
	'send_direct_message_burst',
] as const;

const RATE_LIMIT_KEYS = [
	'rateLimit.createClub',
	'rateLimit.createRoute',
	'rateLimit.createReport',
	'rateLimit.createChallenge',
	'rateLimit.adoptPlan',
	'rateLimit.adoptSessionPlan',
	'rateLimit.adoptGymRoutine',
	'rateLimit.publishRoutine',
	'rateLimit.sendMessage',
	'rateLimit.generic',
] as const;

async function dictFor(loc: Locale): Promise<Record<string, string>> {
	return (await CATALOGUE_LOADERS[loc]()) as unknown as Record<string, string>;
}

function translatorFor(loc: Locale, dict: Record<string, string>): Translate {
	return ((key: string, params?: Record<string, string | number>) =>
		interpolate(dict[key], params, loc)) as Translate;
}

function err(bucket: string, seconds: number) {
	return { code: 'P0001', message: `rate limit exceeded for ${bucket}, retry in ${seconds}s` };
}

test('every catalogue carries every rate-limit key, non-empty', async () => {
	for (const loc of SUPPORTED_LOCALES) {
		const dict = await dictFor(loc);
		for (const key of [
			...RATE_LIMIT_KEYS,
			'rateLimit.waitSeconds',
			'rateLimit.waitMinutes',
			'rateLimit.waitSoon',
		]) {
			assert.ok(dict[key], `${loc} is missing ${key}`);
			assert.ok(dict[key].trim().length > 0, `${loc} has an empty ${key}`);
		}
	}
});

test('every bucket sentence carries the wait slot and nothing else', async () => {
	// § 744: the wait is the ONLY slot, because it is the only fragment that
	// survives translation — German puts the finite verb second and the object
	// last, so an `{activity}` slot could not be dropped into a German frame.
	// A sentence that grew a second slot is a sentence the render glue does not
	// fill, and the reader sees a raw `{token}`.
	for (const loc of SUPPORTED_LOCALES) {
		const dict = await dictFor(loc);
		for (const key of RATE_LIMIT_KEYS) {
			const value = dict[key];
			const slots = [...value.matchAll(/\{(\w+)\}/g)].map((mm) => mm[1]);
			assert.deepEqual(slots, ['wait'], `${loc} ${key} slots: ${slots.join(',')}`);
		}
	}
});

test('every bucket renders a real sentence in every locale, never a bare key', async () => {
	for (const loc of SUPPORTED_LOCALES) {
		const t = translatorFor(loc, await dictFor(loc));
		for (const bucket of BUCKETS) {
			for (const seconds of [0, 1, 30, 89, 90, 3600]) {
				const out = rateLimitErrorMessage(t, err(bucket, seconds));
				assert.ok(out, `${loc}/${bucket}/${seconds}s rendered nothing`);
				assert.ok(!out.includes('rateLimit.'), `${loc}/${bucket} echoed a key: ${out}`);
				assert.ok(!out.includes('{'), `${loc}/${bucket} left a slot unfilled: ${out}`);
				assert.ok(!out.includes('undefined'), `${loc}/${bucket}: ${out}`);
			}
		}
	}
});

test('both direct-message buckets name messages, in every locale', async () => {
	// The defect § 744 found: BOTH platforms fell through to the generic
	// "you're doing that too quickly" for a message the sender had just tried
	// to send. § 737 had priced a DM verb as a lockstep edit and declined it;
	// the price is zero now, so the sentence has to actually be there — in
	// every catalogue, not only English.
	for (const loc of SUPPORTED_LOCALES) {
		const dict = await dictFor(loc);
		const t = translatorFor(loc, dict);
		const generic = rateLimitMessage(t, { bucket: 'no_such_bucket', seconds: 42 });
		for (const bucket of ['send_direct_message', 'send_direct_message_burst']) {
			const out = rateLimitErrorMessage(t, err(bucket, 42));
			assert.equal(
				out,
				interpolate(dict['rateLimit.sendMessage'], { wait: rateLimitWait(t, 42) }, loc),
				`${loc}/${bucket} did not use the sendMessage sentence`,
			);
			assert.notEqual(out, generic, `${loc}/${bucket} fell through to the generic sentence`);
		}
	}
});

test('the two windows of one bucket read identically — the accounting is not the sender\'s business', async () => {
	for (const loc of SUPPORTED_LOCALES) {
		const t = translatorFor(loc, await dictFor(loc));
		assert.equal(
			rateLimitErrorMessage(t, err('send_direct_message', 12)),
			rateLimitErrorMessage(t, err('send_direct_message_burst', 12)),
			loc,
		);
	}
	// Same for the two plan-adopt libraries: one act, two sources.
	for (const loc of SUPPORTED_LOCALES) {
		const t = translatorFor(loc, await dictFor(loc));
		assert.equal(
			rateLimitErrorMessage(t, err('clone_plan_template', 12)),
			rateLimitErrorMessage(t, err('clone_public_plan', 12)),
			loc,
		);
	}
});

test('an unnamed bucket degrades to the generic sentence rather than to English', async () => {
	for (const loc of SUPPORTED_LOCALES) {
		const dict = await dictFor(loc);
		const t = translatorFor(loc, dict);
		const out = rateLimitErrorMessage(t, err('a_bucket_a_later_migration_adds', 30));
		assert.equal(out, interpolate(dict['rateLimit.generic'], { wait: rateLimitWait(t, 30) }, loc));
		if (loc !== 'en') {
			const enDict = await dictFor('en');
			assert.notEqual(
				out,
				interpolate(enDict['rateLimit.generic'], { wait: '30 seconds' }, 'en'),
				`${loc} showed the English generic sentence`,
			);
		}
	}
});

test('every locale actually translated the buckets away from English', async () => {
	// A catalogue that copied the English sentences would pass every other
	// assertion here. Japanese and the two Portuguese variants are the ones
	// most at risk of a straight lift, so this is asserted rather than assumed.
	const enDict = await dictFor('en');
	for (const loc of SUPPORTED_LOCALES) {
		if (loc === 'en') continue;
		const dict = await dictFor(loc);
		for (const key of RATE_LIMIT_KEYS) {
			assert.notEqual(dict[key], enDict[key], `${loc} ${key} is the English string`);
		}
	}
});

test('the wait pluralises through the locale\'s own rules at every boundary', async () => {
	for (const loc of SUPPORTED_LOCALES) {
		const t = translatorFor(loc, await dictFor(loc));
		// Below the cutoff the figure is seconds, verbatim.
		for (const s of [1, 2, 30, 89]) {
			assert.match(rateLimitWait(t, s), new RegExp(`\\b${s}\\b|${s}`), `${loc} ${s}s`);
		}
		// At and above it, minutes, rounded UP so we never invite a retry that
		// is still inside the window.
		assert.match(rateLimitWait(t, 90), /\b2\b|2/, `${loc} 90s`);
		assert.match(rateLimitWait(t, 91), /\b2\b|2/, `${loc} 91s`);
		assert.match(rateLimitWait(t, 3600), /\b60\b|60/, `${loc} 3600s`);
		// No `#` may survive the plural selection.
		for (const s of [1, 89, 90, 3600]) {
			assert.ok(!rateLimitWait(t, s).includes('#'), `${loc} ${s}s left a raw #`);
		}
	}
});

test('a non-positive wait is "a moment", never a literal zero', async () => {
	// § 744: `seconds` is null, not 0, when the trigger reports a non-positive
	// figure — "please wait 0 seconds" invites the retry that fails again.
	for (const loc of SUPPORTED_LOCALES) {
		const dict = await dictFor(loc);
		const t = translatorFor(loc, dict);
		const out = rateLimitErrorMessage(t, err('create_club', 0));
		assert.ok(out, `${loc} rendered nothing for a zero wait`);
		assert.ok(!/\b0\b/.test(out), `${loc} rendered a zero wait: ${out}`);
		assert.ok(out.includes(dict['rateLimit.waitSoon']), `${loc}: ${out}`);
		assert.equal(rateLimitWait(t, null), dict['rateLimit.waitSoon'], loc);
		// A negative figure never reaches the parser at all — `retry in -1s`
		// does not match, so the caller rethrows the original error rather
		// than reading a refusal out of a message it could not parse.
		assert.equal(rateLimitErrorMessage(t, err('create_club', -1)), null, loc);
	}
});

test('the wait fragment is written for a mid-sentence slot, not as its own sentence', async () => {
	// The slot lands inside a running sentence in all seven catalogues, so a
	// capitalised fragment renders "aguarde Um momento e tente novamente" —
	// which is exactly what pt-PT shipped, and exactly the class § 755 names
	// among the derivation's four systematic bugs (case mirrored upward only).
	//
	// The check is on the first character alone. A language that capitalises a
	// noun could legitimately need one here; the fix would then be to lead the
	// fragment with a determiner, as German already does ("einen Moment"),
	// rather than to widen this rule.
	for (const loc of SUPPORTED_LOCALES) {
		const dict = await dictFor(loc);
		for (const key of ['rateLimit.waitSoon', 'rateLimit.waitSeconds', 'rateLimit.waitMinutes']) {
			assert.doesNotMatch(
				dict[key],
				/^\p{Lu}/u,
				`${loc} ${key} starts with a capital but is slotted mid-sentence: ${dict[key]}`,
			);
		}
		// And the slot really is mid-sentence in this catalogue: something
		// precedes it in the frame.
		for (const key of RATE_LIMIT_KEYS) {
			const before = dict[key].split('{wait}')[0];
			assert.ok(before.trim().length > 0, `${loc} ${key} opens on the wait slot`);
		}
	}
});

test('a non-rate-limit error renders nothing in every locale, so the caller rethrows', async () => {
	for (const loc of SUPPORTED_LOCALES) {
		const t = translatorFor(loc, await dictFor(loc));
		assert.equal(rateLimitErrorMessage(t, null), null, loc);
		assert.equal(rateLimitErrorMessage(t, undefined), null, loc);
		assert.equal(rateLimitErrorMessage(t, { code: '23505', message: 'duplicate key' }), null, loc);
		assert.equal(
			rateLimitErrorMessage(t, { code: 'P0001', message: 'something else entirely' }),
			null,
			loc,
		);
	}
});
