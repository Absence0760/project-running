import 'package:core_models/core_models.dart' show FoodEntry;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_food_store.dart';
import '../nutrition_totals.dart';

/// Per-meal detail (mirror of web `/nutrition/[date]/[slot]`): one meal slot's
/// items + macro breakdown + a trailing 7-day calorie trend for that slot.
/// Reads the offline-first [LocalFoodStore]; rebuilds on any store change.
class NutritionMealDetailScreen extends StatefulWidget {
  final LocalFoodStore store;
  final DateTime day;
  final String slot;

  const NutritionMealDetailScreen({
    super.key,
    required this.store,
    required this.day,
    required this.slot,
  });

  @override
  State<NutritionMealDetailScreen> createState() =>
      _NutritionMealDetailScreenState();
}

class _NutritionMealDetailScreenState extends State<NutritionMealDetailScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    _ensureLoaded();
  }

  // Reached from the (already-hydrated) nutrition screen in normal use, but a
  // cold deep-link can land here before the food store has loaded — hydrate it
  // so an empty slot reads as "still loading", not "nothing logged".
  Future<void> _ensureLoaded() async {
    if (widget.store.dir != null) return;
    setState(() => _loading = true);
    await widget.store.init();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  DateTime get _dayStart =>
      DateTime(widget.day.year, widget.day.month, widget.day.day);

  List<FoodEntry> get _slotEntries {
    final start = _dayStart;
    final end = start.add(const Duration(days: 1));
    return [
      for (final r in widget.store.entriesForRange(start, end))
        FoodEntry.fromRow(r),
    ].where((e) => (e.mealSlot ?? 'snack') == widget.slot).toList();
  }

  /// The same slot's calories over the trailing 7 days (this day inclusive),
  /// zero-filled so the bar chart x-axis is stable. Mirrors web's
  /// `slotCalorieTrend`.
  List<({DateTime day, double calories})> get _trend {
    final start = _dayStart;
    final windowStart = start.subtract(const Duration(days: 6));
    final entries = widget.store.entriesForRange(
      windowStart,
      start.add(const Duration(days: 1)),
    );
    final byDay = <String, double>{};
    final keys = <String, DateTime>{};
    for (var i = 6; i >= 0; i--) {
      final d = DateTime(start.year, start.month, start.day - i);
      final key = '${d.year}-${d.month}-${d.day}';
      byDay[key] = 0;
      keys[key] = d;
    }
    for (final r in entries) {
      final slot = (r['meal_slot'] as String?) ?? 'snack';
      if (slot != widget.slot) continue;
      final v = r['started_at'];
      final at = v is String ? DateTime.tryParse(v) : null;
      if (at == null) continue;
      final local = at.toLocal();
      final key = '${local.year}-${local.month}-${local.day}';
      if (byDay.containsKey(key)) {
        byDay[key] =
            byDay[key]! + ((r['calories'] as num?)?.toDouble() ?? 0);
      }
    }
    return [
      for (final entry in byDay.entries)
        (day: keys[entry.key]!, calories: entry.value),
    ];
  }

  String _slotLabel(AppLocalizations l10n) => switch (widget.slot) {
        'breakfast' => l10n.nutritionSlotBreakfast,
        'lunch' => l10n.nutritionSlotLunch,
        'dinner' => l10n.nutritionSlotDinner,
        _ => l10n.nutritionSlotSnack,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final entries = _slotEntries;
    final macros = sumMacros(entries);
    final trend = _trend;
    final maxCal = trend.fold<double>(
        1, (m, t) => t.calories > m ? t.calories : m);

    return Scaffold(
      appBar: AppBar(
        title: Text(_slotLabel(l10n)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(formatDateMed(_dayStart, tag),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: ActivityLoader(kind: ActivityLoaderKind.fuel, size: 76),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _macroCard(theme, l10n, macros),
                const SizedBox(height: 12),
                _itemsCard(theme, l10n, entries),
                const SizedBox(height: 12),
                _trendCard(theme, l10n, trend, maxCal, tag),
              ],
            ),
    );
  }

  Widget _macroCard(
      ThemeData theme, AppLocalizations l10n, MacroTotals macros) {
    Widget stat(String value, String label) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${macros.calories}',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 3),
              Text('kcal',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
          const Spacer(),
          stat('${macros.proteinG}g', l10n.nutritionMealProtein),
          const SizedBox(width: 16),
          stat('${macros.carbsG}g', l10n.nutritionMealCarbs),
          const SizedBox(width: 16),
          stat('${macros.fatG}g', l10n.nutritionMealFat),
        ],
      ),
    );
  }

  Widget _itemsCard(
      ThemeData theme, AppLocalizations l10n, List<FoodEntry> entries) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.nutritionMealItemsHeading,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Text(l10n.nutritionMealNoItems,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline))
          else
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(e.itemName,
                            style: theme.textTheme.bodyMedium)),
                    Text('${(e.calories ?? 0).round()} kcal',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _trendCard(
    ThemeData theme,
    AppLocalizations l10n,
    List<({DateTime day, double calories})> trend,
    double maxCal,
    String tag,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.nutritionMealTrendHeading,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final t in trend)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${t.calories.round()}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            )),
                        const SizedBox(height: 2),
                        Container(
                          height: (t.calories / maxCal * 70).clamp(2, 70),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: _isSameDay(t.day, _dayStart)
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primary.withOpacity(0.45),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(formatDowNarrow(t.day, tag),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            )),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
