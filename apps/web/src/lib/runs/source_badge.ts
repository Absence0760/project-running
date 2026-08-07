import type { RunSource } from '../types.js';

/**
 * The run-source badge's fill and the foreground that fill can carry.
 *
 * Lives here rather than in `core/mock-data.ts` (where `sourceColor` used to
 * sit) for two reasons: it is a display contract rather than fallback data, and
 * `mock-data.ts` transitively imports `$app`, so nothing in it can be reached by
 * `tsx --test`. The pairing below is the kind of thing that must be recomputed
 * by a guard, not eyeballed — see `contrast_guard.test.ts`.
 */

/** Mirrors the `RunSource` union. Exported so a guard can measure all of it. */
export const RUN_SOURCES: readonly RunSource[] = [
	'app',
	'watch',
	'healthkit',
	'healthconnect',
	'strava',
	'garmin',
	'parkrun',
	'race',
] as const;

/**
 * Theme-INDEPENDENT by design: several of these are provider brand hues (Strava
 * orange, Garmin blue, parkrun magenta), and a badge that changed colour with
 * the theme would stop reading as the provider's mark.
 *
 * Two of the eight moved in § 549, each a hue-preserving darkening of a value
 * that could not carry any foreground at 4.5:1 — `healthkit` #E91E63 → #E3165C
 * (hue 339.6° → 339.5°) and `garmin` #007CC3 → #007AC0 (201.8° → 201.9°). The
 * Garmin one is § 546's case exactly: at #007CC3 its best possible foreground
 * reached **4.496:1**, which is not 4.5:1.
 */
export function sourceColor(source: RunSource): string {
	const colors: Record<RunSource, string> = {
		app: '#1E88E5',
		watch: '#0EA5E9',
		healthkit: '#E3165C',
		healthconnect: '#4CAF50',
		strava: '#FC4C02',
		garmin: '#007AC0',
		parkrun: '#D6255B',
		race: '#9C27B0',
	};
	return colors[source];
}

/** Paired with `sourceColor`; both are theme-independent literals. */
const BADGE_LIGHT_INK = '#FFFFFF';
const BADGE_DARK_INK = '#1B1628';

/**
 * The foreground a source badge must use on its own fill.
 *
 * The four badge call sites had each picked their own: two spelled
 * `color: white`, two spelled `var(--color-surface)` — which FLIPS with the
 * theme, so one fill was asked to carry near-white in light and a dark surface
 * in dark, and no single fill can do both. Measured against the grounds they
 * really paint, six of eight failed 4.5:1 in light and five of eight in dark,
 * for text rendered at 10.4–11.2 px / 600.
 *
 * A fill that does not change with the theme has ONE correct foreground, so
 * this derives it from the fill rather than from the surface underneath — the
 * rule § 481 already established for `IdentityAvatar`'s seeded hues.
 */
export function sourceInk(source: RunSource): string {
	const fill = sourceColor(source);
	return contrastRatio(fill, BADGE_LIGHT_INK) >= contrastRatio(fill, BADGE_DARK_INK)
		? BADGE_LIGHT_INK
		: BADGE_DARK_INK;
}

/** WCAG 2.1 relative luminance of an `#RRGGBB` string. */
export function relativeLuminance(hex: string): number {
	const n = parseInt(hex.slice(1), 16);
	const channels = [(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff].map((c) => {
		const s = c / 255;
		return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
	});
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

/** WCAG 2.1 contrast ratio between two `#RRGGBB` strings. */
export function contrastRatio(a: string, b: string): number {
	const la = relativeLuminance(a);
	const lb = relativeLuminance(b);
	const [hi, lo] = la > lb ? [la, lb] : [lb, la];
	return (hi + 0.05) / (lo + 0.05);
}
