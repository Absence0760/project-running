/**
 * Gear wear status — classify a piece of gear by how close its accumulated
 * distance is to its replacement target, so the UI can warn before a shoe is
 * run into the ground.
 *
 * Pure functions, no Supabase / auth. Web-only for now (the mobile gear screen
 * computes its own progress inline; mirroring this classification there is a
 * tracked follow-up — see docs/product/followups.md). When mobile adopts it,
 * add a Dart twin + register the parity pair.
 *
 * Thresholds are deliberately simple: a shoe in the last ~15% of its planned
 * life is "due" (replace soon), and at/over its target is "worn". Untracked
 * gear (no target set) gets no warning — the progress bar already shows raw
 * distance.
 */

export type GearWearStatus = 'untracked' | 'ok' | 'due' | 'worn';

/// Fraction of the replacement target at which gear is flagged "due".
export const GEAR_WEAR_DUE_FRACTION = 0.85;

export interface GearWear {
	status: GearWearStatus;
	/// total / target, uncapped (so a 120%-worn shoe reads 1.2); null when no
	/// target is set. The caller caps the progress *bar* at 100% itself.
	fraction: number | null;
}

/// Classify gear wear from its rolled-up distance vs its replacement target.
/// Negative / non-finite inputs are treated as 0 so a bad row can't surface a
/// scary false "worn" badge.
export function gearWear(
	totalDistanceM: number | null | undefined,
	targetDistanceM: number | null | undefined,
): GearWear {
	const target = Number(targetDistanceM);
	if (!Number.isFinite(target) || target <= 0) {
		return { status: 'untracked', fraction: null };
	}
	const totalRaw = Number(totalDistanceM);
	const total = Number.isFinite(totalRaw) && totalRaw > 0 ? totalRaw : 0;
	const fraction = total / target;
	let status: GearWearStatus;
	if (fraction >= 1) status = 'worn';
	else if (fraction >= GEAR_WEAR_DUE_FRACTION) status = 'due';
	else status = 'ok';
	return { status, fraction };
}
