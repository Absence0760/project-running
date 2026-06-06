import 'dart:math' as math;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show FoodEntry;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_food_store.dart';
import '../nutrition_targets.dart';
import '../nutrition_totals.dart';
import '../settings_sync.dart';
import '../widgets/nutrition_log_sheet.dart';

/// Daily calorie + macro targets for the signed-in user, or null when a
/// required body metric is missing. Shared by [NutritionScreen] and the
/// Home nutrition card so the BMR inputs are resolved one way: height +
/// sex from `user_profiles`, latest weight from `body_metrics`, age from
/// the date-of-birth pref, and the activity-level + goal nutrition prefs.
/// Replaces the former hard-coded `moderate` / `maintain` defaults.
Future<NutritionTargets?> loadNutritionTargets(
  ApiClient api,
  SettingsService? settings,
) async {
  try {
    final profile = await api.fetchMyProfile();
    final weightKg = await api.fetchLatestBodyWeightKg();
    final dobIso = settings?.effective<String>(SettingsKeys.dateOfBirth) ??
        profile?.dateOfBirth?.toIso8601String();
    return computeNutritionTargets(BodyMetricsInput(
      weightKg: weightKg,
      heightCm: profile?.heightCm,
      ageYears: ageFromDob(dobIso, DateTime.now().millisecondsSinceEpoch),
      sex: profile?.gender,
      activityLevel:
          settings?.effective<String>(SettingsKeys.nutritionActivityLevel) ??
              'moderate',
      goal: settings?.effective<String>(SettingsKeys.nutritionGoal) ??
          'maintain',
    ));
  } catch (_) {
    return null;
  }
}

/// Phase 4 multi-modal Nutrition (decisions §63, multi_modal.md § Nutrition).
/// Mirrors web `/nutrition`: Mifflin-St Jeor macro rings vs targets (hidden
/// when body metrics are absent — anti-clutter), a meal-slot daily view, a
/// tap-to-increment water tracker, and a 7-day calorie trend. Reads + writes
/// route through [LocalFoodStore] so logging a meal works offline; a
/// best-effort server fetch overlays the last 7 days on mount.
class NutritionScreen extends StatefulWidget {
  final ApiClient? api;
  final LocalFoodStore store;

  /// Supplies the activity-level / goal / date-of-birth that feed the BMR
  /// target. Null in tests / signed-out — the rings then hide (anti-clutter).
  final SettingsSyncService? settingsSync;

  const NutritionScreen({
    super.key,
    required this.api,
    required this.store,
    this.settingsSync,
  });

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

const _waterUnitMl = 250;

class _NutritionScreenState extends State<NutritionScreen> {
  bool _refreshing = false;
  bool _isOnline = true;
  NutritionTargets? _targets;
  int _waterMl = 0;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
    _loadWater();
    _refresh();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChange);
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  String _waterKey() {
    final d = DateTime.now();
    return 'water_ml_${d.year}-${d.month}-${d.day}';
  }

  Future<void> _loadWater() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _waterMl = prefs.getInt(_waterKey()) ?? 0);
  }

  Future<void> _setWater(int ml) async {
    setState(() => _waterMl = ml);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_waterKey(), ml);
  }

  DateTime get _todayStart {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _tomorrow {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + 1);
  }

  Future<void> _refresh() async {
    final api = widget.api;
    if (api == null || api.userId == null) {
      if (mounted) setState(() => _isOnline = false);
      return;
    }
    setState(() => _refreshing = true);
    try {
      // Pull the last 7 days so both today's list and the trend derive from
      // the one cache.
      final weekStart = _todayStart.subtract(const Duration(days: 6));
      final fresh = await api.fetchFoodLog(from: weekStart, to: _tomorrow);
      await widget.store.replaceFromServer([for (final r in fresh) r.toJson()]);
      if (widget.store.hasPending) await widget.store.syncWithServer(api);
      _targets = await loadNutritionTargets(api, widget.settingsSync?.service);
      _isOnline = true;
    } catch (e) {
      _isOnline = false;
      debugPrint('nutrition_screen: refresh failed, using cache: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _maybeSync() async {
    final api = widget.api;
    if (api == null || !_isOnline) return;
    await widget.store.syncWithServer(api);
  }

  Future<void> _logFood() async {
    final saved = await showNutritionLogSheet(context: context, store: widget.store);
    if (saved == true) await _maybeSync();
  }

  Future<void> _delete(String id) async {
    await widget.store.deleteLocal(id);
    await _maybeSync();
  }

  List<FoodEntry> get _todayEntries => [
        for (final r in widget.store.entriesForRange(_todayStart, _tomorrow))
          FoodEntry.fromRow(r),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final today = _todayEntries;
    final groups = groupByMealSlot(today);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.nutritionTitle),
        actions: [
          IconButton(
            tooltip: l10n.nutritionLogFood,
            icon: const Icon(Icons.add),
            onPressed: _refreshing ? null : _logFood,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isOnline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHigh,
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.store.hasPending
                          ? l10n.nutritionOfflineQueued
                          : l10n.nutritionOfflineCached,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ringsCard(theme, l10n, sumMacros(today)),
                  const SizedBox(height: 12),
                  _waterCard(theme, l10n),
                  const SizedBox(height: 12),
                  if (groups.isEmpty)
                    _emptyState(theme, l10n)
                  else
                    ...groups.map((g) => _mealGroup(theme, l10n, g)),
                  if (today.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _trendCard(theme, l10n),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ringsCard(ThemeData theme, AppLocalizations l10n, MacroTotals c) {
    final rings = <_Ring>[
      _Ring(l10n.nutritionCalories, c.calories, _targets?.calories, 'kcal'),
      _Ring(l10n.nutritionProtein, c.proteinG, _targets?.proteinG, 'g'),
      _Ring(l10n.nutritionCarbs, c.carbsG, _targets?.carbsG, 'g'),
      _Ring(l10n.nutritionFat, c.fatG, _targets?.fatG, 'g'),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [for (final r in rings) _ringWidget(theme, r)],
            ),
            if (_targets == null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.nutritionNoTargets,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ringWidget(ThemeData theme, _Ring r) {
    final frac = ringFraction(r.consumed, r.target);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  value: frac ?? 0,
                  strokeWidth: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text('${r.consumed}', style: theme.textTheme.labelMedium),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          r.target != null ? '${r.label} / ${r.target} ${r.unit}' : r.label,
          style:
              theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }

  Widget _waterCard(ThemeData theme, AppLocalizations l10n) {
    final units = (_waterMl / _waterUnitMl).round();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(l10n.nutritionWater,
                  style: theme.textTheme.titleSmall),
            ),
            IconButton(
              icon: const Icon(Icons.remove),
              tooltip: l10n.nutritionWaterRemove,
              onPressed: _waterMl <= 0
                  ? null
                  : () => _setWater(math.max(0, _waterMl - _waterUnitMl)),
            ),
            Text('$units × 250 ml', style: theme.textTheme.bodyMedium),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: l10n.nutritionWaterAdd,
              onPressed: () => _setWater(_waterMl + _waterUnitMl),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mealGroup(ThemeData theme, AppLocalizations l10n, MealSlotGroup g) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(_slotLabel(l10n, g.slot),
                        style: theme.textTheme.titleSmall)),
                Text('${g.calories} kcal',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
            for (final e in g.entries)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.itemName, style: theme.textTheme.bodyMedium),
                          Text(
                            _macroLine(e),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                    Text('${(e.calories ?? 0).round()}',
                        style: theme.textTheme.bodyMedium),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: l10n.nutritionDelete,
                      onPressed: () => _delete(e.id),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _macroLine(FoodEntry e) {
    final parts = <String>[];
    if ((e.proteinG ?? 0) > 0) parts.add('${e.proteinG!.round()}g P');
    if ((e.carbsG ?? 0) > 0) parts.add('${e.carbsG!.round()}g C');
    if ((e.fatG ?? 0) > 0) parts.add('${e.fatG!.round()}g F');
    return parts.join(' · ');
  }

  Widget _trendCard(ThemeData theme, AppLocalizations l10n) {
    final tag = localeToTag(Localizations.localeOf(context));
    final now = DateTime.now();
    final byDay = <String, double>{};
    for (final r in widget.store.rows) {
      final v = r['started_at'];
      final at = v is String ? DateTime.tryParse(v) : null;
      if (at == null) continue;
      final local = at.toLocal();
      final key = '${local.year}-${local.month}-${local.day}';
      byDay[key] = (byDay[key] ?? 0) + ((r['calories'] as num?)?.toDouble() ?? 0);
    }
    final days = <({String label, double calories})>[];
    for (var i = 6; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day - i);
      final key = '${d.year}-${d.month}-${d.day}';
      days.add((label: formatDowNarrow(d, tag), calories: byDay[key] ?? 0));
    }
    final maxCal = math.max(1.0, days.map((d) => d.calories).fold(0.0, math.max));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.nutritionWeeklyTrend, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in days)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: math.max(2, (d.calories / maxCal) * 72),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(d.label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ThemeData theme, AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          children: [
            Icon(Icons.restaurant, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(l10n.nutritionEmptyTitle,
                style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(l10n.nutritionEmptyBody,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: Text(l10n.nutritionLogFood),
              onPressed: _logFood,
            ),
          ],
        ),
      );

  String _slotLabel(AppLocalizations l10n, String slot) => switch (slot) {
        'breakfast' => l10n.nutritionSlotBreakfast,
        'lunch' => l10n.nutritionSlotLunch,
        'dinner' => l10n.nutritionSlotDinner,
        _ => l10n.nutritionSlotSnack,
      };
}

class _Ring {
  final String label;
  final int consumed;
  final int? target;
  final String unit;
  const _Ring(this.label, this.consumed, this.target, this.unit);
}
