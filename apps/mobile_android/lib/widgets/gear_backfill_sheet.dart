import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import 'top_banner.dart';

/// Post-create backfill sheet: after the user adds a new piece of
/// gear with a `purchased_at` in the past, this sheet proposes the
/// runs from since-then-until-now that could plausibly be in it.
/// All matching runs are selected by default; the user can deselect
/// individual rows then tap "Attach". On confirm we issue a single
/// [ApiClient.addGearToRuns] call.
///
/// Returns the count of runs the user attached, or null on cancel.
Future<int?> showGearBackfillSheet({
  required BuildContext context,
  required ApiClient api,
  required Preferences preferences,
  required String gearId,
  required String gearName,
  required String gearKind,
  required List<cm.Run> candidates,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _GearBackfillSheet(
      api: api,
      preferences: preferences,
      gearId: gearId,
      gearName: gearName,
      gearKind: gearKind,
      candidates: candidates,
    ),
  );
}

class _GearBackfillSheet extends StatefulWidget {
  final ApiClient api;
  final Preferences preferences;
  final String gearId;
  final String gearName;
  final String gearKind;
  final List<cm.Run> candidates;

  const _GearBackfillSheet({
    required this.api,
    required this.preferences,
    required this.gearId,
    required this.gearName,
    required this.gearKind,
    required this.candidates,
  });

  @override
  State<_GearBackfillSheet> createState() => _GearBackfillSheetState();
}

class _GearBackfillSheetState extends State<_GearBackfillSheet> {
  late final Set<String> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.candidates.map((r) => r.id).toSet();
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAll(bool value) {
    setState(() {
      _selected.clear();
      if (value) {
        _selected.addAll(widget.candidates.map((r) => r.id));
      }
    });
  }

  Future<void> _attach() async {
    if (_selected.isEmpty) {
      Navigator.pop(context, 0);
      return;
    }
    setState(() => _saving = true);
    try {
      final n = await widget.api
          .addGearToRuns(widget.gearId, _selected.toList(growable: false));
      if (!mounted) return;
      Navigator.pop(context, n);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTopBanner(
          context, AppLocalizations.of(context).gearBackfillAttachError('$e'));
    }
  }

  String _formatRunLabel(cm.Run r) {
    final unit = widget.preferences.unit;
    final distance = UnitFormat.distance(r.distanceMetres, unit);
    final date =
        '${r.startedAt.toLocal().year}-${r.startedAt.toLocal().month.toString().padLeft(2, '0')}-${r.startedAt.toLocal().day.toString().padLeft(2, '0')}';
    return '$date  •  $distance';
  }

  IconData _activityIcon(cm.Run r) {
    final activity =
        (r.metadata?['activity_type'] as String?)?.toLowerCase() ?? 'run';
    switch (activity) {
      case 'cycle':
        return Icons.directions_bike;
      case 'walk':
        return Icons.directions_walk;
      case 'hike':
        return Icons.terrain;
      case 'run':
      default:
        return Icons.directions_run;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom > 0
        ? mq.viewInsets.bottom
        : mq.viewPadding.bottom;
    final allSelected = _selected.length == widget.candidates.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.gearBackfillTitle(widget.gearName),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.gearBackfillBody(
              widget.candidates.length,
              widget.gearKind == 'bike'
                  ? l10n.gearBackfillActivityCycling
                  : l10n.gearBackfillActivityRunning,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: allSelected,
                tristate: false,
                onChanged: _saving ? null : (v) => _selectAll(v ?? false),
              ),
              GestureDetector(
                onTap: _saving ? null : () => _selectAll(!allSelected),
                child: Text(
                  allSelected
                      ? l10n.gearBackfillSelectNone
                      : l10n.gearBackfillSelectAll,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const Spacer(),
              Text(
                l10n.gearBackfillSelectedCount(
                    _selected.length, widget.candidates.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.candidates.length,
              itemBuilder: (_, i) {
                final r = widget.candidates[i];
                final selected = _selected.contains(r.id);
                return CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.leading,
                  value: selected,
                  onChanged: _saving ? null : (_) => _toggle(r.id),
                  secondary: Icon(_activityIcon(r)),
                  title: Text(_formatRunLabel(r)),
                  dense: true,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, null),
                child: Text(l10n.gearBackfillSkip),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _attach,
                child: Text(_saving
                    ? l10n.gearBackfillAttaching
                    : _selected.isEmpty
                        ? l10n.gearBackfillSkip
                        : l10n.gearBackfillAttach(_selected.length)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
