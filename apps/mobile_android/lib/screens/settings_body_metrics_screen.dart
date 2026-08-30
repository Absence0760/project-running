import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show ListSkeleton;

import '../auth_error.dart';
import '../column_limits.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart' show activeLocaleTag;
import '../l10n/number_format.dart' show formatFixed;
import '../nutrition_targets.dart' show activityLevels, goalKcalDelta;
import '../preferences.dart';
import '../settings_sync.dart';
import '../typed_decimal.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';

/// Localized label for a `nutrition_activity_level` bag value. Shared with
/// `NutritionTargetsScreen`, which shows the same lever, so the two surfaces
/// cannot name the same stored value differently.
String activityLevelLabel(AppLocalizations l10n, String key) => switch (key) {
      'sedentary' => l10n.activitySedentary,
      'light' => l10n.activityLight,
      'active' => l10n.activityVeryActive,
      'very_active' => l10n.activityExtraActive,
      _ => l10n.activityModerate,
    };

/// Localized label for a `nutrition_goal` bag value. See
/// [activityLevelLabel].
String weightGoalLabel(AppLocalizations l10n, String key) => switch (key) {
      'lose' => l10n.goalLose,
      'gain' => l10n.goalGain,
      _ => l10n.goalMaintain,
    };

/// Settings → Body metrics (multi_modal.md § "Body metrics & sensitive
/// data"). Height + weight are special-category health data (GDPR Art 9):
/// they are gated behind an explicit consent toggle and saved through the
/// consent-stamping path (mirrors the web `/settings/preferences`
/// demographics card). Activity level + goal are ordinary nutrition prefs —
/// not special-category — so they auto-save to the universal bag. All four
/// feed `computeNutritionTargets` (see `loadNutritionTargets`).
class SettingsBodyMetricsScreen extends StatefulWidget {
  final ApiClient? api;
  final SettingsSyncService? settingsSync;
  final Preferences preferences;

  const SettingsBodyMetricsScreen({
    super.key,
    required this.api,
    required this.settingsSync,
    required this.preferences,
  });

  @override
  State<SettingsBodyMetricsScreen> createState() =>
      _SettingsBodyMetricsScreenState();
}

class _SettingsBodyMetricsScreenState extends State<SettingsBodyMetricsScreen> {
  final _heightCtl = TextEditingController();
  final _weightCtl = TextEditingController();

  static const _weightKey = 'body_metrics.weight_kg';
  static const _heightKey = 'user_profiles.height_cm';

  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _consent = false;
  DateTime? _consentAt;
  double? _loadedWeightKg;

  String _activity = 'moderate';
  String _goal = 'maintain';

  WeightUnit get _unit => widget.preferences.weightUnit;

  @override
  void initState() {
    super.initState();
    // Both columns are CHECK-bounded (`weight_kg > 0 and <= 500`,
    // `height_cm > 0 and <= 300`), and this screen guarded only `> 0` — so a
    // typed 600 kg reached the insert as a raw 23514 naming a constraint and
    // no field (decisions § 792). Re-render on every keystroke so the error
    // appears under the field the moment it goes out of range, the same
    // moment the web card disables its Save.
    _heightCtl.addListener(_onFieldChanged);
    _weightCtl.addListener(_onFieldChanged);
    _load();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  /// The typed height, or null when the field is empty. Out-of-range values
  /// are returned rather than dropped — [_heightError] is what refuses them,
  /// so the runner is told rather than silently saved without a height.
  double? get _typedHeight => parseTypedDecimal(_heightCtl.text);
  double? get _typedWeightKg => WeightFormat.parseToKg(_weightCtl.text, _unit);

  bool get _heightError {
    final h = _typedHeight;
    return h != null && !withinColumnLimit(_heightKey, h);
  }

  bool get _weightError {
    final w = _typedWeightKg;
    return w != null && !withinColumnLimit(_weightKey, w);
  }

  @override
  void dispose() {
    _heightCtl.removeListener(_onFieldChanged);
    _weightCtl.removeListener(_onFieldChanged);
    _heightCtl.dispose();
    _weightCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _loadFailed = false;
    final settings = widget.settingsSync?.service;
    _activity =
        settings?.effective<String>(SettingsKeys.nutritionActivityLevel) ??
            'moderate';
    _goal = settings?.effective<String>(SettingsKeys.nutritionGoal) ?? 'maintain';
    final api = widget.api;
    if (api != null && api.userId != null) {
      try {
        final profile = await api.fetchMyProfile();
        _consentAt = profile?.healthDataConsentAt;
        _consent = _consentAt != null;
        final h = profile?.heightCm;
        if (h != null && h > 0) _heightCtl.text = h.toStringAsFixed(0);
        final w = await api.fetchLatestBodyWeightKg();
        _loadedWeightKg = w;
        if (w != null && w > 0) {
          _weightCtl.text = WeightFormat.toDisplay(w, _unit).toStringAsFixed(1);
        }
      } catch (e) {
        // Fail closed: a swallowed read leaves _consent false and
        // _consentAt/_loadedWeightKg null, which makes Save read as an Art
        // 7(3) withdrawal — skipping the confirm and erasing the height plus
        // the whole weight series of a user who never touched the toggle.
        debugPrint('settings_body_metrics: load failed: $e');
        _loadFailed = true;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _retryLoad() async {
    setState(() => _loading = true);
    await _load();
  }

  void _snack(String msg) {
    if (!mounted) return;
    showTopBanner(context, msg);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.api;
    if (api == null) return;
    // Checked here as well as on the button's disabled state so a value
    // outside the column's range cannot reach the insert through any other
    // path into this handler.
    if (_heightError || _weightError) {
      _snack(_heightError
          ? l10n.limitsHeightOutOfRange(
              _bound(columnMin(_heightKey)), _bound(columnMax(_heightKey)))
          : _weightRangeMessage(l10n));
      return;
    }
    final h = _typedHeight;
    final heightVal = (h != null && h > 0) ? h : null;
    final weightKg = _typedWeightKg;
    final weightVal = (weightKg != null && weightKg > 0) ? weightKg : null;

    if ((heightVal != null || weightVal != null) && !_consent) {
      _snack(l10n.bodyMetricsConsentRequired);
      return;
    }
    // Withdrawing consent erases the saved height + the entire weight
    // time-series (Art 7(3)) — irreversible, so confirm first.
    final withdrawing = !_consent && (_consentAt != null || _loadedWeightKg != null);
    if (withdrawing) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(l10n.bodyMetricsWithdrawTitle),
              content: Text(l10n.bodyMetricsWithdrawBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.prefsCancel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error),
                  child: Text(l10n.bodyMetricsWithdrawConfirm),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      if (_consent) {
        // First-stamp-wins: only call the consent RPC when not yet granted.
        if (_consentAt == null) {
          _consentAt = await api.grantHealthDataConsent();
        }
        await api.setMyHeightCm(heightVal);
        // Append a measurement only when it actually changed, so re-saving
        // the screen doesn't pad the body_metrics time-series.
        if (weightVal != null &&
            (_loadedWeightKg == null ||
                (weightVal - _loadedWeightKg!).abs() > 0.01)) {
          await api.recordBodyWeightKg(weightVal);
          _loadedWeightKg = weightVal;
        }
      } else {
        // Art 7(3) withdrawal: one RPC nulls consent + the Art 9 profile
        // columns (height, gender) and erases the weight series atomically.
        await api.withdrawHealthDataConsent();
        _consentAt = null;
        _loadedWeightKg = null;
        _heightCtl.clear();
        _weightCtl.clear();
        // Two DOB stores, two purposes (§ 718). The prefs-bag mirror is the
        // Art 9 health-use copy the coach + HR-max reads consume, so the
        // withdrawal clears it — leaving it behind kept withdrawn
        // special-category data feeding those reads. The `user_profiles`
        // column is the child-safety age record and this screen never
        // touches it: since § 721 the RPC leaves it standing, so there is
        // nothing to put back.
        await widget.settingsSync?.updateUniversal(
          <String, dynamic>{SettingsKeys.dateOfBirth: null},
        );
      }
      _snack(l10n.bodyMetricsSaved);
    } catch (e) {
      debugPrint('body metrics save failed: $e');
      _snack(l10n.bodyMetricsSaveFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// A bound rendered the way the field's own value reads: whole numbers
  /// without a `.0`, a converted one to a single decimal, both through the
  /// active locale's separator.
  static String _bound(num v) =>
      formatFixed(v.toDouble(), v == v.roundToDouble() ? 0 : 1, activeLocaleTag);

  String _weightRangeMessage(AppLocalizations l10n) {
    final b = WeightFormat.boundsIn(_weightKey, _unit);
    return l10n.limitsWeightOutOfRange(
        _bound(b.min), _bound(b.max), WeightFormat.label(_unit));
  }

  Future<void> _putBag(String key, String value) async {
    try {
      await widget.settingsSync?.updateUniversal(<String, dynamic>{key: value});
    } catch (e) {
      debugPrint('body metrics pref save failed: $e');
      if (mounted) _snack(AppLocalizations.of(context).bodyMetricsPrefSaveFailed(friendlyError(AppLocalizations.of(context), e)));
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
    if (picked != null) {
      _activity = picked;
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
    if (picked != null) {
      _goal = picked;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.bodyMetricsTitle)),
      body: _loading
          ? ListSkeleton(
              label: l10n.commonLoading,
              rows: 5,
              rowHeight: 56,
              hasLeading: false,
            )
          : _loadFailed
          ? ErrorState(
              message: l10n.bodyMetricsLoadError,
              onRetry: _retryLoad,
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                SwitchListTile(
                  title: Text(l10n.bodyMetricsConsentTitle),
                  subtitle: Text(l10n.bodyMetricsConsentSubtitle),
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v),
                ),
                if (_consent) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: TextField(
                      controller: _heightCtl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: l10n.bodyMetricsHeight,
                        suffixText: 'cm',
                        errorText: _heightError
                            ? l10n.limitsHeightOutOfRange(
                                _bound(columnMin(_heightKey)),
                                _bound(columnMax(_heightKey)))
                            : null,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      controller: _weightCtl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: l10n.bodyMetricsWeight,
                        suffixText: WeightFormat.label(_unit),
                        errorText:
                            _weightError ? _weightRangeMessage(l10n) : null,
                      ),
                    ),
                  ),
                ],
                ListTile(
                  title: Text(l10n.bodyMetricsActivityLevel),
                  subtitle: Text(activityLevelLabel(l10n, _activity)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickActivity,
                ),
                ListTile(
                  title: Text(l10n.bodyMetricsGoal),
                  subtitle: Text(weightGoalLabel(l10n, _goal)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickGoal,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    l10n.bodyMetricsTargetsHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton(
                    onPressed:
                        _saving || _heightError || _weightError ? null : _save,
                    child: Text(l10n.prefsSave),
                  ),
                ),
              ],
            ),
    );
  }
}
