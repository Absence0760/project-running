/**
 * Which pair of a rotation to wear next.
 *
 * A rotation (decisions § 183) is a named grouping of gear, and the single
 * `is_default` "current pair" is what auto-tags new runs. Nothing connected
 * the two: a runner who physically rotates three pairs still had every run
 * stamped with whichever pair last held the star, so the mileage the wear
 * classifier grades was wrong for all three. This picks the pair a rotation
 * says is due to come out next, so the star can follow the rotation.
 *
 * Pure functions, no Supabase / auth.
 */

import { gearWear, type GearWearStatus } from './gear_wear';

export interface RotationMember {
	id: string;
	totalDistanceM: number | null | undefined;
	targetDistanceM: number | null | undefined;
	retiredAt: string | null | undefined;
	isCurrent: boolean;
}

export interface RotationRank {
	id: string;
	status: GearWearStatus;
	/// Share of the pair's replacement target already run. A pair carrying no
	/// target of its own is measured against the rotation's reference target,
	/// so it still sorts against its siblings instead of dropping out.
	share: number;
	isCurrent: boolean;
}

export interface RotationPick {
	/// Best-next first. Retired members are absent entirely.
	ranked: RotationRank[];
	pickId: string | null;
	/// The pick already holds the star, so offering to move it is a no-op.
	pickIsCurrent: boolean;
	/// Every eligible pair is at or past its own replacement target.
	allWorn: boolean;
}

function positiveOrNull(value: number | null | undefined): number | null {
	const n = Number(value);
	return Number.isFinite(n) && n > 0 ? n : null;
}

function median(sorted: number[]): number {
	const mid = sorted.length >> 1;
	return sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Rank a rotation's members by how much life each has left, least-worn first.
///
/// Retired gear is out of service and is dropped rather than ranked last — a
/// retired pair is not a pair you could be asked to wear. A pair at or past its
/// target sorts behind every pair that isn't, whatever the shares say:
/// recommending a shoe the app already calls "worn" would be worse advice than
/// no recommendation at all.
export function rotationPick(members: RotationMember[]): RotationPick {
	const eligible = members.filter((m) => !m.retiredAt);
	if (eligible.length === 0) {
		return { ranked: [], pickId: null, pickIsCurrent: false, allWorn: false };
	}

	// Untracked gear has no target to take a share of. Measuring it against the
	// median of its siblings' targets keeps it comparable; with no tracked
	// sibling at all the reference is 1 m, which reduces the share to raw
	// distance — still the same "even the mileage out" ordering.
	const targets = eligible
		.map((m) => positiveOrNull(m.targetDistanceM))
		.filter((t): t is number => t != null)
		.sort((a, b) => a - b);
	const referenceTarget = targets.length > 0 ? median(targets) : 1;

	const ranked = eligible
		.map((m): RotationRank => {
			const total = positiveOrNull(m.totalDistanceM) ?? 0;
			const target = positiveOrNull(m.targetDistanceM) ?? referenceTarget;
			return {
				id: m.id,
				status: gearWear(m.totalDistanceM, m.targetDistanceM).status,
				share: total / target,
				isCurrent: m.isCurrent,
			};
		})
		.sort((a, b) => {
			const aWorn = a.status === 'worn' ? 1 : 0;
			const bWorn = b.status === 'worn' ? 1 : 0;
			if (aWorn !== bWorn) return aWorn - bWorn;
			if (a.share !== b.share) return a.share - b.share;
			return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
		});

	return {
		ranked,
		pickId: ranked[0].id,
		pickIsCurrent: ranked[0].isCurrent,
		allWorn: ranked.every((r) => r.status === 'worn'),
	};
}
