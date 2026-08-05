// Pure helpers for the user/club avatar fallback (when there's no avatar_url):
// the displayed initial, and a deterministic hue so the same id always gets the
// same placeholder colour. No runes → unit-testable via `tsx --test`.

/** First non-whitespace character of a name, uppercased; `?` when empty. */
export function initial(name: string | null | undefined): string {
	return (name?.trim()?.[0] ?? '?').toUpperCase();
}

/** Stable hue (0–359) derived from an id, for the placeholder background.
 *
 * Deliberately NOT the same arithmetic as mobile's `identityHue` (`& 0x7fffffff`
 * where this wraps signed 32-bit), so the same person can hash to a different
 * hue on the two platforms. Each side is pinned to its own history — changing
 * either recolours every existing avatar — so the parity pair below is the
 * CLAMP, not the hash. */
export function hashHue(id: string): number {
	let h = 0;
	for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) | 0;
	return Math.abs(h) % 360;
}

// The identity-avatar contrast clamp, ported from mobile's
// packages/ui_kit/lib/src/widgets/identity_avatar.dart (decisions § 481). At the
// house saturation and lightness there is a mid-luminance band where NEITHER
// white nor ink reaches AA — at 55% lightness white fails on 297 of the 360
// hues and the best of the two pair still bottoms out at 3.975:1 around magenta
// — so the lightness is nudged out of that band one step at a time, in the
// direction the better foreground already favours. Hues that are legible
// unclamped keep their historical colour exactly.
const SEED_SATURATION = 50;
const SEED_BASE_LIGHTNESS = 55;
const SEED_MIN_CONTRAST = 4.5;

/** Mobile's AppTheme.ink. Theme-independent, because the seed fill is too. */
export const SEED_INK = '#1B1628';
export const SEED_ON_LIGHT = '#FFFFFF';

function hslToRgb(h: number, s: number, l: number): [number, number, number] {
	const sn = s / 100;
	const ln = l / 100;
	const a = sn * Math.min(ln, 1 - ln);
	const f = (n: number): number => {
		const k = (n + h / 30) % 12;
		return ln - a * Math.max(-1, Math.min(k - 3, Math.min(9 - k, 1)));
	};
	// Rounded to 8-bit channels before it is ever measured, because Dart's
	// HSLColor.toColor() does and the clamp loop's exit is a hair above the
	// threshold (4.502:1 at its worst hue) — measuring in float would let a
	// boundary hue stop one step earlier here than there.
	return [f(0), f(8), f(4)].map((v) => Math.round(v * 255) / 255) as [number, number, number];
}

function luminance([r, g, b]: [number, number, number]): number {
	const chan = (v: number): number =>
		v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
	return 0.2126 * chan(r) + 0.7152 * chan(g) + 0.0722 * chan(b);
}

function hexLuminance(hex: string): number {
	const n = parseInt(hex.slice(1), 16);
	return luminance([((n >> 16) & 0xff) / 255, ((n >> 8) & 0xff) / 255, (n & 0xff) / 255]);
}

function contrast(a: number, b: number): number {
	const [hi, lo] = a > b ? [a, b] : [b, a];
	return (hi + 0.05) / (lo + 0.05);
}

/** Lightness (0–100) for `hue`, clamped out of the band where no foreground
 *  reaches AA. */
export function seedLightness(hue: number): number {
	const white = hexLuminance(SEED_ON_LIGHT);
	const ink = hexLuminance(SEED_INK);
	let lightness = SEED_BASE_LIGHTNESS;
	let fill = luminance(hslToRgb(hue, SEED_SATURATION, lightness));
	const darken = contrast(white, fill) >= contrast(ink, fill);
	while (
		contrast(white, fill) < SEED_MIN_CONTRAST &&
		contrast(ink, fill) < SEED_MIN_CONTRAST &&
		lightness > 0 &&
		lightness < 100
	) {
		lightness = Math.min(100, Math.max(0, lightness + (darken ? -1 : 1)));
		fill = luminance(hslToRgb(hue, SEED_SATURATION, lightness));
	}
	return lightness;
}

/** CSS background for a seeded identity avatar. */
export function seedBackground(hue: number): string {
	return `hsl(${hue}, ${SEED_SATURATION}%, ${seedLightness(hue)}%)`;
}

/** Foreground over the seeded background, picked by computed contrast. */
export function seedForeground(hue: number): string {
	const fill = luminance(hslToRgb(hue, SEED_SATURATION, seedLightness(hue)));
	return contrast(hexLuminance(SEED_ON_LIGHT), fill) >= contrast(hexLuminance(SEED_INK), fill)
		? SEED_ON_LIGHT
		: SEED_INK;
}

/** Contrast of the chosen foreground against the resolved fill — exported so
 *  the guard can assert AA over every hue rather than a sampled few. */
export function seedContrast(hue: number): number {
	const fill = luminance(hslToRgb(hue, SEED_SATURATION, seedLightness(hue)));
	return contrast(hexLuminance(seedForeground(hue)), fill);
}
