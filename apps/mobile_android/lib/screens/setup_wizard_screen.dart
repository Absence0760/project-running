import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../locale_defaults.dart';
import '../onboarding.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import '../widgets/top_banner.dart';

/// Post-signup setup wizard — mobile twin of web's 7-step `/onboarding`
/// page. Shown once when a signed-in user's `user_profiles.onboarded_at`
/// is still null; stamps it on Finish or Skip so a returning user never
/// re-sees it. The home-screen gate ([SetupWizardScreen] is pushed by
/// `home_screen.dart`) owns the "show once" decision.
///
/// Distinct from `onboarding_screen.dart`, the FIRST-LAUNCH permission /
/// privacy flow keyed on the local `Preferences.onboarded` flag. This
/// wizard collects account-level setup data and writes the SAME fields
/// web collects (display name, units, goal, demographics + Art 9 consent,
/// privacy default, notifications).
class SetupWizardScreen extends StatefulWidget {
  final ApiClient apiClient;
  final Preferences preferences;
  final SettingsSyncService? settingsSync;

  /// The user's display name from the auth row, if the provider returned
  /// one — prefills the name field so the user can edit before continuing.
  final String? initialDisplayName;

  /// The user's explicitly chosen `preferred_unit` ('km' | 'mi'), if any,
  /// prefilled into the units toggle. Null when the user never picked one
  /// — the wizard then seeds from the device locale.
  final String? initialPreferredUnit;

  const SetupWizardScreen({
    super.key,
    required this.apiClient,
    required this.preferences,
    this.settingsSync,
    this.initialDisplayName,
    this.initialPreferredUnit,
  });

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  int _step = 0;

  final _displayNameCtl = TextEditingController();
  String _preferredUnit = 'km';
  String? _primaryGoal;
  String _gender = '';
  DateTime? _dateOfBirth;
  final _weightCtl = TextEditingController();
  bool _healthDataConsent = false;
  String _privacyDefault = 'private';
  // Mobile's notification control is the universal `push_notifications`
  // bag key (no native OS permission prompt to request here — unlike web
  // — so the wizard step sets the preference). Default 'important' matches
  // the bag default registered in settings.md.
  String _pushNotifications = 'important';

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDisplayName != null) {
      _displayNameCtl.text = widget.initialDisplayName!;
    }
    // Units step default: an explicit prior choice wins, otherwise the
    // device locale decides (mi for US/GB/LR/MM, km elsewhere) instead of
    // hard-coding km for every signup — mirrors web /onboarding's
    // `defaultUnitForLocale(navigator.language)` seed. The raw device
    // locale (not Localizations.localeOf) because the app's resolved
    // locale drops the region subtag the derivation needs.
    final unit = widget.initialPreferredUnit;
    _preferredUnit = (unit == 'km' || unit == 'mi')
        ? unit!
        : defaultUnitForLocale(WidgetsBinding
            .instance.platformDispatcher.locale
            .toLanguageTag());
  }

  @override
  void dispose() {
    _displayNameCtl.dispose();
    _weightCtl.dispose();
    super.dispose();
  }

  bool get _isLastStep => _step == onboardingTotalSteps - 1;

  void _next() {
    if (_step < onboardingTotalSteps - 1) setState(() => _step += 1);
  }

  void _back() {
    if (_step > 0) setState(() => _step -= 1);
  }

  /// Skip-onboarding header link. Stamps `onboarded_at = now()` only — the
  /// minimum required for the gate to stop re-showing the wizard. Every
  /// other field stays at its existing default. Mirrors web's
  /// `skipOnboarding`.
  Future<void> _skip() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      await widget.apiClient.markOnboarded();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTopBanner(context, l10n.setupSaveError(e.toString()));
    }
  }

  /// Final "Open dashboard". Persists every answer, stamps `onboarded_at`.
  /// Mirrors web's `finishAndExit`. When [createPlan] is set (the goal-keyed
  /// "create my training plan" CTA), pops with the chosen `primary_goal` so
  /// the home screen can route straight into the plan wizard preselected.
  Future<void> _finish({bool createPlan = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      // 1. Profile columns + Art 9 consent stamp (the api_client method
      // owns the consent-gating: gender + consent only under the toggle,
      // DOB written unconditionally for the minor-exclusion floor).
      await widget.apiClient.completeOnboarding(
        displayName: _displayNameCtl.text,
        preferredUnit: _preferredUnit,
        dateOfBirth: _dateOfBirth,
        gender: _gender,
        healthDataConsent: _healthDataConsent,
      );

      // 2. Universal-prefs bag (units + privacy + goal + weight + the
      // consent-gated DOB mirror). Best-effort + locally mirrored where a
      // local pref exists, so the privacy default protects new-run
      // visibility immediately even if the bag write fails offline.
      _preferredUnit == 'mi'
          ? widget.preferences.setUseMiles(true)
          : widget.preferences.setUseMiles(false);
      await widget.preferences.setPrivacyDefault(_privacyDefault);

      final bag = <String, dynamic>{
        SettingsKeys.preferredUnit: _preferredUnit,
        SettingsKeys.privacyDefault: _privacyDefault,
        SettingsKeys.pushNotifications: _pushNotifications,
      };
      if (_primaryGoal != null) bag[SettingsKeys.primaryGoal] = _primaryGoal;
      final w = double.tryParse(_weightCtl.text.trim().replaceAll(',', '.'));
      if (w != null && w > 0) bag[SettingsKeys.bodyWeightKg] = w;
      // DOB mirrors into the bag only under health consent — the bag copy
      // feeds the coach / leaderboard read paths (Art 9 surfaces). The
      // minor-exclusion floor reads the profile column written above, not
      // the bag, so the child-safety write doesn't depend on this mirror.
      if (_healthDataConsent && _dateOfBirth != null) {
        bag[SettingsKeys.dateOfBirth] =
            ApiClient.dateOnly(_dateOfBirth!);
      }
      try {
        await widget.settingsSync?.updateUniversal(bag);
      } catch (e) {
        debugPrint('onboarding bag write failed (kept local): $e');
      }

      if (!mounted) return;
      showTopBanner(context, l10n.setupWelcomeToast);
      Navigator.of(context).pop(createPlan ? _primaryGoal : null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTopBanner(context, l10n.setupSaveError(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return PopScope(
      // The gate decides when the wizard shows; a swipe-back would leave
      // onboarded_at null and re-trigger it next launch. Force a choice
      // (Finish or Skip).
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.setupPageTitle),
          actions: [
            TextButton(
              onPressed: _saving ? null : _skip,
              child: Text(l10n.setupSkip),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _ProgressDots(step: _step, total: onboardingTotalSteps),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 8),
                  child: _buildStep(theme, l10n),
                ),
              ),
              _buildNav(l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(ThemeData theme, AppLocalizations l10n) {
    switch (_step) {
      case 0:
        return _stepShell(
          theme,
          title: l10n.setupNameTitle,
          hint: l10n.setupNameHint,
          child: TextField(
            controller: _displayNameCtl,
            maxLength: 60,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.setupNameLabel,
              hintText: l10n.setupNamePlaceholder,
              border: const OutlineInputBorder(),
            ),
          ),
        );
      case 1:
        return _stepShell(
          theme,
          title: l10n.setupUnitsTitle,
          hint: l10n.setupUnitsHint,
          child: Column(
            children: [
              _OptionCard(
                selected: _preferredUnit == 'km',
                title: l10n.setupUnitKm,
                subtitle: l10n.setupUnitKmSample,
                onTap: () => setState(() => _preferredUnit = 'km'),
              ),
              _OptionCard(
                selected: _preferredUnit == 'mi',
                title: l10n.setupUnitMi,
                subtitle: l10n.setupUnitMiSample,
                onTap: () => setState(() => _preferredUnit = 'mi'),
              ),
            ],
          ),
        );
      case 2:
        return _stepShell(
          theme,
          title: l10n.setupGoalTitle,
          hint: l10n.setupGoalHint,
          child: Column(
            children: [
              for (final g in primaryGoalValues)
                _OptionCard(
                  selected: _primaryGoal == g,
                  title: _goalLabel(l10n, g),
                  onTap: () => setState(() => _primaryGoal = g),
                ),
            ],
          ),
        );
      case 3:
        return _buildAboutYou(theme, l10n);
      case 4:
        return _stepShell(
          theme,
          title: l10n.setupPrivacyTitle,
          hint: l10n.setupPrivacyHint,
          child: Column(
            children: [
              _OptionCard(
                selected: _privacyDefault == 'private',
                title: l10n.privacyPrivateTitle,
                subtitle: l10n.privacyPrivateSubtitle,
                onTap: () => setState(() => _privacyDefault = 'private'),
              ),
              _OptionCard(
                selected: _privacyDefault == 'followers',
                title: l10n.privacyFollowersTitle,
                subtitle: l10n.privacyFollowersSubtitle,
                onTap: () => setState(() => _privacyDefault = 'followers'),
              ),
              _OptionCard(
                selected: _privacyDefault == 'public',
                title: l10n.privacyPublicTitle,
                subtitle: l10n.privacyPublicSubtitle,
                onTap: () => setState(() => _privacyDefault = 'public'),
              ),
            ],
          ),
        );
      case 5:
        return _stepShell(
          theme,
          title: l10n.setupNotificationsTitle,
          hint: l10n.setupNotificationsHint,
          child: Column(
            children: [
              _OptionCard(
                selected: _pushNotifications == 'important',
                title: l10n.prefsPushNotifImportant,
                onTap: () =>
                    setState(() => _pushNotifications = 'important'),
              ),
              _OptionCard(
                selected: _pushNotifications == 'all',
                title: l10n.prefsPushNotifAll,
                onTap: () => setState(() => _pushNotifications = 'all'),
              ),
              _OptionCard(
                selected: _pushNotifications == 'off',
                title: l10n.prefsPushNotifOff,
                onTap: () => setState(() => _pushNotifications = 'off'),
              ),
            ],
          ),
        );
      default:
        return _stepShell(
          theme,
          title: l10n.setupDoneTitle,
          // When a goal was picked the body hosts the primary "Create my
          // training plan" CTA, so the hint names that action; otherwise
          // "Open dashboard" in the nav is the primary and the hint names it.
          hint: _primaryGoal == null ? l10n.setupDoneHint : l10n.setupDoneHintGoal,
          // A goal-keyed CTA into the plan wizard (runner-new discoverability
          // nudge) when the runner picked a goal; a plain finish otherwise.
          child: _primaryGoal == null
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _saving ? null : () => _finish(createPlan: true),
                    child: Text(_saving
                        ? l10n.setupSaving
                        : l10n.setupCreatePlanCta),
                  ),
                ),
        );
    }
  }

  Widget _buildAboutYou(ThemeData theme, AppLocalizations l10n) {
    return _stepShell(
      theme,
      title: l10n.setupAboutTitle,
      hint: l10n.setupAboutHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _gender,
            decoration: InputDecoration(
              labelText: l10n.setupGenderLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: '', child: Text(l10n.setupGenderPreferNot)),
              DropdownMenuItem(
                  value: 'female', child: Text(l10n.setupGenderFemale)),
              DropdownMenuItem(
                  value: 'male', child: Text(l10n.setupGenderMale)),
              DropdownMenuItem(
                  value: 'nonbinary', child: Text(l10n.setupGenderNonbinary)),
            ],
            onChanged: (v) => setState(() => _gender = v ?? ''),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDob,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.setupDobLabel,
                helperText: l10n.setupDobNote,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
              child: Text(
                _dateOfBirth == null
                    ? l10n.setupDobPlaceholder
                    : ApiClient.dateOnly(_dateOfBirth!),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _weightCtl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.setupWeightLabel,
              hintText: l10n.setupWeightPlaceholder,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_gender.isNotEmpty || _dateOfBirth != null) ...[
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _healthDataConsent,
              onChanged: (v) =>
                  setState(() => _healthDataConsent = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.setupHealthConsent,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Widget _stepShell(
    ThemeData theme, {
    required String title,
    required String hint,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.outline, height: 1.5),
        ),
        const SizedBox(height: 20),
        child,
      ],
    );
  }

  Widget _buildNav(AppLocalizations l10n) {
    final showSkipStep = _step == 0 || _step == 2 || _step == 3 || _step == 5;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (_step > 0)
            OutlinedButton(
              onPressed: _saving ? null : _back,
              child: Text(l10n.setupBack),
            ),
          const Spacer(),
          if (!_isLastStep && showSkipStep)
            TextButton(
              onPressed: _saving ? null : _next,
              child: Text(l10n.setupSkipStep),
            ),
          const SizedBox(width: 8),
          if (!_isLastStep)
            FilledButton(
              onPressed: _saving ? null : _next,
              child: Text(l10n.setupContinue),
            )
          // On the final step, when the runner picked a goal the body hosts
          // the primary "Create my training plan" CTA — so "Open dashboard"
          // demotes to a secondary action here to avoid two competing primary
          // buttons. With no goal, finishing is the one primary action.
          else if (_primaryGoal == null)
            FilledButton(
              onPressed: _saving ? null : _finish,
              child: Text(_saving ? l10n.setupSaving : l10n.setupOpenDashboard),
            )
          else
            OutlinedButton(
              onPressed: _saving ? null : _finish,
              child: Text(l10n.setupOpenDashboard),
            ),
        ],
      ),
    );
  }

  String _goalLabel(AppLocalizations l10n, String g) => switch (g) {
        'weight_loss' => l10n.setupGoalWeightLoss,
        '5k' => l10n.setupGoal5k,
        '10k' => l10n.setupGoal10k,
        'half_marathon' => l10n.setupGoalHalf,
        'marathon' => l10n.setupGoalMarathon,
        _ => l10n.setupGoalGeneralFitness,
      };
}

class _ProgressDots extends StatelessWidget {
  final int step;
  final int total;
  const _ProgressDots({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final active = i == step;
          final done = i < step;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active
                  ? theme.colorScheme.primary
                  : done
                      ? theme.colorScheme.primary.withValues(alpha: 0.5)
                      : theme.colorScheme.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _OptionCard({
    required this.selected,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withValues(alpha: 0.25),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
