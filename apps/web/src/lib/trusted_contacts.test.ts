import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	MAX_TRUSTED_CONTACTS,
	normaliseTrustedContact,
	normaliseTrustedContacts,
	hasReachableChannel,
	type TrustedContact,
} from './trusted_contacts';

// ── normaliseTrustedContact ────────────────────────────────

test('normaliseTrustedContact: keeps trimmed name + populated optionals', () => {
	const out = normaliseTrustedContact({
		name: '  Alice  ',
		phone: ' +44 7700 900111 ',
		email: '  alice@example.com  ',
		relationship: ' partner ',
	});
	assert.deepStrictEqual(out, {
		name: 'Alice',
		phone: '+44 7700 900111',
		email: 'alice@example.com',
		relationship: 'partner',
	});
});

test('normaliseTrustedContact: drops empty-string optionals (does not store "")', () => {
	// A regression here would persist `{ phone: '' }` into the bag,
	// which downstream code would then have to defensively check for —
	// better to drop the key entirely.
	const out = normaliseTrustedContact({
		name: 'Bob',
		phone: '',
		email: '   ',
		relationship: '',
	});
	assert.deepStrictEqual(out, { name: 'Bob' });
});

test('normaliseTrustedContact: returns null when name is missing or whitespace-only', () => {
	assert.equal(normaliseTrustedContact({ name: '' }), null);
	assert.equal(normaliseTrustedContact({ name: '   ' }), null);
	// Even when other fields are present — without a name there's
	// nothing to display in the notification template.
	assert.equal(
		normaliseTrustedContact({ name: '', phone: '+1 555 0123' }),
		null,
	);
});

// ── normaliseTrustedContacts (the list-level normaliser) ────

test('normaliseTrustedContacts: null / undefined / empty all return []', () => {
	assert.deepStrictEqual(normaliseTrustedContacts(null), []);
	assert.deepStrictEqual(normaliseTrustedContacts(undefined), []);
	assert.deepStrictEqual(normaliseTrustedContacts([]), []);
});

test('normaliseTrustedContacts: filters invalid entries from a mixed list', () => {
	const out = normaliseTrustedContacts([
		{ name: 'Alice', phone: '+1' },
		{ name: '', phone: '+1' }, // dropped — no name
		{ name: '  ' }, // dropped — whitespace-only name
		{ name: 'Bob' },
	]);
	assert.deepStrictEqual(out, [{ name: 'Alice', phone: '+1' }, { name: 'Bob' }]);
});

test('normaliseTrustedContacts: caps at MAX_TRUSTED_CONTACTS', () => {
	// Pin the cap so a runaway editor can't blow up the universal-
	// prefs bag. The cap is intentional product policy, not a
	// technical limit — surface it to the UI rather than failing
	// silently if the user tries to add a sixth.
	const input: TrustedContact[] = Array.from(
		{ length: MAX_TRUSTED_CONTACTS + 3 },
		(_, i) => ({ name: `Contact ${i}` }),
	);
	const out = normaliseTrustedContacts(input);
	assert.equal(out.length, MAX_TRUSTED_CONTACTS);
});

// ── hasReachableChannel ────────────────────────────────────

test('hasReachableChannel: true when phone OR email present', () => {
	assert.equal(hasReachableChannel({ name: 'A', phone: '+1' }), true);
	assert.equal(hasReachableChannel({ name: 'A', email: 'a@b.c' }), true);
	assert.equal(
		hasReachableChannel({ name: 'A', phone: '+1', email: 'a@b.c' }),
		true,
	);
});

test('hasReachableChannel: false when neither phone nor email present', () => {
	// Surfaces the UI warning ("we have no way to reach this person")
	// without blocking the save — the runner may still call manually.
	assert.equal(hasReachableChannel({ name: 'A' }), false);
	assert.equal(hasReachableChannel({ name: 'A', relationship: 'parent' }), false);
});
