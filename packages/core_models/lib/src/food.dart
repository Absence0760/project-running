import 'generated/db_rows.dart';

/// Typed domain view of a food-log entry — the `food_log` row scalars. Built
/// from the raw row map the offline `LocalFoodStore` holds so the nutrition
/// surfaces read typed fields instead of reaching into a
/// `Map<String, dynamic>` by string key.
class FoodEntry {
  const FoodEntry({
    required this.id,
    this.loggedAt,
    required this.itemName,
    this.mealSlot,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.isPublic = false,
    this.externalId,
    this.lastModifiedAt,
    this.createdAt,
  });

  final String id;
  final DateTime? loggedAt;
  final String itemName;
  final String? mealSlot;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final bool isPublic;
  final String? externalId;
  final DateTime? lastModifiedAt;
  final DateTime? createdAt;

  factory FoodEntry.fromRow(Map<String, dynamic> row) => FoodEntry(
        id: row[FoodLogRow.colId] as String,
        loggedAt: _parseTs(row[FoodLogRow.colLoggedAt]),
        itemName: (row[FoodLogRow.colItemName] as String?) ?? '',
        mealSlot: row[FoodLogRow.colMealSlot] as String?,
        calories: (row[FoodLogRow.colCalories] as num?)?.toDouble(),
        proteinG: (row[FoodLogRow.colProteinG] as num?)?.toDouble(),
        carbsG: (row[FoodLogRow.colCarbsG] as num?)?.toDouble(),
        fatG: (row[FoodLogRow.colFatG] as num?)?.toDouble(),
        isPublic: (row[FoodLogRow.colIsPublic] as bool?) ?? false,
        externalId: row[FoodLogRow.colExternalId] as String?,
        lastModifiedAt: _parseTs(row[FoodLogRow.colLastModifiedAt]),
        createdAt: _parseTs(row[FoodLogRow.colCreatedAt]),
      );
}

DateTime? _parseTs(dynamic v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
