/**
 * Scheme guard for `<img src>` values that originate from the database
 * (avatar URLs, run-photo URLs). A DB CHECK constraint is the primary
 * defence, but a row written before the constraint landed — or via a
 * path that bypasses it — could still carry a `javascript:` / `data:`
 * (SVG-with-script) / other hostile scheme that an `<img src>` would
 * happily dereference. This returns the URL only when its scheme is
 * allow-listed, and an empty string otherwise so the browser renders
 * no image (the caller's initials / placeholder shows through).
 *
 * `https:` is the only DB-stored scheme we ever expect. `blob:` and
 * `data:` are opt-in for the local-preview sites that synthesise them
 * client-side (`URL.createObjectURL`) — never for DB values.
 */
export function safeImageSrc(
	url: string | null | undefined,
	opts: { allowBlob?: boolean; allowData?: boolean } = {},
): string {
	if (!url) return '';
	const trimmed = url.trim();
	if (trimmed.startsWith('https://')) return trimmed;
	if (opts.allowBlob && trimmed.startsWith('blob:')) return trimmed;
	if (opts.allowData && trimmed.startsWith('data:image/')) return trimmed;
	return '';
}
