import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
    if (result != null) await prefs.setSplitIntervalMetres(result);
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
    final store = widget.runStore;
    if (store == null) return;
    final runs = store.runs;
    final json = jsonEncode({
      'exported_at': DateTime.now().toIso8601String(),
      'count': runs.length,
      'runs': runs.map((r) => r.toJson()).toList(),
    });
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}/runs-backup-${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Run backup — ${runs.length} runs',
    );
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
            onChanged: prefs.setAudioCues,
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
              leading: const Icon(Icons.download),
              title: const Text('Backup runs'),
              subtitle: Text('${widget.runStore!.runs.length} runs'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _exportBackup,
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
