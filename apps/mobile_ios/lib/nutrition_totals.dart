import 'package:core_models/core_models.dart' show FoodEntry;

/// Pure aggregation for the nutrition daily view — sum a day's logged food
/// into macro totals and group it by meal slot.
///
/// Dart twin of `apps/web/src/lib/nutrition/nutrition_totals.ts` — keep the
/// ordering, null-as-zero, and empty-slot-omission behaviour in lockstep.

const mealSlots = <String>['breakfast', 'lunch', 'dinner', 'snack'];

class MacroTotals {
  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;
  const MacroTotals({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });
}

/// Sum calories + macros across entries. Null fields count as 0 so a
/// partially-logged item (calories only) still contributes.
MacroTotals sumMacros(Iterable<FoodEntry> entries) {
  var c = 0.0, p = 0.0, cb = 0.0, f = 0.0;
  for (final e in entries) {
    c += e.calories ?? 0;
    p += e.proteinG ?? 0;
    cb += e.carbsG ?? 0;
    f += e.fatG ?? 0;
  }
  return MacroTotals(
    calories: c.round(),
    proteinG: p.round(),
    carbsG: cb.round(),
    fatG: f.round(),
  );
}

class MealSlotGroup {
  final String slot;
  final List<FoodEntry> entries;
  final int calories;
  const MealSlotGroup({
    required this.slot,
    required this.entries,
    required this.calories,
  });
}

/// Group entries into the four meal slots in display order, omitting empty
/// slots (anti-clutter — no "Dinner 0 kcal" row). Entries with a null slot
/// fall under 'snack'.
List<MealSlotGroup> groupByMealSlot(List<FoodEntry> entries) {
  final groups = <MealSlotGroup>[];
  for (final slot in mealSlots) {
    final inSlot =
        entries.where((e) => (e.mealSlot ?? 'snack') == slot).toList();
    if (inSlot.isEmpty) continue;
    groups.add(MealSlotGroup(
      slot: slot,
      entries: inSlot,
      calories: sumMacros(inSlot).calories,
    ));
  }
  return groups;
}

/// Fraction of a target consumed, clamped to [0, 1] for ring rendering.
/// Returns null when there's no positive target (hide the comparison).
double? ringFraction(num consumed, num? target) {
  if (target == null || target <= 0) return null;
  final f = consumed / target;
  return f < 0 ? 0 : (f > 1 ? 1 : f.toDouble());
}
