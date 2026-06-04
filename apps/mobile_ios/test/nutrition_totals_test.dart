import 'package:core_models/core_models.dart' show FoodEntry;
import 'package:flutter_test/flutter_test.dart';

import '../lib/nutrition_totals.dart';

FoodEntry _entry({
  String? mealSlot,
  double? calories,
  double? proteinG,
  double? carbsG,
  double? fatG,
}) =>
    FoodEntry.fromRow(<String, dynamic>{
      'id': 'x',
      'item_name': 'item',
      'meal_slot': mealSlot,
      'calories': calories,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'fat_g': fatG,
    });

void main() {
  final rows = [
    _entry(mealSlot: 'breakfast', calories: 412, proteinG: 12, carbsG: 58, fatG: 8),
    _entry(mealSlot: 'lunch', calories: 640, proteinG: 48, carbsG: 52, fatG: 20),
    _entry(mealSlot: null, calories: 150, carbsG: 30), // -> snack
  ];

  test('sumMacros sums fields, treating null as zero', () {
    final t = sumMacros(rows);
    expect(t.calories, 1202);
    expect(t.proteinG, 60);
    expect(t.carbsG, 140);
    expect(t.fatG, 28);
  });

  test('sumMacros of an empty day is all zeros', () {
    final t = sumMacros(const []);
    expect(t.calories, 0);
    expect(t.proteinG, 0);
    expect(t.carbsG, 0);
    expect(t.fatG, 0);
  });

  test('groupByMealSlot orders slots and omits empty ones', () {
    final groups = groupByMealSlot(rows);
    expect(groups.map((g) => g.slot).toList(), ['breakfast', 'lunch', 'snack']);
    expect(groups.where((g) => g.slot == 'dinner'), isEmpty);
    expect(groups.firstWhere((g) => g.slot == 'snack').entries.length, 1);
    expect(groups.firstWhere((g) => g.slot == 'breakfast').calories, 412);
  });

  test('ringFraction clamps to [0,1] and hides on a missing/zero target', () {
    expect(ringFraction(500, 2000), 0.25);
    expect(ringFraction(3000, 2000), 1); // clamped
    expect(ringFraction(500, null), null);
    expect(ringFraction(500, 0), null);
  });
}
