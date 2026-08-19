/// Which pair of a rotation to wear next.
///
/// A rotation (decisions § 183) is a named grouping of gear, and the single
/// `is_default` "current pair" is what auto-tags new runs. Nothing connected
/// the two: a runner who physically rotates three pairs still had every run
/// stamped with whichever pair last held the star, so the mileage the wear
/// classifier grades was wrong for all three. This picks the pair a rotation
/// says is due to come out next, so the star can follow the rotation.
///
/// Pure Dart, no Supabase / auth. Twin of
/// `apps/web/src/lib/gear/rotation_pick.ts` — keep in lockstep (algorithm,
/// edge cases, test counts).
library;

import 'gear_wear.dart';

class RotationMember {
  final String id;
  final num? totalDistanceM;
  final num? targetDistanceM;
  final String? retiredAt;
  final bool isCurrent;

  const RotationMember({
    required this.id,
    this.totalDistanceM,
    this.targetDistanceM,
    this.retiredAt,
    this.isCurrent = false,
  });
}

class RotationRank {
  final String id;
  final GearWearStatus status;

  /// Share of the pair's replacement target already run. A pair carrying no
  /// target of its own is measured against the rotation's reference target,
  /// so it still sorts against its siblings instead of dropping out.
  final double share;
  final bool isCurrent;

  const RotationRank({
    required this.id,
    required this.status,
    required this.share,
    required this.isCurrent,
  });
}

class RotationPick {
  /// Best-next first. Retired members are absent entirely.
  final List<RotationRank> ranked;
  final String? pickId;

  /// The pick already holds the star, so offering to move it is a no-op.
  final bool pickIsCurrent;

  /// Every eligible pair is at or past its own replacement target.
  final bool allWorn;

  const RotationPick({
    required this.ranked,
    required this.pickId,
    required this.pickIsCurrent,
    required this.allWorn,
  });
}

double? _positiveOrNull(num? value) {
  final n = value?.toDouble() ?? 0.0;
  return n.isFinite && n > 0 ? n : null;
}

double _median(List<double> sorted) {
  final mid = sorted.length >> 1;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Rank a rotation's members by how much life each has left, least-worn first.
///
/// Retired gear is out of service and is dropped rather than ranked last — a
/// retired pair is not a pair you could be asked to wear. A pair at or past its
/// target sorts behind every pair that isn't, whatever the shares say:
/// recommending a shoe the app already calls "worn" would be worse advice than
/// no recommendation at all.
RotationPick rotationPick(List<RotationMember> members) {
  final eligible = members
      .where((m) => m.retiredAt == null || m.retiredAt!.isEmpty)
      .toList(growable: false);
  if (eligible.isEmpty) {
    return const RotationPick(
        ranked: [], pickId: null, pickIsCurrent: false, allWorn: false);
  }

  // Untracked gear has no target to take a share of. Measuring it against the
  // median of its siblings' targets keeps it comparable; with no tracked
  // sibling at all the reference is 1 m, which reduces the share to raw
  // distance — still the same "even the mileage out" ordering.
  final targets = eligible
      .map((m) => _positiveOrNull(m.targetDistanceM))
      .whereType<double>()
      .toList()
    ..sort();
  final referenceTarget = targets.isNotEmpty ? _median(targets) : 1.0;

  final ranked = eligible.map((m) {
    final total = _positiveOrNull(m.totalDistanceM) ?? 0.0;
    final target = _positiveOrNull(m.targetDistanceM) ?? referenceTarget;
    return RotationRank(
      id: m.id,
      status: gearWear(m.totalDistanceM, m.targetDistanceM).status,
      share: total / target,
      isCurrent: m.isCurrent,
    );
  }).toList()
    ..sort((a, b) {
      final aWorn = a.status == GearWearStatus.worn ? 1 : 0;
      final bWorn = b.status == GearWearStatus.worn ? 1 : 0;
      if (aWorn != bWorn) return aWorn - bWorn;
      if (a.share != b.share) return a.share.compareTo(b.share);
      return a.id.compareTo(b.id);
    });

  return RotationPick(
    ranked: ranked,
    pickId: ranked.first.id,
    pickIsCurrent: ranked.first.isCurrent,
    allWorn: ranked.every((r) => r.status == GearWearStatus.worn),
  );
}
