import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../preferences.dart';
import '../widgets/gear_form_sheet.dart';
import '../widgets/top_banner.dart';

/// Settings → Gear: per-user inventory of shoes and bikes plus the
/// rolled-up total mileage each item has accrued via assigned runs.
/// Mirrors `apps/web/src/routes/settings/gear/+page.svelte` — same
/// shape (sub-tabs by kind, active/retired sections, modal for
/// create + edit), same retirement-target math.
class GearScreen extends StatefulWidget {
  final ApiClient api;
  final Preferences preferences;
  const GearScreen({super.key, required this.api, required this.preferences});

  @override
  State<GearScreen> createState() => _GearScreenState();
}

class _GearScreenState extends State<GearScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String _activeKind = 'shoe';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await widget.api.fetchMyGearWithDistance();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showTopBanner(context, 'Failed to load gear: $e');
    }
  }

  List<Map<String, dynamic>> get _visible =>
      _rows.where((r) => r['kind'] == _activeKind).toList();
  List<Map<String, dynamic>> get _active =>
      _visible.where((r) => r['retired_at'] == null).toList();
  List<Map<String, dynamic>> get _retired =>
      _visible.where((r) => r['retired_at'] != null).toList();

  Future<void> _create() async {
    final created = await showGearFormSheet(
      context: context,
      api: widget.api,
      preferences: widget.preferences,
      kind: _activeKind,
    );
    if (created == true) _load();
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final edited = await showGearFormSheet(
      context: context,
      api: widget.api,
      preferences: widget.preferences,
      kind: row['kind'] as String,
      existing: row,
    );
    if (edited == true) _load();
  }

  Future<void> _retire(Map<String, dynamic> row) async {
    try {
      if (row['retired_at'] == null) {
        await widget.api.retireGear(row['id'] as String);
      } else {
        await widget.api.unretireGear(row['id'] as String);
      }
      await _load();
    } catch (e) {
      if (mounted) showTopBanner(context, 'Failed: $e');
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete gear?'),
            content: Text(
              'Delete "${row['name']}"? Mileage history on past runs will '
              'be lost. Retire instead to keep the records.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await widget.api.deleteGear(row['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) showTopBanner(context, 'Delete failed: $e');
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gear'),
        actions: [
          IconButton(
            tooltip: 'Add gear',
            icon: const Icon(Icons.add),
            onPressed: _loading ? null : _create,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'shoe',
                  label: Text('Shoes'),
                  icon: Icon(Icons.directions_run),
                ),
                ButtonSegment(
                  value: 'bike',
                  label: Text('Bikes'),
                  icon: Icon(Icons.directions_bike),
                ),
              ],
              selected: {_activeKind},
              onSelectionChanged: (s) => setState(() => _activeKind = s.first),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visible.isEmpty
                    ? _emptyState(theme)
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final row in _active) _gearTile(row, theme),
                          if (_retired.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'RETIRED',
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
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
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
            'No ${_activeKind == 'shoe' ? 'shoes' : 'bikes'} yet',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Add a pair to track mileage and get retirement reminders.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add gear'),
            onPressed: _create,
          ),
        ],
      ),
    );
  }

  Widget _gearTile(Map<String, dynamic> row, ThemeData theme) {
    final prog = _progress(row);
    final name = row['name'] as String;
    final brand = row['brand'] as String?;
    final model = row['model'] as String?;
    final runCount = (row['run_count'] as num?)?.toInt() ?? 0;
    final hasTarget = (row['target_distance_m'] as num?) != null;
    final brandModel = [brand, model].where((s) => s != null && s.isNotEmpty).join(' ');
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
                          '$runCount run${runCount == 1 ? '' : 's'}',
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
                    child: Text(row['retired_at'] == null ? 'Retire' : 'Restore'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
