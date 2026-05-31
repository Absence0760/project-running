// Pure helpers for the user/club avatar fallback (when there's no avatar_url):
// the displayed initial, and a deterministic hue so the same id always gets the
// same placeholder colour. No runes → unit-testable via `tsx --test`.

/** First non-whitespace character of a name, uppercased; `?` when empty. */
export function initial(name: string | null | undefined): string {
	return (name?.trim()?.[0] ?? '?').toUpperCase();
}

/** Stable hue (0–359) derived from an id, for the placeholder background. */
export function hashHue(id: string): number {
	let h = 0;
	for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) | 0;
	return Math.abs(h) % 360;
}
