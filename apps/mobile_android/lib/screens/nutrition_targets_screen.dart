import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ui_kit/ui_kit.dart' show EmptyState, ListSkeleton, SectionHeader;

import '../adaptive_width.dart';
import '../auth_error.dart';
import '../diary_day.dart';
import '../exercise_calories.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../nutrition_targets.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';
import 'nutrition_screen.dart' show exerciseInputsForDay;
import 'settings_body_metrics_screen.dart';

/// Nutrition → Targets, the mobile mirror of web `/nutrition/targets`
/// (multi_modal.md § "Status (targets peer)"). Shows how the day's calorie +
/// macro goal is derived — resting metabolism, the activity factor, the goal
/// delta, the base, today's workout add-on, then the macro split — and carries
/// the two non-sensitive levers that shape it.
///
/// Composed entirely from what `nutrition_targets.dart` already exports, so
/// there is no arithmetic here and no obligation on the TS twin.
///
/// Height / weight / date of birth / sex are Art 9 special-category data and
/// stay editable only in [SettingsBodyMetricsScreen] behind its explicit
/// consent gate — this screen displays them and links there. A second input
/// would be a second consent surface.
class NutritionTargetsScreen extends StatefulWidget {
  final ApiClient? api;
  final SettingsSyncService? settingsSync;

  const NutritionTargetsScreen({
    super.key,
    required this.api,
    required this.settingsSync,
  });

  @override
  State<NutritionTargetsScreen> createState() => _NutritionTargetsScreenState();
}

class _NutritionTargetsScreenState extends State<NutritionTargetsScreen> {
  bool _loading = true;
  bool _loadFailed = false;

  double? _weightKg;
  double? _heightCm;
  int? _ageYears;
  String? _sex;
  double _exerciseKcal = 0;
  String _activity = 'moderate';
  String _goal = 'maintain';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loadFailed = false;
    final settings = widget.settingsSync?.service;
    _activity =
        settings?.effective<String>(SettingsKeys.nutritionActivityLevel) ??
            'moderate';
    _goal =
        settings?.effective<String>(SettingsKeys.nutritionGoal) ?? 'maintain';
    final api = widget.api;
    if (api != null && api.userId != null) {
      try {
        final profile = await api.fetchMyProfile();
        _heightCm = profile?.heightCm;
        _sex = profile?.gender;
        final dobIso = settings?.effective<String>(SettingsKeys.dateOfBirth) ??
            profile?.dateOfBirth?.toIso8601String();
        _ageYears =
            ageFromDob(dobIso, DateTime.now().millisecondsSinceEpoch);
        _weightKg = await api.fetchLatestBodyWeightKg();
        _exerciseKcal = await _todayExerciseKcal(api, _weightKg);
      } catch (e) {
        debugPrint('nutrition_targets: load failed: $e');
        _loadFailed = true;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Today's logged runs + gym sessions as burned kcal, the dynamic-TDEE
  /// add-on the derivation shows on its own line. Best-effort: a failure
  /// leaves the goal base-only rather than failing the whole screen, so the
  /// derivation still renders for a runner whose activity read broke.
  Future<double> _todayExerciseKcal(ApiClient api, double? weightKg) async {
    try {
      final w = diaryWindow(isoDateOf(DateTime.now()));
      if (w == null) return 0;
      final activities = await api.fetchActivities(limit: 50);
      final day = exerciseInputsForDay(activities, w.start, w.end);
      return exerciseCaloriesForDay(
        runs: day.runs,
        gymSessions: day.gym,
        weightKg: weightKg,
      ).toDouble();
    } catch (e) {
      debugPrint('nutrition_targets: exercise fetch failed: $e');
      return 0;
    }
  }

  Future<void> _retry() async {
    setState(() => _loading = true);
    await _load();
  }

  NutritionTargets? get _targets => computeNutritionTargets(BodyMetricsInput(
        weightKg: _weightKg,
        heightCm: _heightCm,
        ageYears: _ageYears,
        sex: _sex,
        activityLevel: _activity,
        goal: _goal,
        exerciseKcal: _exerciseKcal,
      ));

  double? get _bmr {
    final w = _weightKg;
    final h = _heightCm;
    final a = _ageYears;
    if (w == null || h == null || a == null) return null;
    return mifflinStJeorBmr(w, h, a, _sex);
  }

  double get _activityFactor {
    for (final a in activityLevels) {
      if (a.key == _activity) return a.factor;
    }
    return 1.55;
  }

  double get _goalDelta => goalKcalDelta[_goal] ?? 0;

  /// True when the engine's floor is what the base reads, so the shown terms
  /// visibly failing to add up to the base is explained rather than looking
  /// like a bug. Compared against the unrounded BMR so this agrees with the
  /// engine at the boundary, exactly as the web page does.
  bool get _baseFloored {
    final bmr = _bmr;
    if (bmr == null) return false;
    return bmr * _activityFactor + _goalDelta < minCalorieTarget;
  }

  Future<void> _putBag(String key, String value) async {
    final l10n = AppLocalizations.of(context);
    try {
      await widget.settingsSync?.updateUniversal(<String, dynamic>{key: value});
    } catch (e) {
      debugPrint('nutrition_targets: pref save failed: $e');
      if (mounted) {
        showTopBanner(
            context, l10n.bodyMetricsPrefSaveFailed(friendlyError(l10n, e)));
      }
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickActivity() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pick(
      title: l10n.bodyMetricsActivityLevel,
      options: [for (final a in activityLevels) a.key],
      labels: [for (final a in activityLevels) activityLevelLabel(l10n, a.key)],
      current: _activity,
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => _activity = picked);
      await _putBag(SettingsKeys.nutritionActivityLevel, picked);
    }
  }

  Future<void> _pickGoal() async {
    final l10n = AppLocalizations.of(context);
    final keys = goalKcalDelta.keys.toList();
    final picked = await _pick(
      title: l10n.bodyMetricsGoal,
      options: keys,
      labels: [for (final k in keys) weightGoalLabel(l10n, k)],
      current: _goal,
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => _goal = picked);
      await _putBag(SettingsKeys.nutritionGoal, picked);
    }
  }

  Future<String?> _pick({
    required String title,
    required List<String> options,
    required List<String> labels,
    required String current,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (var i = 0; i < options.length; i++)
            RadioListTile<String>(
              title: Text(labels[i]),
              value: options[i],
              groupValue: current,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
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
    await _retry();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.nutritionTargetsTitle)),
      body: contentColumn(
        context,
        _loading
            ? ListSkeleton(
                label: l10n.commonLoading,
                rows: 4,
                rowHeight: 96,
                hasLeading: false,
              )
            : _loadFailed
                ? ErrorState(
                    message: l10n.nutritionTargetsLoadError,
                    onRetry: _retry,
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        l10n.nutritionTargetsSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      if (_targets != null) ...[
                        _derivationCard(theme, l10n, _targets!),
                        const SizedBox(height: 12),
                        _macrosCard(theme, l10n, _targets!),
                      ] else
                        EmptyState(
                          icon: Icons.straighten,
                          title: l10n.nutritionTargetsEmptyTitle,
                          body: l10n.nutritionTargetsEmptyBody,
                          ctaLabel: activePreferences == null
                              ? null
                              : l10n.nutritionAddBodyMetrics,
                          onCta:
                              activePreferences == null ? null : _openBodyMetrics,
                          ctaIcon: Icons.straighten,
                        ),
                      const SizedBox(height: 12),
                      _defaultsCard(theme, l10n),
                      const SizedBox(height: 12),
                      _metricsCard(theme, l10n),
                    ],
                  ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );

  Widget _row(
    ThemeData theme, {
    required String term,
    String? hint,
    required String value,
    bool emphasis = false,
  }) {
    final termStyle = emphasis
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(term, style: termStyle),
                if (hint != null)
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(value, style: termStyle),
        ],
      ),
    );
  }

  Widget _derivationCard(
      ThemeData theme, AppLocalizations l10n, NutritionTargets t) {
    final tag = localeToTag(Localizations.localeOf(context));
    final delta = _goalDelta.round();
    // decimalPattern rather than formatFixed: the factors carry one, two or
    // three meaningful digits (1.2 / 1.55 / 1.375) and a fixed width would
    // print "1.200" for the first.
    final factor = NumberFormat.decimalPattern(tag).format(_activityFactor);
    return _card(
      children: [
        Row(
          children: [
            Expanded(
              child: SectionHeader(label: l10n.nutritionTargetsTotal),
            ),
            Text(
              '${t.calories} kcal',
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _row(theme,
            term: l10n.nutritionTargetsBmr,
            value: '${_bmr!.round()} kcal'),
        _row(theme,
            term: l10n.bodyMetricsActivityLevel,
            value: '× $factor'),
        _row(theme,
            term: l10n.bodyMetricsGoal,
            value: '${delta > 0 ? '+' : ''}$delta kcal'),
        _row(theme,
            term: l10n.nutritionTargetsBase,
            value: '${t.baseCalories} kcal',
            emphasis: true),
        if (t.exerciseKcal > 0)
          _row(theme,
              term: l10n.nutritionTargetsExercise,
              hint: l10n.nutritionTargetsExerciseHint,
              value: '+${t.exerciseKcal} kcal'),
        if (_baseFloored) ...[
          const SizedBox(height: 4),
          Text(
            l10n.nutritionTargetsBaseFloored(minCalorieTarget),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _macrosCard(
      ThemeData theme, AppLocalizations l10n, NutritionTargets t) {
    final tag = localeToTag(Localizations.localeOf(context));
    return _card(
      children: [
        SectionHeader(label: l10n.nutritionTargetsMacrosHeading),
        const SizedBox(height: 4),
        _row(theme,
            term: l10n.nutritionProtein,
            hint: l10n.nutritionTargetsProteinHint(
                formatFixed(proteinGPerKg, 1, tag)),
            value: '${t.proteinG} g'),
        _row(theme,
            term: l10n.nutritionCarbs,
            hint: l10n.nutritionTargetsCarbsHint,
            value: '${t.carbsG} g'),
        _row(theme,
            term: l10n.nutritionFat,
            hint: l10n.nutritionTargetsFatHint((fatKcalFraction * 100).round()),
            value: '${t.fatG} g'),
      ],
    );
  }

  Widget _defaultsCard(ThemeData theme, AppLocalizations l10n) {
    return _card(
      children: [
        SectionHeader(label: l10n.nutritionTargetsDefaultsHeading),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.bodyMetricsActivityLevel),
          subtitle: Text(activityLevelLabel(l10n, _activity)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickActivity,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.bodyMetricsGoal),
          subtitle: Text(weightGoalLabel(l10n, _goal)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickGoal,
        ),
        Text(
          l10n.nutritionTargetsDefaultsHint,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _metricsCard(ThemeData theme, AppLocalizations l10n) {
    final unset = l10n.nutritionTargetsUnset;
    final h = _heightCm;
    final w = _weightKg;
    final a = _ageYears;
    return _card(
      children: [
        Row(
          children: [
            Expanded(
              child: SectionHeader(label: l10n.nutritionTargetsMetricsHeading),
            ),
            if (activePreferences != null)
              TextButton(
                onPressed: _openBodyMetrics,
                child: Text(l10n.nutritionTargetsEditMetrics),
              ),
          ],
        ),
        _row(theme,
            term: l10n.bodyMetricsHeight,
            value: h == null ? unset : '${h.round()} cm'),
        _row(theme,
            term: l10n.bodyMetricsWeight,
            value: w == null ? unset : WeightFormat.format(w, activeWeightUnit)),
        _row(theme,
            term: l10n.nutritionTargetsAge,
            value: a == null ? unset : l10n.nutritionTargetsAgeYears(a)),
        _row(theme,
            term: l10n.setupGenderLabel,
            value: switch (_sex) {
              'male' => l10n.setupGenderMale,
              'female' => l10n.setupGenderFemale,
              _ => l10n.setupGenderPreferNot,
            }),
        const SizedBox(height: 4),
        Text(
          l10n.nutritionTargetsMetricsHint,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
