/// Who a targeted in-app send may be offered to.
///
/// The `direct_messages` INSERT policy (migration `20261026_001`) admits a
/// send when a follow edge exists in EITHER direction and neither party has
/// blocked the other. The picker is therefore built from the union of the
/// sender's followers and the people they follow: a list built from followers
/// alone hides people the send would in fact accept, and one built from an
/// open people search offers sends RLS is going to refuse.
///
/// The block half of that gate is deliberately not modelled here. `user_blocks`
/// is owner-read only, so a client cannot see a block placed ON it — marking a
/// row "can't be messaged" would require leaking exactly that. Those sends are
/// refused server-side and surfaced by `sendDm`'s 42501 branch.

// The canonical accent-and-case fold, not a local copy. The copy that used
// to live here skipped the final-sigma collapse, which made this the only
// sigma-SENSITIVE search key left in the product: a display name `ΟΔΟΣ`
// folds to a trailing ς, so a reader typing the medial σ their keyboard
// produces could not find it (decisions § 1340).
import { fold } from '../segments/catalogue_browse';

export type DmRelation = 'mutual' | 'follows_you' | 'you_follow';

/// The profile shape both `fetchFollowers` and `fetchFollowing` return.
export interface DmCandidateProfile {
	id: string;
	display_name: string | null;
	avatar_url: string | null;
}

export interface DmRecipient {
	id: string;
	displayName: string | null;
	avatarUrl: string | null;
	relation: DmRelation;
}


/// Merge the two follow directions into one deduped, display-ordered list.
///
/// `selfId` is dropped when present: the `direct_messages` CHECK forbids
/// `sender_id = recipient_id` outright, so a self row reaching the list some
/// other way must not be offered as a send that can only fail.
///
/// Ordering is by display name, unnamed last, with the id as a total tiebreak
/// so two renders of the same follow graph list people in the same order
/// regardless of which of the two fetches resolved first.
export function dmRecipientCandidates(
	followers: readonly DmCandidateProfile[],
	following: readonly DmCandidateProfile[],
	selfId?: string | null
): DmRecipient[] {
	const byId = new Map<string, DmRecipient>();
	const add = (p: DmCandidateProfile, relation: Exclude<DmRelation, 'mutual'>) => {
		if (!p?.id || p.id === selfId) return;
		const seen = byId.get(p.id);
		if (seen) {
			if (seen.relation !== relation) seen.relation = 'mutual';
			return;
		}
		byId.set(p.id, {
			id: p.id,
			displayName: p.display_name ?? null,
			avatarUrl: p.avatar_url ?? null,
			relation
		});
	};
	for (const p of followers) add(p, 'follows_you');
	for (const p of following) add(p, 'you_follow');

	return [...byId.values()].sort((a, b) => {
		if (a.displayName === null || b.displayName === null) {
			if (a.displayName !== b.displayName) return a.displayName === null ? 1 : -1;
		} else {
			const byName = a.displayName.localeCompare(b.displayName, undefined, {
				sensitivity: 'base'
			});
			if (byName !== 0) return byName;
		}
		return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
	});
}

/// Narrow the candidate list by a typed name query, accent-folded so a
/// diacritic the sender didn't type still matches the name that carries it.
/// A blank query keeps everyone; a recipient with no display name matches no
/// non-blank query, because there is no text on the row to have matched.
export function filterDmRecipients(
	recipients: readonly DmRecipient[],
	query: string
): DmRecipient[] {
	const q = fold(query.trim());
	if (q === '') return [...recipients];
	return recipients.filter((r) => r.displayName !== null && fold(r.displayName).includes(q));
}
