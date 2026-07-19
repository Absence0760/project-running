// A `<input type="number" bind:value>` binds a NUMBER even when the bound field
// is declared string (Svelte coercion — see apps/web/CLAUDE.md), so both coercers
// accept the number and pass it through rather than rejecting every numeric input
// as "not a string" (which silently dropped the typed value before parsing).
// Web-only: Dart form fields have no equivalent bind:value coercion, so there is
// no twin.

export function intOrNull(s: string | number): number | null {
	if (typeof s === 'number') return Number.isFinite(s) ? Math.trunc(s) : null;
	if (typeof s !== 'string' || s.trim() === '') return null;
	const n = parseInt(s, 10);
	return Number.isFinite(n) ? n : null;
}

export function floatOrNull(s: string | number): number | null {
	if (typeof s === 'number') return Number.isFinite(s) ? s : null;
	if (typeof s !== 'string' || s.trim() === '') return null;
	const n = parseFloat(s);
	return Number.isFinite(n) ? n : null;
}
