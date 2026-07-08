// Dev-only screen: live status from the simulated custom watch.
//
// Reached from Settings only when the backend is a loopback Supabase
// (dev/prod isolation — see dev_auto_login.dart). Connects to the
// watch-sim phone link (bin/watch-sim.sh) and renders each status frame
// as it arrives, so "the emulated watch and the phone app talk to each
// other" is verifiable end-to-end on a workstation.

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../reactive_ble_watch_transport.dart';
import '../sim_watch_link.dart';
import '../sim_watch_sync.dart';
import '../watch_ingest_queue.dart';

class SimWatchScreen extends StatefulWidget {
  final SimWatchLink Function(String host, int port) linkFactory;

  /// Injectable so a widget test can drive the run-sync path with a fake BLE
  /// transport (the real one needs a paired watch + a SoftDevice radio).
  final WatchBleTransport Function() transportFactory;

  /// Where a decoded watch run is delivered. Defaults to the existing
  /// [WatchIngestQueue] (drains to `api.saveRun` on the next sign-in), so this
  /// dev screen needs no `ApiClient` of its own.
  final WatchRunSink runSink;

  const SimWatchScreen({
    super.key,
    this.linkFactory = _defaultLinkFactory,
    this.transportFactory = _defaultTransportFactory,
    this.runSink = _defaultRunSink,
  });

  static SimWatchLink _defaultLinkFactory(String host, int port) =>
      SimWatchLink(host: host, port: port);

  static WatchBleTransport _defaultTransportFactory() =>
      ReactiveBleWatchTransport();

  static Future<void> _defaultRunSink(Map<String, dynamic> payload) async {
    final queue = WatchIngestQueue();
    await queue.init();
    await queue.enqueue(payload);
  }

  @override
  State<SimWatchScreen> createState() => _SimWatchScreenState();
}

enum _LinkState { idle, connecting, connected, failed }

class _SimWatchScreenState extends State<SimWatchScreen> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  SimWatchLink? _link;
  StreamSubscription<SimWatchStatus>? _subscription;
  _LinkState _state = _LinkState.idle;
  String? _error;
  SimWatchStatus? _status;
  bool _syncing = false;
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: simWatchDefaultHost());
    _port = TextEditingController(text: '$simWatchDefaultPort');
  }

  @override
  void dispose() {
    _teardown();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _teardown() {
    _subscription?.cancel();
    _subscription = null;
    _link?.close();
    _link = null;
  }

  Future<void> _connect() async {
    final port = int.tryParse(_port.text.trim()) ?? simWatchDefaultPort;
    final link = widget.linkFactory(_host.text.trim(), port);
    setState(() {
      _state = _LinkState.connecting;
      _error = null;
      _status = null;
      _link = link;
    });
    try {
      final frames = await link.connect();
      if (!mounted || _link != link) return;
      _subscription = frames.listen(
        (status) => setState(() => _status = status),
        onError: (Object e) => _dropped('$e'),
        onDone: () => _dropped(null),
      );
      setState(() => _state = _LinkState.connected);
    } catch (e) {
      if (!mounted || _link != link) return;
      setState(() {
        _state = _LinkState.failed;
        _error = '$e';
      });
    }
  }

  void _dropped(String? error) {
    if (!mounted) return;
    _teardown();
    setState(() {
      _state = error == null ? _LinkState.idle : _LinkState.failed;
      _error = error;
    });
  }

  void _disconnect() {
    _teardown();
    setState(() {
      _state = _LinkState.idle;
      _status = null;
    });
  }

  Future<void> _syncRuns() async {
    if (_syncing) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _syncing = true;
      _syncMessage = l10n.simWatchSyncing(0, 0);
    });
    try {
      final client = WatchSyncClient(
        transport: widget.transportFactory(),
        onRun: widget.runSink,
      );
      final result = await client.sync(
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _syncMessage = l10n.simWatchSyncing(done, total));
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _syncMessage = result.total == 0
            ? l10n.simWatchNoRuns
            : l10n.simWatchResult(result.synced, result.total);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncMessage = l10n.simWatchSyncFailed('$e'));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _hms(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds ~/ 60) % 60;
    final s = totalSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final connected = _state == _LinkState.connected;
    final busy = _state == _LinkState.connecting;
    final status = _status;
    final fix = status?.fix;
    final elev = status?.elev;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.simWatchTitle),
        actions: [
          IconButton(
            tooltip: l10n.simWatchSyncAction,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: _syncing ? null : _syncRuns,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_syncMessage != null) ...[
            Text(_syncMessage!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _host,
                  enabled: !connected && !busy,
                  decoration:
                      InputDecoration(labelText: l10n.simWatchHostLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _port,
                  enabled: !connected && !busy,
                  keyboardType: TextInputType.number,
                  decoration:
                      InputDecoration(labelText: l10n.simWatchPortLabel),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : (connected ? _disconnect : _connect),
            child: Text(
              busy
                  ? l10n.simWatchConnecting
                  : connected
                      ? l10n.simWatchDisconnect
                      : l10n.simWatchConnect,
            ),
          ),
          const SizedBox(height: 16),
          if (_state == _LinkState.failed && _error != null)
            Text(
              l10n.simWatchConnectionFailed(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (connected && status == null) Text(l10n.simWatchWaitingFrames),
          if (status != null) ...[
            ListTile(
              dense: true,
              title: Text(l10n.simWatchUptime),
              trailing: Text(_hms(status.uptimeS)),
            ),
            if (fix == null)
              ListTile(dense: true, title: Text(l10n.simWatchNoFix))
            else ...[
              ListTile(
                dense: true,
                title: Text(l10n.simWatchPosition),
                trailing: Text(
                  '${fix.lat.toStringAsFixed(5)}, '
                  '${fix.lon.toStringAsFixed(5)}',
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l10n.simWatchSpeed),
                trailing: Text('${fix.speedMps.toStringAsFixed(1)} m/s'),
              ),
              ListTile(
                dense: true,
                title: Text(l10n.simWatchSatellites),
                trailing: Text('${fix.sats}'),
              ),
              if (fix.altM != null)
                ListTile(
                  dense: true,
                  title: Text(l10n.simWatchAltitude),
                  trailing: Text('${fix.altM!.toStringAsFixed(0)} m'),
                ),
              ListTile(
                dense: true,
                title: Text(l10n.simWatchFixAge),
                trailing: Text(l10n.simWatchSeconds(fix.ageS)),
              ),
            ],
            if (elev != null) ...[
              ListTile(
                dense: true,
                title: Text(l10n.simWatchBaroAltitude),
                trailing: Text('${elev.altM.toStringAsFixed(0)} m'),
              ),
              ListTile(
                dense: true,
                title: Text(l10n.simWatchAscent),
                trailing: Text('+${elev.gainM.toStringAsFixed(0)} m'),
              ),
              ListTile(
                dense: true,
                title: Text(l10n.simWatchDescent),
                trailing: Text('-${elev.lossM.toStringAsFixed(0)} m'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
