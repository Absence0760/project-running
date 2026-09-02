/// Menstrual-cycle-aware and pregnancy-aware plan-adjustment logic.
///
/// SENSITIVE: the inputs (cycle length, last-period-start, due date) are GDPR
/// Art 9 special-category reproductive-health data. This module is the PURE
/// half — it takes already-consented inputs plus a plan workout and returns
/// the modest, bounded patch to apply. Consent gating, the fail-closed feature
/// flag, and persistence live at the call sites.
///
/// The algorithm is deliberately conservative and reuses the recovery-week
/// ease shape (clear the strict pace target, scale distance) rather than
/// inventing new intensity math. Full rationale + exact bounds in
/// docs/architecture/decisions.md § 231 and docs/features/training.md.
///
/// Dart twin of `apps/web/src/lib/training/cycle_plan.ts` — keep the algorithm,
/// edge cases, outputs, and test counts in lockstep.
library;

enum CyclePhase { menstrual, follicular, ovulatory, luteal }

/// Sane menstrual-cycle bounds. Outside this range the phase derivation is
/// refused (no adjustment) rather than guessing off an implausible input.
const int minCycleLengthDays = 21;
const int maxCycleLengthDays = 40;

const int _lutealLengthDays = 14;
const int _menstrualDays = 5;
const int _ovulatoryRadiusDays = 1;
const int _lateLutealDays = 3;

/// Modest, bounded volume trim applied on eased cycle days — 15% off, NOT the
/// 40% of a full recovery week.
const double cycleEaseScale = 0.85;

/// Pregnancy volume taper by trimester — a progressive reduction. Conservative
/// caps, NOT a medical prescription (the in-UI disclaimer carries that).
const Map<int, double> pregnancyVolumeScale = {1: 0.9, 2: 0.75, 3: 0.5};

const int _gestationWeeks = 40;

const Set<String> _qualityKinds = {'tempo', 'interval', 'marathon_pace'};

// ─────────────────────── Date helpers ───────────────────────

/// A calendar date and nothing else. The anchors this module reads —
/// last-period start, due date — come out of the settings bag, which is jsonb,
/// so an entry another client or a hand edit wrote is a string of unknown
/// shape. `int.parse` THROWS on one where the web twin's `parseInt` returns
/// NaN and propagates it to a null result, so the check has to be stated on
/// both sides rather than left to a coincidence of numeric-parse conventions.
final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

int? _isoToEpochDay(String iso) {
  if (!_isoDate.hasMatch(iso)) return null;
  final parts = iso.split('-');
  final utc = DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
  return (utc.millisecondsSinceEpoch / 86400000).floor();
}

/// Whole days from one ISO date to another, or null when either is not an ISO
/// date. Fail-safe like everything else here: leaving the plan as prescribed
/// beats easing it off an anchor we could not read.
int? daysBetweenIso(String fromIso, String toIso) {
  final from = _isoToEpochDay(fromIso);
  final to = _isoToEpochDay(toIso);
  return from == null || to == null ? null : to - from;
}

// ─────────────────────── Menstrual cycle ───────────────────────

class CycleDayInfo {
  final int dayInCycle;
  final CyclePhase phase;
  final bool isEaseDay;

  const CycleDayInfo({
    required this.dayInCycle,
    required this.phase,
    required this.isEaseDay,
  });
}

/// Derive the cycle-day info for [dateIso] from the last-period-start anchor
/// and cycle length. Returns null when the cycle length is outside the sane
/// band (the caller then leaves the plan unadjusted).
CycleDayInfo? cycleDayInfo(
  String lastPeriodStartIso,
  int cycleLengthDays,
  String dateIso,
) {
  if (cycleLengthDays < minCycleLengthDays ||
      cycleLengthDays > maxCycleLengthDays) {
    return null;
  }
  final raw = daysBetweenIso(lastPeriodStartIso, dateIso);
  if (raw == null) return null;
  final len = cycleLengthDays;
  final dayInCycle = ((raw % len) + len) % len;

  final ovulationDay = len - _lutealLengthDays;
  final CyclePhase phase;
  if (dayInCycle < _menstrualDays) {
    phase = CyclePhase.menstrual;
  } else if (dayInCycle < ovulationDay - _ovulatoryRadiusDays) {
    phase = CyclePhase.follicular;
  } else if (dayInCycle <= ovulationDay + _ovulatoryRadiusDays) {
    phase = CyclePhase.ovulatory;
  } else {
    phase = CyclePhase.luteal;
  }
  final isLateLuteal = dayInCycle >= len - _lateLutealDays;
  final isEaseDay = phase == CyclePhase.menstrual || isLateLuteal;
  return CycleDayInfo(
    dayInCycle: dayInCycle,
    phase: phase,
    isEaseDay: isEaseDay,
  );
}

// ─────────────────────── Pregnancy ───────────────────────

/// Trimester (1/2/3) for [dateIso] given the due date. Returns null when the
/// date falls outside the pregnancy — before the conception window or more
/// than two weeks past the due date — so those weeks run as prescribed.
int? trimesterForDate(String dueDateIso, String dateIso) {
  final daysUntilDue = daysBetweenIso(dateIso, dueDateIso);
  if (daysUntilDue == null) return null;
  final gestWeeks = _gestationWeeks - daysUntilDue / 7;
  if (gestWeeks < 0) return null;
  if (gestWeeks > _gestationWeeks + 2) return null;
  if (gestWeeks < 14) return 1;
  if (gestWeeks < 28) return 2;
  return 3;
}

// ─────────────────────── Workout patch ───────────────────────

enum CyclePlanMode { cycle, pregnancy }

class CyclePlanConfig {
  final CyclePlanMode mode;
  final int cycleLengthDays;
  final String lastPeriodStartIso;
  final String dueDateIso;

  const CyclePlanConfig.cycle({
    required this.cycleLengthDays,
    required this.lastPeriodStartIso,
  })  : mode = CyclePlanMode.cycle,
        dueDateIso = '';

  const CyclePlanConfig.pregnancy({required this.dueDateIso})
      : mode = CyclePlanMode.pregnancy,
        cycleLengthDays = 0,
        lastPeriodStartIso = '';
}

/// The subset of `plan_workouts` fields a cycle/pregnancy adjustment touches.
/// A field present in the map is written; absent means "leave unchanged".
/// `structure` present-and-null clears the stored jsonb.
class CyclePlanWorkoutPatch {
  final Map<String, Object?> fields;
  const CyclePlanWorkoutPatch(this.fields);
  bool get isEmpty => fields.isEmpty;
}

/// Compute the patch to apply to one plan workout under a cycle/pregnancy
/// adjustment. Returns null for workouts that shouldn't change on that date.
CyclePlanWorkoutPatch? cyclePlanWorkoutPatch(
  String kind,
  num? targetDistanceM,
  String scheduledDate,
  CyclePlanConfig cfg,
) {
  if (kind == 'rest') return null;

  if (cfg.mode == CyclePlanMode.cycle) {
    final info = cycleDayInfo(
      cfg.lastPeriodStartIso,
      cfg.cycleLengthDays,
      scheduledDate,
    );
    if (info == null || !info.isEaseDay) return null;
    if (kind == 'race') return null;
    final fields = <String, Object?>{};
    if (_qualityKinds.contains(kind)) {
      fields['target_pace_sec_per_km'] = null;
      fields['target_pace_tolerance_sec'] = null;
    }
    if (targetDistanceM != null) {
      fields['target_distance_m'] = (targetDistanceM * cycleEaseScale).round();
    }
    return fields.isEmpty ? null : CyclePlanWorkoutPatch(fields);
  }

  final tri = trimesterForDate(cfg.dueDateIso, scheduledDate);
  if (tri == null) return null;
  final fields = <String, Object?>{};
  if (_qualityKinds.contains(kind) || kind == 'race') {
    fields['kind'] = 'easy';
    fields['target_pace_sec_per_km'] = null;
    fields['target_pace_tolerance_sec'] = null;
    fields['structure'] = null;
  }
  if (targetDistanceM != null) {
    fields['target_distance_m'] =
        (targetDistanceM * pregnancyVolumeScale[tri]!).round();
  }
  return fields.isEmpty ? null : CyclePlanWorkoutPatch(fields);
}
