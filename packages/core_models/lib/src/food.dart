import 'generated/db_rows.dart';

/// Typed domain view of a food-log entry — the `food_log` row scalars. Built
/// from the raw row map the offline `LocalFoodStore` holds so the nutrition
/// surfaces read typed fields instead of reaching into a
/// `Map<String, dynamic>` by string key.
class FoodEntry {
  const FoodEntry({
    required this.id,
    this.startedAt,
    required this.itemName,
    this.mealSlot,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    this.sugarG,
    this.sodiumMg,
    this.saturatedFatG,
    this.cholesterolMg,
    this.isPublic = false,
    this.externalId,
    this.lastModifiedAt,
    this.createdAt,
  });

  final String id;
  final DateTime? startedAt;
  final String itemName;
  final String? mealSlot;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  /// Extended nutrients (issue #492), all nullable. Grams for fibre / sugar /
  /// saturated fat; milligrams for sodium / cholesterol.
  final double? fiberG;
  final double? sugarG;
  final double? sodiumMg;
  final double? saturatedFatG;
  final double? cholesterolMg;
  final bool isPublic;
  final String? externalId;
  final DateTime? lastModifiedAt;
  final DateTime? createdAt;

  factory FoodEntry.fromRow(Map<String, dynamic> row) => FoodEntry(
        id: row[FoodLogRow.colId] as String,
        startedAt: _parseTs(row[FoodLogRow.colStartedAt]),
        itemName: (row[FoodLogRow.colItemName] as String?) ?? '',
        mealSlot: row[FoodLogRow.colMealSlot] as String?,
        calories: (row[FoodLogRow.colCalories] as num?)?.toDouble(),
        proteinG: (row[FoodLogRow.colProteinG] as num?)?.toDouble(),
        carbsG: (row[FoodLogRow.colCarbsG] as num?)?.toDouble(),
        fatG: (row[FoodLogRow.colFatG] as num?)?.toDouble(),
        fiberG: (row[FoodLogRow.colFiberG] as num?)?.toDouble(),
        sugarG: (row[FoodLogRow.colSugarG] as num?)?.toDouble(),
        sodiumMg: (row[FoodLogRow.colSodiumMg] as num?)?.toDouble(),
        saturatedFatG: (row[FoodLogRow.colSaturatedFatG] as num?)?.toDouble(),
        cholesterolMg: (row[FoodLogRow.colCholesterolMg] as num?)?.toDouble(),
        isPublic: (row[FoodLogRow.colIsPublic] as bool?) ?? false,
        externalId: row[FoodLogRow.colExternalId] as String?,
        lastModifiedAt: _parseTs(row[FoodLogRow.colLastModifiedAt]),
        createdAt: _parseTs(row[FoodLogRow.colCreatedAt]),
      );
}

DateTime? _parseTs(dynamic v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
