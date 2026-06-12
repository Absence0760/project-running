/// Pure shaping for the routine builder (gym_programming.md P2/P4 authoring).
///
/// Dart twin of `apps/web/src/lib/gym/routine_editor_build.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
///
/// The editor carries a "superset with next" flag per exercise. [assignSupersetGroups]
/// turns that per-row flag into the relational (superset_group, superset_order)
/// the schema stores, honouring the gym_routine_exercises_superset_chk invariant
/// (group + order are both null or both set). The runner consumes the persisted
/// columns via expandRoutineSteps.
library;

/// One exercise's (group, order) assignment. Both fields are null for a
/// standalone exercise; both set for a superset member.
class SupersetAssignment {
  final int? supersetGroup;
  final int? supersetOrder;
  const SupersetAssignment({this.supersetGroup, this.supersetOrder});
}

/// Walk the (already non-blank, in display order) exercises and assign a shared
/// group id to each maximal run linked by "superset with next". A flagged
/// exercise and the one after it land in the same group; a run of flagged
/// exercises forms one longer group. Standalone exercises get (null, null).
/// `flags[i]` is true when exercise i should superset with exercise i+1; the
/// last flag is ignored (nothing follows).
List<SupersetAssignment> assignSupersetGroups(List<bool> flags) {
  final out = <SupersetAssignment>[];
  var groupId = 0;
  var inGroup = false;
  var groupOrder = 0;
  var prevFlagged = false;

  for (var i = 0; i < flags.length; i++) {
    final isLast = i == flags.length - 1;
    final flagged = !isLast && flags[i];

    if (flagged || prevFlagged) {
      if (!inGroup) {
        groupId += 1;
        groupOrder = 0;
        inGroup = true;
      }
      out.add(SupersetAssignment(supersetGroup: groupId, supersetOrder: groupOrder));
      groupOrder += 1;
    } else {
      inGroup = false;
      out.add(const SupersetAssignment());
    }
    prevFlagged = flagged;
  }
  return out;
}
