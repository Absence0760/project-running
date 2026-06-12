import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../goals.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../main.dart' show themeModeNotifier, localeNotifier;
import '../preferences.dart';
import '../settings_sync.dart';
import 'settings_body_metrics_screen.dart';

class SettingsPreferencesScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final Preferences preferences;
  final SettingsSyncService? settingsSync;

  const SettingsPreferencesScreen({
    super.key,
    this.apiClient,
    required this.preferences,
    required this.settingsSync,
  });

  @override
  State<SettingsPreferencesScreen> createState() =>
      _SettingsPreferencesScreenState();
}

class _SettingsPreferencesScreenState extends State<SettingsPreferencesScreen> {
  bool _darkMode = themeModeNotifier.value == ThemeMode.dark;
  bool _localeBackfillDone = false;

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onChange);
    widget.settingsSync?.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeBackfillLocale());
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onChange);
    widget.settingsSync?.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
    _maybeBackfillLocale();
  }

  String _unitSubtitle() {
    final l10n = AppLocalizations.of(context);
    final base =
        widget.preferences.useMiles ? l10n.prefsUnitImperial : l10n.prefsUnitMetric;
    final sync = widget.settingsSync;
    if (sync == null || !sync.synced) return base;
    return l10n.prefsSyncedSuffix(base);
  }

  static String _splitIntervalLabel(int metres, DistanceUnit unit) {
    if (unit == DistanceUnit.mi) {
      final miles = metres / 1609.344;
      if ((miles - miles.roundToDouble()).abs() < 0.01) {
        return '${miles.round()} mi';
      }
      return '${formatFixed(miles, 1, activeLocaleTag)} mi';
    }
    if (metres >= 1000 && metres % 1000 == 0) {
      return '${metres ~/ 1000} km';
    }
    return '${metres}m';
  }

  Future<void> _editSplitInterval() async {
    final l10n = AppLocalizations.of(context);
    final prefs = widget.preferences;
    final options = prefs.useMiles
        ? <int>[0, 805, 1609, 3219, 8047]
        : <int>[0, 500, 1000, 2000, 5000];
    final labels = prefs.useMiles
        ? [l10n.prefsSplitIntervalDefault, '0.5 mi', '1 mi', '2 mi', '5 mi']
        : [l10n.prefsSplitIntervalDefault, '500m', '1 km', '2 km', '5 km'];

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.prefsSplitInterval),
        children: [
          for (var i = 0; i < options.length; i++)
            RadioListTile<int>(
              title: Text(labels[i]),
              value: options[i],
              groupValue: prefs.splitIntervalMetres,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
    if (result != null) {
      await prefs.setSplitIntervalMetres(result);
      await widget.settingsSync?.pushSplitInterval();
    }
  }

  Future<void> _editTargetPace() async {
    final l10n = AppLocalizations.of(context);
    final prefs = widget.preferences;
    final current = prefs.targetPaceSecPerKm;
    final mCtl =
        TextEditingController(text: '${current > 0 ? current ~/ 60 : 5}');
    final sCtl =
        TextEditingController(text: '${current > 0 ? current % 60 : 30}');

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.prefsLivePaceAlert),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 60,
              child: TextField(
                controller: mCtl,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: l10n.prefsLivePaceAlertMin),
                textAlign: TextAlign.center,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(':', style: TextStyle(fontSize: 20)),
            ),
            SizedBox(
              width: 60,
              child: TextField(
                controller: sCtl,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: l10n.prefsLivePaceAlertSec),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: Text(l10n.prefsClear),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l10n.prefsCancel),
          ),
          FilledButton(
            onPressed: () {
              final m = int.tryParse(mCtl.text) ?? 0;
              final s = int.tryParse(sCtl.text) ?? 0;
              Navigator.pop(ctx, m * 60 + s);
            },
            child: Text(l10n.prefsSave),
          ),
        ],
      ),
    );
    if (result != null) await prefs.setTargetPaceSecPerKm(result);
  }

  static String _toTitle(String raw) => raw
      .split('_')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  static String _activityTypeLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'run':
        return l10n.prefsActivityRun;
      case 'walk':
        return l10n.prefsActivityWalk;
      case 'hike':
        return l10n.prefsActivityHike;
      case 'cycle':
        return l10n.prefsActivityCycle;
      default:
        return _toTitle(raw);
    }
  }

  static String _paceFormatLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'min_per_km':
        return l10n.prefsPaceFormatMinPerKm;
      case 'min_per_mi':
        return l10n.prefsPaceFormatMinPerMi;
      case 'kph':
        return l10n.prefsPaceFormatKph;
      case 'mph':
        return l10n.prefsPaceFormatMph;
      default:
        return _toTitle(raw);
    }
  }

  static String _mapStyleLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'streets':
        return l10n.prefsMapStyleStreets;
      case 'satellite':
        return l10n.prefsMapStyleSatellite;
      case 'outdoors':
        return l10n.prefsMapStyleOutdoors;
      case 'dark':
        return l10n.prefsMapStyleDark;
      default:
        return _toTitle(raw);
    }
  }

  static String _weekStartLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'monday':
        return l10n.prefsWeekStartMonday;
      case 'sunday':
        return l10n.prefsWeekStartSunday;
      default:
        return _toTitle(raw);
    }
  }

  static String _privacyLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'public':
        return l10n.privacyPublicTitle;
      case 'followers':
        return l10n.privacyFollowersTitle;
      case 'private':
        return l10n.privacyPrivateTitle;
      default:
        return _toTitle(raw);
    }
  }

  static String _coachLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'supportive':
        return l10n.prefsCoachSupportive;
      case 'drill_sergeant':
        return l10n.prefsCoachDrillSergeant;
      case 'analytical':
        return l10n.prefsCoachAnalytical;
      default:
        return _toTitle(raw);
    }
  }

  static String _emailNotifLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'all':
        return l10n.prefsEmailNotifAll;
      case 'important':
        return l10n.prefsEmailNotifImportant;
      case 'off':
        return l10n.prefsEmailNotifOff;
      default:
        return _toTitle(raw);
    }
  }

  String _hrZonesSummary() {
    final l10n = AppLocalizations.of(context);
    final raw = _bagValue<Map>(SettingsKeys.hrZones);
    if (raw == null) return l10n.prefsNotSet;
    final vals = ['z1', 'z2', 'z3', 'z4', 'z5']
        .map((k) => raw[k])
        .whereType<num>()
        .map((n) => n.round().toString())
        .toList();
    if (vals.isEmpty) return l10n.prefsNotSet;
    return l10n.prefsHrZonesSummary(vals.join(' · '));
  }

  String _weeklyGoalSummary() {
    final l10n = AppLocalizations.of(context);
    final metres =
        _bagValue<num>(SettingsKeys.weeklyMileageGoalMetres)?.toDouble();
    if (metres == null) return l10n.prefsNotSet;
    final useMiles = widget.preferences.useMiles;
    final display = useMiles ? metres / 1609.344 : metres / 1000;
    return l10n.prefsWeeklyGoalSummary(
      formatFixed(display, display < 10 ? 1 : 0, activeLocaleTag),
      useMiles ? 'mi' : 'km',
    );
  }

  /// The bag-backed tiles light up as soon as the [SettingsSyncService]
  /// reports `synced`. With an on-disk cache in play (the default on
  /// production builds) this now becomes true on cache hit, not only
  /// after a successful server round-trip — so an airplane-mode
  /// signed-in user can still read + write every prefs key.
  bool get _bagReady => widget.settingsSync?.synced == true;

  T? _bagValue<T>(String key) =>
      widget.settingsSync?.service?.effective<T>(key);

  Future<void> _putUniversal(String key, dynamic value) async {
    await widget.settingsSync?.updateUniversal(<String, dynamic>{key: value});
    if (mounted) setState(() {});
  }

  Future<T?> _pickRadio<T>({
    required String title,
    required List<T> options,
    required List<String> labels,
    required T? current,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (var i = 0; i < options.length; i++)
            RadioListTile<T>(
              title: Text(labels[i]),
              value: options[i],
              groupValue: current,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
  }

  Future<int?> _pickInt({
    required String title,
    required int? current,
    required String suffix,
    int minValue = 0,
    int maxValue = 1 << 30,
    bool allowClear = true,
  }) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: current == null ? '' : '$current',
    );
    return showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(suffixText: suffix),
          autofocus: true,
        ),
        actions: [
          if (allowClear)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: Text(l10n.prefsClear),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l10n.prefsCancel),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < minValue || v > maxValue) {
                Navigator.pop(ctx, null);
              } else {
                Navigator.pop(ctx, v);
              }
            },
            child: Text(l10n.prefsSave),
          ),
        ],
      ),
    );
  }

  Future<double?> _pickDouble({
    required String title,
    required double? current,
    required String suffix,
    double minValue = 0,
    double maxValue = double.infinity,
    bool allowClear = true,
  }) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: current == null ? '' : '$current',
    );
    return showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: suffix),
          autofocus: true,
        ),
        actions: [
          if (allowClear)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1.0),
              child: Text(l10n.prefsClear),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l10n.prefsCancel),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              if (v == null || v < minValue || v > maxValue) {
                Navigator.pop(ctx, null);
              } else {
                Navigator.pop(ctx, v);
              }
            },
            child: Text(l10n.prefsSave),
          ),
        ],
      ),
    );
  }

  Future<void> _editDefaultActivityType() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['run', 'walk', 'hike', 'cycle'];
    final labels = [
      l10n.prefsActivityRun,
      l10n.prefsActivityWalk,
      l10n.prefsActivityHike,
      l10n.prefsActivityCycle,
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsDefaultActivity,
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.defaultActivityType) ?? 'run',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.defaultActivityType, picked);
      await widget.preferences.setDefaultActivityType(picked);
    }
  }

  Future<void> _editWeightUnit() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['kg', 'lbs'];
    final labels = [l10n.prefsWeightUnitKg, l10n.prefsWeightUnitLbs];
    final picked = await _pickRadio<String>(
      title: l10n.prefsWeightUnit,
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.weightUnit) ?? 'kg',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.weightUnit, picked);
      await widget.preferences.setWeightUnit(WeightFormat.unitFromWire(picked));
    }
  }

  String _weightUnitLabel(AppLocalizations l10n, String raw) =>
      raw == 'lbs' ? l10n.prefsWeightUnitLbs : l10n.prefsWeightUnitKg;

  Future<void> _editLanguage() async {
    final t = AppLocalizations.of(context);
    // '' is the "follow device locale" sentinel; the rest are canonical tags.
    const tags = ['', 'en', 'de', 'fr', 'es', 'ja', 'pt-BR'];
    final labels = [
      t.prefsLanguageSystem,
      localeLabels['en']!,
      localeLabels['de']!,
      localeLabels['fr']!,
      localeLabels['es']!,
      localeLabels['ja']!,
      localeLabels['pt-BR']!,
    ];
    final current = widget.preferences.locale == null
        ? ''
        : localeToTag(widget.preferences.locale!);
    final picked = await _pickRadio<String>(
      title: t.prefsLanguage,
      options: tags,
      labels: labels,
      current: current,
    );
    if (picked == null) return;
    final next = picked.isEmpty ? null : localeFromTag(picked);
    await widget.preferences.setLocale(next);
    localeNotifier.value = next;
    // Mirror the applied locale into the universal bag so the worker can
    // localize email (decisions §120). For "follow device" (empty pick),
    // resolve the concrete tag the device negotiates to. The per-device UI
    // locale above stays the source of truth for what THIS device shows.
    final tag = picked.isEmpty
        ? resolveActiveLocaleTag(
            null, WidgetsBinding.instance.platformDispatcher.locales)
        : picked;
    await _putUniversal(SettingsKeys.locale, tag);
    if (mounted) setState(() {});
  }

  // One-shot backfill: when the bag has no `locale` yet, persist the active
  // locale so a user who never opens the language picker still gets email in
  // their language (decisions §120). Gated on a real settings service (the
  // server-backed bag) so it no-ops in widget tests with a stubbed sync.
  void _maybeBackfillLocale() {
    if (_localeBackfillDone) return;
    final sync = widget.settingsSync;
    final svc = sync?.service;
    if (sync == null || !sync.synced || svc == null) return; // not ready; retry on next change
    _localeBackfillDone = true;
    if (svc.effective<String>(SettingsKeys.locale) != null) return; // already set
    final tag = resolveActiveLocaleTag(
        widget.preferences.locale, WidgetsBinding.instance.platformDispatcher.locales);
    _putUniversal(SettingsKeys.locale, tag);
  }

  Future<void> _editMapStyle() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['streets', 'satellite', 'outdoors', 'dark'];
    final labels = [
      l10n.prefsMapStyleStreets,
      l10n.prefsMapStyleSatellite,
      l10n.prefsMapStyleOutdoors,
      l10n.prefsMapStyleDark,
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsMapStyle,
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.mapStyle) ?? 'streets',
    );
    if (picked != null) await _putUniversal(SettingsKeys.mapStyle, picked);
  }

  Future<void> _editPaceFormat() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['min_per_km', 'min_per_mi', 'kph', 'mph'];
    final labels = [
      l10n.prefsPaceFormatMinPerKm,
      l10n.prefsPaceFormatMinPerMi,
      l10n.prefsPaceFormatKph,
      l10n.prefsPaceFormatMph,
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsPaceFormat,
      options: opts,
      labels: labels,
      current:
          _bagValue<String>(SettingsKeys.unitsPaceFormat) ?? 'min_per_km',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.unitsPaceFormat, picked);
    }
  }

  Future<void> _editPrivacyDefault() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['public', 'followers', 'private'];
    final labels = [
      l10n.privacyPublicTitle,
      l10n.privacyFollowersTitle,
      l10n.privacyPrivateTitle,
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsDefaultRunVisibility,
      options: opts,
      labels: labels,
      current:
          _bagValue<String>(SettingsKeys.privacyDefault) ?? 'followers',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.privacyDefault, picked);
    }
  }

  Future<void> _editCoachPersonality() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['supportive', 'drill_sergeant', 'analytical'];
    final labels = [
      l10n.prefsCoachSupportive,
      l10n.prefsCoachDrillSergeant,
      l10n.prefsCoachAnalytical,
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsCoachPersonality,
      options: opts,
      labels: labels,
      current:
          _bagValue<String>(SettingsKeys.coachPersonality) ?? 'supportive',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.coachPersonality, picked);
    }
  }

  Future<void> _editEmailNotifications() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['important', 'all', 'off'];
    final labels = [
      l10n.prefsEmailNotifImportant,
      l10n.prefsEmailNotifAll,
      l10n.prefsEmailNotifOff,
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsEmailNotifications,
      options: opts,
      labels: labels,
      current:
          _bagValue<String>(SettingsKeys.emailNotifications) ?? 'important',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.emailNotifications, picked);
    }
  }

  Future<void> _editEmailWeeklyDigest() async {
    // Opt-IN consent stored as 'on'|'off' (default 'off'); deliberately a
    // separate key from the transactional email_notifications.
    final on = _bagValue<String>(SettingsKeys.emailWeeklyDigest) == 'on';
    await _putUniversal(SettingsKeys.emailWeeklyDigest, on ? 'off' : 'on');
  }

  Future<void> _editWeekStartDay() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['monday', 'sunday'];
    final labels = [l10n.prefsWeekStartMonday, l10n.prefsWeekStartSunday];
    final picked = await _pickRadio<String>(
      title: l10n.prefsWeekStart,
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.weekStartDay) ?? 'monday',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.weekStartDay, picked);
    }
  }

  Future<void> _editStravaAutoShare() async {
    final current = _bagValue<bool>(SettingsKeys.stravaAutoShare) ?? false;
    await _putUniversal(SettingsKeys.stravaAutoShare, !current);
  }

  Future<void> _editDiscoverableInSearch() async {
    final current =
        _bagValue<bool>(SettingsKeys.discoverableInSearch) ?? true;
    await _putUniversal(SettingsKeys.discoverableInSearch, !current);
  }

  Future<void> _editExcludeGymFromReadiness() async {
    final current =
        _bagValue<bool>(SettingsKeys.excludeGymFromReadiness) ?? false;
    await _putUniversal(SettingsKeys.excludeGymFromReadiness, !current);
  }

  Future<void> _editDateOfBirth() async {
    final raw = _bagValue<String>(SettingsKeys.dateOfBirth);
    final current = raw != null ? DateTime.tryParse(raw) : null;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      helpText: AppLocalizations.of(context).prefsDateOfBirth,
    );
    if (picked == null) return;
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    await _putUniversal(SettingsKeys.dateOfBirth, iso);
  }

  Future<void> _editRestingHr() async {
    final picked = await _pickInt(
      title: AppLocalizations.of(context).prefsRestingHr,
      current: _bagValue<num>(SettingsKeys.restingHrBpm)?.round(),
      suffix: 'bpm',
      minValue: 20,
      maxValue: 200,
    );
    if (picked == null) return;
    await _putUniversal(
      SettingsKeys.restingHrBpm,
      picked == -1 ? null : picked,
    );
  }

  Future<void> _editMaxHr() async {
    final picked = await _pickInt(
      title: AppLocalizations.of(context).prefsMaxHr,
      current: _bagValue<num>(SettingsKeys.maxHrBpm)?.round(),
      suffix: 'bpm',
      minValue: 80,
      maxValue: 240,
    );
    if (picked == null) return;
    await _putUniversal(
      SettingsKeys.maxHrBpm,
      picked == -1 ? null : picked,
    );
  }

  Future<void> _editHrZones() async {
    final l10n = AppLocalizations.of(context);
    final current = _bagValue<Map>(SettingsKeys.hrZones);
    int? z(String k) {
      final v = current?[k];
      return v is num ? v.round() : null;
    }

    final controllers = <String, TextEditingController>{
      for (final k in const ['z1', 'z2', 'z3', 'z4', 'z5'])
        k: TextEditingController(text: z(k)?.toString() ?? ''),
    };
    final result = await showDialog<Map<String, int>?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.prefsHrZonesDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in controllers.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: entry.value,
                  keyboardType: TextInputType.number,
                  decoration:
                      InputDecoration(labelText: entry.key.toUpperCase()),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, <String, int>{}),
            child: Text(l10n.prefsClear),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l10n.prefsCancel),
          ),
          FilledButton(
            onPressed: () {
              final out = <String, int>{};
              for (final entry in controllers.entries) {
                final v = int.tryParse(entry.value.text.trim());
                if (v != null && v > 0) out[entry.key] = v;
              }
              Navigator.pop(ctx, out);
            },
            child: Text(l10n.prefsSave),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _putUniversal(
      SettingsKeys.hrZones,
      result.isEmpty ? null : result,
    );
  }

  Future<void> _editWeeklyGoal() async {
    final current =
        _bagValue<num>(SettingsKeys.weeklyMileageGoalMetres)?.toDouble();
    final useMiles = widget.preferences.useMiles;
    final currentDisplay = current == null
        ? null
        : (useMiles ? current / 1609.344 : current / 1000);
    final picked = await _pickDouble(
      title: AppLocalizations.of(context).prefsWeeklyGoal,
      current: currentDisplay,
      suffix: useMiles ? 'mi' : 'km',
      minValue: 0.1,
      maxValue: 500,
    );
    if (picked == null) return;
    if (picked == -1.0) {
      await _putUniversal(SettingsKeys.weeklyMileageGoalMetres, null);
      final existing = widget.preferences.goals.firstWhere(
        (g) => g.period == GoalPeriod.week && g.distanceMetres != null,
        orElse: () => const RunGoal(id: '', period: GoalPeriod.week),
      );
      if (existing.id.isNotEmpty) {
        await widget.preferences.removeGoal(existing.id);
      }
    } else {
      final metres = useMiles ? picked * 1609.344 : picked * 1000;
      await _putUniversal(
        SettingsKeys.weeklyMileageGoalMetres,
        metres.round(),
      );
      final existing = widget.preferences.goals.firstWhere(
        (g) => g.period == GoalPeriod.week && g.distanceMetres != null,
        orElse: () => const RunGoal(id: '', period: GoalPeriod.week),
      );
      await widget.preferences.upsertGoal(RunGoal(
        id: existing.id.isEmpty ? newGoalId() : existing.id,
        period: GoalPeriod.week,
        distanceMetres: metres,
        title: existing.title,
        timeSeconds: existing.timeSeconds,
        avgPaceSecPerKm: existing.avgPaceSecPerKm,
        runCount: existing.runCount,
      ));
    }
  }

  Widget _sectionLabel(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.8,
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = widget.preferences;
    final offlineNotice = widget.settingsSync?.synced == true &&
            widget.settingsSync?.service?.isServerHydrated == false
        ? widget.settingsSync?.lastError
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.prefsTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            if (offlineNotice != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        offlineNotice,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            _sectionLabel(AppLocalizations.of(context).prefsSectionUnitsDisplay),
            ListTile(
              title: Text(AppLocalizations.of(context).prefsLanguage),
              subtitle: Text(
                widget.preferences.locale == null
                    ? AppLocalizations.of(context).prefsLanguageSystem
                    : localeLabels[localeToTag(widget.preferences.locale!)] ??
                        '—',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editLanguage,
            ),
            SwitchListTile(
              title: Text(l10n.prefsUseMiles),
              subtitle: Text(_unitSubtitle()),
              value: prefs.useMiles,
              onChanged: (v) async {
                await prefs.setUseMiles(v);
                await widget.settingsSync?.pushPreferredUnit();
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              title: Text(l10n.prefsPaceFormat),
              subtitle: Text(_paceFormatLabel(
                l10n,
                _bagValue<String>(SettingsKeys.unitsPaceFormat) ?? 'min_per_km',
              )),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editPaceFormat,
            ),
            ListTile(
              title: Text(l10n.prefsWeightUnit),
              subtitle: Text(_weightUnitLabel(
                l10n,
                _bagValue<String>(SettingsKeys.weightUnit) ?? 'kg',
              )),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editWeightUnit,
            ),
            ListTile(
              title: Text(l10n.prefsMapStyle),
              subtitle: Text(
                _mapStyleLabel(
                    l10n, _bagValue<String>(SettingsKeys.mapStyle) ?? 'streets'),
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editMapStyle,
            ),
            SwitchListTile(
              title: Text(l10n.prefsDarkMode),
              value: _darkMode,
              onChanged: (v) {
                final mode = v ? ThemeMode.dark : ThemeMode.light;
                setState(() => _darkMode = v);
                themeModeNotifier.value = mode;
                widget.preferences.setThemeMode(mode);
              },
            ),

            _sectionLabel(l10n.prefsSectionActivityRecording),
            ListTile(
              title: Text(l10n.prefsDefaultActivity),
              subtitle: Text(_activityTypeLabel(
                l10n,
                _bagValue<String>(SettingsKeys.defaultActivityType) ?? 'run',
              )),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editDefaultActivityType,
            ),
            SwitchListTile(
              title: Text(l10n.prefsAudioCues),
              subtitle: Text(l10n.prefsAudioCuesSubtitle),
              value: prefs.audioCues,
              onChanged: (v) async {
                await prefs.setAudioCues(v);
                await widget.settingsSync?.pushAudioCues();
              },
            ),
            if (prefs.audioCues)
              SwitchListTile(
                title: Text(l10n.prefsMinimalVoiceCues),
                subtitle: Text(l10n.prefsMinimalVoiceCuesSubtitle),
                value: prefs.voiceFeedbackVerbosity == 'minimal',
                onChanged: (v) async {
                  final value = v ? 'minimal' : 'full';
                  await prefs.setVoiceFeedbackVerbosity(value);
                  await widget.settingsSync?.updateUniversal(
                    <String, dynamic>{SettingsKeys.voiceFeedbackVerbosity: value},
                  );
                },
              ),
            ListTile(
              title: Text(l10n.prefsSplitInterval),
              subtitle: Text(
                prefs.splitIntervalMetres > 0
                    ? _splitIntervalLabel(prefs.splitIntervalMetres, prefs.unit)
                    : l10n.prefsSplitIntervalDefaultSubtitle,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editSplitInterval,
            ),
            ListTile(
              title: Text(l10n.prefsLivePaceAlert),
              subtitle: Text(
                prefs.targetPaceSecPerKm > 0
                    ? l10n.prefsLivePaceAlertOn(
                        UnitFormat.pace(
                            prefs.targetPaceSecPerKm.toDouble(), prefs.unit),
                        UnitFormat.paceLabel(prefs.unit),
                      )
                    : l10n.prefsLivePaceAlertOff,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editTargetPace,
            ),
            SwitchListTile(
              title: Text(l10n.prefsKeepScreenOn),
              subtitle: Text(l10n.prefsKeepScreenOnSubtitle),
              value: prefs.keepScreenOn,
              onChanged: (v) async {
                await prefs.setKeepScreenOn(v);
                await widget.settingsSync?.pushKeepScreenOn();
              },
            ),
            SwitchListTile(
              title: Text(l10n.prefsAdvancedGps),
              subtitle: Text(l10n.prefsAdvancedGpsSubtitle),
              value: prefs.advancedGps,
              onChanged: prefs.setAdvancedGps,
            ),
            // multi_modal.md § "Protect the core runner": a pure runner can
            // keep the centre Log button as a one-tap run start (long-press
            // still opens the full capture sheet).
            SwitchListTile(
              title: Text(l10n.prefsKeepRunPrimary),
              subtitle: Text(l10n.prefsKeepRunPrimarySubtitle),
              value: prefs.keepRunPrimary,
              onChanged: prefs.setKeepRunPrimary,
            ),
            _sectionLabel(l10n.prefsSectionTrainingDemographics),
            if (!_bagReady)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.prefsSignInToEdit,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ListTile(
              title: Text(l10n.bodyMetricsTitle),
              subtitle: Text(l10n.bodyMetricsTileSubtitle),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsBodyMetricsScreen(
                    api: widget.apiClient,
                    settingsSync: widget.settingsSync,
                    preferences: widget.preferences,
                  ),
                ),
              ),
            ),
            ListTile(
              title: Text(l10n.prefsDateOfBirth),
              subtitle: Text(
                _bagValue<String>(SettingsKeys.dateOfBirth) ?? l10n.prefsNotSet,
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editDateOfBirth,
            ),
            ListTile(
              title: Text(l10n.prefsRestingHr),
              subtitle: Text(
                _bagValue<num>(SettingsKeys.restingHrBpm) != null
                    ? l10n.prefsHrBpm(
                        _bagValue<num>(SettingsKeys.restingHrBpm)!.round())
                    : l10n.prefsNotSet,
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editRestingHr,
            ),
            ListTile(
              title: Text(l10n.prefsMaxHr),
              subtitle: Text(
                _bagValue<num>(SettingsKeys.maxHrBpm) != null
                    ? l10n.prefsHrBpm(
                        _bagValue<num>(SettingsKeys.maxHrBpm)!.round())
                    : l10n.prefsMaxHrNotSet,
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editMaxHr,
            ),
            ListTile(
              title: Text(l10n.prefsHrZones),
              subtitle: Text(_hrZonesSummary()),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editHrZones,
            ),
            ListTile(
              title: Text(l10n.prefsWeeklyGoal),
              subtitle: Text(_weeklyGoalSummary()),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editWeeklyGoal,
            ),
            ListTile(
              title: Text(l10n.prefsWeekStart),
              subtitle: Text(
                _weekStartLabel(l10n,
                    _bagValue<String>(SettingsKeys.weekStartDay) ?? 'monday'),
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editWeekStartDay,
            ),
            SwitchListTile(
              title: Text(l10n.prefsExcludeGymFromReadiness),
              subtitle: Text(l10n.prefsExcludeGymFromReadinessHint),
              value:
                  _bagValue<bool>(SettingsKeys.excludeGymFromReadiness) ?? false,
              onChanged: _bagReady
                  ? (_) => _editExcludeGymFromReadiness()
                  : null,
            ),

            _sectionLabel(l10n.prefsSectionPrivacySharing),
            ListTile(
              title: Text(l10n.prefsDefaultRunPrivacy),
              subtitle: Text(_privacyLabel(
                l10n,
                _bagValue<String>(SettingsKeys.privacyDefault) ?? 'followers',
              )),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editPrivacyDefault,
            ),
            SwitchListTile(
              title: Text(l10n.prefsStravaAutoShare),
              subtitle: Text(l10n.prefsStravaAutoShareSubtitle),
              value: _bagValue<bool>(SettingsKeys.stravaAutoShare) ?? false,
              onChanged: _bagReady ? (_) => _editStravaAutoShare() : null,
            ),
            SwitchListTile(
              title: Text(l10n.prefsDiscoverable),
              subtitle: Text(l10n.prefsDiscoverableSubtitle),
              value:
                  _bagValue<bool>(SettingsKeys.discoverableInSearch) ?? true,
              onChanged:
                  _bagReady ? (_) => _editDiscoverableInSearch() : null,
            ),

            _sectionLabel(l10n.prefsSectionAiCoach),
            ListTile(
              title: Text(l10n.prefsCoachPersonality),
              subtitle: Text(_coachLabel(
                l10n,
                _bagValue<String>(SettingsKeys.coachPersonality) ??
                    'supportive',
              )),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editCoachPersonality,
            ),

            _sectionLabel(l10n.prefsSectionNotifications),
            ListTile(
              title: Text(l10n.prefsEmailNotifications),
              subtitle: Text(_emailNotifLabel(
                l10n,
                _bagValue<String>(SettingsKeys.emailNotifications) ??
                    'important',
              )),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editEmailNotifications,
            ),
            SwitchListTile(
              title: Text(l10n.prefsEmailWeeklyDigest),
              subtitle: Text(l10n.prefsEmailWeeklyDigestHint),
              value:
                  _bagValue<String>(SettingsKeys.emailWeeklyDigest) == 'on',
              onChanged:
                  _bagReady ? (_) => _editEmailWeeklyDigest() : null,
            ),
          ],
        ),
      ),
    );
  }
}
