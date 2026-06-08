/// Gear wear status — classify a piece of gear by how close its accumulated
/// distance is to its replacement target, so the UI can warn before a shoe is
/// run into the ground.
///
/// Pure Dart, no Supabase / auth. Twin of `apps/web/src/lib/gear/gear_wear.ts`
/// — keep in lockstep (algorithm, thresholds, edge cases, test counts).
///
/// Thresholds are deliberately simple: a shoe in the last ~15% of its planned
/// life is "due" (replace soon), and at/over its target is "worn". Untracked
/// gear (no target set) gets no warning — the progress bar already shows raw
/// distance.
library;

enum GearWearStatus { untracked, ok, due, worn }

/// Fraction of the replacement target at which gear is flagged "due".
const double gearWearDueFraction = 0.85;

class GearWear {
  final GearWearStatus status;

  /// total / target, uncapped (so a 120%-worn shoe reads 1.2); null when no
  /// target is set. The caller caps the progress *bar* at 100% itself.
  final double? fraction;

  const GearWear(this.status, this.fraction);
}

/// Classify gear wear from its rolled-up distance vs its replacement target.
/// Negative / non-finite inputs are treated as 0 so a bad row can't surface a
/// scary false "worn" badge.
GearWear gearWear(num? totalDistanceM, num? targetDistanceM) {
  final target = targetDistanceM?.toDouble() ?? double.nan;
  if (!target.isFinite || target <= 0) {
    return const GearWear(GearWearStatus.untracked, null);
  }
  final totalRaw = totalDistanceM?.toDouble() ?? double.nan;
  final total = totalRaw.isFinite && totalRaw > 0 ? totalRaw : 0.0;
  final fraction = total / target;
  final GearWearStatus status;
  if (fraction >= 1) {
    status = GearWearStatus.worn;
  } else if (fraction >= gearWearDueFraction) {
    status = GearWearStatus.due;
  } else {
    status = GearWearStatus.ok;
  }
  return GearWear(status, fraction);
}
