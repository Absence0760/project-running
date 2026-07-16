import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../nutrition_targets.dart' show activityLevels, goalKcalDelta;
import '../preferences.dart';
import '../settings_sync.dart';
import '../widgets/top_banner.dart';

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

  bool _loading = true;
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
    _load();
  }

  @override
  void dispose() {
    _heightCtl.dispose();
    _weightCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
        debugPrint('settings_body_metrics: load failed: $e');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String msg) {
    if (!mounted) return;
    showTopBanner(context, msg);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.api;
    if (api == null) return;
    final hRaw = _heightCtl.text.trim().replaceAll(',', '.');
    final h = double.tryParse(hRaw);
    final heightVal = (h != null && h > 0) ? h : null;
    final weightKg = WeightFormat.parseToKg(_weightCtl.text, _unit);
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
        // columns and erases the weight series atomically.
        await api.withdrawHealthDataConsent();
        _consentAt = null;
        _loadedWeightKg = null;
        _heightCtl.clear();
        _weightCtl.clear();
      }
      _snack(l10n.bodyMetricsSaved);
    } catch (e) {
      debugPrint('body metrics save failed: $e');
      _snack(l10n.bodyMetricsSaveFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

  String _activityLabel(AppLocalizations l10n, String key) => switch (key) {
        'sedentary' => l10n.activitySedentary,
        'light' => l10n.activityLight,
        'active' => l10n.activityVeryActive,
        'very_active' => l10n.activityExtraActive,
        _ => l10n.activityModerate,
      };

  String _goalLabel(AppLocalizations l10n, String key) => switch (key) {
        'lose' => l10n.goalLose,
        'gain' => l10n.goalGain,
        _ => l10n.goalMaintain,
      };

  Future<void> _pickActivity() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pick(
      title: l10n.bodyMetricsActivityLevel,
      options: [for (final a in activityLevels) a.key],
      labels: [for (final a in activityLevels) _activityLabel(l10n, a.key)],
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
      labels: [for (final k in keys) _goalLabel(l10n, k)],
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
          ? const Center(child: CircularProgressIndicator())
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
                      ),
                    ),
                  ),
                ],
                ListTile(
                  title: Text(l10n.bodyMetricsActivityLevel),
                  subtitle: Text(_activityLabel(l10n, _activity)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickActivity,
                ),
                ListTile(
                  title: Text(l10n.bodyMetricsGoal),
                  subtitle: Text(_goalLabel(l10n, _goal)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickGoal,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    l10n.bodyMetricsTargetsHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(l10n.prefsSave),
                  ),
                ),
              ],
            ),
    );
  }
}
