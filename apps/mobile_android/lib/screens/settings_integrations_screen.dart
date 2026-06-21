import 'dart:async';
import 'dart:io' show Platform;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ble_heart_rate.dart';
import '../ble_treadmill.dart';
import '../health_connect_exporter.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../race_service.dart';
import '../strava.dart';
import '../widgets/top_banner.dart';
import 'races_screen.dart';

class SettingsIntegrationsScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final BleHeartRate heartRate;
  final BleTreadmill treadmill;
  final Preferences preferences;

  const SettingsIntegrationsScreen({
    super.key,
    required this.apiClient,
    required this.heartRate,
    required this.treadmill,
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
  final RaceService _raceService = RaceService();
  bool _runSignUpAvailable = false;
  bool _chronoTrackAvailable = false;

  @override
  void initState() {
    super.initState();
    _refreshIntegrations();
    _probeRunSignUp();
    _probeChronoTrack();
  }

  Future<void> _probeRunSignUp() async {
    try {
      final ok = await _raceService.isRunSignUpConfigured();
      if (mounted) setState(() => _runSignUpAvailable = ok);
    } catch (_) {
      if (mounted) setState(() => _runSignUpAvailable = false);
    }
  }

  Future<void> _probeChronoTrack() async {
    try {
      final ok = await _raceService.isChronoTrackConfigured();
      if (mounted) setState(() => _chronoTrackAvailable = ok);
    } catch (_) {
      if (mounted) setState(() => _chronoTrackAvailable = false);
    }
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

  static String _relTime(DateTime t, AppLocalizations l10n) {
    final diff = DateTime.now().toUtc().difference(t.toUtc());
    if (diff.inMinutes < 1) return l10n.integrationsJustNow;
    if (diff.inHours < 1) return l10n.integrationsMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.integrationsHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.integrationsDaysAgo(diff.inDays);
    return l10n.integrationsWeeksAgo((diff.inDays / 7).floor());
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
        showTopBanner(context, AppLocalizations.of(context).integrationsCouldNotOpen(e));
      }
    }
  }

  Future<void> _connectStrava() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    if (api == null) return;

    if (!isStravaConfigured()) {
      await _openExternal('https://threkir.com/settings/integrations');
      if (!mounted) return;
      showTopBanner(context, l10n.integrationsStravaBrowserHint);
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
              ? l10n.integrationsStravaCancelled
              : l10n.integrationsStravaSignInFailed(
                  cb.error ?? 'no code returned'),
        );
        return;
      }
      if (cb.state != state) {
        if (!mounted) return;
        showTopBanner(context, l10n.integrationsStravaCsrfMismatch);
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
        showTopBanner(context, l10n.integrationsStravaConnectFailed(err));
        return;
      }
      showTopBanner(context, l10n.integrationsStravaConnected);
      await _refreshIntegrations();
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.integrationsStravaSignInFailed(e));
    } finally {
      if (mounted) setState(() => _stravaBusy = false);
    }
  }

  Future<void> _syncStrava() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    if (api == null) return;
    setState(() => _stravaBusy = true);
    try {
      final res = await api.syncStrava();
      if (!mounted) return;
      final imported = (res['imported'] as num?)?.toInt() ?? 0;
      final skipped = (res['skipped'] as num?)?.toInt() ?? 0;
      showTopBanner(context, l10n.integrationsSyncResult(imported, skipped));
      await _refreshIntegrations();
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.integrationsSyncFailed(e));
    } finally {
      if (mounted) setState(() => _stravaBusy = false);
    }
  }

  Future<void> _disconnectStrava() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    if (api == null) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.integrationsStravaDisconnectTitle),
            content: Text(l10n.integrationsStravaDisconnectBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.integrationsCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.integrationsDisconnect),
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
      showTopBanner(context, l10n.integrationsStravaDisconnected);
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.integrationsDisconnectFailed(e));
    } finally {
      if (mounted) setState(() => _stravaBusy = false);
    }
  }

  void _openRaces() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RacesScreen(service: _raceService),
    ));
  }

  Future<void> _importParkrun() async {
    final l10n = AppLocalizations.of(context);
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
        title: Text(l10n.integrationsParkrunTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.integrationsParkrunBody),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 20,
              decoration: InputDecoration(
                labelText: l10n.integrationsParkrunFieldLabel,
                hintText: 'A123456',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.integrationsCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(l10n.integrationsImport),
          ),
        ],
      ),
    );
    if (athleteNumber == null || athleteNumber.isEmpty) return;
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(l10n.integrationsParkrunImporting)),
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
            ? l10n.integrationsParkrunImported(imported)
            : l10n.integrationsParkrunNoneNew,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showTopBanner(context, l10n.integrationsImportFailed(e));
    }
  }

  Widget _buildStravaTile() {
    final l10n = AppLocalizations.of(context);
    final s = _strava();
    final connected = s != null;
    final last = s?.lastSyncAt;
    final subtitle = !connected
        ? l10n.integrationsStravaConnectSubtitle
        : last == null
            ? l10n.integrationsStravaWaitingFirstSync
            : l10n.integrationsStravaLastSync(_relTime(last, l10n));
    return ListTile(
      leading: const Icon(Icons.sync, color: Color(0xFFFC4C02)),
      title: Text(l10n.integrationsStravaName),
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
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'sync', child: Text(l10n.integrationsSyncNow)),
                    PopupMenuItem(
                        value: 'disconnect',
                        child: Text(l10n.integrationsDisconnect)),
                  ],
                )
              : const Icon(Icons.chevron_right),
      onTap: _stravaBusy ? null : (connected ? _syncStrava : _connectStrava),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signedIn = widget.apiClient?.userId != null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.integrationsTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            if (signedIn) ...[
              _buildStravaTile(),
              ListTile(
                leading: const Icon(Icons.directions_run),
                title: Text(l10n.integrationsParkrunName),
                subtitle: Text(l10n.integrationsParkrunTileSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: _importParkrun,
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(l10n.integrationsRunsignup),
                subtitle: Text(_runSignUpAvailable
                    ? l10n.integrationsRunsignupConnect
                    : l10n.integrationsRunsignupUnavailable),
                trailing:
                    _runSignUpAvailable ? const Icon(Icons.chevron_right) : null,
                onTap: _runSignUpAvailable ? _openRaces : null,
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(l10n.integrationsChronotrack),
                subtitle: Text(_chronoTrackAvailable
                    ? l10n.integrationsChronotrackConnect
                    : l10n.integrationsChronotrackUnavailable),
                trailing:
                    _chronoTrackAvailable ? const Icon(Icons.chevron_right) : null,
                onTap: _chronoTrackAvailable ? _openRaces : null,
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(l10n.integrationsSignInTitle),
                subtitle: Text(l10n.integrationsSignInSubtitle),
              ),
            const Divider(),
            HeartRateMonitorTile(heartRate: widget.heartRate),
            const Divider(),
            TreadmillTile(treadmill: widget.treadmill),
            if (Platform.isAndroid) ...[
              const Divider(),
              SwitchListTile(
                secondary: const Icon(Icons.health_and_safety_outlined),
                title: Text(l10n.integrationsHealthConnectTitle),
                subtitle: Text(l10n.integrationsHealthConnectSubtitle),
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
      showTopBanner(context, AppLocalizations.of(context).integrationsHealthConnectDenied);
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
          showTopBanner(
              context, AppLocalizations.of(context).integrationsHrPairFailed(e));
        }
      }
      await _refresh();
    }
  }

  Future<void> _forget() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.integrationsHrTitle),
            content: Text(l10n.integrationsHrForgetConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.integrationsCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.integrationsHrForget),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await widget.heartRate.forget();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final paired = _pairedName;
    return ListTile(
      leading: const Icon(Icons.favorite_border),
      title: Text(l10n.integrationsHrTitle),
      subtitle: Text(
        _loading
            ? l10n.integrationsHrChecking
            : paired != null
                ? l10n.integrationsHrPaired(paired)
                : l10n.integrationsHrNotPaired,
      ),
      trailing: paired != null
          ? IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.integrationsHrForget,
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
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.integrationsHrScanTitle,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
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
            Text(
              l10n.integrationsHrScanHint,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (_results.isEmpty && !_scanning)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(l10n.integrationsHrScanEmpty),
              ),
            ..._results.map((r) {
              return ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(r.name),
                subtitle: Text(l10n.integrationsHrRssi(r.rssi)),
                onTap: () => Navigator.of(context).pop(r),
              );
            }),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.integrationsCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings tile to pair / forget a BLE FTMS treadmill. Mirrors
/// [HeartRateMonitorTile]; takes the app-owned [BleTreadmill] singleton so the
/// belt paired here is the same instance the run screen reads for treadmill
/// mode. While connected it shows the live belt speed so the user can confirm
/// the pairing works.
class TreadmillTile extends StatefulWidget {
  final BleTreadmill treadmill;
  const TreadmillTile({super.key, required this.treadmill});

  @override
  State<TreadmillTile> createState() => _TreadmillTileState();
}

class _TreadmillTileState extends State<TreadmillTile> {
  String? _pairedName;
  bool _loading = true;
  double? _liveSpeedKmh;
  StreamSubscription<TreadmillSample>? _sampleSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _sampleSub = widget.treadmill.stream.listen(
      (s) {
        if (mounted) setState(() => _liveSpeedKmh = s.instantaneousSpeedKmh);
      },
      onError: (Object e) => debugPrint('treadmill sample stream error: $e'),
    );
  }

  @override
  void dispose() {
    _sampleSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final name = await widget.treadmill.pairedName();
    if (!mounted) return;
    setState(() {
      _pairedName = name;
      _loading = false;
    });
  }

  Future<void> _pair() async {
    final device = await showModalBottomSheet<BleTreadmillCandidate>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TreadmillScanSheet(treadmill: widget.treadmill),
    );
    if (device != null) {
      try {
        await widget.treadmill.pair(device);
      } catch (e) {
        if (mounted) {
          showTopBanner(context,
              AppLocalizations.of(context).integrationsTreadmillPairFailed(e));
        }
      }
      await _refresh();
    }
  }

  Future<void> _forget() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.integrationsTreadmillTitle),
            content: Text(l10n.integrationsTreadmillForgetConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.integrationsCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.integrationsTreadmillForget),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await widget.treadmill.forget();
    if (mounted) setState(() => _liveSpeedKmh = null);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final paired = _pairedName;
    final live = _liveSpeedKmh;
    return ListTile(
      leading: const Icon(Icons.directions_run_outlined),
      title: Text(l10n.integrationsTreadmillTitle),
      subtitle: Text(
        _loading
            ? l10n.integrationsTreadmillChecking
            : live != null
                ? l10n.integrationsTreadmillLiveSpeed(live.toStringAsFixed(1))
                : paired != null
                    ? l10n.integrationsTreadmillPaired(paired)
                    : l10n.integrationsTreadmillNotPaired,
      ),
      trailing: paired != null
          ? IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.integrationsTreadmillForget,
              onPressed: _forget,
            )
          : const Icon(Icons.chevron_right),
      onTap: _pair,
    );
  }
}

class _TreadmillScanSheet extends StatefulWidget {
  final BleTreadmill treadmill;
  const _TreadmillScanSheet({required this.treadmill});

  @override
  State<_TreadmillScanSheet> createState() => _TreadmillScanSheetState();
}

class _TreadmillScanSheetState extends State<_TreadmillScanSheet> {
  List<BleTreadmillCandidate> _results = const [];
  bool _scanning = true;
  StreamSubscription<List<BleTreadmillCandidate>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.treadmill.scan().listen(
      (list) {
        if (mounted) setState(() => _results = list);
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
      onError: (Object e) {
        debugPrint('treadmill scan error: $e');
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
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.integrationsTreadmillScanTitle,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
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
            Text(
              l10n.integrationsTreadmillScanHint,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (_results.isEmpty && !_scanning)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(l10n.integrationsTreadmillScanEmpty),
              ),
            ..._results.map((r) {
              return ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(r.name),
                subtitle: Text(l10n.integrationsHrRssi(r.rssi)),
                onTap: () => Navigator.of(context).pop(r),
              );
            }),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.integrationsCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
