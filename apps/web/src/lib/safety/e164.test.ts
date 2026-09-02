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

	it('strips EVERY member of the hyphen family', () => {
		// The class used to hold three of these under a comment claiming the
		// family, and this suite's one case exercised two. A macOS or Word
		// autocorrect produces U+2013 or U+2014; a CJK keyboard U+FF0D; a
		// spreadsheet export U+2212 — so the same contact card could be
		// accepted once and refused once.
		const family = [
			'\u002D', '\u2010', '\u2011', '\u2012', '\u2013',
			'\u2014', '\u2015', '\u2212', '\uFE58', '\uFE63', '\uFF0D',
		];
		for (const dash of family) {
			assert.equal(
				normaliseE164(`+44${dash}7700${dash}900123`),
				'+447700900123',
				`U+${dash.charCodeAt(0).toString(16).toUpperCase().padStart(4, '0')}`,
			);
		}
	});

	it('strips the invisible characters a paste carries', () => {
		// A zero-width space, a soft hyphen or a BOM survives a copy off a web
		// page and no reader can see one to delete it.
		for (const invisible of ['\u00AD', '\u200B', '\u200C', '\u200D', '\uFEFF', '\u3000', '\u205F']) {
			assert.equal(
				normaliseE164(`+44${invisible}7700${invisible}900123`),
				'+447700900123',
				`U+${invisible.charCodeAt(0).toString(16).toUpperCase().padStart(4, '0')}`,
			);
		}
	});

	it('deletes a FULLWIDTH parenthesised trunk zero whole, like the ASCII one', () => {
		// The bracket sets in SEPARATORS and TRUNK_ZERO have to match. A bracket
		// the separator class folds but the trunk-zero one does not leaves the
		// 0 behind and yields a different, CONFORMING number that would deliver
		// the overdue alert to nobody.
		assert.equal(normaliseE164('+44\uFF080\uFF09 7700 900123'), '+447700900123');
		assert.equal(normaliseE164('+44 (0) 7700 900123'), '+447700900123');
	});

	it('refuses a separator it does not know rather than guessing', () => {
		// An unrecognised separator surfaces as an error the owner can act on;
		// silently dropping an unknown character could change the number.
		assert.equal(normaliseE164('+44_7700_900123'), null);
		assert.equal(normaliseE164('+44*7700*900123'), null);
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
