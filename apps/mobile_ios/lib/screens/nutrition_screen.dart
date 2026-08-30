import 'dart:math' as math;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show FoodEntry;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import '../adaptive_width.dart';
import '../auth_error.dart';
import '../column_limits.dart';
import '../diary_day.dart';
import '../exercise_calories.dart';
import '../exercise_day.dart';
import '../extended_nutrients.dart';
import '../food_search.dart' show FoodMacros;
import '../health_consent.dart';
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
import '../preferences.dart';
import '../typed_decimal.dart';
import '../undo_queue.dart';
import '../recipe.dart';
import '../nutrition_totals.dart';
import '../nutrition_week.dart';
import '../settings_sync.dart';
import '../widgets/nutrition_log_sheet.dart';
import '../widgets/pending_sync_banner.dart';
import '../widgets/top_banner.dart';
import '../widgets/undo_bar.dart';
import 'nutrition_meal_detail_screen.dart';
import 'nutrition_targets_screen.dart';
import 'settings_body_metrics_screen.dart';

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
    // The settings-bag mirror already follows consent in both directions;
    // the profile column is the ungated age record, so its fallback takes the
    // Art 9 term (§ 718 / § 722).
    final dobIso = settings?.effective<String>(SettingsKeys.dateOfBirth) ??
        healthUseDob(profile);
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

  /// The viewed day's run + gym active minutes — feeds the hydration goal's
  /// sweat-replacement add (runs/gym without a duration contribute nothing).
  int _exerciseMinutes = 0;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
    _templateStore.addListener(_onStoreChange);
    _recipeStore.addListener(_onStoreChange);
    _loadWater();
    _initOwnedStores();
    _refresh();
  }

  /// `init()`, never a bare `loadAll()`: `loadAll` alone leaves `dir` null, and
  /// every subsequent write then refuses (see `OfflineSyncStore`), so a saved
  /// meal or recipe would live in memory for the session and never reach disk
  /// or the server. Failures are per-store so a broken meal-template directory
  /// can't cost the user their recipes.
  Future<void> _initOwnedStores() async {
    try {
      await _templateStore.init();
    } catch (e) {
      debugPrint('nutrition_screen: meal template store init failed: $e');
    }
    try {
      await _recipeStore.init();
    } catch (e) {
      debugPrint('nutrition_screen: recipe store init failed: $e');
    }
    if (mounted) setState(() {});
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
    // User-scoped (issue #231): a shared device's next account must not
    // inherit — or increment — the prior account's water count.
    final uid = widget.api?.userId ?? 'anon';
    return 'water_ml_${uid}_${waterDayKey(_viewDate)}';
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

  /// The `YYYY-MM-DD` calendar day the diary is showing. A local-calendar
  /// identity, never an instant: it is only ever assigned from the `diary_day`
  /// helpers, which step through `DateTime(y, m, d + n)` so a 23- or 25-hour
  /// DST day cannot repeat or skip one.
  String _viewDate = isoDateOf(DateTime.now());

  DiaryWindow get _dayWindow {
    final w = diaryWindow(_viewDate);
    if (w != null) return w;
    final n = DateTime.now();
    return DiaryWindow(
        DateTime(n.year, n.month, n.day), DateTime(n.year, n.month, n.day + 1));
  }

  void _goToDay(String iso) {
    if (iso == _viewDate) return;
    setState(() => _viewDate = iso);
    _loadWater();
    _refresh();
  }

  Future<void> _refresh() async {
    final api = widget.api;
    if (api == null || api.userId == null) {
      if (mounted) setState(() => _isOnline = false);
      return;
    }
    setState(() => _refreshing = true);
    try {
      // Pull the 7 days ending on the viewed day so both its list and the
      // trend derive from the one cache. A row outside that window is
      // preserved rather than pruned, so stepping back does not evict today.
      final trend = diaryWindow(_viewDate, 7) ?? _dayWindow;
      final fresh = await api.fetchFoodLog(from: trend.start, to: trend.end);
      await widget.store.replaceFromServer(
        [for (final r in fresh) r.toJson()],
        windowStart: trend.start,
        windowEnd: trend.end,
      );
      if (widget.store.hasPending) await widget.store.syncWithServer(api);
      await _hydrateTemplates(api);
      await _hydrateRecipes(api);
      _weightKg = await api.fetchLatestBodyWeightKg();
      final exercise = await _dayExercise(api, _weightKg);
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

  /// The always-available route to the number the rings are measured against.
  /// Deliberately ungated: a runner with no targets yet is precisely the one
  /// who needs the derivation and the two levers (decisions § 695).
  Future<void> _openTargets() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NutritionTargetsScreen(
          api: widget.api,
          settingsSync: widget.settingsSync,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openBodyMetrics() async {
    final prefs = activePreferences;
    if (prefs == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsBodyMetricsScreen(
          api: widget.api,
          settingsSync: widget.settingsSync,
          preferences: prefs,
        ),
      ),
    );
    await _refresh();
  }

  /// The viewed day's run + gym exercise reduced to (a) whole active minutes
  /// for the hydration goal's sweat-replacement add and (b) estimated burned
  /// kcal for the dynamic-TDEE "base + exercise" calorie goal (decisions §134).
  /// Both best-effort; a failure leaves them at 0 so the goal stays base-only.
  Future<({int minutes, int kcal})> _dayExercise(
    ApiClient api,
    double? weightKg,
  ) async {
    try {
      final activities = await api.fetchActivities(limit: 50);
      final w = _dayWindow;
      final day = exerciseInputsForDay(activities, w.start, w.end);
      final kcal = exerciseCaloriesForDay(
        runs: day.runs,
        gymSessions: day.gym,
        weightKg: weightKg,
      );
      return (minutes: (day.seconds / 60).round(), kcal: kcal);
    } catch (e) {
      debugPrint('nutrition_screen: exercise fetch failed: $e');
      return (minutes: 0, kcal: 0);
    }
  }

  Future<void> _maybeSync() async {
    final api = widget.api;
    if (api == null || !_isOnline) return;
    await widget.store.syncWithServer(api);
    if (mounted && widget.store.hasPending) setState(() {});
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
    final saved = await showNutritionLogSheet(
        context: context, store: widget.store, diaryDate: _viewDate);
    if (saved == true) await _maybeSync();
  }

  /// Promote the viewed day's logged entries into a named meal template via the
  /// pure `templateFromEntries` parity helper (default slot derived when the day's
  /// entries agree). The name is collected in an AlertDialog.
  Future<void> _saveAsMeal() async {
    if (_savingMeal) return;
    final l10n = AppLocalizations.of(context);
    final today = _dayEntries;
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
    FocusManager.instance.primaryFocus?.unfocus();
    if (name == null) return;
    if (_savingMeal) return;
    if (!mounted) return;
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
      debugPrint('nutrition template save failed: $e');
      if (mounted) {
        showTopBanner(context, l10n.nutritionTemplateSaveFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _savingMeal = false);
    }
  }

  Future<void> _maybeSyncTemplates() async {
    final api = widget.api;
    if (api == null || !_isOnline) return;
    await _templateStore.syncWithServer(api);
    if (mounted && _templateStore.hasPending) setState(() {});
  }

  /// Log every item of [t] as a food_log entry inside the VIEWED day, via the
  /// pure `entriesFromTemplate` parity helper (slot resolves item → template-default)
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
          startedAt: entryTimestampFor(_viewDate, DateTime.now()),
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
      debugPrint('nutrition template log failed: $e');
      if (mounted) {
        showTopBanner(context, l10n.nutritionTemplateLogFailed(friendlyError(l10n, e)));
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
      debugPrint('nutrition template delete failed: $e');
      if (mounted) {
        showTopBanner(context, l10n.nutritionTemplateDeleteFailed(friendlyError(l10n, e)));
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
    if (mounted && _recipeStore.hasPending) setState(() {});
  }

  /// Promote the viewed day's logged entries into a named recipe. The name + servings
  /// are collected in an AlertDialog; the ingredients come from `recipeFromEntries`.
  Future<void> _saveAsRecipe() async {
    if (_savingRecipe) return;
    final l10n = AppLocalizations.of(context);
    final today = _dayEntries;
    if (today.isEmpty) return;
    final nameController = TextEditingController();
    // `recipes.servings` has a floor of 1 in the column and no ceiling there,
    // but `numeric(5,1)` has one — so an unbounded field turned a mistyped 9
    // into a raw 22003 and a typed 0 into a 23514 (decisions § 792). The
    // dialog refuses rather than clamping: silently rewriting a typed number
    // is the same swallow one layer down.
    const servingsKey = 'recipes.servings';
    final servingsController =
        TextEditingController(text: '${columnMin(servingsKey).toInt()}');
    String boundText(num v) =>
        formatFixed(v.toDouble(), v == v.roundToDouble() ? 0 : 1, activeLocaleTag);
    final result = await showDialog<({String name, double servings})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final typed = parseTypedDecimal(servingsController.text);
          final outOfRange =
              typed != null && !withinColumnLimit(servingsKey, typed);
          return AlertDialog(
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.nutritionRecipeServings,
                    errorText: outOfRange
                        ? l10n.limitsServingsOutOfRange(
                            boundText(columnMin(servingsKey)),
                            boundText(columnMax(servingsKey)))
                        : null,
                  ),
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
                onPressed: outOfRange
                    ? null
                    : () => Navigator.pop(
                          ctx,
                          (
                            name: nameController.text,
                            servings: typed ?? columnMin(servingsKey).toDouble(),
                          ),
                        ),
                child: Text(l10n.nutritionSaveRecipe),
              ),
            ],
          );
        },
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    if (result == null) return;
    if (_savingRecipe) return;
    if (!mounted) return;
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
      debugPrint('nutrition recipe save failed: $e');
      if (mounted) {
        showTopBanner(context, l10n.nutritionRecipeSaveFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _savingRecipe = false);
    }
  }

  /// The common meal slot across the viewed day's entries when they all agree, else
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
          startedAt: entryTimestampFor(_viewDate, DateTime.now()),
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
      debugPrint('nutrition recipe log failed: $e');
      if (mounted) {
        showTopBanner(context, l10n.nutritionRecipeLogFailed(friendlyError(l10n, e)));
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
      debugPrint('nutrition recipe delete failed: $e');
      if (mounted) {
        showTopBanner(context, l10n.nutritionRecipeDeleteFailed(friendlyError(l10n, e)));
      }
    }
  }

  /// The app's most frequently deleted row, and one re-typed in seconds — so
  /// it drops its confirm for undo (decisions § 514).
  ///
  /// The list here is derived from [LocalFoodStore], not held in state, so the
  /// optimistic removal is a hidden-id set rather than a list snapshot: the
  /// stored row is not touched at all while the offer stands, which is a
  /// stronger form of the same contract — the entry comes back bit for bit,
  /// including its pending sync state.
  void _delete(FoodEntry e) {
    final l10n = AppLocalizations.of(context);
    final store = widget.store;
    setState(() => _deferredDeleteIds = {..._deferredDeleteIds, e.id});
    deferDestructive(
      context,
      DeferredDestruction(
        message: l10n.nutritionEntryRemoved(e.itemName),
        commit: () async {
          await store.deleteLocal(e.id);
          await _maybeSync();
        },
        restore: () {
          if (!mounted) return;
          setState(() =>
              _deferredDeleteIds = _deferredDeleteIds.difference({e.id}));
        },
        onCommitError: (err) {
          debugPrint('nutrition delete failed: $err');
          if (!mounted) return;
          showTopBanner(
              context, l10n.nutritionDeleteFailed(friendlyError(l10n, err)));
        },
      ),
    );
  }

  /// Entries whose delete is deferred behind an open undo offer. They are
  /// hidden from every read of the list while the offer stands; the stored row
  /// itself is untouched until the window closes.
  Set<String> _deferredDeleteIds = {};

  List<FoodEntry> get _dayEntries => [
        for (final r
            in widget.store.entriesForRange(_dayWindow.start, _dayWindow.end))
          if (!_deferredDeleteIds.contains(r['id'])) FoodEntry.fromRow(r),
      ];

  bool get _anyPending =>
      widget.store.hasPending ||
      _templateStore.hasPending ||
      _recipeStore.hasPending;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final today = _dayEntries;
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
      body: contentColumn(
        context,
        Column(
          children: [
            if (!_isOnline && !_anyPending)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: theme.colorScheme.surfaceContainerHigh,
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.nutritionOfflineCached,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            PendingSyncBanner(
              api: widget.api,
              isOnline: _isOnline,
              stores: [widget.store, _templateStore, _recipeStore],
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _dayBar(theme, l10n),
                    const SizedBox(height: 12),
                    _ringsCard(theme, l10n, sumMacros(today)),
                    const SizedBox(height: 12),
                    _waterCard(theme, l10n),
                    const SizedBox(height: 12),
                    ...(() {
                      final nutrients = _nutrientBudgets(today);
                      return nutrients.isEmpty
                          ? const <Widget>[]
                          : <Widget>[
                              _nutrientsCard(theme, l10n, nutrients),
                              const SizedBox(height: 12),
                            ];
                    })(),
                    if (_templateStore.templates.isNotEmpty) ...[
                      _templatesCard(theme, l10n),
                      const SizedBox(height: 12),
                    ],
                    if (_recipeStore.recipes.isNotEmpty) ...[
                      _recipesCard(theme, l10n),
                      const SizedBox(height: 12),
                    ],
                    if (groups.isEmpty)
                      EmptyState(
                        icon: Icons.restaurant,
                        title: _viewingToday
                            ? l10n.nutritionEmptyTitle
                            : l10n.nutritionDayEmptyPast,
                        body: l10n.nutritionEmptyBody,
                        ctaLabel: l10n.nutritionLogFood,
                        onCta: _logFood,
                      )
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
      ),
    );
  }

  bool get _viewingToday => isDiaryToday(_viewDate, DateTime.now());

  String _dayLabel(AppLocalizations l10n, String tag) {
    final now = DateTime.now();
    if (isDiaryToday(_viewDate, now)) return l10n.nutritionDayToday;
    if (_viewDate == stepDiaryDate(isoDateOf(now), -1, now)) {
      return l10n.nutritionDayYesterday;
    }
    return formatDateMed(_dayWindow.start, tag);
  }

  /// The day stepper above the rings, mirroring web `/nutrition`'s day bar:
  /// back a day, the day's label, forward a day (disabled on today), a Today
  /// reset, and — off today — the hint that a log lands on the viewed day.
  Widget _dayBar(ThemeData theme, AppLocalizations l10n) {
    final tag = localeToTag(Localizations.localeOf(context));
    final now = DateTime.now();
    return Semantics(
      container: true,
      label: l10n.nutritionDayNavLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: l10n.nutritionDayPrevious,
                onPressed: () =>
                    _goToDay(stepDiaryDate(_viewDate, -1, DateTime.now())),
              ),
              Expanded(
                child: Text(
                  _dayLabel(l10n, tag),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: l10n.nutritionDayNext,
                onPressed: canStepForward(_viewDate, now)
                    ? () =>
                        _goToDay(stepDiaryDate(_viewDate, 1, DateTime.now()))
                    : null,
              ),
              if (!_viewingToday)
                TextButton(
                  onPressed: () => _goToDay(isoDateOf(DateTime.now())),
                  child: Text(l10n.nutritionDayToday),
                ),
            ],
          ),
          if (!_viewingToday)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.history,
                      size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.nutritionDayBackfillHint,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
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
                      _viewingToday
                          ? l10n.nutritionGoalBreakdown(
                              _targets!.baseCalories,
                              _targets!.exerciseKcal,
                            )
                          : l10n.nutritionDayGoalBreakdown(
                              _targets!.baseCalories,
                              _targets!.exerciseKcal,
                            ),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              if (activePreferences != null) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _openBodyMetrics,
                  icon: const Icon(Icons.straighten),
                  label: Text(l10n.nutritionAddBodyMetrics),
                ),
              ],
            ],
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: _openTargets,
                icon: const Icon(Icons.tune, size: 18),
                label: Text(l10n.nutritionTargetsLink),
              ),
            ),
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
    return StatusPill(label: text, foreground: fg, fill: bg);
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
              // The value lives inside the arc, so the ring bounds it: a
              // four-digit calorie count already fills 50 of the 56 px at
              // 1.0x, and at 2x it was being wrapped and cropped.
              if (over)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('+${r.budget!.over}',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.error)),
                )
              else if (reached)
                Icon(Icons.check,
                    size: 18, color: theme.colorScheme.primary)
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${r.consumed}',
                      style: theme.textTheme.labelMedium),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          r.target != null ? '${r.label} / ${r.target} ${r.unit}' : r.label,
          style:
              theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  List<NutrientBudget> _nutrientBudgets(List<FoodEntry> today) =>
      extendedNutrientBudgets(
        [
          for (final e in today)
            ExtendedNutrientRow(
              fiberG: e.fiberG,
              sugarG: e.sugarG,
              sodiumMg: e.sodiumMg,
              saturatedFatG: e.saturatedFatG,
              cholesterolMg: e.cholesterolMg,
            ),
        ],
        extendedNutrientTargets(_targets, _exerciseMinutes),
      );

  Widget _nutrientsCard(
      ThemeData theme, AppLocalizations l10n, List<NutrientBudget> budgets) {
    final tag = localeToTag(Localizations.localeOf(context));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.nutritionNutrients, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final n in budgets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _nutrientRow(theme, l10n, tag, n),
              ),
            const SizedBox(height: 4),
            Text(l10n.nutritionNutrientsHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _nutrientRow(ThemeData theme, AppLocalizations l10n, String tag,
      NutrientBudget n) {
    final label = _nutrientLabel(l10n, n.labelKey);
    final amount = StringBuffer();
    if (n.partial) amount.write('${l10n.nutritionNutrientAtLeast} ');
    amount.write(_nutrientAmount(n.consumed, n.unit, tag));
    if (n.target != null) {
      amount.write(' / ${_nutrientAmount(n.target!.toDouble(), n.unit, tag)}');
    }
    amount.write(' ${n.unit}');
    // The coverage sentence rides as a semantics label rather than only as a
    // tooltip: it is the one thing qualifying the number beside it, and a
    // long-press tooltip is unreachable to a screen reader.
    final coverage = n.partial
        ? l10n.nutritionNutrientPartial(n.reportedEntries, n.totalEntries, label)
        : null;
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Semantics(
          label: coverage,
          child: Text(amount.toString(), style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(width: 8),
        _nutrientChip(theme, l10n, tag, n),
      ],
    );
  }

  Widget _nutrientChip(ThemeData theme, AppLocalizations l10n, String tag,
      NutrientBudget n) {
    String text;
    Color bg;
    Color fg;
    if (n.exceeded) {
      text = l10n.nutritionNutrientOver(
          _nutrientAmount(n.consumed - n.target!, n.unit, tag), n.unit);
      bg = theme.colorScheme.errorContainer;
      fg = theme.colorScheme.onErrorContainer;
    } else if (n.reached) {
      text = l10n.nutritionNutrientReached;
      bg = theme.colorScheme.secondaryContainer;
      fg = theme.colorScheme.onSecondaryContainer;
    } else if (n.remaining != null) {
      text = l10n.nutritionNutrientLeft(
          _nutrientAmount(n.remaining!, n.unit, tag), n.unit);
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
    } else if (n.target == null) {
      text = l10n.nutritionNutrientUntargeted;
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
    } else {
      // Targeted but partially covered: the helper withheld `remaining`
      // because the unreported entries could have consumed all of it, and
      // "No daily target" would be a different — and false — claim.
      return const SizedBox.shrink();
    }
    return StatusPill(
        label: text, foreground: fg, fill: bg, size: StatusPillSize.compact);
  }

  /// Grams carry one decimal, milligrams none — mirroring the helper's own
  /// rounding — with a trailing `.0` trimmed so a whole number reads as one.
  String _nutrientAmount(double value, String unit, String tag) {
    if (unit != 'g') return formatFixed(value, 0, tag);
    return formatFixed(value, 1, tag).replaceAll(RegExp(r'[.,]0$'), '');
  }

  String _nutrientLabel(AppLocalizations l10n, String labelKey) {
    switch (labelKey) {
      case 'nutritionSodium':
        return l10n.nutritionSodium;
      case 'nutritionFiber':
        return l10n.nutritionFiber;
      case 'nutritionSaturatedFat':
        return l10n.nutritionSaturatedFat;
      case 'nutritionSugar':
        return l10n.nutritionSugar;
      case 'nutritionCholesterol':
        return l10n.nutritionCholesterol;
    }
    return labelKey;
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
    return StatusPill(
        label: text, foreground: fg, fill: bg, size: StatusPillSize.compact);
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                            ?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
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
                                ?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
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
    final calByDay = <String, double>{};
    final proByDay = <String, double>{};
    for (final r in widget.store.rows) {
      final v = r['started_at'];
      final at = v is String ? DateTime.tryParse(v) : null;
      if (at == null) continue;
      final key = isoDateOf(at);
      calByDay[key] = (calByDay[key] ?? 0) + ((r['calories'] as num?)?.toDouble() ?? 0);
      proByDay[key] = (proByDay[key] ?? 0) + ((r['protein_g'] as num?)?.toDouble() ?? 0);
    }
    final days = <({String label, double calories, double protein})>[];
    for (final iso in trailingDates(_viewDate, 7)) {
      final base = diaryWindow(iso);
      if (base == null) continue;
      days.add((
        label: formatDowNarrow(base.start, tag),
        calories: calByDay[iso] ?? 0,
        protein: proByDay[iso] ?? 0,
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
    // The lane under the bars holds a bodySmall day label, so it is a
    // text-derived dimension and has to track the OS text scale: a fixed 24
    // overflowed the chart by 12 px per column at 2x.
    final labelLane = MediaQuery.textScalerOf(context).scale(24.0);
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
                  child: Text(
                      _viewingToday
                          ? l10n.nutritionWeeklyTrend
                          : l10n.nutritionDayTrendEnding(
                              formatDateMed(_dayWindow.start, tag)),
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
              height: barArea + labelLane,
              child: Stack(
                children: [
                  if (goal != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: (labelLane - 4) + (goal / maxCal) * barArea,
                      child: Tooltip(
                        message: '${l10n.nutritionGoalLine}: $goal kcal',
                        child: Container(
                          height: 1.5,
                          color: theme.colorScheme.outline,
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
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                d.label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
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
    return StatusPill(
        label: text, foreground: fg, fill: bg, size: StatusPillSize.compact);
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
    return StatusPill(
        label: l10n.nutritionWeekProtein(p.daysMetGoal!, p.loggedDays),
        foreground: fg,
        fill: bg,
        size: StatusPillSize.compact);
  }

  void _openMealDetail(String slot) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NutritionMealDetailScreen(
          store: widget.store,
          day: _dayWindow.start,
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
