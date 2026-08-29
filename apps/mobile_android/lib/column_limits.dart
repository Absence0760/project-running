/// The bound a client puts on an input, for a column the database also bounds.
///
/// `text_limits.dart` is the same idea one field at a time: a composer capped
/// ABOVE its column's CHECK hands the user a postgres 23514 they cannot act on.
/// This module widens that to the whole class — a numeric range as well as a
/// character cap — and to the caps a client applies that are deliberately
/// NARROWER than the column allows, which is the other half of the same
/// contract: it is legal, but only if it is written down once.
///
/// Every key is `<table>.<column>`, which is also the locator: the guard in
/// `scripts/check_shared_constants.mjs` resolves that column's CHECK (and its
/// `numeric(p,s)` precision) by replaying every migration and proves this bound
/// sits INSIDE it, so nothing here is a transcription of a number the database
/// owns. decisions § 792.
///
/// A value bound is inclusive at both ends and stated in the column's own
/// CANONICAL unit — kilograms for a weight, centimetres for a height. A field
/// that takes input in the reader's unit converts the bound for display; see
/// `WeightFormat.boundsIn` in `preferences.dart`, which is where the unit
/// conversion lives so this module stays dependency-free.
///
/// Dart twin of `apps/web/src/lib/core/column_limits.ts`.
library;

/// One column's client-side bound. A length limit leaves [min] null.
class ColumnLimit {
  final num? min;
  final num max;
  final bool isLength;
  const ColumnLimit.value(num this.min, this.max) : isLength = false;
  const ColumnLimit.length(this.max)
      : min = null,
        isLength = true;
}

const Map<String, ColumnLimit> kColumnLimits = {
  // 20 kg is a plausible-human floor rather than the column's `> 0`: a body
  // weight is the input to a BMR, and a typo two orders of magnitude out
  // produces a calorie target instead of an error. 250 is the same judgement
  // at the other end, well inside the column's 500.
  'body_metrics.weight_kg': ColumnLimit.value(20, 250),
  // The column allows anything above 0; 50 cm is below every human who can
  // hold a phone, and catches a height typed in feet.
  'user_profiles.height_cm': ColumnLimit.value(50, 300),
  // The race-director weigh-in, where the column's own 20..400 is already the
  // right range — a runner is weighed against their own start baseline, so
  // nothing narrower is defensible.
  'checkpoint_crossings.body_weight_kg': ColumnLimit.value(20, 400),
  // The column's floor is 1; it has no ceiling, but `numeric(5,1)` does, and
  // a recipe divided into 9,999 servings is a mistyped 9.
  'recipes.servings': ColumnLimit.value(1, 99),
  // Deliberately far below the column's 4096: a club post is a notice board,
  // not an essay. Four surfaces write this column and all four said 1200.
  'club_posts.body': ColumnLimit.length(1200),
  // Below the column's 2000, for the same reason.
  'events.description': ColumnLimit.length(1000),
  // Below the column's 120 — a plan name is a header, and 80 is what both
  // plan editors and the create wizard already offered.
  'training_plans.name': ColumnLimit.length(80),
  // EQUAL to the column's 32. A parkrun athlete id is `A` + digits and never
  // approaches either number, so there is no product reason to be stricter —
  // and being stricter is what silently truncated an id on the phone while
  // the same id typed fine on the web (decisions § 792).
  'user_profiles.parkrun_number': ColumnLimit.length(32),
};

ColumnLimit _limit(String key) {
  final limit = kColumnLimits[key];
  if (limit == null) throw ArgumentError('unknown column limit: $key');
  return limit;
}

/// The inclusive lower bound for a value column, in the column's canonical unit.
num columnMin(String key) {
  final limit = _limit(key);
  final min = limit.min;
  if (min == null) throw ArgumentError('$key is a length limit, not a value limit');
  return min;
}

/// The inclusive upper bound for a value column, in the column's canonical unit.
num columnMax(String key) {
  final limit = _limit(key);
  if (limit.isLength) throw ArgumentError('$key is a length limit, not a value limit');
  return limit.max;
}

/// The character cap for a text column.
int columnLength(String key) {
  final limit = _limit(key);
  if (!limit.isLength) throw ArgumentError('$key is a value limit, not a length limit');
  return limit.max.toInt();
}

/// True when [value] is inside the column's client range. A non-finite value is
/// outside it — a caller that admitted `NaN` would send `null` or a 22P02, not
/// a measurement.
bool withinColumnLimit(String key, double value) {
  return value.isFinite && value >= columnMin(key) && value <= columnMax(key);
}
