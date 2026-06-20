/// Server-side badge-share SVG builder for /og/badge/[id].png. Pure string
/// concatenation so unit tests can pin the wire shape without the PNG renderer.
///
/// A badge card shows the badge name, tier, and the runner attribution — it
/// embeds no track/location data (public-row column discipline: a badge is a
/// numeric milestone + a date, nothing else).

import { englishBadge, type AchievementTier } from '../social/badges';
import { formatDateStable } from './share_meta';
import { xmlEscape } from './og_run_image';

const W = 1200;
const H = 630;
const PAD = 40;

const BG = '#ffffff';
const BRAND = '#3b82f6';
const STAT_FILL = '#0f172a';
const META_FILL = '#64748b';

const TIER_COLOR: Record<AchievementTier, string> = {
	bronze: '#b08d57',
	silver: '#9aa3ad',
	gold: '#d4af37',
	platinum: '#7fd3e0',
};

export type BadgeImageInput = {
	badge_key?: string | null;
	tier?: string | null;
	earned_at?: string | null;
	displayName?: string | null;
};

/// Build the og:image SVG for a badge share page.
export function buildBadgeOgSvg(input: BadgeImageInput): string {
	const tier = (input.tier ?? 'bronze') as AchievementTier;
	const resolved = input.badge_key ? englishBadge(input.badge_key, tier) : null;
	const tierColor = TIER_COLOR[tier] ?? META_FILL;

	const parts: string[] = [];
	parts.push(
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">`,
	);
	parts.push(`<rect width="${W}" height="${H}" fill="${BG}"/>`);
	parts.push(`<rect width="${W}" height="12" fill="${tierColor}"/>`);

	parts.push(
		`<text x="${PAD}" y="${PAD + 36}" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="28" font-weight="700" fill="${BRAND}">Threkir</text>`,
	);

	const heroText = resolved?.label || 'Achievement';
	parts.push(
		`<text x="${W / 2}" y="${H / 2 - 10}" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="96" font-weight="800" fill="${STAT_FILL}" text-anchor="middle">${xmlEscape(heroText)}</text>`,
	);

	parts.push(
		`<text x="${W / 2}" y="${H / 2 + 64}" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="40" font-weight="700" fill="${tierColor}" text-anchor="middle">${xmlEscape(tier.toUpperCase())}</text>`,
	);

	const sub = buildBadgeSubline(input);
	if (sub) {
		parts.push(
			`<text x="${W / 2}" y="${H - PAD - 10}" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="36" font-weight="500" fill="${META_FILL}" text-anchor="middle">${xmlEscape(sub)}</text>`,
		);
	}

	parts.push('</svg>');
	return parts.join('');
}

export function buildBadgeSubline(input: BadgeImageInput): string {
	const date = formatDateStable(input.earned_at);
	const by = input.displayName?.trim() || '';
	if (by && date) return `${by} · ${date}`;
	if (by) return by;
	if (date) return date;
	return '';
}
