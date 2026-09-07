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
 */
export function clipText(s: string, max: number): string {
	if (s.length <= max) return s;
	return `${s.slice(0, Math.max(0, max - 1)).trimEnd()}…`;
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
