/**
 * Achievement badge catalogue — defined as code, the guided-runs pattern.
 *
 * The catalogue (the *definition* of every badge + tier + threshold) lives
 * here, not in the DB. The DB stores only awards (which user earned which
 * badge, when). This keeps the catalogue versionable/testable and avoids a
 * round-trip to know what badges exist.
 *
 * `evaluateBadges` is a pure dispatcher: it takes the user's milestone
 * primitives (PR count, lifetime/single-run distance, best streak, completed
 * plan count) and returns the earned set with the highest tier reached per
 * family. The SQL `award_achievements_for_user` function duplicates these
 * exact thresholds; `badges.test.ts` (web) + `achievements_test.sql` (pgtap)
 * pin the contract so drift fails CI.
 *
 * Labels/descriptions are NOT stored on the catalogue entries — only their
 * i18n keys. The display layer resolves `labelKey`/`descKey` via `m(key)`
 * (web) / `AppLocalizations` (mobile) so the grid re-renders on locale switch.
 *
 * Mirrors `apps/mobile_android/lib/badges.dart`. Keep in lockstep — the
 * shared-library-syncer agent watches the pair.
 */

import type { MessageKey } from '$lib/i18n/messages';
import type { AchievementTier, AchievementSourceKind } from '$lib/types';
import { en } from '../i18n/locales/en';

export type { AchievementTier, AchievementSourceKind };

/** Tier order, low → high. The earned tier is the highest threshold met. */
export const TIER_ORDER: AchievementTier[] = ['bronze', 'silver', 'gold', 'platinum'];

export interface BadgeTier {
	tier: AchievementTier;
	/** Numeric threshold in the family's native unit (metres / days / count). */
	threshold: number;
	/** Material Symbols ligature name. */
	icon: string;
	labelKey: MessageKey;
	descKey: MessageKey;
}

export interface Badge {
	/** Stable catalogue id, matches the DB `badge_key`. */
	id: string;
	sourceKind: AchievementSourceKind;
	/** Ordered low → high; `evaluateBadges` returns the highest tier met. */
	tiers: BadgeTier[];
}

/** The numeric the user fed in that earned the tier (display + DB dedupe). */
export interface EarnedBadge {
	badgeKey: string;
	sourceKind: AchievementSourceKind;
	tier: AchievementTier;
	threshold: number;
	icon: string;
	labelKey: MessageKey;
	descKey: MessageKey;
	/** The user's actual value that cleared the threshold. */
	valueNum: number;
}

/** Primitives the catalogue evaluates. All non-negative; absent → 0. */
export interface BadgeInput {
	/** Best single-run distance in metres (longest run). */
	longestRunM: number;
	/** Lifetime summed distance in metres. */
	lifetimeDistanceM: number;
	/** Best run streak in days. */
	bestStreakDays: number;
	/** Count of distinct PR distances held (0–5: 5k/10k/half/marathon/mile). */
	prCount: number;
	/** Count of completed training plans. */
	completedPlanCount: number;
}

/**
 * The catalogue. Thresholds are the lockstep contract with the SQL award
 * function — if you change a number here, change it in
 * `20270206_001_achievements.sql` too (the pgtap pins it).
 */
export const BADGE_CATALOGUE: Badge[] = [
	{
		id: 'distance_single',
		sourceKind: 'distance',
		tiers: [
			{ tier: 'bronze', threshold: 5000, icon: 'directions_run', labelKey: 'badges.distanceSingle5k.label', descKey: 'badges.distanceSingle5k.desc' },
			{ tier: 'silver', threshold: 21097, icon: 'military_tech', labelKey: 'badges.distanceSingleHalf.label', descKey: 'badges.distanceSingleHalf.desc' },
			{ tier: 'gold', threshold: 42195, icon: 'military_tech', labelKey: 'badges.distanceSingleMarathon.label', descKey: 'badges.distanceSingleMarathon.desc' },
			{ tier: 'platinum', threshold: 50000, icon: 'workspace_premium', labelKey: 'badges.distanceSingleUltra.label', descKey: 'badges.distanceSingleUltra.desc' },
		],
	},
	{
		id: 'distance_lifetime',
		sourceKind: 'distance',
		tiers: [
			{ tier: 'bronze', threshold: 100000, icon: 'route', labelKey: 'badges.distanceLifetime100.label', descKey: 'badges.distanceLifetime100.desc' },
			{ tier: 'silver', threshold: 500000, icon: 'route', labelKey: 'badges.distanceLifetime500.label', descKey: 'badges.distanceLifetime500.desc' },
			{ tier: 'gold', threshold: 1000000, icon: 'public', labelKey: 'badges.distanceLifetime1000.label', descKey: 'badges.distanceLifetime1000.desc' },
			{ tier: 'platinum', threshold: 5000000, icon: 'public', labelKey: 'badges.distanceLifetime5000.label', descKey: 'badges.distanceLifetime5000.desc' },
		],
	},
	{
		id: 'streak',
		sourceKind: 'streak',
		tiers: [
			{ tier: 'bronze', threshold: 7, icon: 'local_fire_department', labelKey: 'badges.streak7.label', descKey: 'badges.streak7.desc' },
			{ tier: 'silver', threshold: 30, icon: 'local_fire_department', labelKey: 'badges.streak30.label', descKey: 'badges.streak30.desc' },
			{ tier: 'gold', threshold: 100, icon: 'local_fire_department', labelKey: 'badges.streak100.label', descKey: 'badges.streak100.desc' },
			{ tier: 'platinum', threshold: 365, icon: 'whatshot', labelKey: 'badges.streak365.label', descKey: 'badges.streak365.desc' },
		],
	},
	{
		id: 'pr',
		sourceKind: 'pr',
		tiers: [
			{ tier: 'bronze', threshold: 1, icon: 'timer', labelKey: 'badges.pr1.label', descKey: 'badges.pr1.desc' },
			{ tier: 'silver', threshold: 3, icon: 'timer', labelKey: 'badges.pr3.label', descKey: 'badges.pr3.desc' },
			{ tier: 'gold', threshold: 5, icon: 'trophy', labelKey: 'badges.pr5.label', descKey: 'badges.pr5.desc' },
		],
	},
	{
		id: 'plan_finisher',
		sourceKind: 'plan',
		tiers: [
			{ tier: 'bronze', threshold: 1, icon: 'flag', labelKey: 'badges.plan1.label', descKey: 'badges.plan1.desc' },
			{ tier: 'silver', threshold: 3, icon: 'flag', labelKey: 'badges.plan3.label', descKey: 'badges.plan3.desc' },
			{ tier: 'gold', threshold: 10, icon: 'emoji_events', labelKey: 'badges.plan10.label', descKey: 'badges.plan10.desc' },
		],
	},
];

/** Map a catalogue family to the input value it evaluates against. */
function valueForBadge(badge: Badge, input: BadgeInput): number {
	switch (badge.id) {
		case 'distance_single':
			return input.longestRunM;
		case 'distance_lifetime':
			return input.lifetimeDistanceM;
		case 'streak':
			return input.bestStreakDays;
		case 'pr':
			return input.prCount;
		case 'plan_finisher':
			return input.completedPlanCount;
		default:
			return 0;
	}
}

/**
 * Pure dispatcher. Returns at most one `EarnedBadge` per catalogue family —
 * the highest tier whose threshold the user's value clears. A user at gold
 * does NOT also earn bronze/silver of the same family (one tile per family,
 * highest tier wins), mirroring `recap.ts`'s tiered pick.
 *
 * Deterministic + side-effect-free so it is unit-testable and matches the
 * SQL award function. Output order follows `BADGE_CATALOGUE` order.
 */
export function evaluateBadges(input: BadgeInput): EarnedBadge[] {
	const out: EarnedBadge[] = [];
	for (const badge of BADGE_CATALOGUE) {
		const value = valueForBadge(badge, input);
		let earned: BadgeTier | null = null;
		for (const t of badge.tiers) {
			if (value >= t.threshold) earned = t;
		}
		if (earned) {
			out.push({
				badgeKey: badge.id,
				sourceKind: badge.sourceKind,
				tier: earned.tier,
				threshold: earned.threshold,
				icon: earned.icon,
				labelKey: earned.labelKey,
				descKey: earned.descKey,
				valueNum: value,
			});
		}
	}
	return out;
}

/** Resolve a catalogue entry's tier definition from a stored award. */
export function tierFor(badgeKey: string, tier: AchievementTier): BadgeTier | null {
	const badge = BADGE_CATALOGUE.find((b) => b.id === badgeKey);
	if (!badge) return null;
	return badge.tiers.find((t) => t.tier === tier) ?? null;
}

/**
 * Server-safe English label/desc for a stored award — used by the share page
 * meta + OG card, which run under SSR/Lambda with no i18n runtime. Reads the
 * static English catalogue directly so the wire output is locale-independent
 * (the live grid still localises via `m(labelKey)`).
 */
export function englishBadge(
	badgeKey: string,
	tier: AchievementTier,
): { label: string; desc: string; icon: string } | null {
	const t = tierFor(badgeKey, tier);
	if (!t) return null;
	return { label: en[t.labelKey] ?? badgeKey, desc: en[t.descKey] ?? '', icon: t.icon };
}
