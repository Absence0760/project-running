/// Numeric bounds on user-entered columns, stated once per client and enforced
/// by a matching CHECK constraint in the database.
///
/// The sibling of `text_limits.dart` for the numeric half of the same defect. A
/// field capped below the constraint is merely conservative; one capped above
/// it — or not capped at all — hands the runner a postgres 23514 naming a
/// constraint, which is not a sentence anybody can act on. That is what
/// `body_metrics.weight_kg` did: a bare `> 0` guard against
/// `check (weight_kg > 0 and weight_kg <= 500)`, so 600 kg (or 1200 lb, which
/// is 544 kg) round-tripped to a raw error. decisions.md § 792.
///
/// Every entry is the constraint's own effective INCLUSIVE range, not a
/// paraphrase of it: an exclusive `> 0` becomes the smallest value the column's
/// `numeric(p, s)` scale can hold above zero, because that is the bound a form
/// can actually state. `scripts/check_shared_constants.mjs` reads the CHECK out
/// of the migrations and compares, so neither number here is a transcription
/// anyone has to keep true by hand.
///
/// A field may enforce something NARROWER — the 20–250 kg plausible-human
/// range below is inside `bodyMetricsWeightKg` and is what the body-metrics
/// screen actually shows. The registry is the ceiling that narrowing may never
/// exceed.
///
/// Dart twin of `apps/web/src/lib/core/numeric_limits.ts`.
library;

class NumericLimit {
  const NumericLimit(this.min, this.max);

  final double min;
  final double max;
}

const Map<String, NumericLimit> kNumericLimits = {
  'bodyMetricsWeightKg': NumericLimit(0.01, 500),
  'profileHeightCm': NumericLimit(0.1, 300),
  'checkpointBodyWeightKg': NumericLimit(20, 400),
  'gymSetRpe': NumericLimit(0, 10),
  'routineTargetRpe': NumericLimit(0, 10),
  'routineRestS': NumericLimit(0, 3600),
};

/// The `<table>.<column>` each bound is enforced on, so the guard can find its
/// CHECK.
const Map<String, String> kNumericLimitColumns = {
  'bodyMetricsWeightKg': 'body_metrics.weight_kg',
  'profileHeightCm': 'user_profiles.height_cm',
  'checkpointBodyWeightKg': 'checkpoint_crossings.body_weight_kg',
  'gymSetRpe': 'gym_sets.rpe',
  'routineTargetRpe': 'gym_routine_sets.target_rpe',
  'routineRestS': 'gym_routine_sets.rest_s',
};

enum NumericLimitVerdict { ok, below, above, invalid }

/// Grade a value already converted to the column's CANONICAL unit. Callers that
/// take a typed value in a display unit must convert first: refusing 1200 lb
/// because it is above a bound of 500 would be refusing the wrong number.
NumericLimitVerdict checkNumericLimit(NumericLimit limit, double value) {
  if (value.isNaN || value.isInfinite) return NumericLimitVerdict.invalid;
  if (value < limit.min) return NumericLimitVerdict.below;
  if (value > limit.max) return NumericLimitVerdict.above;
  return NumericLimitVerdict.ok;
}

/// The bound restated in the unit the field is TYPED in, rounded INWARD to one
/// decimal place.
///
/// Inward, because the number this returns is shown to the runner — as the
/// field's hint and in the refusal — and a bound the runner cannot satisfy by
/// typing it is a loop they cannot escape. The cost is that the pounds form
/// cannot express the last 0.03 lb below a 500 kg ceiling, which excludes no
/// weight any human has.
NumericLimit numericBoundsIn(
  NumericLimit limit, {
  double Function(double canonical) toDisplay = _identity,
}) {
  return NumericLimit(
    (toDisplay(limit.min) * 10).ceil() / 10,
    (toDisplay(limit.max) * 10).floor() / 10,
  );
}

double _identity(double v) => v;

/// The plausible HUMAN body-weight range, narrower than
/// `bodyMetricsWeightKg` on purpose: the same parse also reads gym-load
/// weights (a barbell one-rep max) that routinely exceed 250 kg, so this stays
/// the separate check a body-weight field opts into.
///
/// Twin of `BODY_WEIGHT_MIN_KG` / `BODY_WEIGHT_MAX_KG` in
/// `apps/web/src/lib/format/weight.ts`, registered in
/// `scripts/check_shared_constants.mjs`.
const NumericLimit kBodyWeightRangeKg = NumericLimit(20, 250);
