import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup.dart';
import '../ble_heart_rate.dart';
import '../goals.dart';
import '../local_run_store.dart';
import '../main.dart' show themeModeNotifier;
import '../preferences.dart';
import '../revenuecat.dart';
import '../settings_sync.dart';
import '../strava.dart';
import 'import_screen.dart';
import 'devices_screen.dart';
import 'gear_screen.dart';
import 'guided_runs_screen.dart';
import 'privacy_zones_screen.dart';
import 'profile_screen.dart';
import 'sign_in_screen.dart';
import '../widgets/top_banner.dart';

/// Account settings, preferences, and integrations.
class SettingsScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final Preferences preferences;
  final LocalRunStore? runStore;
  final BleHeartRate heartRate;
  final SettingsSyncService? settingsSync;

  const SettingsScreen({
    super.key,
    this.apiClient,
    required this.preferences,
    required this.heartRate,
    this.runStore,
    this.settingsSync,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = themeModeNotifier.value == ThemeMode.dark;
  List<IntegrationRow> _integrations = const [];
  bool _stravaBusy = false;

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onChange);
    _refreshIntegrations();
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _refreshIntegrations() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    try {
      final list = await api.fetchIntegrations();
      if (!mounted) return;
      setState(() => _integrations = list);
    } catch (_) {}
  }

  IntegrationRow? _strava() {
    for (final i in _integrations) {
      if (i.provider == 'strava') return i;
    }
    return null;
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

  Future<void> _signIn() async {
    final api = widget.apiClient;
    if (api == null) {
      showTopBanner(context, 'Backend not configured');
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SignInScreen(apiClient: api)),
    );
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _signOut() async {
    final api = widget.apiClient;
    if (api == null) return;
    try {
      await api.signOut();
    } catch (e) {
      if (mounted) {
        showTopBanner(context, 'Sign out failed — check your connection');
        return;
      }
    }
    if (mounted) setState(() {});
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
        ? <int>[0, 805, 1609, 3219, 8047]   // ~0.5 mi, 1 mi, 2 mi, 5 mi
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
    int minutes = current > 0 ? current ~/ 60 : 5;
    int seconds = current > 0 ? current % 60 : 30;

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        final mCtl = TextEditingController(text: '$minutes');
        final sCtl = TextEditingController(text: '$seconds');
        return AlertDialog(
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
        );
      },
    );
    if (result != null) await prefs.setTargetPaceSecPerKm(result);
  }

  Future<void> _exportRunsCsv() async {
    final store = widget.runStore;
    final runs = store?.runs ?? const [];
    if (runs.isEmpty) {
      showTopBanner(context, 'No runs to export.');
      return;
    }
    try {
      final buf = StringBuffer('date,distance_m,duration_s,pace_s_per_km,source\n');
      for (final r in runs) {
        final pace = r.distanceMetres > 0
            ? (r.duration.inSeconds / (r.distanceMetres / 1000)).round()
            : 0;
        buf.writeln(
          '${r.startedAt.toUtc().toIso8601String()},'
          '${r.distanceMetres.round()},'
          '${r.duration.inSeconds},'
          '$pace,'
          '${r.source.name}',
        );
      }
      final tmp = await getTemporaryDirectory();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${tmp.path}/runs-$ts.csv');
      await file.writeAsString(buf.toString());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        text: 'Run app — runs export',
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'CSV export failed: $e');
    }
  }

  Future<void> _exportBackup() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      showTopBanner(context, 'Sign in first to back up your runs.');
      return;
    }
    showTopBanner(context, 'Preparing backup…');
    try {
      final tmp = await getTemporaryDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${tmp.path}/run-app-backup-$ts.zip');
      await BackupService(api: api).createBackup(outputFile: file);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Run app backup',
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Backup failed: $e');
    }
  }

  Future<void> _restoreBackup() async {
    final api = widget.apiClient;
    final store = widget.runStore;
    // Restore can run with no api at all (release builds without
    // SUPABASE_URL/ANON_KEY baked in) — `BackupService` falls through
    // to the offline path when api is null. We only need a runStore
    // to hydrate into; without that there's nowhere for the rows to
    // land.
    if (store == null) {
      showTopBanner(context, 'Backup service unavailable.');
      return;
    }
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null) return;
    final offline = api == null || api.userId == null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: Text(
          offline
              ? 'You\'re not signed in. Runs will be restored to this device '
                  'and synced to your account the next time you sign in.'
              : 'This adds or overwrites runs and routes matching IDs in the '
                  'backup. It will not delete runs or routes that aren\'t in '
                  'the backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    showTopBanner(context, 'Restoring…');
    try {
      final res = await BackupService(api: api).restore(
        zipFile: File(path),
        runStore: store,
      );
      if (!mounted) return;
      showTopBanner(
        context,
        'Restored ${res.runsImported} runs · ${res.tracksUploaded} tracks · ${res.routesImported} routes'
        '${res.warnings.isNotEmpty ? ' · ${res.warnings.length} warnings' : ''}',
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Restore failed: $e');
    }
  }

  // ---------- Label helpers for bag-backed tiles ----------

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

  // ---------- Bag-backed settings helpers ----------
  //
  // Thin wrappers around `SettingsSyncService.updateUniversal` for keys that
  // don't have a local `Preferences` mirror — the settings screen reads
  // through `service.effective<T>(key)` and writes the user's choice
  // straight to the cloud bag. Offline edits are silently dropped; the
  // cloud value is the source of truth for these keys across devices.

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
              onPressed: () => Navigator.pop(ctx, -1), // sentinel "clear"
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
              onPressed: () => Navigator.pop(ctx, -1.0), // sentinel "clear"
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
    final current = _bagValue<num>(SettingsKeys.autoPauseSpeedMps)?.toDouble();
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
                  decoration: InputDecoration(labelText: entry.key.toUpperCase()),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, <String, int>{}), // clear
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
    final currentDisplay =
        current == null ? null : (useMiles ? current / 1609.344 : current / 1000);
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
      // Also clear the local weekly distance goal so the dashboard
      // doesn't keep showing one after the user removed it here.
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
      // Mirror into the local list so the dashboard's Goals row picks
      // it up immediately.
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

  // ---------- Account actions ----------

  Widget _buildStravaTile() {
    final s = _strava();
    final connected = s != null;
    final last = s?.lastSyncAt;
    final subtitle = !connected
        ? 'Connect to auto-sync activities'
        : last == null
            ? 'Connected · waiting for first sync'
            : 'Connected · last sync ${_relTime(last)}';
    return ListTile(
      leading: const Icon(Icons.sync, color: Color(0xFFFC4C02)),
      title: const Text('Strava'),
      subtitle: Text(subtitle),
      trailing: _stravaBusy
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : connected
              ? PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'sync') _syncStrava();
                    if (v == 'disconnect') _disconnectStrava();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'sync', child: Text('Sync now')),
                    PopupMenuItem(
                        value: 'disconnect', child: Text('Disconnect')),
                  ],
                )
              : const Icon(Icons.chevron_right),
      onTap: _stravaBusy ? null : (connected ? _syncStrava : _connectStrava),
    );
  }

  static String _relTime(DateTime t) {
    final diff = DateTime.now().toUtc().difference(t.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  Future<void> _connectStrava() async {
    final api = widget.apiClient;
    if (api == null) return;

    // Fall back to the browser flow on unconfigured builds — the native
    // OAuth call needs STRAVA_CLIENT_ID in dotenv. Older builds will
    // continue to land on the web Settings page rather than hit a
    // confusing StateError.
    if (!isStravaConfigured()) {
      await _openExternal('https://run.app/settings/integrations');
      if (!mounted) return;
      showTopBanner(
        context,
        'Complete the Strava sign-in in your browser, then return here '
            'and pull to refresh.',
      );
      return;
    }

    setState(() => _stravaBusy = true);
    try {
      final authUrl = stravaAuthUrl(redirectUri: kStravaCallbackUri);
      final resultUrl = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: kStravaCallbackScheme,
      );
      final cb = parseStravaCallback(resultUrl);
      if (!cb.isSuccess) {
        if (!mounted) return;
        showTopBanner(
          context,
          cb.error == 'access_denied'
              ? 'Strava sign-in cancelled.'
              : 'Strava sign-in failed: ${cb.error ?? 'no code returned'}',
        );
        return;
      }
      final res = await api.completeStravaOAuth(
        code: cb.code!,
        scope: cb.scope ?? '',
        redirectUri: kStravaCallbackUri,
      );
      if (!mounted) return;
      final err = res['error'];
      if (err is String) {
        showTopBanner(context, 'Strava connect failed: $err');
        return;
      }
      showTopBanner(context, 'Strava connected.');
      await _refreshIntegrations();
    } catch (e) {
      // FlutterWebAuth2 throws PlatformException on user cancel, network
      // failure, or scheme mismatch — same broad surface as the EF
      // failures, so one catch is enough. L4 per layered resilience:
      // a failure here can't break the rest of Settings.
      if (!mounted) return;
      showTopBanner(context, 'Strava sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _stravaBusy = false);
    }
  }

  Future<void> _syncStrava() async {
    final api = widget.apiClient;
    if (api == null) return;
    setState(() => _stravaBusy = true);
    try {
      final res = await api.syncStrava();
      if (!mounted) return;
      final imported = (res['imported'] as num?)?.toInt() ?? 0;
      final skipped = (res['skipped'] as num?)?.toInt() ?? 0;
      showTopBanner(context, 'Synced. $imported new, $skipped already present.');
      await _refreshIntegrations();
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Sync failed: $e');
    } finally {
      if (mounted) setState(() => _stravaBusy = false);
    }
  }

  Future<void> _disconnectStrava() async {
    final api = widget.apiClient;
    if (api == null) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Disconnect Strava?'),
            content: const Text(
              'Future activities will stop syncing automatically. Already-imported '
              'runs stay in your history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Disconnect'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    setState(() => _stravaBusy = true);
    try {
      await api.disconnectIntegration('strava');
      await _refreshIntegrations();
      if (!mounted) return;
      showTopBanner(context, 'Strava disconnected.');
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Disconnect failed: $e');
    } finally {
      if (mounted) setState(() => _stravaBusy = false);
    }
  }

  Future<void> _importParkrun() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;

    // Pre-fill from user_profiles.parkrun_number when available so a
    // returning user doesn't have to re-type it. Use the self-read RPC
    // path because parkrun_number is column-level revoked from direct
    // SELECT (migration 20260707_001).
    String existing = '';
    try {
      final profile = await api.fetchMyProfile();
      existing = profile?.parkrunNumber ?? '';
    } catch (_) {}

    final ctrl = TextEditingController(text: existing);
    if (!mounted) return;
    final athleteNumber = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import parkrun results'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter your parkrun athlete number (e.g. A123456). We\'ll '
              'fetch your finish history and add any new results to your '
              'runs list.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: 'Athlete number',
                hintText: 'A123456',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (athleteNumber == null || athleteNumber.isEmpty) return;
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Importing parkrun results…')),
          ],
        ),
      ),
    );

    try {
      // Persist the number first so the next import is one-tap.
      await api.setParkrunAthleteNumber(athleteNumber);
      final imported = await api.importParkrunResults(athleteNumber);
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss progress
      showTopBanner(context, imported > 0
                ? 'Imported $imported parkrun result${imported == 1 ? '' : 's'}.'
                : 'No new parkrun results since last import.',);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showTopBanner(context, 'Import failed: $e');
    }
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        await Share.share(url);
      }
    } catch (_) {
      if (!mounted) return;
      try {
        await Share.share(url);
      } catch (e) {
        if (!mounted) return;
        showTopBanner(context, 'Could not open: $e');
      }
    }
  }

  Future<void> _startProCheckout() async {
    // Three-way fallback to keep this tile useful on every build:
    //   1. RC configured + signed in → native sheet
    //   2. RC unconfigured (no API key in dotenv)        → web URL
    //   3. RC configured but anonymous (no Supabase user) → web URL,
    //      since the purchase needs to attach to a user id
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (!isRevenueCatConfigured() || userId == null) {
      await _openExternal('https://run.app/settings/upgrade');
      return;
    }
    final r = await startProCheckout(userId);
    if (!mounted) return;
    switch (r) {
      case PurchaseResult.purchased:
        showTopBanner(context, 'Welcome to Pro! Pulling your benefits…');
        // The revenuecat-webhook flips subscription_tier server-side;
        // a profile refetch a few seconds later picks it up. Caller
        // surfaces are already wired via `ApiClient.isPro()`.
        break;
      case PurchaseResult.cancelled:
        // Benign — user dismissed the sheet.
        break;
      case PurchaseResult.failed:
        showTopBanner(context, 'Purchase failed. Try again later.');
        break;
      case PurchaseResult.notConfigured:
        // Shouldn't fire (we gated on isRevenueCatConfigured above),
        // but if the SDK init itself failed, fall through to web.
        await _openExternal('https://run.app/settings/upgrade');
        break;
    }
  }

  Future<void> _changePassword() async {
    final pwdCtl = TextEditingController();
    final confirmCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setInner) => AlertDialog(
            title: const Text('Change password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pwdCtl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (pwdCtl.text.length < 8) {
                    setInner(() => error = 'Password must be at least 8 characters');
                    return;
                  }
                  if (pwdCtl.text != confirmCtl.text) {
                    setInner(() => error = 'Passwords do not match');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
    if (!mounted) return;
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: pwdCtl.text));
      if (!mounted) return;
      showTopBanner(context, 'Password updated');
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Could not update password: $e');
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently removes your runs, routes, and profile from the '
          'server. Local device data is kept unless you sign in as a new '
          'user. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    try {
      await Supabase.instance.client.functions.invoke('delete-account');
      await widget.apiClient?.signOut();
      if (mounted) {
        showTopBanner(context, 'Account deleted');
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Account deletion failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = widget.preferences;
    final signedIn = widget.apiClient?.userId != null;

    return Scaffold(
      // No AppBar — the bottom-nav labels this tab "Settings", and
      // there are no actions to surface. SafeArea keeps the first
      // section clear of the status bar (the previous AppBar was
      // providing that inset implicitly).
      body: SafeArea(
        child: ListView(
        children: [
          // Account
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Account', style: theme.textTheme.titleSmall),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: signedIn
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              child: Text(
                // userEmail can be the empty string for an OAuth user
                // without a verified email — guard against [0] crashing
                // with RangeError on '' before .toUpperCase().
                (widget.apiClient?.userEmail?.isNotEmpty ?? false)
                    ? widget.apiClient!.userEmail![0].toUpperCase()
                    : '?',
              ),
            ),
            title: Text(widget.apiClient?.userEmail ?? 'Offline mode'),
            subtitle: Text(signedIn
                ? 'Signed in — runs will sync'
                : 'Sign in to sync runs across devices'),
            trailing: signedIn
                ? IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Sign out',
                    onPressed: _signOut,
                  )
                : FilledButton.tonal(
                    onPressed: _signIn,
                    child: const Text('Sign in'),
                  ),
          ),
          if (signedIn) ...[
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('View profile'),
              subtitle:
                  const Text('Your runs, followers, following, notifications'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final api = widget.apiClient;
                final uid = api?.userId;
                if (api == null || uid == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(api: api, userId: uid),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.devices_other),
              title: const Text('Devices'),
              subtitle: const Text(
                  'Where you\'re signed in and per-device overrides'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final api = widget.apiClient;
                if (api == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DevicesScreen(
                      api: api,
                      currentDeviceId: widget.preferences.deviceId,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.directions_run_outlined),
              title: const Text('Gear'),
              subtitle: const Text('Track shoes + bikes and per-item mileage'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final api = widget.apiClient;
                if (api == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GearScreen(
                      api: api,
                      preferences: widget.preferences,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.headset),
              title: const Text('Guided runs'),
              subtitle:
                  const Text('Coach-voice scripted workouts with TTS cues'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const GuidedRunsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy zones'),
              subtitle:
                  const Text('Clip start/end of public tracks near home'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final s = widget.settingsSync;
                if (s == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PrivacyZonesScreen(settingsSync: s),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('Subscribe to Pro'),
              subtitle: Text(
                isRevenueCatConfigured()
                    ? 'Unlock the AI coach and priority processing'
                    : 'Opens the subscription portal in your browser',
              ),
              trailing: Icon(
                isRevenueCatConfigured()
                    ? Icons.chevron_right
                    : Icons.open_in_new,
                size: 18,
              ),
              onTap: _startProCheckout,
            ),
            ListTile(
              leading: const Icon(Icons.volunteer_activism_outlined),
              title: const Text('Support the app'),
              subtitle: const Text('One-off donation in your browser'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openExternal('https://run.app/settings/upgrade'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changePassword,
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete account',
                style: TextStyle(color: Colors.red),
              ),
              subtitle: const Text('Permanently removes server data'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _deleteAccount,
            ),
          ],
          const Divider(),

          // Sensors
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Sensors', style: theme.textTheme.titleSmall),
          ),
          _HeartRateTile(heartRate: widget.heartRate),
          const Divider(),

          // Integrations
          if (signedIn) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Integrations', style: theme.textTheme.titleSmall),
            ),
            _buildStravaTile(),
            ListTile(
              leading: const Icon(Icons.directions_run),
              title: const Text('parkrun'),
              subtitle: const Text('Import results by athlete number'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _importParkrun,
            ),
            const Divider(),
          ],

          // Preferences
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Preferences', style: theme.textTheme.titleSmall),
          ),
          SwitchListTile(
            title: const Text('Use miles'),
            subtitle: Text(_unitSubtitle()),
            value: prefs.useMiles,
            onChanged: (v) async {
              await prefs.setUseMiles(v);
              // Best-effort cloud push — no UI error if we're offline.
              // The cloud value is re-pulled on next sign-in anyway.
              await widget.settingsSync?.pushPreferredUnit();
              if (mounted) setState(() {});
            },
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
          SwitchListTile(
            title: const Text('Keep screen on'),
            subtitle: const Text('Hold a wakelock during a run'),
            value: prefs.keepScreenOn,
            onChanged: (v) async {
              await prefs.setKeepScreenOn(v);
              await widget.settingsSync?.pushKeepScreenOn();
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
            title: const Text('Dark mode'),
            value: _darkMode,
            onChanged: (v) {
              final mode = v ? ThemeMode.dark : ThemeMode.light;
              setState(() => _darkMode = v);
              themeModeNotifier.value = mode;
              // Persist so the choice survives app restarts. Was
              // previously only setting the in-memory notifier, so
              // every cold start fell back to the default dark mode.
              widget.preferences.setThemeMode(mode);
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
          ListTile(
            title: const Text('Default activity'),
            subtitle: Text(_activityTypeLabel(
              _bagValue<String>(SettingsKeys.defaultActivityType) ?? 'run',
            )),
            trailing: const Icon(Icons.chevron_right),
            enabled: _bagReady,
            onTap: _editDefaultActivityType,
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
          ListTile(
            title: const Text('Pace format'),
            subtitle: Text(_paceFormatLabel(
              _bagValue<String>(SettingsKeys.unitsPaceFormat) ?? 'min_per_km',
            )),
            trailing: const Icon(Icons.chevron_right),
            enabled: _bagReady,
            onTap: _editPaceFormat,
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
          const Divider(),

          // Profile & training (universal bag)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Profile & training', style: theme.textTheme.titleSmall),
          ),
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
              _toTitle(_bagValue<String>(SettingsKeys.weekStartDay) ?? 'monday'),
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: _bagReady,
            onTap: _editWeekStartDay,
          ),
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
          ListTile(
            title: const Text('Coach personality'),
            subtitle: Text(_toTitle(
              _bagValue<String>(SettingsKeys.coachPersonality) ?? 'supportive',
            )),
            trailing: const Icon(Icons.chevron_right),
            enabled: _bagReady,
            onTap: _editCoachPersonality,
          ),
          const Divider(),

          // Data
          if (widget.runStore != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Data', style: theme.textTheme.titleSmall),
            ),
            ListTile(
              leading: const Icon(Icons.move_to_inbox),
              title: const Text('Import from another app'),
              subtitle: const Text('Strava, GPX, TCX'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImportScreen(
                      apiClient: widget.apiClient,
                      runStore: widget.runStore!,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Full backup'),
              subtitle: const Text(
                'Every run with its GPS trace, plus routes, profile, and preferences. '
                'Restores on web or Android.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _exportBackup,
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Export runs as CSV'),
              subtitle: const Text(
                'date, distance, duration, pace, source — one row per run. '
                'Same shape as the web GDPR export.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _exportRunsCsv,
            ),
            ListTile(
              leading: const Icon(Icons.unarchive_outlined),
              title: const Text('Restore from backup'),
              subtitle: const Text('Pick a previously saved .zip backup.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _restoreBackup,
            ),
            const Divider(),
          ],

          // About
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('About', style: theme.textTheme.titleSmall),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('0.1.0 (dev)'),
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('Licenses'),
            onTap: () => showLicensePage(context: context),
          ),
        ],
        ),
      ),
    );
  }
}

/// List tile that shows whether a BLE chest strap is paired and opens a
/// scan sheet to pair one. Delegates to `BleHeartRate` for everything.
class _HeartRateTile extends StatefulWidget {
  final BleHeartRate heartRate;
  const _HeartRateTile({required this.heartRate});

  @override
  State<_HeartRateTile> createState() => _HeartRateTileState();
}

class _HeartRateTileState extends State<_HeartRateTile> {
  String? _pairedName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final name = await widget.heartRate.pairedName();
    if (!mounted) return;
    setState(() {
      _pairedName = name;
      _loading = false;
    });
  }

  Future<void> _pair() async {
    final device = await showModalBottomSheet<BleDeviceCandidate>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _HeartRateScanSheet(heartRate: widget.heartRate),
    );
    if (device != null) {
      try {
        await widget.heartRate.pair(device);
      } catch (e) {
        if (mounted) {
          showTopBanner(context, 'Pair failed: $e');
        }
      }
      await _refresh();
    }
  }

  Future<void> _forget() async {
    await widget.heartRate.forget();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final paired = _pairedName;
    return ListTile(
      leading: const Icon(Icons.favorite_border),
      title: const Text('Heart rate monitor'),
      subtitle: Text(
        _loading
            ? 'Checking…'
            : paired != null
                ? 'Paired: $paired'
                : 'No strap paired — tap to scan',
      ),
      trailing: paired != null
          ? IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Forget',
              onPressed: _forget,
            )
          : const Icon(Icons.chevron_right),
      onTap: _pair,
    );
  }
}

/// Modal bottom sheet that scans for BLE straps advertising the Heart
/// Rate Service and returns the selected `BleDeviceCandidate` via `pop`.
/// `BleDeviceCandidate` is a plain value type defined in `BleHeartRate`,
/// so this sheet doesn't depend on the underlying flutter_reactive_ble
/// types.
class _HeartRateScanSheet extends StatefulWidget {
  final BleHeartRate heartRate;
  const _HeartRateScanSheet({required this.heartRate});

  @override
  State<_HeartRateScanSheet> createState() => _HeartRateScanSheetState();
}

class _HeartRateScanSheetState extends State<_HeartRateScanSheet> {
  List<BleDeviceCandidate> _results = const [];
  bool _scanning = true;
  StreamSubscription<List<BleDeviceCandidate>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.heartRate.scan().listen(
      (list) {
        if (mounted) setState(() => _results = list);
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Scan for heart rate monitor',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (_scanning)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Wake your strap / chest band. Apps typically take 3–8 seconds.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (_results.isEmpty && !_scanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No straps found. Make sure it\'s nearby and awake.'),
              ),
            ..._results.map((r) {
              return ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(r.name),
                subtitle: Text('RSSI ${r.rssi} dBm'),
                onTap: () => Navigator.of(context).pop(r),
              );
            }),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
