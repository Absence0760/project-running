/**
 * Length-clipping for user-authored text that is about to be interpolated into
 * a `<head>` meta tag, an SVG text node, or a JSON-LD value — a share title, a
 * club description, a route name on an og:image card.
 *
 * `max` is a budget in UTF-16 code units, which is what every caller's cap was
 * already measured in.
 */

/**
 * At most `max` code units, with the last one spent on an ellipsis when
 * anything was dropped.
 *
 * A code-unit index can land between the two halves of a surrogate pair, and
 * slicing there emits a lone surrogate — which is not text: it has no UTF-8
 * encoding, so the response encoder substitutes U+FFFD and a club description
 * cut mid-emoji reaches every crawler with a replacement character on the end.
 * So the cut steps back off a high surrogate and drops the character whole.
 * Postgres will not store an unpaired surrogate in `text` or in `jsonb`, so
 * the cut is the only place one can be introduced.
 *
 * A grapheme CLUSTER can still be split — a ZWJ sequence, a base letter and
 * its combining mark — which changes the glyph without making the string
 * ill-formed. That is a rendering nicety and is deliberately not attempted
 * here; it would need Intl.Segmenter and a budget in graphemes.
 */
export function clipText(s: string, max: number): string {
	if (s.length <= max) return s;
	const at = Math.max(0, max - 1);
	const before = at > 0 ? s.charCodeAt(at - 1) : 0;
	const end = before >= 0xd800 && before <= 0xdbff ? at - 1 : at;
	return `${s.slice(0, end).trimEnd()}…`;
}

/**
 * Collapse runs of whitespace, trim, then clip. A non-string (a `null` column,
 * a number out of a jsonb bag) is nothing to say, so it yields `''` rather
 * than the word `null`.
 */
export function collapseAndClip(raw: unknown, max: number): string {
	const collapsed = (typeof raw === 'string' ? raw : '').replace(/\s+/g, ' ').trim();
	if (!collapsed) return '';
	return clipText(collapsed, max);
}
