import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { normaliseE164, E164_PATTERN } from './e164';

describe('normaliseE164', () => {
	it('passes an already-bare E.164 number through unchanged', () => {
		assert.equal(normaliseE164('+447700900123'), '+447700900123');
	});

	it('strips the spacing people paste off a contact card', () => {
		assert.equal(normaliseE164('+44 7700 900 123'), '+447700900123');
	});

	it('strips hyphens, dots, slashes and brackets', () => {
		assert.equal(normaliseE164('+1 (555) 010-1234'), '+15550101234');
		assert.equal(normaliseE164('+1.555.010.1234'), '+15550101234');
		assert.equal(normaliseE164('+49 30/1234567'), '+49301234567');
	});

	it('strips non-breaking and narrow-no-break spaces', () => {
		assert.equal(normaliseE164('+33 6 12 34 56 78'), '+33612345678');
	});

	it('strips the hyphen family, not just ASCII hyphen-minus', () => {
		assert.equal(normaliseE164('+44‑7700–900123'), '+447700900123');
	});

	it('reads the ITU access prefix 00 as +', () => {
		assert.equal(normaliseE164('0044 7700 900123'), '+447700900123');
	});

	it('deletes a parenthesised trunk zero rather than keeping the digit', () => {
		// The dangerous case: stripping only the brackets yields
		// +4407700900123, a different number that still passes the CHECK.
		assert.equal(normaliseE164('+44 (0) 7700 900123'), '+447700900123');
		assert.equal(normaliseE164('+44 (0)7700900123'), '+447700900123');
	});

	it('leaves a real bracketed area code alone', () => {
		assert.equal(normaliseE164('+61 (2) 5550 1234'), '+61255501234');
	});

	it('refuses a national-format number with no country', () => {
		// Guessing a country here would arm the escalation at a stranger.
		assert.equal(normaliseE164('07700900123'), null);
		assert.equal(normaliseE164('7700900123'), null);
	});

	it('refuses a lone trunk-prefixed number once the (0) is deleted', () => {
		assert.equal(normaliseE164('(0)7700900123'), null);
	});

	it('refuses letters, extensions and anything else non-numeric', () => {
		assert.equal(normaliseE164('+44 7700 900123 ext 12'), null);
		assert.equal(normaliseE164('not a phone'), null);
	});

	it('refuses a leading zero after the plus (E.164 has no country code 0)', () => {
		assert.equal(normaliseE164('+0447700900123'), null);
	});

	it('refuses numbers outside the 7..15 digit span', () => {
		assert.equal(normaliseE164('+123456'), null);
		assert.equal(normaliseE164('+1234567'), '+1234567');
		assert.equal(normaliseE164('+123456789012345'), '+123456789012345');
		assert.equal(normaliseE164('+1234567890123456'), null);
	});

	it('treats empty, blank and null as no number on file', () => {
		assert.equal(normaliseE164(''), null);
		assert.equal(normaliseE164('   '), null);
		assert.equal(normaliseE164(null), null);
		assert.equal(normaliseE164(undefined), null);
	});

	it('exposes the same pattern the column CHECK enforces', () => {
		assert.ok(E164_PATTERN.test('+447700900123'));
		assert.ok(!E164_PATTERN.test('+44 7700 900123'));
	});

	it('is idempotent — normalising its own output changes nothing', () => {
		const once = normaliseE164('+44 (0) 7700-900 123');
		assert.equal(once, '+447700900123');
		assert.equal(normaliseE164(once), once);
	});
});
