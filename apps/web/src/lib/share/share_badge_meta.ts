/// Per-badge `<head>` meta-tag builder for the share-badge page. Pure string
/// helpers — shared between the SvelteKit +page.svelte (dev-server SSR) and the
/// production share-badge Lambda. Reuses the generic `ShareRunMeta` shape +
/// `injectShareRunMeta` (title/description/ogUrl/ogImageUrl is run-agnostic).

import { englishBadge, type AchievementTier } from '../social/badges';
import type { ShareRunMeta } from './share_run_meta';
import type { SharedBadge } from './share_badge_lookup';

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
		ogUrl: `${base}/share/badge/${id}`,
		ogImageUrl: `${base}/og/badge/${id}.png`,
	};
}
