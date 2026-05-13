import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../preferences.dart';
import 'top_banner.dart';

/// Modal bottom sheet for creating or editing a [GearRow]. Returns
/// `true` from [showGearFormSheet] when the user saves (so the
/// caller can refetch); `null` / `false` on cancel. Mirrors the web
/// `+page.svelte` form on /settings/gear — same fields, same
/// unit-aware retirement-target input.
Future<bool?> showGearFormSheet({
  required BuildContext context,
  required ApiClient api,
  required Preferences preferences,
  required String kind,
  Map<String, dynamic>? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _GearFormSheet(
      api: api,
      preferences: preferences,
      kind: kind,
      existing: existing,
    ),
  );
}

class _GearFormSheet extends StatefulWidget {
  final ApiClient api;
  final Preferences preferences;
  final String kind;
  final Map<String, dynamic>? existing;
  const _GearFormSheet({
    required this.api,
    required this.preferences,
    required this.kind,
    this.existing,
  });

  @override
  State<_GearFormSheet> createState() => _GearFormSheetState();
}

class _GearFormSheetState extends State<_GearFormSheet> {
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _target = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _purchasedAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e['name'] as String? ?? '';
      _brand.text = e['brand'] as String? ?? '';
      _model.text = e['model'] as String? ?? '';
      _notes.text = e['notes'] as String? ?? '';
      final p = e['purchased_at'] as String?;
      if (p != null && p.isNotEmpty) _purchasedAt = DateTime.tryParse(p);
      final t = e['target_distance_m'] as num?;
      if (t != null) {
        final div =
            widget.preferences.unit == DistanceUnit.mi ? 1609.344 : 1000.0;
        _target.text = (t.toDouble() / div).toStringAsFixed(0);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _model.dispose();
    _target.dispose();
    _notes.dispose();
    super.dispose();
  }

  int? _parseTargetMetres() {
    final raw = _target.text.trim();
    if (raw.isEmpty) return null;
    final n = double.tryParse(raw);
    if (n == null || n <= 0) return null;
    final mult =
        widget.preferences.unit == DistanceUnit.mi ? 1609.344 : 1000.0;
    return (n * mult).round();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchasedAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _purchasedAt = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      if (widget.existing != null) {
        await widget.api.updateGear(
          widget.existing!['id'] as String,
          name: name,
          brand: _brand.text.trim(),
          model: _model.text.trim(),
          purchasedAt: _purchasedAt,
          targetDistanceM: _parseTargetMetres(),
          notes: _notes.text.trim(),
        );
      } else {
        await widget.api.createGear(
          kind: widget.kind,
          name: name,
          brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
          model: _model.text.trim().isEmpty ? null : _model.text.trim(),
          purchasedAt: _purchasedAt,
          targetDistanceM: _parseTargetMetres(),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTopBanner(context, 'Save failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitLabel = widget.preferences.unit == DistanceUnit.mi ? 'mi' : 'km';
    final insets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing != null
                  ? 'Edit gear'
                  : 'Add ${widget.kind == 'shoe' ? 'shoes' : 'bike'}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Pegasus 39',
              ),
              maxLength: 80,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _brand,
                    decoration: const InputDecoration(labelText: 'Brand'),
                    maxLength: 60,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _model,
                    decoration: const InputDecoration(labelText: 'Model'),
                    maxLength: 60,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Bought'),
                      child: Text(_purchasedAt == null
                          ? 'Tap to pick'
                          : _purchasedAt!.toIso8601String().substring(0, 10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _target,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Retire at ($unitLabel)',
                      hintText: '500',
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLength: 500,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving
                      ? 'Saving…'
                      : widget.existing != null
                          ? 'Save'
                          : 'Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
