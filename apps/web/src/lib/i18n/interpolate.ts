// Pure {placeholder} substitution for message strings. Extracted from the
// reactive runtime (store.svelte.ts) so it unit-tests under `tsx --test`
// without the Svelte compiler — the runes file can't be tsx-tested.
// Replacement is by literal string (not regex), so a value containing
// regex-special characters is substituted verbatim, and an unreferenced
// placeholder is left intact rather than blanked.
export function interpolate(
	template: string,
	params?: Record<string, string | number>,
): string {
	if (!params) return template;
	let out = template;
	for (const [key, value] of Object.entries(params)) {
		out = out.replaceAll(`{${key}}`, String(value));
	}
	return out;
}
