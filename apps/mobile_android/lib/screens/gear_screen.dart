import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../gear_backfill.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_gear_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../widgets/gear_backfill_sheet.dart';
import '../widgets/gear_form_sheet.dart';
import '../widgets/top_banner.dart';

/// Settings → Gear: per-user inventory of shoes and bikes plus the
/// rolled-up total mileage each item has accrued via assigned runs.
///
/// Reads + writes route through [LocalGearStore] so the screen stays
/// usable offline. On mount the store hydrates from disk (so previously-
/// loaded gear renders immediately on a cold offline start); a best-
/// effort server fetch overlays the latest mileage. Mutations
/// (create / edit / retire / unretire / delete) hit the store first,
/// which mirrors them to the server when online and queues them for
/// the next drain when not.
class GearScreen extends StatefulWidget {
  /// Optional. When null (no Supabase env vars OR user is signed-out),
  /// the screen reads + writes exclusively to [LocalGearStore]; the
  /// pending queue drains on the next mount that does have an api.
  final ApiClient? api;
  final Preferences preferences;
  final LocalGearStore store;

  /// Optional. When supplied, post-create the screen scans for past
  /// runs that match the new gear's activity-type + purchased_at and
  /// offers a backfill sheet so the user can attach them in one go.
  /// Without a run store the prompt is skipped — that path is fine,
  /// the user can still attach gear manually via each run's detail
  /// screen.
  final LocalRunStore? runStore;

  const GearScreen({
    super.key,
    required this.api,
    required this.preferences,
    required this.store,
    this.runStore,
  });

  @override
  State<GearScreen> createState() => _GearScreenState();
}

class _GearScreenState extends State<GearScreen> {
  bool _refreshing = false;
  bool _isOnline = true;
  String _activeKind = 'shoe';

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
    _refresh();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChange);
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    final api = widget.api;
    if (api == null || api.userId == null) {
      // No api or signed-out — rely on whatever the local store holds.
      // The pending queue stays put for the next mount that has an api.
      if (mounted) setState(() => _isOnline = false);
      return;
    }
    setState(() => _refreshing = true);
    try {
      final fresh = await api.fetchMyGearWithDistance();
      await widget.store.replaceFromServer(fresh);
      if (widget.store.hasPending) {
        await widget.store.syncWithServer(api);
      }
      _isOnline = true;
    } catch (e) {
      _isOnline = false;
      debugPrint('gear_screen: refresh failed, using cache: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  List<Map<String, dynamic>> get _visible =>
      widget.store.rows.where((r) => r['kind'] == _activeKind).toList();
  List<Map<String, dynamic>> get _active =>
      _visible.where((r) => r['retired_at'] == null).toList();
  List<Map<String, dynamic>> get _retired =>
      _visible.where((r) => r['retired_at'] != null).toList();

  Future<void> _maybeSync() async {
    final api = widget.api;
    if (api == null || !_isOnline) return;
    await widget.store.syncWithServer(api);
  }

  Future<void> _create() async {
    final result = await showGearFormSheet(
      context: context,
      store: widget.store,
      preferences: widget.preferences,
      kind: _activeKind,
    );
    if (result == null) return;
    await _maybeSync();
    if (result.isNew) await _maybeOfferBackfill(result);
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final result = await showGearFormSheet(
      context: context,
      store: widget.store,
      preferences: widget.preferences,
      kind: row['kind'] as String,
      existing: row,
    );
    if (result != null) await _maybeSync();
  }

  /// If the just-created gear has a past `purchased_at` AND we have
  /// a run store AND an online api, propose attaching the matching
  /// past runs in one go. Skip silently when any of those is
  /// missing — the user can still attach gear per-run via the run
  /// detail screen. Backfill is online-only because the
  /// pending-write queue for `run_gear` would be a separate piece
  /// of plumbing; the first version keeps the scope tight.
  Future<void> _maybeOfferBackfill(GearFormResult result) async {
    final runStore = widget.runStore;
    final api = widget.api;
    final purchased = result.purchasedAt;
    if (runStore == null ||
        api == null ||
        api.userId == null ||
        !_isOnline ||
        purchased == null) {
      return;
    }
    final now = DateTime.now();
    if (!purchased.isBefore(now)) return;
    final candidates = gearBackfillCandidates(
      gearKind: result.kind,
      since: purchased,
      runs: runStore.runs,
    );
    if (candidates.isEmpty) return;
    if (!mounted) return;
    final attached = await showGearBackfillSheet(
      context: context,
      api: api,
      preferences: widget.preferences,
      gearId: result.gearId,
      gearName: result.name,
      gearKind: result.kind,
      candidates: candidates,
    );
    if (!mounted || attached == null || attached == 0) return;
    showTopBanner(
      context,
      AppLocalizations.of(context).gearAttached(result.name, attached),
    );
    await _refresh();
  }

  Future<void> _retire(Map<String, dynamic> row) async {
    if (row['retired_at'] == null) {
      await widget.store.retireLocal(row['id'] as String);
    } else {
      await widget.store.unretireLocal(row['id'] as String);
    }
    await _maybeSync();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.gearDeleteTitle),
            content: Text(l10n.gearDeleteBody(row['name'] as String)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.gearCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(l10n.gearDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await widget.store.deleteLocal(row['id'] as String);
    await _maybeSync();
    if (mounted && !_isOnline) {
      showTopBanner(context, l10n.gearDeletedOffline);
    }
  }

  ({double pct, String label}) _progress(Map<String, dynamic> row) {
    final unit = widget.preferences.unit;
    final div = unit == DistanceUnit.mi ? 1609.344 : 1000.0;
    final unitLabel = unit == DistanceUnit.mi ? 'mi' : 'km';
    final accrued = (row['total_distance_m'] as num?)?.toDouble() ?? 0.0;
    final target = (row['target_distance_m'] as num?)?.toDouble() ?? 0.0;
    if (target <= 0) {
      return (pct: 0, label: '${(accrued / div).toStringAsFixed(1)} $unitLabel');
    }
    final pct = (accrued / target).clamp(0.0, 1.0);
    return (
      pct: pct,
      label:
          '${(accrued / div).toStringAsFixed(1)} / ${(target / div).toStringAsFixed(0)} $unitLabel'
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pendingCount = widget.store.hasPending
        ? widget.store.rows.length -
            widget.store.rows
                .where((r) => r['id'] != null && !widget.store.hasPending)
                .length
        : 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gearTitle),
        actions: [
          IconButton(
            tooltip: l10n.gearAddGear,
            icon: const Icon(Icons.add),
            onPressed: _refreshing ? null : _create,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isOnline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHigh,
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.store.hasPending && pendingCount > 0
                          ? l10n.gearOfflineQueued(pendingCount)
                          : l10n.gearOfflineCached,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'shoe',
                  label: Text(l10n.gearShoes),
                  icon: const Icon(Icons.directions_run),
                ),
                ButtonSegment(
                  value: 'bike',
                  label: Text(l10n.gearBikes),
                  icon: const Icon(Icons.directions_bike),
                ),
              ],
              selected: {_activeKind},
              onSelectionChanged: (s) => setState(() => _activeKind = s.first),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _visible.isEmpty
                  ? _emptyState(theme)
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final row in _active) _gearTile(row, theme),
                        if (_retired.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            l10n.gearRetired,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final row in _retired)
                            Opacity(opacity: 0.65, child: _gearTile(row, theme)),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _activeKind == 'shoe'
                      ? Icons.directions_run
                      : Icons.directions_bike,
                  size: 64,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  _activeKind == 'shoe'
                      ? l10n.gearEmptyShoes
                      : l10n.gearEmptyBikes,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.gearEmptySubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(l10n.gearAddGear),
                  onPressed: _create,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _gearTile(Map<String, dynamic> row, ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final prog = _progress(row);
    final name = row['name'] as String;
    final brand = row['brand'] as String?;
    final model = row['model'] as String?;
    final runCount = (row['run_count'] as num?)?.toInt() ?? 0;
    final hasTarget = (row['target_distance_m'] as num?) != null;
    final brandModel =
        [brand, model].where((s) => s != null && s.isNotEmpty).join(' ');
    return Card(
      child: InkWell(
        onTap: () => _edit(row),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleSmall),
                    if (brandModel.isNotEmpty)
                      Text(brandModel,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline)),
                    const SizedBox(height: 6),
                    if (hasTarget)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: prog.pct,
                          minHeight: 6,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(prog.label, style: theme.textTheme.bodySmall),
                        Text(
                          l10n.gearRunCount(runCount),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'retire') _retire(row);
                  if (v == 'delete') _delete(row);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'retire',
                    child: Text(row['retired_at'] == null
                        ? l10n.gearRetire
                        : l10n.gearRestore),
                  ),
                  PopupMenuItem(value: 'delete', child: Text(l10n.gearDelete)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
