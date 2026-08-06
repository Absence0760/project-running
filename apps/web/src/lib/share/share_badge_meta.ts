/// Per-badge `<head>` meta-tag builder for the share-badge page. Pure string
/// helpers — shared between the SvelteKit +page.svelte (dev-server SSR) and the
/// production share-badge Lambda. Reuses the generic `ShareRunMeta` shape +
/// `injectShareRunMeta` (title/description/canonical/ogImageUrl is run-agnostic).
/// The badge page carries no JSON-LD node yet, so `jsonLd` is left unset.

import { englishBadge, type AchievementTier } from '../social/badges';
import { normaliseSiteUrl } from './share_meta';
import type { ShareRunMeta } from './share_run_meta';
import type { SharedBadge } from './share_badge_lookup';

/// Absolute URL of a badge's public share page. The one definition of the
/// path: the `<head>` canonical below resolves it against `PUBLIC_SITE_URL`,
/// and the profile page's copy-to-clipboard resolves it against
/// `location.origin` so a preview host yields a preview link (§ 520).
export function buildBadgeShareCanonical(
	base: string | null | undefined,
	id: string,
): string {
	return `${normaliseSiteUrl(base)}/share/badge/${id}`;
}

/// Absolute URL of the per-badge `og:image` PNG. Sibling of the canonical
/// above; see `buildRunOgImageUrl` for why an og:image path owes a builder.
export function buildBadgeOgImageUrl(
	base: string | null | undefined,
	id: string,
): string {
	return `${normaliseSiteUrl(base)}/og/badge/${id}.png`;
}

export interface ShareBadgeMetaInput {
	id: string;
	badge: SharedBadge | null;
	displayName: string | null;
	siteUrl: string;
}

export function buildShareBadgeMeta(input: ShareBadgeMetaInput): ShareRunMeta {
	const { id, badge, displayName, siteUrl } = input;
	const base = siteUrl.replace(/\/$/, '');
	const resolved = badge ? englishBadge(badge.badge_key, badge.tier as AchievementTier) : null;
	const who = displayName?.trim();
	const title = resolved
		? who
			? `${who} earned the ${resolved.label} badge`
			: `${resolved.label} — Achievement`
		: 'Achievements — Threkir';
	const description = resolved?.desc ?? "This badge isn't available.";
	return {
		title,
		description,
		canonical: buildBadgeShareCanonical(base, id),
		ogImageUrl: buildBadgeOgImageUrl(base, id),
	};
}
