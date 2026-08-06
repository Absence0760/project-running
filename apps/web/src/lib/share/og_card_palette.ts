/// The two palettes every rasterised share card paints with.
///
/// These are `fixed-canvas` colours in the § 526 register's sense: each card is
/// concatenated into an SVG string and rendered to a PNG that leaves the site,
/// so no device theme reaches it and a CSS custom property would be a value the
/// rasteriser cannot resolve. A fixed canvas is exempt from THEMING, never from
/// contrast (§ 511) — so every ink below carries its measured ratio and the
/// ground it was measured against, computed rather than remembered (§ 534).
///
/// They live here because five card builders had spelled them independently:
/// the light palette four values deep in `og_run_image` / `og_route_image` /
/// `og_badge_image`, and the dark one five values deep in `og_recap_image` /
/// `recap_share_image` — 22 literals expressing 9 values, and the two recap
/// cards byte-identical. Two cards of the same product drifting apart is
/// invisible until someone puts the unfurl and the shared PNG side by side.
///
/// Each card keeps its own geometry, its own type scale and any hue that is
/// genuinely its own (the route card's start/finish caps), because those are
/// not shared and pretending otherwise would be the abstraction this project
/// warns about. Only the palette is common.

/// White-paper card: the run, route and badge unfurls.
///
/// Measured against `bg` (#FFFFFF):
///   brand  3.678:1 — the "Threkir" wordmark at 28-32 px weight 700-800, which
///                    is WCAG large text (>= 18.66 px bold), so its floor is
///                    1.4.3's 3:1 and not 4.5:1.
///   ink   17.853:1 — the hero numeral.
///   muted  4.759:1 — the sub-line and source label; clears AA's 4.5:1 outright
///                    rather than relying on the large-text allowance.
export const OG_CARD_LIGHT = {
	bg: '#FFFFFF',
	brand: '#3B82F6',
	ink: '#0F172A',
	muted: '#64748B',
} as const;

/// Dark card: the recap unfurl (1200x630) and the in-app recap share PNG
/// (1080 square). Same palette, different geometry.
///
/// Measured against `bg` (#0F172A):
///   brand  7.022:1
///   hero  17.853:1 — the distance numeral.
///   label  6.963:1 — the letter-spaced kicker and stat labels.
///   stat  14.482:1 — the stat values and subhead.
export const OG_CARD_DARK = {
	bg: '#0F172A',
	brand: '#60A5FA',
	hero: '#FFFFFF',
	label: '#94A3B8',
	stat: '#E2E8F0',
} as const;
