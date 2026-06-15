import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../local_crossings_store.dart';
import '../l10n/gen/app_localizations.dart';
import '../widgets/top_banner.dart';

/// P3 weigh-in fields are Art 9 health data — gated fail-closed behind this
/// dotenv flag (OFF by default; mirrors `ADAPTIVE_FITNESS_GATE` in
/// plan_detail_screen). When off, the screen never collects or sends body
/// weight / medical-hold data. Production enablement is the owner+CISO+counsel
/// sign-off (decisions §150).
bool get _weighInGate {
  try {
    final v = dotenv.env['WEIGH_IN_GATE'];
    return v == '1' || v == 'true';
  } catch (_) {
    return false;
  }
}

/// Offline aid-station check-in for race-crew volunteers. Pick the checkpoint,
/// enter/scan a bib (account linkage optional), stamp IN / OUT. Writes flow
/// through [LocalCrossingsStore] so the surface works fully offline; the server
/// merges two volunteers' stamps via the upsert RPC. Reached from an
/// organiser-gated action on the event detail screen.
class CheckpointCheckinScreen extends StatefulWidget {
  final String eventId;
  final DateTime instanceStart;

  /// Test seam — production passes null and the screen builds its own.
  final ApiClient? api;
  final LocalCrossingsStore? store;

  const CheckpointCheckinScreen({
    super.key,
    required this.eventId,
    required this.instanceStart,
    this.api,
    this.store,
  });

  @override
  State<CheckpointCheckinScreen> createState() =>
      _CheckpointCheckinScreenState();
}

class _CheckpointCheckinScreenState extends State<CheckpointCheckinScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late final LocalCrossingsStore _store = widget.store ?? LocalCrossingsStore();
  final TextEditingController _bib = TextEditingController();

  List<EventCheckpointRow> _checkpoints = const [];
  EventCheckpointRow? _selected;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _bib.dispose();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      if (_store.dir == null) await _store.init();
      final checkpoints = await _api.fetchEventCheckpoints(widget.eventId);
      // Best-effort overlay of already-synced crossings so the volunteer sees
      // who's been stamped from another phone; pending local stamps survive it.
      try {
        final crossings = await _api.fetchCheckpointCrossings(
            widget.eventId, widget.instanceStart);
        await _store
            .replaceFromServer(crossings.map((c) => c.toJson()).toList());
      } catch (_) {
        // Offline / not yet synced — the local store is the source of truth.
      }
      if (!mounted) return;
      setState(() {
        _checkpoints = checkpoints;
        _selected ??= checkpoints.isNotEmpty ? checkpoints.first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _store.syncWithServer(_api);
    await _load();
  }

  Future<void> _stamp({required bool isOut}) async {
    final cp = _selected;
    final bib = _bib.text.trim();
    if (cp == null) return;
    final l10n = AppLocalizations.of(context);
    if (bib.isEmpty) {
      showTopBanner(context, l10n.checkpointBibRequired);
      return;
    }

    var healthConsent = false;
    double? bodyWeightKg;
    bool? medicalHold;
    if (_weighInGate && cp.requiresWeighIn) {
      final result = await _showWeighInSheet();
      if (result == null) return; // cancelled
      healthConsent = result.consent;
      if (healthConsent) {
        bodyWeightKg = result.bodyWeightKg;
        medicalHold = result.medicalHold;
      }
    }

    setState(() => _busy = true);
    final now = DateTime.now().toUtc();
    try {
      await _store.createLocal(
        eventId: widget.eventId,
        checkpointId: cp.id,
        instanceStart: widget.instanceStart,
        bib: bib,
        inTime: isOut ? null : now,
        outTime: isOut ? now : null,
        healthConsent: healthConsent,
        bodyWeightKg: bodyWeightKg,
        medicalHold: medicalHold,
      );
      // Best-effort immediate push; the offline store keeps it pending on
      // failure and drains on the next refresh / connectivity return.
      try {
        await _store.syncWithServer(_api);
      } catch (_) {}
      if (!mounted) return;
      _bib.clear();
      showTopBanner(
        context,
        isOut ? l10n.checkpointStampedOut(bib) : l10n.checkpointStampedIn(bib),
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.checkpointStampFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_WeighInResult?> _showWeighInSheet() {
    return showModalBottomSheet<_WeighInResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _WeighInSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.checkpointCheckinTitle),
        actions: [
          if (_store.hasPending)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  l10n.checkpointPending,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ),
          IconButton(
            tooltip: l10n.checkpointSyncNow,
            icon: const Icon(Icons.sync),
            onPressed: _busy ? null : _refresh,
          ),
        ],
      ),
      body: _buildBody(l10n, theme),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.checkpointLoadFailed,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _load, child: Text(l10n.checkpointRetry)),
            ],
          ),
        ),
      );
    }
    if (_checkpoints.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.checkpointNone,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
      );
    }

    final selected = _selected;
    final stamped = selected == null
        ? const <Map<String, dynamic>>[]
        : _store.rowsForCheckpoint(
            widget.eventId, selected.id, widget.instanceStart);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.checkpointPickLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: selected?.id,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final cp in _checkpoints)
                DropdownMenuItem(
                  value: cp.id,
                  child: Text(cp.requiresWeighIn && _weighInGate
                      ? '${cp.name}  ⚖'
                      : cp.name),
                ),
            ],
            onChanged: (id) => setState(() {
              _selected = _checkpoints.firstWhere((c) => c.id == id);
            }),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _bib,
            autofocus: true,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              labelText: l10n.checkpointBibLabel,
              hintText: l10n.checkpointBibHint,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.tag),
            ),
            onSubmitted: (_) => _busy ? null : _stamp(isOut: false),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _stamp(isOut: false),
                  icon: const Icon(Icons.login),
                  label: Text(l10n.checkpointStampIn),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _stamp(isOut: true),
                  icon: const Icon(Icons.logout),
                  label: Text(l10n.checkpointStampOut),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            l10n.checkpointLoggedHere(stamped.length),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          if (stamped.isEmpty)
            Text(
              l10n.checkpointNoneLoggedHere,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            )
          else
            for (final r in stamped)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.person_outline),
                title: Text(r['bib'] != null
                    ? l10n.checkpointBibRow('${r['bib']}')
                    : (r['runner_name'] as String? ?? '—')),
                subtitle: Text(_inOutSummary(l10n, r)),
              ),
        ],
      ),
    );
  }

  String _inOutSummary(AppLocalizations l10n, Map<String, dynamic> r) {
    String fmt(dynamic v) {
      final dt = v is String ? DateTime.tryParse(v)?.toLocal() : null;
      if (dt == null) return '—';
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }

    return l10n.checkpointInOut(fmt(r['in_time']), fmt(r['out_time']));
  }
}

class _WeighInResult {
  final bool consent;
  final double? bodyWeightKg;
  final bool? medicalHold;
  const _WeighInResult({
    required this.consent,
    this.bodyWeightKg,
    this.medicalHold,
  });
}

/// Art 9 weigh-in capture, only reachable when `WEIGH_IN_GATE` is on AND the
/// checkpoint requires a weigh-in. Body weight + medical hold persist only
/// after the explicit on-screen consent toggle (mirrors the Art 9 consent
/// pattern in settings_body_metrics_screen).
class _WeighInSheet extends StatefulWidget {
  @override
  State<_WeighInSheet> createState() => _WeighInSheetState();
}

class _WeighInSheetState extends State<_WeighInSheet> {
  final TextEditingController _weight = TextEditingController();
  bool _consent = false;
  bool _medicalHold = false;

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + insets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.checkpointWeighInTitle,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            l10n.checkpointWeighInConsentBlurb,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.checkpointWeighInConsent,
                style: theme.textTheme.bodyMedium),
            value: _consent,
            onChanged: (v) => setState(() => _consent = v),
          ),
          if (_consent) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _weight,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.checkpointWeighInWeightKg,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.checkpointMedicalHold,
                  style: theme.textTheme.bodyMedium),
              value: _medicalHold,
              onChanged: (v) => setState(() => _medicalHold = v ?? false),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.checkpointCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(_WeighInResult(
                    consent: _consent,
                    bodyWeightKg: _consent
                        ? double.tryParse(_weight.text.trim())
                        : null,
                    medicalHold: _consent ? _medicalHold : null,
                  ));
                },
                child: Text(l10n.checkpointWeighInSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
