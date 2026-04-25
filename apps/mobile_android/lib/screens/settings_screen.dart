import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup.dart';
import '../ble_heart_rate.dart';
import '../local_run_store.dart';
import '../main.dart' show themeModeNotifier;
import '../preferences.dart';
import '../settings_sync.dart';
import 'import_screen.dart';
import 'sign_in_screen.dart';

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

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onChange);
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

  Future<void> _signIn() async {
    final api = widget.apiClient;
    if (api == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backend not configured')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign out failed — check your connection')),
        );
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

  Future<void> _exportBackup() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in first to back up your runs.')),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Preparing backup…')),
    );
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
      messenger.showSnackBar(
        SnackBar(content: Text('Backup failed: $e')),
      );
    }
  }

  Future<void> _restoreBackup() async {
    final api = widget.apiClient;
    final store = widget.runStore;
    if (api == null || store == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup service unavailable.')),
      );
      return;
    }
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null) return;
    final offline = api.userId == null;
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Restoring…')));
    try {
      final res = await BackupService(api: api).restore(
        zipFile: File(path),
        runStore: store,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Restored ${res.runsImported} runs · ${res.tracksUploaded} tracks · ${res.routesImported} routes'
            '${res.warnings.isNotEmpty ? ' · ${res.warnings.length} warnings' : ''}',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
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
    } else {
      final metres = useMiles ? picked * 1609.344 : picked * 1000;
      await _putUniversal(
        SettingsKeys.weeklyMileageGoalMetres,
        metres.round(),
      );
    }
  }

  // ---------- Account actions ----------

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
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: pwdCtl.text));
      messenger.showSnackBar(
        const SnackBar(content: Text('Password updated')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update password: $e')),
      );
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
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.functions.invoke('delete-account');
      await widget.apiClient?.signOut();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Account deleted')),
        );
        setState(() {});
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Account deletion failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = widget.preferences;
    final signedIn = widget.apiClient?.userId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
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
                widget.apiClient?.userEmail != null
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
              setState(() => _darkMode = v);
              themeModeNotifier.value = v ? ThemeMode.dark : ThemeMode.light;
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
            subtitle: const Text(
              'Stops the clock when you stop moving. Moving time is also '
              'recomputed from the GPS trace at save time.',
            ),
            value: _bagValue<bool>(SettingsKeys.autoPauseEnabled) ?? true,
            onChanged: _bagReady
                ? (v) => _putUniversal(SettingsKeys.autoPauseEnabled, v)
                : null,
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
    final device = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _HeartRateScanSheet(heartRate: widget.heartRate),
    );
    if (device != null) {
      try {
        await widget.heartRate.pair(device);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pair failed: $e')),
          );
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
/// Rate Service and returns the selected `BluetoothDevice` via `pop`.
/// Re-imports `flutter_blue_plus` dynamically so the public surface of
/// `BleHeartRate` can keep the dep hidden from UI callers.
class _HeartRateScanSheet extends StatefulWidget {
  final BleHeartRate heartRate;
  const _HeartRateScanSheet({required this.heartRate});

  @override
  State<_HeartRateScanSheet> createState() => _HeartRateScanSheetState();
}

class _HeartRateScanSheetState extends State<_HeartRateScanSheet> {
  List<dynamic> _results = const [];
  bool _scanning = true;
  StreamSubscription<List<dynamic>>? _sub;

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
              final device = r.device;
              final name = device.platformName.isNotEmpty
                  ? device.platformName
                  : device.remoteId.str;
              return ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(name),
                subtitle: Text('RSSI ${r.rssi} dBm'),
                onTap: () => Navigator.of(context).pop(device),
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
