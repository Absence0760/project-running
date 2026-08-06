import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show
        AppSemanticColors,
        AppTheme,
        ChoiceChipOption,
        ChoiceChipRow,
        EmptyState,
        ProgressBar,
        StatusPill,
        StatusPillSize;

import '../gear_backfill.dart';
import '../gear_wear.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../local_gear_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../widgets/gear_backfill_sheet.dart';
import '../widgets/gear_form_sheet.dart';
import '../widgets/pending_sync_banner.dart';
import '../widgets/top_banner.dart';
import 'gear_rotations_screen.dart';

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
    if (mounted && widget.store.hasPending) setState(() {});
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

  /// Open the rotations management screen. Online-only (gated in the
  /// AppBar): rotations live outside [LocalGearStore], like the wear-log
  /// + backfill sub-flows.
  Future<void> _openRotations() async {
    final api = widget.api;
    if (api == null || api.userId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GearRotationsScreen(api: api, gearStore: widget.store),
      ),
    );
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final result = await showGearFormSheet(
      context: context,
      store: widget.store,
      preferences: widget.preferences,
      kind: row['kind'] as String,
      existing: row,
      api: widget.api,
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
      // Backfill scans from the gear's purchase date — potentially years back —
      // so it reads the full-history index (activity_type + startedAt), not the
      // resident window. Only ids flow on from here (addGearToRuns).
      runs: runStore.summaryRuns,
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
                style: TextButton.styleFrom(
                    foregroundColor: AppSemanticColors.of(context).danger),
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
    final tag = activeLocaleTag;
    if (target <= 0) {
      return (
        pct: 0,
        label: '${formatFixed(accrued / div, 1, tag)} $unitLabel'
      );
    }
    final pct = (accrued / target).clamp(0.0, 1.0);
    return (
      pct: pct,
      label:
          '${formatFixed(accrued / div, 1, tag)} / ${formatFixed(target / div, 0, tag)} $unitLabel'
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gearTitle),
        actions: [
          if (widget.api != null && widget.api!.userId != null)
            IconButton(
              tooltip: l10n.gearRotationsTitle,
              icon: const Icon(Icons.sync_alt),
              onPressed: _refreshing ? null : _openRotations,
            ),
          IconButton(
            tooltip: l10n.gearAddGear,
            icon: const Icon(Icons.add),
            onPressed: _refreshing ? null : _create,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isOnline && !widget.store.hasPending)
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
                      l10n.gearOfflineCached,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          PendingSyncBanner(
            api: widget.api,
            isOnline: _isOnline,
            stores: [widget.store],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ChoiceChipRow<String>(
              options: [
                ChoiceChipOption(
                  value: 'shoe',
                  label: l10n.gearShoes,
                  icon: Icons.directions_run,
                ),
                ChoiceChipOption(
                  value: 'bike',
                  label: l10n.gearBikes,
                  icon: Icons.directions_bike,
                ),
              ],
              selected: _activeKind,
              onChanged: (v) => setState(() => _activeKind = v),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _visible.isEmpty
                  ? EmptyState(
                      icon: _activeKind == 'shoe'
                          ? Icons.directions_run
                          : Icons.directions_bike,
                      title: _activeKind == 'shoe'
                          ? l10n.gearEmptyShoes
                          : l10n.gearEmptyBikes,
                      body: l10n.gearEmptySubtitle,
                      ctaLabel: l10n.gearAddGear,
                      onCta: _create,
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final row in _active) _gearTile(row, theme),
                        if (_retired.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            l10n.gearRetired,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final row in _retired)
                            Opacity(
                                opacity: AppTheme.dimmedSubtreeOpacity,
                                child: _gearTile(row, theme)),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _wearBadge(GearWear wear, ThemeData theme, AppLocalizations l10n) {
    final semantic = AppSemanticColors.ofTheme(theme);
    final (Color bg, Color fg, IconData icon, String label) = switch (
        wear.status) {
      GearWearStatus.due => (
          semantic.warning,
          semantic.onWarning,
          Icons.schedule,
          l10n.gearWearDue,
        ),
      GearWearStatus.worn => (
          theme.colorScheme.errorContainer,
          theme.colorScheme.onErrorContainer,
          Icons.change_circle,
          l10n.gearWearWorn,
        ),
      _ => (Colors.transparent, Colors.transparent, Icons.circle, ''),
    };
    if (label.isEmpty) return null;
    return StatusPill(
      label: label,
      foreground: fg,
      fill: bg,
      icon: icon,
      size: StatusPillSize.compact,
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
    // Retired gear shows no wear warning — it's off the rotation, so "replace
    // soon" is moot. Mirrors web, which only classifies the active list.
    final wear = row['retired_at'] != null
        ? const GearWear(GearWearStatus.untracked, null)
        : gearWear(
            row['total_distance_m'] as num?, row['target_distance_m'] as num?);
    final wearBadge = _wearBadge(wear, theme, l10n);
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
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        // Cap the name + ellipsize so a long gear name can't
                        // blow past the card width (RenderFlex overflow) —
                        // Wrap doesn't width-constrain its children the way
                        // Row/Column do. Mirrors run_gear_chips.dart.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            name,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ?wearBadge,
                      ],
                    ),
                    if (brandModel.isNotEmpty)
                      Text(brandModel,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    if (hasTarget)
                      ProgressBar(
                        value: prog.pct,
                        // Not colorScheme.error: it is 2.991:1 against the
                        // bar's track in light. danger is the token that
                        // clears it.
                        fill: switch (wear.status) {
                          GearWearStatus.due =>
                            AppSemanticColors.ofTheme(theme).warning,
                          GearWearStatus.worn =>
                            AppSemanticColors.ofTheme(theme).danger,
                          _ => null,
                        },
                      ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(prog.label, style: theme.textTheme.bodySmall),
                        Flexible(
                          child: Text(
                            l10n.gearRunCount(runCount),
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
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
