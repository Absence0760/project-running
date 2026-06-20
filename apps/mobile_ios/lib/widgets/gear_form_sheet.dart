import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../local_gear_store.dart';
import '../preferences.dart';
import 'full_screen_form.dart';
import 'top_banner.dart';

/// Full-screen dialog for creating or editing a gear row. Returns
/// a [GearFormResult] carrying the saved row's id + the purchased_at
/// date the user picked (so the caller can drive a backfill prompt
/// against past runs); `null` on cancel. Mirrors the web
/// `+page.svelte` form on /settings/gear — same fields, same
/// unit-aware retirement-target input. Presentation goes through
/// [showFullScreenForm], the shared create/edit-entity wrapper.
///
/// Writes go through [LocalGearStore] so offline edits are persisted
/// + queued for the next server drain.
class GearFormResult {
  GearFormResult({
    required this.gearId,
    required this.name,
    required this.kind,
    required this.isNew,
    this.purchasedAt,
  });
  final String gearId;
  final String name;
  final String kind;
  final bool isNew;
  final DateTime? purchasedAt;
}

Future<GearFormResult?> showGearFormSheet({
  required BuildContext context,
  required LocalGearStore store,
  required Preferences preferences,
  required String kind,
  Map<String, dynamic>? existing,
  ApiClient? api,
}) {
  final l10n = AppLocalizations.of(context);
  return showFullScreenForm<GearFormResult>(
    context,
    title: existing != null
        ? l10n.gearFormTitleEdit
        : (kind == 'shoe'
            ? l10n.gearFormTitleAddShoes
            : l10n.gearFormTitleAddBike),
    builder: (_) => _GearFormSheet(
      store: store,
      preferences: preferences,
      kind: kind,
      existing: existing,
      api: api,
    ),
  );
}

class _GearFormSheet extends StatefulWidget {
  final LocalGearStore store;
  final Preferences preferences;
  final String kind;
  final Map<String, dynamic>? existing;
  final ApiClient? api;
  const _GearFormSheet({
    required this.store,
    required this.preferences,
    required this.kind,
    this.existing,
    this.api,
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
  final _wearNote = TextEditingController();
  DateTime? _purchasedAt;
  bool _saving = false;

  // Wear log — only loaded when editing an existing item AND an api is
  // wired. Online-only, mirroring the gear-backfill sheet: wear logs are
  // not part of the offline LocalGearStore pipeline.
  String? _gearId;
  List<GearWearLogRow> _wearLogs = const [];
  bool _wearLoading = false;
  bool _wearAdding = false;
  String? _wearArea;

  static const _wearAreas = ['outsole', 'midsole', 'upper', 'other'];

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
      _gearId = e['id'] as String?;
      if (_gearId != null && widget.api != null) _loadWearLogs();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _model.dispose();
    _target.dispose();
    _notes.dispose();
    _wearNote.dispose();
    super.dispose();
  }

  Future<void> _loadWearLogs() async {
    final api = widget.api;
    final gearId = _gearId;
    if (api == null || gearId == null) return;
    setState(() => _wearLoading = true);
    try {
      final logs = await api.fetchGearWearLogs(gearId);
      if (mounted) setState(() => _wearLogs = logs);
    } catch (_) {
      // L4: a wear-log fetch failure leaves the section empty, never
      // blocks the gear form.
    } finally {
      if (mounted) setState(() => _wearLoading = false);
    }
  }

  Future<void> _addWearLog() async {
    final api = widget.api;
    final gearId = _gearId;
    final note = _wearNote.text.trim();
    if (api == null || gearId == null || note.isEmpty) return;
    setState(() => _wearAdding = true);
    try {
      final created = await api.addGearWearLog(
        gearId: gearId,
        note: note,
        area: _wearArea,
      );
      if (!mounted) return;
      setState(() {
        _wearLogs = [created, ..._wearLogs];
        _wearNote.clear();
        _wearArea = null;
      });
    } catch (e) {
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).gearWearLogAddError('$e'));
    } finally {
      if (mounted) setState(() => _wearAdding = false);
    }
  }

  Future<void> _deleteWearLog(GearWearLogRow log) async {
    final api = widget.api;
    if (api == null) return;
    try {
      await api.deleteGearWearLog(log.id);
      if (mounted) {
        setState(() =>
            _wearLogs = _wearLogs.where((l) => l.id != log.id).toList());
      }
    } catch (e) {
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).gearWearLogDeleteError('$e'));
    }
  }

  String _wearAreaLabel(AppLocalizations l10n, String area) {
    switch (area) {
      case 'outsole':
        return l10n.gearWearLogAreaOutsole;
      case 'midsole':
        return l10n.gearWearLogAreaMidsole;
      case 'upper':
        return l10n.gearWearLogAreaUpper;
      default:
        return l10n.gearWearLogAreaOther;
    }
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
      final brand = _brand.text.trim();
      final model = _model.text.trim();
      final notes = _notes.text.trim();
      String savedId;
      if (widget.existing != null) {
        savedId = widget.existing!['id'] as String;
        await widget.store.updateLocal(savedId, {
          'name': name,
          'brand': brand.isEmpty ? null : brand,
          'model': model.isEmpty ? null : model,
          'purchased_at':
              _purchasedAt?.toIso8601String().substring(0, 10),
          'target_distance_m': _parseTargetMetres(),
          'notes': notes.isEmpty ? null : notes,
        });
      } else {
        final created = await widget.store.createLocal(
          kind: widget.kind,
          name: name,
          brand: brand.isEmpty ? null : brand,
          model: model.isEmpty ? null : model,
          purchasedAt: _purchasedAt,
          targetDistanceM: _parseTargetMetres(),
          notes: notes.isEmpty ? null : notes,
        );
        savedId = created.id;
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        GearFormResult(
          gearId: savedId,
          name: name,
          kind: widget.kind,
          isNew: widget.existing == null,
          purchasedAt: _purchasedAt,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTopBanner(
          context, AppLocalizations.of(context).gearFormSaveError('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unitLabel = widget.preferences.unit == DistanceUnit.mi ? 'mi' : 'km';
    // Heading lives in the host AppBar (showFullScreenForm).
    return FullScreenFormBody(
      children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.gearFormNameLabel,
                hintText: l10n.gearFormNameHint,
              ),
              maxLength: 80,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _brand,
                    decoration:
                        InputDecoration(labelText: l10n.gearFormBrandLabel),
                    maxLength: 60,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _model,
                    decoration:
                        InputDecoration(labelText: l10n.gearFormModelLabel),
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
                      decoration:
                          InputDecoration(labelText: l10n.gearFormBoughtLabel),
                      child: Text(_purchasedAt == null
                          ? l10n.gearFormBoughtPick
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
                      labelText: l10n.gearFormRetireAt(unitLabel),
                      hintText: l10n.gearFormRetireHint,
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _notes,
              decoration: InputDecoration(labelText: l10n.gearFormNotesLabel),
              maxLength: 500,
              maxLines: 3,
            ),
            if (_gearId != null && widget.api != null) ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              Text(l10n.gearWearLogHeading,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                l10n.gearWearLogHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _wearNote,
                decoration: InputDecoration(
                  labelText: l10n.gearWearLogAddNote,
                  hintText: l10n.gearWearLogNoteHint,
                ),
                maxLength: 500,
                maxLines: 2,
              ),
              DropdownButtonFormField<String?>(
                initialValue: _wearArea,
                decoration:
                    InputDecoration(labelText: l10n.gearWearLogArea),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l10n.gearWearLogAreaNone),
                  ),
                  for (final a in _wearAreas)
                    DropdownMenuItem<String?>(
                      value: a,
                      child: Text(_wearAreaLabel(l10n, a)),
                    ),
                ],
                onChanged: (v) => setState(() => _wearArea = v),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _wearAdding ? null : _addWearLog,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(_wearAdding
                      ? l10n.gearWearLogAdding
                      : l10n.gearWearLogAdd),
                ),
              ),
              const SizedBox(height: 12),
              if (_wearLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                      child: SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else if (_wearLogs.isEmpty)
                Text(l10n.gearWearLogEmpty,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline))
              else
                for (final log in _wearLogs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(log.note),
                    subtitle: Text([
                      log.loggedOn.toIso8601String().substring(0, 10),
                      if (log.area != null) _wearAreaLabel(l10n, log.area!),
                    ].join(' · ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: l10n.gearWearLogDelete,
                      onPressed: () => _deleteWearLog(log),
                    ),
                  ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.gearFormCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving
                      ? l10n.gearFormSaving
                      : widget.existing != null
                          ? l10n.gearFormSave
                          : l10n.gearFormAdd),
                ),
              ],
            ),
          ],
        );
  }
}
