import 'dart:math' as math;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show FoodEntry;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../exercise_calories.dart';
import '../food_search.dart' show FoodMacros;
import '../hydration.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../local_food_store.dart';
import '../local_meal_template_store.dart';
import '../local_recipe_store.dart';
import '../meal_template.dart';
import '../nutrition_budget.dart';
import '../nutrition_targets.dart';
import '../recipe.dart';
import '../nutrition_totals.dart';
import '../nutrition_week.dart';
import '../settings_sync.dart';
import '../widgets/nutrition_log_sheet.dart';
import '../widgets/top_banner.dart';
import 'nutrition_meal_detail_screen.dart';

/// Daily calorie + macro targets for the signed-in user, or null when a
/// required body metric is missing. Shared by [NutritionScreen] and the
/// Home nutrition card so the BMR inputs are resolved one way: height +
/// sex from `user_profiles`, latest weight from `body_metrics`, age from
/// the date-of-birth pref, and the activity-level + goal nutrition prefs.
/// Replaces the former hard-coded `moderate` / `maintain` defaults.
Future<NutritionTargets?> loadNutritionTargets(
  ApiClient api,
  SettingsService? settings, {
  double exerciseKcal = 0,
}) async {
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
      exerciseKcal: exerciseKcal,
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
  double? _weightKg;

  /// Owned offline-first cache for saved meal templates (mirrors how
  /// `gym_detail_screen` owns a `LocalRoutineStore`). Hydrated best-effort
  /// from `api` on mount; create/delete/log all route through it.
  final LocalMealTemplateStore _templateStore = LocalMealTemplateStore();
  bool _loggingTemplateId = false;
  String? _loggingId;
  bool _savingMeal = false;

  /// Owned offline-first cache for saved recipes (sibling of `_templateStore`).
  /// Where a template logs each item, a recipe logs ONE summed entry.
  final LocalRecipeStore _recipeStore = LocalRecipeStore();
  bool _loggingRecipe = false;
  String? _loggingRecipeId;
  bool _savingRecipe = false;

  /// Today's run + gym active minutes — feeds the hydration goal's
  /// sweat-replacement add (runs/gym without a duration contribute nothing).
  int _exerciseMinutes = 0;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
    _templateStore.addListener(_onStoreChange);
    _recipeStore.addListener(_onStoreChange);
    _loadWater();
    _templateStore.loadAll();
    _recipeStore.loadAll();
    _refresh();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChange);
    _templateStore.removeListener(_onStoreChange);
    _recipeStore.removeListener(_onStoreChange);
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
      await widget.store.replaceFromServer(
        [for (final r in fresh) r.toJson()],
        windowStart: weekStart,
        windowEnd: _tomorrow,
      );
      if (widget.store.hasPending) await widget.store.syncWithServer(api);
      await _hydrateTemplates(api);
      await _hydrateRecipes(api);
      _weightKg = await api.fetchLatestBodyWeightKg();
      final exercise = await _todayExercise(api, _weightKg);
      _exerciseMinutes = exercise.minutes;
      _targets = await loadNutritionTargets(
        api,
        widget.settingsSync?.service,
        exerciseKcal: exercise.kcal.toDouble(),
      );
      _isOnline = true;
    } catch (e) {
      _isOnline = false;
      debugPrint('nutrition_screen: refresh failed, using cache: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Today's run + gym exercise reduced to (a) whole active minutes for the
  /// hydration goal's sweat-replacement add and (b) estimated burned kcal for
  /// the dynamic-TDEE "base + exercise" calorie goal (decisions §134). Both
  /// best-effort; a failure leaves them at 0 so the goal stays base-only.
  Future<({int minutes, int kcal})> _todayExercise(
    ApiClient api,
    double? weightKg,
  ) async {
    try {
      final activities = await api.fetchActivities(limit: 50);
      final start = _todayStart;
      final end = _tomorrow;
      var seconds = 0.0;
      final runs = <RunForCalories>[];
      final gym = <GymSessionForCalories>[];
      for (final a in activities) {
        if (a.kind != 'run' && a.kind != 'gym') continue;
        final at = a.startedAt.toLocal();
        if (at.isBefore(start) || !at.isBefore(end)) continue;
        final durationS = (a.summary['duration_s'] as num?)?.toDouble();
        seconds += durationS ?? 0;
        if (a.kind == 'run') {
          runs.add(RunForCalories((a.summary['distance_m'] as num?)?.toDouble()));
        } else {
          gym.add(GymSessionForCalories(durationS));
        }
      }
      final kcal = exerciseCaloriesForDay(
        runs: runs,
        gymSessions: gym,
        weightKg: weightKg,
      );
      return (minutes: (seconds / 60).round(), kcal: kcal);
    } catch (e) {
      debugPrint('nutrition_screen: exercise fetch failed: $e');
      return (minutes: 0, kcal: 0);
    }
  }

  Future<void> _maybeSync() async {
    final api = widget.api;
    if (api == null || !_isOnline) return;
    await widget.store.syncWithServer(api);
  }

  /// Best-effort: pull saved meal templates (with their items) and overlay the
  /// offline cache. A failure leaves the cache as-is (offline-first).
  Future<void> _hydrateTemplates(ApiClient api) async {
    try {
      final summaries = await api.fetchMealTemplates();
      final detailed = <({
        Map<String, dynamic> template,
        List<StoredMealTemplateItem> items
      })>[];
      for (final t in summaries) {
        final d = await api.fetchMealTemplateDetail(t.id);
        if (d == null) continue;
        detailed.add((
          template: d.template.toJson(),
          items: [
            for (final it in d.items)
              StoredMealTemplateItem(
                itemName: it.itemName,
                mealSlot: it.mealSlot,
                calories: it.calories,
                proteinG: it.proteinG,
                carbsG: it.carbsG,
                fatG: it.fatG,
                externalId: it.externalId,
              ),
          ],
        ));
      }
      await _templateStore.replaceFromServer(detailed);
      if (_templateStore.hasPending) await _templateStore.syncWithServer(api);
    } catch (e) {
      debugPrint('nutrition_screen: template hydrate failed: $e');
    }
  }

  Future<void> _logFood() async {
    final saved = await showNutritionLogSheet(context: context, store: widget.store);
    if (saved == true) await _maybeSync();
  }

  /// Promote today's logged entries into a named meal template via the pure
  /// `templateFromEntries` parity helper (default slot derived when the day's
  /// entries agree). The name is collected in an AlertDialog.
  Future<void> _saveAsMeal() async {
    if (_savingMeal) return;
    final l10n = AppLocalizations.of(context);
    final today = _todayEntries;
    if (today.isEmpty) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.nutritionSaveAsMealTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.nutritionTemplateName,
            hintText: l10n.nutritionTemplateNamePlaceholder,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.nutritionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.nutritionSaveTemplate),
          ),
        ],
      ),
    );
    if (name == null) return;
    if (_savingMeal) return;
    setState(() => _savingMeal = true);
    final draft = templateFromEntries(
      name,
      [
        for (final e in today)
          TemplateSourceEntry(
            itemName: e.itemName,
            mealSlot: e.mealSlot,
            calories: e.calories,
            proteinG: e.proteinG,
            carbsG: e.carbsG,
            fatG: e.fatG,
            externalId: e.externalId,
          ),
      ],
    );
    try {
      await _templateStore.createLocal(
        name: draft.name,
        mealSlot: draft.mealSlot,
        items: [
          for (final it in draft.items)
            StoredMealTemplateItem(
              itemName: it.itemName,
              mealSlot: it.mealSlot,
              calories: it.calories,
              proteinG: it.proteinG,
              carbsG: it.carbsG,
              fatG: it.fatG,
              externalId: it.externalId,
            ),
        ],
      );
      await _maybeSyncTemplates();
      if (mounted) {
        showTopBanner(context, l10n.nutritionTemplateSaved);
      }
    } catch (e) {
      if (mounted) {
        showTopBanner(context, l10n.nutritionTemplateSaveFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _savingMeal = false);
    }
  }

  Future<void> _maybeSyncTemplates() async {
    final api = widget.api;
    if (api == null || !_isOnline) return;
    await _templateStore.syncWithServer(api);
  }

  /// Log every item of [t] as a food_log entry at now, via the pure
  /// `entriesFromTemplate` parity helper (slot resolves item → template-default)
  /// + an offline-first batch write to the food store.
  Future<void> _logTemplate(StoredMealTemplate t) async {
    if (_loggingTemplateId) return;
    setState(() {
      _loggingTemplateId = true;
      _loggingId = t.id;
    });
    final l10n = AppLocalizations.of(context);
    try {
      final inputs = entriesFromTemplate(PlannedTemplate(
        name: t.name,
        mealSlot: t.mealSlot,
        items: [
          for (var i = 0; i < t.items.length; i++)
            PlannedTemplateItem(
              position: i,
              itemName: t.items[i].itemName,
              mealSlot: t.items[i].mealSlot,
              calories: t.items[i].calories,
              proteinG: t.items[i].proteinG,
              carbsG: t.items[i].carbsG,
              fatG: t.items[i].fatG,
              externalId: t.items[i].externalId,
            ),
        ],
      ));
      for (final it in inputs) {
        await widget.store.createLocal(
          startedAt: DateTime.now(),
          itemName: it.itemName,
          mealSlot: it.mealSlot,
          calories: it.calories,
          proteinG: it.proteinG,
          carbsG: it.carbsG,
          fatG: it.fatG,
        );
      }
      await _maybeSync();
      if (mounted) {
        showTopBanner(
          context,
          l10n.nutritionTemplateLogged(inputs.length, t.name),
        );
      }
    } catch (e) {
      if (mounted) {
        showTopBanner(context, l10n.nutritionTemplateLogFailed(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loggingTemplateId = false;
          _loggingId = null;
        });
      }
    }
  }

  Future<void> _deleteTemplate(StoredMealTemplate t) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.nutritionDeleteTemplateTitle),
            content: Text(l10n.nutritionDeleteTemplateMessage(t.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.nutritionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: Text(l10n.nutritionDeleteTemplate),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await _templateStore.deleteLocal(t.id);
      await _maybeSyncTemplates();
    } catch (e) {
      if (mounted) {
        showTopBanner(context, l10n.nutritionTemplateDeleteFailed('$e'));
      }
    }
  }

  /// Best-effort: pull saved recipes (with their ingredients) and overlay the
  /// offline cache. A failure leaves the cache as-is (offline-first).
  Future<void> _hydrateRecipes(ApiClient api) async {
    try {
      final summaries = await api.fetchRecipes();
      final detailed = <({
        Map<String, dynamic> recipe,
        List<StoredRecipeIngredient> ingredients
      })>[];
      for (final r in summaries) {
        final d = await api.fetchRecipeDetail(r.id);
        if (d == null) continue;
        detailed.add((
          recipe: d.recipe.toJson(),
          ingredients: [
            for (final it in d.ingredients)
              StoredRecipeIngredient(
                itemName: it.itemName,
                quantity: it.quantity,
                calories: it.calories,
                proteinG: it.proteinG,
                carbsG: it.carbsG,
                fatG: it.fatG,
                externalId: it.externalId,
              ),
          ],
        ));
      }
      await _recipeStore.replaceFromServer(detailed);
      if (_recipeStore.hasPending) await _recipeStore.syncWithServer(api);
    } catch (e) {
      debugPrint('nutrition_screen: recipe hydrate failed: $e');
    }
  }

  Future<void> _maybeSyncRecipes() async {
    final api = widget.api;
    if (api == null || !_isOnline) return;
    await _recipeStore.syncWithServer(api);
  }

  /// Promote today's logged entries into a named recipe. The name + servings
  /// are collected in an AlertDialog; the ingredients come from `recipeFromEntries`.
  Future<void> _saveAsRecipe() async {
    if (_savingRecipe) return;
    final l10n = AppLocalizations.of(context);
    final today = _todayEntries;
    if (today.isEmpty) return;
    final nameController = TextEditingController();
    final servingsController = TextEditingController(text: '1');
    final result = await showDialog<({String name, double servings})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.nutritionSaveAsRecipeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.nutritionRecipeName,
                hintText: l10n.nutritionRecipeNamePlaceholder,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: servingsController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l10n.nutritionRecipeServings),
            ),
            const SizedBox(height: 8),
            Text(l10n.nutritionRecipeServingsHint,
                style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.nutritionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              ctx,
              (
                name: nameController.text,
                servings: double.tryParse(servingsController.text) ?? 1,
              ),
            ),
            child: Text(l10n.nutritionSaveRecipe),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (_savingRecipe) return;
    setState(() => _savingRecipe = true);
    final draft = recipeFromEntries(
      result.name,
      [
        for (final e in today)
          RecipeSourceEntry(
            itemName: e.itemName,
            calories: e.calories,
            proteinG: e.proteinG,
            carbsG: e.carbsG,
            fatG: e.fatG,
            externalId: e.externalId,
          ),
      ],
    );
    try {
      await _recipeStore.createLocal(
        name: draft.name,
        servings: result.servings >= 1 ? result.servings : 1,
        mealSlot: _commonSlot(today),
        ingredients: [
          for (final it in draft.ingredients)
            StoredRecipeIngredient(
              itemName: it.itemName,
              quantity: it.quantity,
              calories: it.calories,
              proteinG: it.proteinG,
              carbsG: it.carbsG,
              fatG: it.fatG,
              externalId: it.externalId,
            ),
        ],
      );
      await _maybeSyncRecipes();
      if (mounted) {
        showTopBanner(context, l10n.nutritionRecipeSaved);
      }
    } catch (e) {
      if (mounted) {
        showTopBanner(context, l10n.nutritionRecipeSaveFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _savingRecipe = false);
    }
  }

  /// The common meal slot across today's entries when they all agree, else
  /// null — used as the recipe's default slot (mirrors web, which derives it
  /// the same way via templateFromEntries).
  static String? _commonSlot(List<FoodEntry> entries) {
    String? found;
    for (final e in entries) {
      final s = e.mealSlot;
      if (s == null) continue;
      if (found == null) {
        found = s;
      } else if (found != s) {
        return null;
      }
    }
    return found;
  }

  /// Log ONE serving of [r] as a single food_log entry carrying the summed
  /// per-serving macros, via the pure `logInputFromRecipe` parity helper +
  /// an offline-first write to the food store.
  Future<void> _logRecipe(StoredRecipe r) async {
    if (_loggingRecipe) return;
    setState(() {
      _loggingRecipe = true;
      _loggingRecipeId = r.id;
    });
    final l10n = AppLocalizations.of(context);
    try {
      final input = logInputFromRecipe(PlannedRecipe(
        name: r.name,
        servings: r.servings,
        mealSlot: r.mealSlot,
        ingredients: [
          for (var i = 0; i < r.ingredients.length; i++)
            PlannedRecipeIngredient(
              position: i,
              itemName: r.ingredients[i].itemName,
              quantity: r.ingredients[i].quantity,
              calories: r.ingredients[i].calories,
              proteinG: r.ingredients[i].proteinG,
              carbsG: r.ingredients[i].carbsG,
              fatG: r.ingredients[i].fatG,
              externalId: r.ingredients[i].externalId,
            ),
        ],
      ));
      if (input != null) {
        await widget.store.createLocal(
          startedAt: DateTime.now(),
          itemName: input.itemName,
          mealSlot: input.mealSlot,
          calories: input.calories,
          proteinG: input.proteinG,
          carbsG: input.carbsG,
          fatG: input.fatG,
        );
        await _maybeSync();
        if (mounted) {
          showTopBanner(context, l10n.nutritionRecipeLogged(1, r.name));
        }
      }
    } catch (e) {
      if (mounted) {
        showTopBanner(context, l10n.nutritionRecipeLogFailed(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loggingRecipe = false;
          _loggingRecipeId = null;
        });
      }
    }
  }

  Future<void> _deleteRecipe(StoredRecipe r) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.nutritionDeleteRecipeTitle),
            content: Text(l10n.nutritionDeleteRecipeMessage(r.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.nutritionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: Text(l10n.nutritionDeleteRecipe),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await _recipeStore.deleteLocal(r.id);
      await _maybeSyncRecipes();
    } catch (e) {
      if (mounted) {
        showTopBanner(context, l10n.nutritionRecipeDeleteFailed('$e'));
      }
    }
  }

  Future<void> _delete(FoodEntry e) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.nutritionDeleteEntryTitle),
            content: Text(l10n.nutritionDeleteEntryMessage(e.itemName)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.nutritionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: Text(l10n.nutritionDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await widget.store.deleteLocal(e.id);
      await _maybeSync();
    } catch (err) {
      if (mounted) {
        showTopBanner(context, l10n.nutritionDeleteFailed('$err'));
      }
    }
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
          if (today.isNotEmpty)
            IconButton(
              tooltip: l10n.nutritionSaveAsMeal,
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: (_refreshing || _savingMeal) ? null : _saveAsMeal,
            ),
          if (today.isNotEmpty)
            IconButton(
              tooltip: l10n.nutritionSaveAsRecipe,
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: (_refreshing || _savingRecipe) ? null : _saveAsRecipe,
            ),
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
                  if (_templateStore.templates.isNotEmpty) ...[
                    _templatesCard(theme, l10n),
                    const SizedBox(height: 12),
                  ],
                  if (_recipeStore.recipes.isNotEmpty) ...[
                    _recipesCard(theme, l10n),
                    const SizedBox(height: 12),
                  ],
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

  /// Saved meal templates — a self-hiding section above the day's meals,
  /// mirroring web `/nutrition`. Each row logs the whole meal with one tap or
  /// deletes behind an AlertDialog.
  Widget _templatesCard(ThemeData theme, AppLocalizations l10n) {
    final templates = _templateStore.templates;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                l10n.nutritionTemplates,
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final t in templates)
              ListTile(
                title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(l10n.nutritionTemplateItems(t.itemCount)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loggingTemplateId && _loggingId == t.id)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      TextButton(
                        onPressed: _loggingTemplateId ? null : () => _logTemplate(t),
                        child: Text(l10n.nutritionLogTemplate),
                      ),
                    IconButton(
                      tooltip: l10n.nutritionDeleteTemplate,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteTemplate(t),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Saved recipes — a self-hiding section, sibling of the templates card.
  /// Each row logs ONE summed serving with one tap or deletes behind a dialog.
  Widget _recipesCard(ThemeData theme, AppLocalizations l10n) {
    final recipes = _recipeStore.recipes;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                l10n.nutritionRecipes,
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final r in recipes)
              ListTile(
                title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    l10n.nutritionRecipeMeta(r.ingredientCount, r.servings)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loggingRecipe && _loggingRecipeId == r.id)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      TextButton(
                        onPressed: _loggingRecipe ? null : () => _logRecipe(r),
                        child: Text(l10n.nutritionLogRecipe),
                      ),
                    IconButton(
                      tooltip: l10n.nutritionDeleteRecipe,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteRecipe(r),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ringsCard(ThemeData theme, AppLocalizations l10n, MacroTotals c) {
    final budget = computeDayBudget(
      FoodMacros(
        calories: c.calories,
        proteinG: c.proteinG,
        carbsG: c.carbsG,
        fatG: c.fatG,
      ),
      _targets,
    );
    final rings = <_Ring>[
      _Ring(l10n.nutritionCalories, c.calories, _targets?.calories, 'kcal',
          budget?.calories),
      _Ring(l10n.nutritionProtein, c.proteinG, _targets?.proteinG, 'g',
          budget?.protein),
      _Ring(l10n.nutritionCarbs, c.carbsG, _targets?.carbsG, 'g', budget?.carbs),
      _Ring(l10n.nutritionFat, c.fatG, _targets?.fatG, 'g', budget?.fat),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (budget != null) ...[
              _calorieChip(theme, l10n, budget.calories),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [for (final r in rings) _ringWidget(theme, r)],
            ),
            if (_targets != null && _targets!.exerciseKcal > 0) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_fire_department,
                      size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      l10n.nutritionGoalBreakdown(
                        _targets!.baseCalories,
                        _targets!.exerciseKcal,
                      ),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ],
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

  /// "X kcal left" / "X kcal over" / "On target" headline chip. The ring arc
  /// clamps at full, so an over day is invisible without this.
  Widget _calorieChip(ThemeData theme, AppLocalizations l10n, MacroBudget b) {
    final String text;
    final Color bg;
    final Color fg;
    if (b.exceeded) {
      text = l10n.nutritionCaloriesOver(b.over);
      bg = theme.colorScheme.errorContainer;
      fg = theme.colorScheme.onErrorContainer;
    } else if (b.remaining == 0) {
      text = l10n.nutritionOnTarget;
      bg = theme.colorScheme.secondaryContainer;
      fg = theme.colorScheme.onSecondaryContainer;
    } else {
      text = l10n.nutritionCaloriesLeft(b.remaining ?? 0);
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _ringWidget(ThemeData theme, _Ring r) {
    final frac = ringFraction(r.consumed, r.target);
    // Ceiling rings (calories/fat) gone over recolour to the danger tone, so an
    // over day reads at a glance even though the arc clamps full.
    final over = r.budget?.exceeded ?? false;
    final reached = r.budget?.reached ?? false;
    final ringColor = over ? theme.colorScheme.error : theme.colorScheme.primary;
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
                  color: ringColor,
                ),
              ),
              if (over)
                Text('+${r.budget!.over}',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.error))
              else if (reached)
                Icon(Icons.check,
                    size: 18, color: theme.colorScheme.primary)
              else
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
    final tag = localeToTag(Localizations.localeOf(context));
    final units = (_waterMl / _waterUnitMl).round();
    final targetMl = hydrationTargetMl(_weightKg, _exerciseMinutes);
    final budget = hydrationBudget(_waterMl, targetMl);
    final drunkPips = (_waterMl / _waterUnitMl).round();
    // Goal-relative: enough pips to span the goal, but never fewer than the
    // amount already drunk (or a sensible floor of 8).
    final pipCount = [
      8,
      (targetMl / _waterUnitMl).round(),
      drunkPips,
    ].reduce(math.max);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.nutritionWater,
                      style: theme.textTheme.titleSmall),
                ),
                Text(
                  l10n.nutritionWaterAmount(
                    _litres(_waterMl, tag),
                    _litres(targetMl, tag),
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(width: 8),
                _waterChip(theme, l10n, budget),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  tooltip: l10n.nutritionWaterRemove,
                  onPressed: _waterMl <= 0
                      ? null
                      : () => _setWater(math.max(0, _waterMl - _waterUnitMl)),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < pipCount; i++)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < drunkPips
                                ? (budget.reached
                                    ? theme.colorScheme.secondary
                                    : theme.colorScheme.primary)
                                : theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('$units × 250 ml', style: theme.textTheme.bodySmall),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: l10n.nutritionWaterAdd,
                  onPressed: () => _setWater(_waterMl + _waterUnitMl),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _waterChip(ThemeData theme, AppLocalizations l10n, HydrationBudget b) {
    final reached = b.reached;
    final text =
        reached ? l10n.nutritionWaterGoalReached : l10n.nutritionWaterRemaining(b.remainingMl);
    final bg = reached
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final fg = reached
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Litres for a millilitre amount, trimmed of trailing zeros (mirrors web
  /// `litres()`): 2450 -> "2.45", 2000 -> "2".
  String _litres(int ml, String tag) {
    final raw = formatFixed(ml / 1000, 2, tag);
    // Trim trailing zeros + a dangling separator (locale-aware: '.' or ',').
    return raw.replaceAll(RegExp(r'[.,]?0+$'), '');
  }

  Widget _mealGroup(ThemeData theme, AppLocalizations l10n, MealSlotGroup g) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openMealDetail(g.slot),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(_slotLabel(l10n, g.slot),
                            style: theme.textTheme.titleSmall)),
                    Text('${g.calories} kcal',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                    Icon(Icons.chevron_right,
                        size: 18, color: theme.colorScheme.outline),
                  ],
                ),
              ),
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
                      onPressed: () => _delete(e),
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
    final calByDay = <String, double>{};
    final proByDay = <String, double>{};
    for (final r in widget.store.rows) {
      final v = r['started_at'];
      final at = v is String ? DateTime.tryParse(v) : null;
      if (at == null) continue;
      final local = at.toLocal();
      final key = '${local.year}-${local.month}-${local.day}';
      calByDay[key] = (calByDay[key] ?? 0) + ((r['calories'] as num?)?.toDouble() ?? 0);
      proByDay[key] = (proByDay[key] ?? 0) + ((r['protein_g'] as num?)?.toDouble() ?? 0);
    }
    final days = <({String label, double calories, double protein})>[];
    for (var i = 6; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day - i);
      final key = '${d.year}-${d.month}-${d.day}';
      days.add((
        label: formatDowNarrow(d, tag),
        calories: calByDay[key] ?? 0,
        protein: proByDay[key] ?? 0,
      ));
    }
    final goal = _targets?.calories;
    final summary = weeklyIntakeSummary(
      [for (final d in days) d.calories],
      goal,
    );
    final protein = weeklyProteinSummary(
      [for (final d in days) d.protein],
      _targets?.proteinG,
    );
    // Bars + the goal reference line share one scale; include the goal so its
    // line stays on-chart even when no logged day reaches it.
    const barArea = 72.0;
    final maxCal = [
      1.0,
      days.map((d) => d.calories).fold(0.0, math.max),
      (goal ?? 0).toDouble(),
    ].reduce(math.max);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.nutritionWeeklyTrend,
                      style: theme.textTheme.titleSmall),
                ),
                if (summary.deltaPerDay != null)
                  _weekDeltaChip(theme, l10n, summary.deltaPerDay!),
                if (protein.daysMetGoal != null) ...[
                  const SizedBox(width: 6),
                  _weekProteinChip(theme, l10n, protein),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: barArea + 24,
              child: Stack(
                children: [
                  if (goal != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 20 + (goal / maxCal) * barArea,
                      child: Tooltip(
                        message: '${l10n.nutritionGoalLine}: $goal kcal',
                        child: Container(
                          height: 1.5,
                          color: theme.colorScheme.secondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final d in days)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: math.max(2, (d.calories / maxCal) * barArea),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekDeltaChip(ThemeData theme, AppLocalizations l10n, int delta) {
    final String text;
    final Color bg;
    final Color fg;
    if (delta == 0) {
      text = l10n.nutritionWeekOnGoal;
      bg = theme.colorScheme.secondaryContainer;
      fg = theme.colorScheme.onSecondaryContainer;
    } else if (delta < 0) {
      text = l10n.nutritionWeekUnderGoal(-delta);
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
    } else {
      text = l10n.nutritionWeekOverGoal(delta);
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _weekProteinChip(
      ThemeData theme, AppLocalizations l10n, WeeklyProteinSummary p) {
    final allMet = p.daysMetGoal == p.loggedDays;
    final bg = allMet
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final fg = allMet
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        l10n.nutritionWeekProtein(p.daysMetGoal!, p.loggedDays),
        style: theme.textTheme.labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
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

  void _openMealDetail(String slot) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NutritionMealDetailScreen(
          store: widget.store,
          day: _todayStart,
          slot: slot,
        ),
      ),
    );
  }

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
  final MacroBudget? budget;
  const _Ring(this.label, this.consumed, this.target, this.unit, this.budget);
}
