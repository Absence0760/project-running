// Meal-template plan <-> log shaping (multi_modal.md Nutrition mid tier).
//
// Dart twin of apps/web/src/lib/nutrition/meal_template.ts (parity pair — keep
// algorithm, edge cases, outputs, and test counts in lockstep).
//
//   templateFromEntries — promote a set of logged food entries into a template
//     draft (name + ordered items carrying each entry's macros). The
//     "Save as meal" path. Mirrors gym_routine.routineFromWorkout.
//   entriesFromTemplate — expand a saved template into food-log inputs ready to
//     insert, with one tap. The "Log template" path. Mirrors
//     gym_routine.prefillFromRoutine.
//
// A template is a reusable plan, NOT a dated activity, so it never feeds the
// activities view. An item's slot falls back to the template's default slot,
// which falls back to the slot passed at log time.

const List<String> _slots = ['breakfast', 'lunch', 'dinner', 'snack'];

bool _isSlot(Object? v) => v is String && _slots.contains(v);

String? _slotOrNull(Object? v) => _isSlot(v) ? v as String : null;

double? _numericOrNull(Object? v) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }
  if (v is String) {
    final n = double.tryParse(v);
    return (n != null && n.isFinite) ? n : null;
  }
  return null;
}

/// A logged food entry, as it arrives from `food_log` (free-text name, nullable
/// macros + slot). The minimal shape the promotion reads.
class TemplateSourceEntry {
  const TemplateSourceEntry({
    required this.itemName,
    this.mealSlot,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.externalId,
  });

  final String itemName;
  final String? mealSlot;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String? externalId;
}

/// One item within a template draft. Mirrors a `meal_template_items` row
/// (sans ids). Macros are copied straight from the source entry.
class MealTemplateDraftItem {
  const MealTemplateDraftItem({
    required this.position,
    required this.itemName,
    required this.mealSlot,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.externalId,
  });

  final int position;
  final String itemName;
  final String? mealSlot;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String? externalId;
}

/// The in-memory template shape "Save as meal" hands to the create call.
/// `itemCount` is the client-stamped denormalised count (meal_templates
/// non-authoritative cache — derived_state.md). `mealSlot` is the template's
/// default slot, derived from the source entries when they all agree.
class MealTemplateDraft {
  const MealTemplateDraft({
    required this.name,
    required this.mealSlot,
    required this.itemCount,
    required this.items,
  });

  final String name;
  final String? mealSlot;
  final int itemCount;
  final List<MealTemplateDraftItem> items;
}

/// A persisted template item, as read back from `meal_template_items`.
class PlannedTemplateItem {
  const PlannedTemplateItem({
    required this.position,
    required this.itemName,
    this.mealSlot,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.externalId,
  });

  final int position;
  final String itemName;
  final String? mealSlot;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String? externalId;
}

/// A persisted template flattened for instantiation: its items (ordered by
/// `position`) plus the template default slot.
class PlannedTemplate {
  const PlannedTemplate({
    required this.name,
    required this.mealSlot,
    required this.items,
  });

  final String name;
  final String? mealSlot;
  final List<PlannedTemplateItem> items;
}

/// One food-log entry ready to insert (the shape the food-log create takes).
/// `startedAt` is left to the caller — every instantiated item logs at "now"
/// (or a caller-chosen day), never at the template's creation time.
class TemplateLogInput {
  const TemplateLogInput({
    required this.itemName,
    required this.mealSlot,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.externalId,
  });

  final String itemName;
  final String? mealSlot;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String? externalId;
}

/// The default slot for a template promoted from `entries`: the common slot
/// when every entry that has a slot agrees, else null (a mixed-slot day has no
/// single default). An entry with no slot doesn't veto agreement.
String? _commonSlot(List<TemplateSourceEntry> entries) {
  String? found;
  for (final e in entries) {
    final s = _slotOrNull(e.mealSlot);
    if (s == null) continue;
    if (found == null) {
      found = s;
    } else if (found != s) {
      return null;
    }
  }
  return found;
}

/// Promote logged food entries into a template draft. Blank-named entries are
/// dropped. Each surviving entry becomes one ordered item carrying its macros.
/// The template's default slot is the entries' common slot (above). The name
/// defaults to `fallbackName` when blank.
MealTemplateDraft templateFromEntries(
  String? name,
  List<TemplateSourceEntry> entries, {
  String fallbackName = 'Meal',
}) {
  final items = <MealTemplateDraftItem>[];
  for (final e in entries) {
    final itemName = e.itemName.trim();
    if (itemName.isEmpty) continue;
    final ext = e.externalId;
    items.add(MealTemplateDraftItem(
      position: items.length,
      itemName: itemName,
      mealSlot: _slotOrNull(e.mealSlot),
      calories: _numericOrNull(e.calories),
      proteinG: _numericOrNull(e.proteinG),
      carbsG: _numericOrNull(e.carbsG),
      fatG: _numericOrNull(e.fatG),
      externalId: (ext != null && ext.isNotEmpty) ? ext : null,
    ));
  }
  final trimmed = (name ?? '').trim();
  final finalName = trimmed.isNotEmpty ? trimmed : fallbackName;
  return MealTemplateDraft(
    name: finalName,
    mealSlot: _commonSlot(entries),
    itemCount: items.length,
    items: items,
  );
}

/// Expand a saved template into food-log inputs ready to insert. Items are
/// ordered by `position` (defensively sorted — the caller may pass them in any
/// order). Each item's slot resolves to: the item's own slot, else the
/// template's default slot, else the caller's `slotOverride` (e.g. the slot the
/// user picked in the log sheet), else null. An empty template yields no
/// inputs (the caller treats that as a no-op, not an error).
List<TemplateLogInput> entriesFromTemplate(
  PlannedTemplate template, {
  String? slotOverride,
}) {
  final ordered = [...template.items]
    ..sort((a, b) => a.position.compareTo(b.position));
  return [
    for (final it in ordered)
      TemplateLogInput(
        itemName: it.itemName,
        mealSlot: it.mealSlot ?? template.mealSlot ?? slotOverride,
        calories: it.calories,
        proteinG: it.proteinG,
        carbsG: it.carbsG,
        fatG: it.fatG,
        externalId: it.externalId,
      ),
  ];
}
