/// Canonical parser for a public boolean feature-flag env var.
///
/// Every fail-closed `PUBLIC_*_ENABLED` gate reads its env string
/// through this one function so the accepted-affirmative set can't
/// drift between flags. An unset / empty / unrecognised value reads
/// as `false` (fail-closed): a flag can only ever be turned ON by an
/// explicit affirmative, never left on by a typo.
///
/// Accepts `1`, `true`, `yes`, `on` — trimmed and case-insensitive —
/// so `TRUE`, ` yes `, `On` all enable, matching operator intuition.
export function isTruthyFlagValue(raw: string | null | undefined): boolean {
	const v = (raw ?? '').trim().toLowerCase();
	return v === '1' || v === 'true' || v === 'yes' || v === 'on';
}
