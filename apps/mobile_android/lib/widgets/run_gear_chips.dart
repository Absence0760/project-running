import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import 'top_banner.dart';

/// Run-detail gear chips. Mirrors `apps/web/src/lib/components/
/// RunGearChips.svelte`. Renders the gear assigned to the run as
/// pill-shaped chips; owners get an inline "+ Tag gear" / "Edit"
/// affordance that opens a multi-select bottom sheet of the
/// runner's active gear inventory. RLS gates everything — non-owner
/// viewers of a public run see the chips read-only.
class RunGearChips extends StatefulWidget {
  final String runId;
  final String runOwnerId;
  final ApiClient api;
  const RunGearChips({
    super.key,
    required this.runId,
    required this.runOwnerId,
    required this.api,
  });

  @override
  State<RunGearChips> createState() => _RunGearChipsState();
}

class _RunGearChipsState extends State<RunGearChips> {
  List<GearRow> _assigned = const [];
  bool _loading = true;

  bool get _canManage => widget.api.userId == widget.runOwnerId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.api.fetchRunGear(widget.runId);
      if (!mounted) return;
      setState(() {
        _assigned = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openPicker() async {
    final List<Map<String, dynamic>> myGear;
    try {
      myGear = await widget.api.fetchMyGearWithDistance();
    } catch (e) {
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).runGearChipsLoadError('$e'));
      return;
    }
    if (!mounted) return;
    final picked = <String>{..._assigned.map((g) => g.id)};
    final saved = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          final l10n = AppLocalizations.of(ctx);
          final active = myGear.where((g) => g['retired_at'] == null).toList();
          return Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.runGearChipsPickerTitle,
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (active.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      l10n.runGearChipsEmpty,
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final g in active)
                          CheckboxListTile(
                            value: picked.contains(g['id']),
                            title: Text(g['name'] as String),
                            subtitle: () {
                              final brand = g['brand'] as String?;
                              final model = g['model'] as String?;
                              final s = [brand, model]
                                  .where((x) => x != null && x.isNotEmpty)
                                  .join(' ');
                              return s.isEmpty ? null : Text(s);
                            }(),
                            secondary: Icon(
                              g['kind'] == 'bike'
                                  ? Icons.directions_bike
                                  : Icons.directions_run,
                            ),
                            onChanged: (v) => setLocal(() {
                              if (v == true) {
                                picked.add(g['id'] as String);
                              } else {
                                picked.remove(g['id'] as String);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l10n.runGearChipsCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: active.isEmpty
                          ? null
                          : () => Navigator.pop(ctx, picked),
                      child: Text(l10n.runGearChipsSave),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );
    if (saved == null) return;
    try {
      await widget.api.setRunGear(widget.runId, saved.toList());
      await _load();
    } catch (e) {
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).runGearChipsSaveError('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_assigned.isEmpty && !_canManage) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final g in _assigned)
            Chip(
              avatar: Icon(
                g.kind == 'bike'
                    ? Icons.directions_bike
                    : Icons.directions_run,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              // Cap the chip + ellipsize so a long gear name can't blow
              // past the row width (RenderFlex overflow).
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(g.name, overflow: TextOverflow.ellipsis),
              ),
              visualDensity: VisualDensity.compact,
            ),
          if (_canManage)
            OutlinedButton(
              onPressed: _openPicker,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: Text(_assigned.isEmpty
                  ? l10n.runGearChipsTag
                  : l10n.runGearChipsEdit),
            ),
        ],
      ),
    );
  }
}
