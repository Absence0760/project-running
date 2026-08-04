import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors;

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../live_broadcaster.dart';
import '../live_freshness.dart';
import '../live_hub_client.dart';
import '../live_watch_forwarder.dart';
import '../privacy.dart';
import '../reactive_ble_watch_transport.dart';
import '../settings_sync.dart';
import '../sim_watch_sync.dart';
import '../watch_ingest_queue.dart';
import '../watch_status_link.dart';
import '../widgets/top_banner.dart';

/// Settings → Integrations → Custom watch: relays the watch's per-second BLE
/// status frames into the live spectator feed, so a run recorded on the wrist
/// is followable at `/live/{run_id}`.
///
/// This is the production caller [WatchStatusLink] (decisions §456) and
/// [WatchLiveForwarder] (§447) were built for; before it, the whole rail was
/// reachable only from the dev-gated Sim Watch screen's TCP link.
///
/// **Screen-scoped by design.** The relay lives exactly as long as this route
/// is mounted: leaving stops the link and concludes the broadcast. A relay
/// that outlived its surface would need a foreground service of its own, and
/// a runner would have no way to tell whether their position was still going
/// out.
///
/// **Stop around a sync (§456).** Two simultaneous `connectToDevice` streams
/// against one watch is not something flutter_reactive_ble promises, so
/// [_syncRuns] takes the status link down, syncs, and arms a *fresh* link
/// afterwards. The forwarder keeps its run id across that, so the spectator
/// follows one run rather than two.
///
/// L4 (`docs/architecture/conventions.md § Layered resilience`). Nothing here
/// touches recording — the run is on the wrist, and every BLE failure lands
/// as a state on this screen, never as an error into the frame stream.
class WatchLiveScreen extends StatefulWidget {
  final ApiClient? apiClient;

  /// Source of the runner's privacy zones for [LiveBroadcaster] (decisions
  /// §33). Null means no zones, which is what a signed-out or unsynced
  /// device already reports.
  final SettingsSyncService? settingsSync;

  /// Builds the status link. Called afresh on every arm — a spent link is
  /// never re-started (§456), and a new one buys a new scan.
  final WatchStatusLink Function() linkFactory;

  /// The run-sync transport, separate from the status link's connection.
  final WatchBleTransport Function() transportFactory;

  /// Where a decoded watch run is delivered by [_syncRuns].
  final WatchRunSink runSink;

  /// Injectable so a test can age a frame past [liveStaleAfterMs] without
  /// waiting; shared with the forwarder so its freshness and this screen's
  /// clock can't disagree.
  final DateTime Function() now;

  const WatchLiveScreen({
    super.key,
    required this.apiClient,
    this.settingsSync,
    this.linkFactory = _defaultLinkFactory,
    this.transportFactory = ReactiveBleWatchTransport.new,
    this.runSink = _defaultRunSink,
    this.now = DateTime.now,
  });

  static WatchStatusLink _defaultLinkFactory() =>
      WatchStatusLink(ReactiveBleWatchFrameSource());

  static Future<void> _defaultRunSink(Map<String, dynamic> payload) async {
    final queue = WatchIngestQueue();
    await queue.init();
    await queue.enqueue(payload);
  }

  @override
  State<WatchLiveScreen> createState() => _WatchLiveScreenState();
}

enum _RelayState { off, connecting, live, gap, lost }

class _WatchLiveScreenState extends State<WatchLiveScreen> {
  WatchStatusLink? _link;
  WatchLiveForwarder? _forwarder;
  Timer? _ticker;
  bool _busy = false;
  bool _syncing = false;
  String? _syncMessage;

  @override
  void dispose() {
    _ticker?.cancel();
    final link = _link;
    final forwarder = _forwarder;
    _link = null;
    _forwarder = null;
    unawaited(_teardown(link, forwarder));
    super.dispose();
  }

  Future<void> _teardown(
      WatchStatusLink? link, WatchLiveForwarder? forwarder) async {
    await link?.stop();
    await forwarder?.stop();
  }

  _RelayState get _state {
    final link = _link;
    if (link == null) return _RelayState.off;
    if (link.state == WatchLinkState.lost) return _RelayState.lost;
    final fresh = _forwarder?.linkFreshness();
    if (fresh == null) return _RelayState.connecting;
    return fresh.stale ? _RelayState.gap : _RelayState.live;
  }

  List<PrivacyZone> _privacyZones() {
    final service = widget.settingsSync?.service;
    if (service == null) return const [];
    try {
      final raw = service.effective<List<dynamic>>(
        privacyZonesKey,
        fallback: const <dynamic>[],
      );
      if (raw == null || raw.isEmpty) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(PrivacyZone.fromJson)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[WatchLiveScreen] privacy zones read failed: $e');
      return const [];
    }
  }

  String _env(String key) {
    try {
      if (!dotenv.isInitialized) return '';
      return dotenv.env[key] ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Start (or re-arm after a sync / a give-up) the relay. Never throws: a
  /// backend that refuses the broadcast leaves the screen off with a reason,
  /// and a watch that is absent leaves the link retrying on its own ladder.
  Future<void> _arm() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      if (mounted) showTopBanner(context, _l10n.runLiveShareNeedsSignIn);
      return;
    }
    final hubUrl = _env('LIVE_HUB_URL');
    final forwarder = _forwarder ??= WatchLiveForwarder(
      api: api,
      broadcaster: LiveBroadcaster(
        api,
        hubClient: hubUrl.isNotEmpty ? LiveHubClient(baseUrl: hubUrl) : null,
        privacyZonesProvider: _privacyZones,
      ),
      now: widget.now,
    );
    final link = widget.linkFactory();
    // Subscribe before the radio opens so the first frame can't be missed.
    final runId = await forwarder.start(link.frames);
    if (runId == null) {
      await link.stop();
      if (mounted) showTopBanner(context, _l10n.watchLiveStartFailed);
      return;
    }
    if (!mounted) {
      await link.stop();
      return;
    }
    _link = link;
    _ticker?.cancel();
    // Freshness ages with the wall clock, so a gap has to appear without any
    // new frame arriving — nothing else would ever repaint it.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    setState(() {});
    await link.start();
  }

  /// Take the radio down without ending the broadcast — the §456 pre-sync
  /// step. The forwarder keeps its run id so a re-arm resumes the same run.
  Future<void> _pause() async {
    _ticker?.cancel();
    _ticker = null;
    final link = _link;
    _link = null;
    await link?.stop();
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    await _pause();
    final forwarder = _forwarder;
    _forwarder = null;
    await forwarder?.stop();
    if (mounted) setState(() {});
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    switch (_state) {
      // A link that gave up is spent (§456): retrying means a fresh one,
      // which the forwarder joins to the SAME run rather than a second.
      case _RelayState.lost:
        await _pause();
        await _arm();
      case _RelayState.off:
        await _arm();
      case _RelayState.connecting:
      case _RelayState.live:
      case _RelayState.gap:
        await _stop();
    }
  }

  Future<void> _share() async {
    final runId = _forwarder?.runId;
    if (runId == null) return;
    final base = _env('WEB_BASE_URL');
    final root = base.isEmpty
        ? 'https://threkir.com'
        : base.replaceAll(RegExp(r'/+$'), '');
    try {
      await Share.share('$root/live/$runId', subject: _l10n.runShareSubject);
    } catch (e) {
      debugPrint('[WatchLiveScreen] share failed: $e');
      if (mounted) {
        showTopBanner(context, _l10n.runCouldNotShareLink(friendlyError(_l10n, e)));
      }
    }
  }

  Future<void> _syncRuns() async {
    if (_syncing) return;
    final wasArmed = _link != null;
    setState(() {
      _syncing = true;
      _syncMessage = _l10n.simWatchSyncing(0, 0);
    });
    if (wasArmed) await _pause();
    try {
      final client = WatchSyncClient(
        transport: widget.transportFactory(),
        onRun: widget.runSink,
      );
      final result = await client.sync(
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _syncMessage = _l10n.simWatchSyncing(done, total));
          }
        },
      );
      if (mounted) {
        setState(() => _syncMessage = result.total == 0
            ? _l10n.simWatchNoRuns
            : _l10n.simWatchResult(result.synced, result.total));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _syncMessage = _l10n.simWatchSyncFailed('$e'));
      }
    } finally {
      if (wasArmed && mounted) await _arm();
      if (mounted) setState(() => _syncing = false);
    }
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  String _stateLabel(_RelayState state) {
    switch (state) {
      case _RelayState.off:
        return _l10n.watchLiveStateOff;
      case _RelayState.connecting:
        return _l10n.watchLiveStateConnecting;
      case _RelayState.live:
        return _l10n.watchLiveStateLive;
      case _RelayState.gap:
        return _l10n.watchLiveStateGap;
      case _RelayState.lost:
        return _l10n.watchLiveStateLost;
    }
  }

  String _stateDetail(_RelayState state) {
    switch (state) {
      case _RelayState.off:
        return _l10n.watchLiveDetailOff;
      case _RelayState.connecting:
        return _link?.state == WatchLinkState.connected
            ? _l10n.watchLiveDetailAwaitingFix
            : _l10n.watchLiveDetailSearching;
      case _RelayState.live:
        return _freshnessLabel(_forwarder!.linkFreshness()!);
      case _RelayState.gap:
        return '${_freshnessLabel(_forwarder!.linkFreshness()!)} — '
            '${_l10n.watchLiveDetailGap}';
      case _RelayState.lost:
        return _l10n.watchLiveDetailLost;
    }
  }

  String _freshnessLabel(Freshness f) {
    switch (f.bucket) {
      case FreshnessBucket.now:
        return _l10n.liveUpdatedNow;
      case FreshnessBucket.seconds:
        return _l10n.liveUpdatedSeconds(f.value);
      case FreshnessBucket.minutes:
        return _l10n.liveUpdatedMinutes(f.value);
      case FreshnessBucket.hours:
        return _l10n.liveUpdatedHours(f.value);
      case FreshnessBucket.days:
        return _l10n.liveUpdatedDays(f.value);
    }
  }

  Color _stateColour(_RelayState state, ThemeData theme) {
    final scheme = theme.colorScheme;
    switch (state) {
      case _RelayState.off:
        return scheme.onSurfaceVariant;
      case _RelayState.connecting:
        return scheme.primary;
      case _RelayState.live:
        return AppSemanticColors.ofTheme(theme).success;
      case _RelayState.gap:
        return AppSemanticColors.ofTheme(theme).warning;
      case _RelayState.lost:
        return scheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final theme = Theme.of(context);
    final state = _state;
    final runId = _forwarder?.runId;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.watchLiveTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.watchLiveIntro, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _stateColour(state, theme),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _stateLabel(state),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _stateColour(state, theme),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _stateDetail(state),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed:
                  _busy || _syncing ? null : () => _guard(_toggle),
              child: Text(
                switch (state) {
                  _RelayState.lost => l10n.watchLiveRetry,
                  _RelayState.off => l10n.watchLiveStart,
                  _ => l10n.watchLiveStop,
                },
              ),
            ),
            if (state == _RelayState.lost) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy || _syncing ? null : () => _guard(_stop),
                child: Text(l10n.watchLiveStop),
              ),
            ],
            if (runId != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _share,
                icon: const Icon(Icons.ios_share),
                label: Text(l10n.watchLiveShare),
              ),
            ],
            const Divider(height: 40),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _syncing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              title: Text(l10n.watchLiveSyncAction),
              subtitle: Text(l10n.watchLiveSyncSubtitle),
              onTap: _syncing || _busy ? null : _syncRuns,
            ),
            if (_syncMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_syncMessage!, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}
