import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	dmRecipientCandidates,
	filterDmRecipients,
	type DmCandidateProfile
} from './dm_recipients';

function profile(id: string, name: string | null = null): DmCandidateProfile {
	return { id, display_name: name, avatar_url: null };
}

test('a follower who is not followed back is still a candidate', () => {
	// The INSERT policy admits a follow edge in EITHER direction, so
	// offering only mutuals would hide a send RLS would accept.
	const out = dmRecipientCandidates([profile('a', 'Ana')], []);
	assert.deepEqual(
		out.map((r) => [r.id, r.relation]),
		[['a', 'follows_you']]
	);
});

test('someone the sender follows who does not follow back is a candidate', () => {
	const out = dmRecipientCandidates([], [profile('b', 'Bo')]);
	assert.deepEqual(
		out.map((r) => [r.id, r.relation]),
		[['b', 'you_follow']]
	);
});

test('a person on both sides appears once, as mutual', () => {
	const out = dmRecipientCandidates([profile('a', 'Ana')], [profile('a', 'Ana')]);
	assert.equal(out.length, 1);
	assert.equal(out[0].relation, 'mutual');
});

test('the sender is never offered as a recipient', () => {
	// direct_messages CHECKs sender_id <> recipient_id, so a self row could
	// only ever produce a send that fails.
	const out = dmRecipientCandidates([profile('me', 'Me')], [profile('me', 'Me')], 'me');
	assert.deepEqual(out, []);
});

test('rows with no id are dropped rather than offered as an unsendable target', () => {
	const out = dmRecipientCandidates([profile('', 'Nameless id')], []);
	assert.deepEqual(out, []);
});

test('candidates are ordered by display name, case- and accent-insensitively', () => {
	const out = dmRecipientCandidates(
		[profile('3', 'zoe'), profile('1', 'Émile')],
		[profile('2', 'ana')]
	);
	assert.deepEqual(
		out.map((r) => r.displayName),
		['ana', 'Émile', 'zoe']
	);
});

test('unnamed candidates sort last, and ties break on id so the order is total', () => {
	const out = dmRecipientCandidates(
		[profile('z-id'), profile('a-id'), profile('m', 'Mo')],
		[]
	);
	assert.deepEqual(
		out.map((r) => r.id),
		['m', 'a-id', 'z-id']
	);
});

test('the merge order of the two fetches does not change the result', () => {
	const followers = [profile('b', 'Bo'), profile('a', 'Ana')];
	const following = [profile('c', 'Cy'), profile('a', 'Ana')];
	assert.deepEqual(
		dmRecipientCandidates(followers, following),
		dmRecipientCandidates(followers, following)
	);
	assert.deepEqual(
		dmRecipientCandidates(followers, following).map((r) => r.id),
		['a', 'b', 'c']
	);
});

test('avatar and display name are carried through from whichever side supplied them', () => {
	const out = dmRecipientCandidates(
		[{ id: 'a', display_name: 'Ana', avatar_url: 'https://example.test/a.png' }],
		[]
	);
	assert.equal(out[0].displayName, 'Ana');
	assert.equal(out[0].avatarUrl, 'https://example.test/a.png');
});

test('a blank query keeps every candidate', () => {
	const all = dmRecipientCandidates([profile('a', 'Ana'), profile('b')], []);
	assert.equal(filterDmRecipients(all, '').length, 2);
	assert.equal(filterDmRecipients(all, '   ').length, 2);
});

test('filtering matches a substring, case- and accent-insensitively', () => {
	const all = dmRecipientCandidates([profile('a', 'Émile Zola'), profile('b', 'Bo')], []);
	assert.deepEqual(
		filterDmRecipients(all, 'emile').map((r) => r.id),
		['a']
	);
	assert.deepEqual(
		filterDmRecipients(all, 'ZOL').map((r) => r.id),
		['a']
	);
});

test('an unnamed candidate matches no non-blank query', () => {
	// There is no text on the row to have matched — claiming a hit would put a
	// row in the results the sender has no way to recognise.
	const all = dmRecipientCandidates([profile('a')], []);
	assert.deepEqual(filterDmRecipients(all, 'a'), []);
});

test('filtering does not mutate the list it was given', () => {
	const all = dmRecipientCandidates([profile('a', 'Ana'), profile('b', 'Bo')], []);
	filterDmRecipients(all, 'ana');
	assert.equal(all.length, 2);
});

test('filterDmRecipients: the search is not sigma-sensitive', () => {
	// A Greek display name lowercases to a FINAL sigma (ς) at the end of a
	// word, while the keyboard a reader types the query on produces the medial
	// σ. The private fold this module used to carry skipped the collapse that
	// reconciles them, so `οδοσ` did not reach `ΟΔΟΣ` — the one sigma-sensitive
	// search key left in the product (decisions § 1340).
	const list = [
		{ id: 'a', displayName: 'ΟΔΟΣ', avatarUrl: null, relation: 'follower' as const }
	];
	assert.equal(filterDmRecipients(list, 'οδοσ').length, 1);
	assert.equal(filterDmRecipients(list, 'οδος').length, 1);
});

test('filterDmRecipients: the search folds accents, like every other search key', () => {
	const list = [
		{ id: 'a', displayName: 'Zoë Müller', avatarUrl: null, relation: 'following' as const }
	];
	assert.equal(filterDmRecipients(list, 'zoe muller').length, 1);
});
