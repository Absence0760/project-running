/**
 * Canonical HTML/XML escaping for strings interpolated into raw-HTML or
 * raw-SVG sinks — MapLibre `Popup.setHTML`, hand-built SVG (finisher
 * certificate, recap image), and the share-run Lambda `<head>` injection.
 *
 * Encodes the five characters that change parse context in HTML text, HTML
 * attribute, and XML/SVG contexts. Uses the numeric `&#39;` (not `&apos;`)
 * for the apostrophe so the output is valid in HTML4/5 and XML/SVG alike.
 *
 * This ESCAPES (the value survives as inert text). It is NOT a sanitiser —
 * for untrusted *markup* that must keep some tags, use the DOMPurify path in
 * `coach/markdown.ts` instead.
 */
export function escapeHtml(s: string): string {
	return s
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&#39;');
}

/**
 * Scheme guard for an `href` interpolated into a raw-HTML sink. `escapeHtml`
 * alone does NOT neutralise a `javascript:` / `data:` URI — none of those
 * strings contain the five escaped characters, so they survive attribute
 * escaping intact and execute on click. Any href that isn't built from a
 * fixed root-relative or http(s) template must pass through here first.
 *
 * Returns the URL when it is root-relative (`/…`, but not protocol-relative
 * `//host` which the browser resolves to an external origin) or http(s);
 * otherwise `#`. Pair with `escapeHtml` for the attribute-context encoding:
 * `href="${escapeHtml(safeHref(url))}"`.
 */
export function safeHref(url: string): string {
	const u = url.trim();
	if (/^https?:\/\//i.test(u)) return u;
	if (u.startsWith('/') && !u.startsWith('//')) return u;
	return '#';
}
