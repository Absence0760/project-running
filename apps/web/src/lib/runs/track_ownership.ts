/// Whether the current viewer owns this track. The owner reads the
/// unclipped track via a direct Storage download; every other viewer
/// (including anon) goes through the clip-public-track Edge Function so
/// the unclipped blob never crosses the wire (decisions.md §33). Strict
/// null + equality: supabase-js returns `null` (not `undefined`) for an
/// anon viewer today, but the explicit `!= null` guards remove the
/// dependency on that detail — without them an `undefined === undefined`
/// would route an anon viewer down the owner branch and skip the clip.
export function isTrackOwner(
	viewerId: string | null | undefined,
	ownerUserId: string | null | undefined,
): boolean {
	return viewerId != null && ownerUserId != null && viewerId === ownerUserId;
}

export interface TrackOwnership {
	isOwner: boolean;
	shouldClip: boolean;
}

/// Resolve the owner / clip decision only AFTER auth has settled.
///
/// The public share surfaces (`/share/run/[id]`, feed thumbnails) are
/// shell-less and mount before the root layout's auth gate resolves. If
/// the ownership check reads `auth.user?.id` at mount, a load where the
/// owner's session hasn't finished restoring reads `null`, classifies the
/// owner as a non-owner, and takes the clip Edge Function path instead of
/// the direct Storage read — an avoidable round trip with a worse failure
/// mode (issue #347). Awaiting `ready` first, then reading `getViewerId`,
/// pins the decision to the hydrated session. Not a security backstop —
/// the EF re-derives caller identity from the JWT (`isOwnerBypass`).
///
/// `shouldClip` mirrors the non-owner-including-anon rule: clip whenever
/// an owner is known and the viewer is not that owner.
export async function resolveTrackOwnership(
	ready: () => Promise<void>,
	getViewerId: () => string | null | undefined,
	ownerUserId: string | null | undefined,
): Promise<TrackOwnership> {
	await ready();
	const owner = isTrackOwner(getViewerId(), ownerUserId);
	return { isOwner: owner, shouldClip: ownerUserId != null && !owner };
}
