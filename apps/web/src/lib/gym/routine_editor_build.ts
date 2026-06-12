// Pure shaping for the RoutineEditor (gym_programming.md P2 authoring).
// assignSupersetGroups must keep (superset_group, superset_order) both-null or
// both-set to satisfy the gym_routine_exercises_superset_chk constraint.

export interface SupersetAssignment {
	supersetGroup: number | null;
	supersetOrder: number | null;
}

/// Walk the (already non-blank, in display order) exercises and assign a shared
/// group id to each maximal run linked by `supersetWithNext`. A flagged
/// exercise and the one after it land in the same group; a run of flagged
/// exercises forms one longer group. Standalone exercises get (null, null).
/// `flags[i]` is true when exercise i should superset with exercise i+1; the
/// last flag is ignored (nothing follows).
export function assignSupersetGroups(flags: boolean[]): SupersetAssignment[] {
	const out: SupersetAssignment[] = [];
	let groupId = 0;
	let inGroup = false;
	let groupOrder = 0;
	let prevFlagged = false;

	for (let i = 0; i < flags.length; i++) {
		const isLast = i === flags.length - 1;
		const flagged = !isLast && flags[i];

		if (flagged || prevFlagged) {
			if (!inGroup) {
				groupId += 1;
				groupOrder = 0;
				inGroup = true;
			}
			out.push({ supersetGroup: groupId, supersetOrder: groupOrder });
			groupOrder += 1;
		} else {
			inGroup = false;
			out.push({ supersetGroup: null, supersetOrder: null });
		}
		prevFlagged = flagged;
	}
	return out;
}
