/// Read the value of an `<input type="number">` bound with `bind:value`.
///
/// Svelte replaces the bound state with a NUMBER on the first keystroke, and
/// with `null` when the field holds something the browser cannot parse — so a
/// state initialised to `''` is a string only until the user touches it.
/// Reading it as a string after that throws `.trim is not a function`, and a
/// derived that throws takes its whole reactive chain with it: the save never
/// ran and a perfectly valid entry was dropped with nothing surfaced. Nine
/// number inputs across the settings pages share this shape, so the read has
/// one home rather than a copy per field.
export function numberInputValue(raw: unknown): number | null {
	if (raw === null || raw === undefined || raw === '') return null;
	const n = typeof raw === 'number' ? raw : Number.parseInt(String(raw).trim(), 10);
	return Number.isFinite(n) ? n : null;
}
