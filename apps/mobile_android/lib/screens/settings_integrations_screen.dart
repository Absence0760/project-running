import 'dart:async';
import 'dart:io' show Platform;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ble_heart_rate.dart';
import '../health_connect_exporter.dart';
import '../preferences.dart';
import '../strava.dart';
import '../widgets/top_banner.dart';

class SettingsIntegrationsScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final BleHeartRate heartRate;
  final Preferences preferences;

  const SettingsIntegrationsScreen({
    super.key,
    required this.apiClient,
    required this.heartRate,
    required this.preferences,
  });

  @override
  State<SettingsIntegrationsScreen> createState() =>
      _SettingsIntegrationsScreenState();
}

class _SettingsIntegrationsScreenState
    extends State<SettingsIntegrationsScreen> {
  List<IntegrationRow> _integrations = const [];
  bool _stravaBusy = false;

  @override
  void initState() {
    super.initState();
    _refreshIntegrations();
  }

  Future<void> _refreshIntegrations() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    try {
      final list = await api.fetchIntegrations();
      if (!mounted) return;
      setState(() => _integrations = list);
    } catch (e) {
      debugPrint('settings: integrations refresh failed: $e');
    }
  }

  IntegrationRow? _strava() {
    for (final i in _integrations) {
      if (i.provider == 'strava') return i;
    }
    return null;
  }

  static String _relTime(DateTime t) {
    final diff = DateTime.now().toUtc().difference(t.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
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

  Future<void> _connectStrava() async {
    final api = widget.apiClient;
    if (api == null) return;

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
      final state = mintStravaOAuthState();
      final authUrl =
          stravaAuthUrl(redirectUri: kStravaCallbackUri, state: state);
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
      if (cb.state != state) {
        if (!mounted) return;
        showTopBanner(
          context,
          'Strava sign-in rejected: CSRF state mismatch. Please retry.',
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
      showTopBanner(
          context, 'Synced. $imported new, $skipped already present.');
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

    String existing = '';
    try {
      final profile = await api.fetchMyProfile();
      existing = profile?.parkrunNumber ?? '';
    } catch (e) {
      debugPrint('settings: parkrun profile fetch failed: $e');
    }

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
      await api.setParkrunAthleteNumber(athleteNumber);
      final imported = await api.importParkrunResults(athleteNumber);
      if (!mounted) return;
      Navigator.of(context).pop();
      showTopBanner(
        context,
        imported > 0
            ? 'Imported $imported parkrun result${imported == 1 ? '' : 's'}.'
            : 'No new parkrun results since last import.',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showTopBanner(context, 'Import failed: $e');
    }
  }

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
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
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

  @override
  Widget build(BuildContext context) {
    final signedIn = widget.apiClient?.userId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Integrations')),
      body: SafeArea(
        child: ListView(
          children: [
            if (signedIn) ...[
              _buildStravaTile(),
              ListTile(
                leading: const Icon(Icons.directions_run),
                title: const Text('parkrun'),
                subtitle: const Text('Import results by athlete number'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _importParkrun,
              ),
            ] else
              const ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Sign in to connect services'),
                subtitle: Text(
                  'Strava + parkrun require an account so synced activities '
                  'land in your history.',
                ),
              ),
            const Divider(),
            HeartRateMonitorTile(heartRate: widget.heartRate),
            if (Platform.isAndroid) ...[
              const Divider(),
              SwitchListTile(
                secondary: const Icon(Icons.health_and_safety_outlined),
                title: const Text('Write runs to Health Connect'),
                subtitle: const Text(
                  'Send each finished run to Health Connect so it appears in '
                  'Google Fit, Samsung Health, Fitbit and others.',
                ),
                value: widget.preferences.writeToHealthConnect,
                onChanged: _toggleHealthConnectWrite,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleHealthConnectWrite(bool enable) async {
    if (!enable) {
      await widget.preferences.setWriteToHealthConnect(false);
      if (mounted) setState(() {});
      return;
    }
    // Turning on requires the Health Connect WRITE grant; only flip the
    // pref if the user actually grants it, so a denied prompt doesn't
    // leave the toggle on with nothing being written.
    bool granted = false;
    try {
      granted = await HealthConnectExporter.requestWritePermission();
    } catch (e) {
      debugPrint('Health Connect write-permission request failed: $e');
    }
    await widget.preferences.setWriteToHealthConnect(granted);
    if (!mounted) return;
    setState(() {});
    if (!granted) {
      showTopBanner(
        context,
        'Health Connect permission not granted — runs won\'t be written.',
      );
    }
  }
}

class HeartRateMonitorTile extends StatefulWidget {
  final BleHeartRate heartRate;
  const HeartRateMonitorTile({super.key, required this.heartRate});

  @override
  State<HeartRateMonitorTile> createState() => _HeartRateMonitorTileState();
}

class _HeartRateMonitorTileState extends State<HeartRateMonitorTile> {
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
