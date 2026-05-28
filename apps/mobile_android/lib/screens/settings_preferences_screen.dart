import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../goals.dart';
import '../main.dart' show themeModeNotifier;
import '../preferences.dart';
import '../settings_sync.dart';

class SettingsPreferencesScreen extends StatefulWidget {
  final Preferences preferences;
  final SettingsSyncService? settingsSync;

  const SettingsPreferencesScreen({
    super.key,
    required this.preferences,
    required this.settingsSync,
  });

  @override
  State<SettingsPreferencesScreen> createState() =>
      _SettingsPreferencesScreenState();
}

class _SettingsPreferencesScreenState extends State<SettingsPreferencesScreen> {
  bool _darkMode = themeModeNotifier.value == ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onChange);
    widget.settingsSync?.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onChange);
    widget.settingsSync?.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _unitSubtitle() {
    final base = widget.preferences.useMiles ? 'mi, ft' : 'km, m';
    final sync = widget.settingsSync;
    if (sync == null || !sync.synced) return base;
    return '$base · synced to your other devices';
  }

  static String _splitIntervalLabel(int metres, DistanceUnit unit) {
    if (unit == DistanceUnit.mi) {
      final miles = metres / 1609.344;
      if ((miles - miles.roundToDouble()).abs() < 0.01) {
        return '${miles.round()} mi';
      }
      return '${miles.toStringAsFixed(1)} mi';
    }
    if (metres >= 1000 && metres % 1000 == 0) {
      return '${metres ~/ 1000} km';
    }
    return '${metres}m';
  }

  Future<void> _editSplitInterval() async {
    final prefs = widget.preferences;
    final options = prefs.useMiles
        ? <int>[0, 805, 1609, 3219, 8047]
        : <int>[0, 500, 1000, 2000, 5000];
    final labels = prefs.useMiles
        ? ['Default', '0.5 mi', '1 mi', '2 mi', '5 mi']
        : ['Default', '500m', '1 km', '2 km', '5 km'];

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Split interval'),
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
    final prefs = widget.preferences;
    final current = prefs.targetPaceSecPerKm;
    final mCtl =
        TextEditingController(text: '${current > 0 ? current ~/ 60 : 5}');
    final sCtl =
        TextEditingController(text: '${current > 0 ? current % 60 : 30}');

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Live pace alert'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 60,
              child: TextField(
                controller: mCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'min'),
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
                decoration: const InputDecoration(labelText: 'sec'),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final m = int.tryParse(mCtl.text) ?? 0;
              final s = int.tryParse(sCtl.text) ?? 0;
              Navigator.pop(ctx, m * 60 + s);
            },
            child: const Text('Save'),
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

  static String _activityTypeLabel(String raw) {
    switch (raw) {
      case 'run':
        return 'Run';
      case 'walk':
        return 'Walk';
      case 'hike':
        return 'Hike';
      case 'cycle':
        return 'Cycle';
      default:
        return _toTitle(raw);
    }
  }

  static String _paceFormatLabel(String raw) {
    switch (raw) {
      case 'min_per_km':
        return 'Minutes per km';
      case 'min_per_mi':
        return 'Minutes per mile';
      case 'kph':
        return 'km/h';
      case 'mph':
        return 'mph';
      default:
        return _toTitle(raw);
    }
  }

  String _hrZonesSummary() {
    final raw = _bagValue<Map>(SettingsKeys.hrZones);
    if (raw == null) return 'Not set';
    final vals = ['z1', 'z2', 'z3', 'z4', 'z5']
        .map((k) => raw[k])
        .whereType<num>()
        .map((n) => n.round().toString())
        .toList();
    if (vals.isEmpty) return 'Not set';
    return '${vals.join(' · ')} bpm';
  }

  String _weeklyGoalSummary() {
    final metres =
        _bagValue<num>(SettingsKeys.weeklyMileageGoalMetres)?.toDouble();
    if (metres == null) return 'Not set';
    final useMiles = widget.preferences.useMiles;
    final display = useMiles ? metres / 1609.344 : metres / 1000;
    return '${display.toStringAsFixed(display < 10 ? 1 : 0)} ${useMiles ? 'mi' : 'km'} / week';
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
              child: const Text('Clear'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
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
            child: const Text('Save'),
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
              child: const Text('Clear'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editDefaultActivityType() async {
    const opts = ['run', 'walk', 'hike', 'cycle'];
    const labels = ['Run', 'Walk', 'Hike', 'Cycle'];
    final picked = await _pickRadio<String>(
      title: 'Default activity',
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.defaultActivityType) ?? 'run',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.defaultActivityType, picked);
      await widget.preferences.setDefaultActivityType(picked);
    }
  }

  Future<void> _editMapStyle() async {
    const opts = ['streets', 'satellite', 'outdoors', 'dark'];
    const labels = ['Streets', 'Satellite', 'Outdoors', 'Dark'];
    final picked = await _pickRadio<String>(
      title: 'Map style',
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.mapStyle) ?? 'streets',
    );
    if (picked != null) await _putUniversal(SettingsKeys.mapStyle, picked);
  }

  Future<void> _editPaceFormat() async {
    const opts = ['min_per_km', 'min_per_mi', 'kph', 'mph'];
    const labels = ['Minutes per km', 'Minutes per mile', 'km/h', 'mph'];
    final picked = await _pickRadio<String>(
      title: 'Pace format',
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
    const opts = ['public', 'followers', 'private'];
    const labels = ['Public', 'Followers', 'Private'];
    final picked = await _pickRadio<String>(
      title: 'Default run visibility',
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
    const opts = ['supportive', 'drill_sergeant', 'analytical'];
    const labels = ['Supportive', 'Drill sergeant', 'Analytical'];
    final picked = await _pickRadio<String>(
      title: 'Coach personality',
      options: opts,
      labels: labels,
      current:
          _bagValue<String>(SettingsKeys.coachPersonality) ?? 'supportive',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.coachPersonality, picked);
    }
  }

  Future<void> _editWeekStartDay() async {
    const opts = ['monday', 'sunday'];
    const labels = ['Monday', 'Sunday'];
    final picked = await _pickRadio<String>(
      title: 'Week starts on',
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.weekStartDay) ?? 'monday',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.weekStartDay, picked);
    }
  }

  Future<void> _editAutoPauseSpeed() async {
    final current =
        _bagValue<num>(SettingsKeys.autoPauseSpeedMps)?.toDouble();
    final picked = await _pickDouble(
      title: 'Auto-pause below',
      current: current ?? 0.8,
      suffix: 'm/s',
      minValue: 0.1,
      maxValue: 3.0,
    );
    if (picked == null) return;
    await _putUniversal(
      SettingsKeys.autoPauseSpeedMps,
      picked == -1.0 ? null : picked,
    );
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

  Future<void> _editDateOfBirth() async {
    final raw = _bagValue<String>(SettingsKeys.dateOfBirth);
    final current = raw != null ? DateTime.tryParse(raw) : null;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked == null) return;
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    await _putUniversal(SettingsKeys.dateOfBirth, iso);
  }

  Future<void> _editRestingHr() async {
    final picked = await _pickInt(
      title: 'Resting heart rate',
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
      title: 'Max heart rate',
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
        title: const Text('Heart-rate zones (upper bounds, bpm)'),
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
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
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
            child: const Text('Save'),
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
      title: 'Weekly mileage goal',
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
    final prefs = widget.preferences;
    final offlineNotice = widget.settingsSync?.synced == true &&
            widget.settingsSync?.service?.isServerHydrated == false
        ? widget.settingsSync?.lastError
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Preferences')),
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
            _sectionLabel('Units & display'),
            SwitchListTile(
              title: const Text('Use miles'),
              subtitle: Text(_unitSubtitle()),
              value: prefs.useMiles,
              onChanged: (v) async {
                await prefs.setUseMiles(v);
                await widget.settingsSync?.pushPreferredUnit();
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              title: const Text('Pace format'),
              subtitle: Text(_paceFormatLabel(
                _bagValue<String>(SettingsKeys.unitsPaceFormat) ?? 'min_per_km',
              )),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editPaceFormat,
            ),
            ListTile(
              title: const Text('Map style'),
              subtitle: Text(
                _toTitle(_bagValue<String>(SettingsKeys.mapStyle) ?? 'streets'),
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editMapStyle,
            ),
            SwitchListTile(
              title: const Text('Dark mode'),
              value: _darkMode,
              onChanged: (v) {
                final mode = v ? ThemeMode.dark : ThemeMode.light;
                setState(() => _darkMode = v);
                themeModeNotifier.value = mode;
                widget.preferences.setThemeMode(mode);
              },
            ),

            _sectionLabel('Activity & recording'),
            ListTile(
              title: const Text('Default activity'),
              subtitle: Text(_activityTypeLabel(
                _bagValue<String>(SettingsKeys.defaultActivityType) ?? 'run',
              )),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editDefaultActivityType,
            ),
            SwitchListTile(
              title: const Text('Audio cues'),
              subtitle: const Text('Spoken split announcements'),
              value: prefs.audioCues,
              onChanged: (v) async {
                await prefs.setAudioCues(v);
                await widget.settingsSync?.pushAudioCues();
              },
            ),
            ListTile(
              title: const Text('Split interval'),
              subtitle: Text(
                prefs.splitIntervalMetres > 0
                    ? _splitIntervalLabel(prefs.splitIntervalMetres, prefs.unit)
                    : 'Default (1 km for running, 5 km for cycling)',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editSplitInterval,
            ),
            ListTile(
              title: const Text('Live pace alert'),
              subtitle: Text(
                prefs.targetPaceSecPerKm > 0
                    ? '${UnitFormat.pace(prefs.targetPaceSecPerKm.toDouble(), prefs.unit)} '
                        '${UnitFormat.paceLabel(prefs.unit)} '
                        '— spoken alert during a run when 30s+ off'
                    : 'Off — set a pace to get spoken alerts during a run',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editTargetPace,
            ),
            SwitchListTile(
              title: const Text('Keep screen on'),
              subtitle: const Text('Hold a wakelock during a run'),
              value: prefs.keepScreenOn,
              onChanged: (v) async {
                await prefs.setKeepScreenOn(v);
                await widget.settingsSync?.pushKeepScreenOn();
              },
            ),
            SwitchListTile(
              title: const Text('Advanced GPS'),
              subtitle: const Text(
                'Higher accuracy, finer track detail, more battery usage',
              ),
              value: prefs.advancedGps,
              onChanged: prefs.setAdvancedGps,
            ),
            SwitchListTile(
              title: const Text('Auto-pause'),
              subtitle: const Text('Not available on this device.'),
              value: _bagValue<bool>(SettingsKeys.autoPauseEnabled) ?? true,
              onChanged: null,
            ),
            ListTile(
              title: const Text('Auto-pause threshold'),
              subtitle: Text(
                '${(_bagValue<num>(SettingsKeys.autoPauseSpeedMps)?.toDouble() ?? 0.8).toStringAsFixed(1)} m/s',
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editAutoPauseSpeed,
            ),

            _sectionLabel('Training & demographics'),
            if (!_bagReady)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Sign in to edit profile-level settings that sync across devices.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ListTile(
              title: const Text('Date of birth'),
              subtitle: Text(
                _bagValue<String>(SettingsKeys.dateOfBirth) ?? 'Not set',
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editDateOfBirth,
            ),
            ListTile(
              title: const Text('Resting heart rate'),
              subtitle: Text(
                _bagValue<num>(SettingsKeys.restingHrBpm) != null
                    ? '${_bagValue<num>(SettingsKeys.restingHrBpm)!.round()} bpm'
                    : 'Not set',
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editRestingHr,
            ),
            ListTile(
              title: const Text('Max heart rate'),
              subtitle: Text(
                _bagValue<num>(SettingsKeys.maxHrBpm) != null
                    ? '${_bagValue<num>(SettingsKeys.maxHrBpm)!.round()} bpm'
                    : 'Not set — falls back to 220 − age',
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editMaxHr,
            ),
            ListTile(
              title: const Text('Heart-rate zones'),
              subtitle: Text(_hrZonesSummary()),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editHrZones,
            ),
            ListTile(
              title: const Text('Weekly mileage goal'),
              subtitle: Text(_weeklyGoalSummary()),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editWeeklyGoal,
            ),
            ListTile(
              title: const Text('Week starts on'),
              subtitle: Text(
                _toTitle(
                    _bagValue<String>(SettingsKeys.weekStartDay) ?? 'monday'),
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editWeekStartDay,
            ),

            _sectionLabel('Privacy & sharing'),
            ListTile(
              title: const Text('Default run privacy'),
              subtitle: Text(_toTitle(
                _bagValue<String>(SettingsKeys.privacyDefault) ?? 'followers',
              )),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editPrivacyDefault,
            ),
            SwitchListTile(
              title: const Text('Strava auto-share'),
              subtitle: const Text(
                'Auto-push every new run to Strava. Requires a connected Strava '
                'integration once that lands.',
              ),
              value: _bagValue<bool>(SettingsKeys.stravaAutoShare) ?? false,
              onChanged: _bagReady ? (_) => _editStravaAutoShare() : null,
            ),
            SwitchListTile(
              title: const Text('Show me in name search'),
              subtitle: const Text(
                "When off, your account won't appear when other runners "
                'search by display name. Your public runs and profile '
                'remain reachable to anyone with the URL.',
              ),
              value:
                  _bagValue<bool>(SettingsKeys.discoverableInSearch) ?? true,
              onChanged:
                  _bagReady ? (_) => _editDiscoverableInSearch() : null,
            ),

            _sectionLabel('AI coach'),
            ListTile(
              title: const Text('Coach personality'),
              subtitle: Text(_toTitle(
                _bagValue<String>(SettingsKeys.coachPersonality) ??
                    'supportive',
              )),
              trailing: const Icon(Icons.chevron_right),
              enabled: _bagReady,
              onTap: _editCoachPersonality,
            ),
          ],
        ),
      ),
    );
  }
}
