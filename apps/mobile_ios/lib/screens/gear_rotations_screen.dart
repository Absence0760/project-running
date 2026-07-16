import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_gear_store.dart';
import '../widgets/top_banner.dart';

/// Settings → Gear → Rotations: named multi-pair groupings a runner cycles
/// gear through (a "Daily trainers" set, a "Race day" set). Distinct from
/// the single `is_default` current pair — a rotation is a many-to-many
/// named group, complementary to the auto-tag default.
///
/// Online-only, by deliberate scope: rotations live OUTSIDE
/// [LocalGearStore] (like the wear-log + backfill sub-flows) — a rotation
/// is inventory organisation, not a record that must survive offline. The
/// screen reads gear rows from the passed [LocalGearStore] (so the member
/// picker works without a round trip) but reads/writes rotations through
/// the [ApiClient].
class GearRotationsScreen extends StatefulWidget {
  final ApiClient api;
  final LocalGearStore gearStore;

  const GearRotationsScreen({
    super.key,
    required this.api,
    required this.gearStore,
  });

  @override
  State<GearRotationsScreen> createState() => _GearRotationsScreenState();
}

class _GearRotationsScreenState extends State<GearRotationsScreen> {
  List<GearRotationWithMembers> _rotations = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final fresh = await widget.api.fetchMyGearRotations();
      if (!mounted) return;
      setState(() {
        _rotations = fresh;
        _loading = false;
      });
    } catch (e) {
      debugPrint('gear rotation save failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      showTopBanner(
          context, AppLocalizations.of(context).gearRotationSaveFailed(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final name = await _promptName(title: l10n.gearRotationNew, initial: '');
    if (name == null || name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.api.createGearRotation(name);
      await _load();
    } catch (e) {
      debugPrint('gear rotation save failed: $e');
      if (mounted) showTopBanner(context, l10n.gearRotationSaveFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(GearRotationWithMembers r) async {
    final l10n = AppLocalizations.of(context);
    final name = await _promptName(title: l10n.gearRotationRename, initial: r.name);
    if (name == null || name.isEmpty || name == r.name) return;
    try {
      await widget.api.renameGearRotation(r.id, name);
      await _load();
    } catch (e) {
      debugPrint('gear rotation save failed: $e');
      if (mounted) showTopBanner(context, l10n.gearRotationSaveFailed(friendlyError(l10n, e)));
    }
  }

  Future<void> _delete(GearRotationWithMembers r) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.gearRotationDeleteTitle),
            content: Text(l10n.gearRotationDeleteBody(r.name)),
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
    try {
      await widget.api.deleteGearRotation(r.id);
      await _load();
    } catch (e) {
      debugPrint('gear rotation save failed: $e');
      if (mounted) showTopBanner(context, l10n.gearRotationSaveFailed(friendlyError(l10n, e)));
    }
  }

  Future<void> _editMembers(GearRotationWithMembers r) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RotationMembersSheet(
        api: widget.api,
        rotation: r,
        gearRows: widget.gearStore.rows,
      ),
    );
    if (saved == true) await _load();
  }

  Future<String?> _promptName(
      {required String title, required String initial}) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(labelText: l10n.gearRotationName),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(l10n.gearCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.gearRotationCreate),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gearRotationsTitle),
        actions: [
          IconButton(
            tooltip: l10n.gearRotationNew,
            icon: const Icon(Icons.add),
            onPressed: _busy ? null : _create,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l10n.gearRotationsHint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                if (_rotations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      l10n.gearRotationsEmpty,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  )
                else
                  for (final r in _rotations) _rotationTile(r, theme, l10n),
              ],
            ),
    );
  }

  Widget _rotationTile(
      GearRotationWithMembers r, ThemeData theme, AppLocalizations l10n) {
    return Card(
      child: ListTile(
        title: Text(r.name, style: theme.textTheme.titleSmall),
        subtitle: Text(l10n.gearRotationMemberCount(r.gearIds.length)),
        onTap: () => _editMembers(r),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'members') _editMembers(r);
            if (v == 'rename') _rename(r);
            if (v == 'delete') _delete(r);
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'members', child: Text(l10n.gearRotationManage)),
            PopupMenuItem(value: 'rename', child: Text(l10n.gearRotationRename)),
            PopupMenuItem(value: 'delete', child: Text(l10n.gearDelete)),
          ],
        ),
      ),
    );
  }
}

/// Member-edit sheet: a checkbox per gear item, pre-checked for the
/// rotation's current members. On Done it replaces the membership via
/// [ApiClient.setGearRotationMembers]. Returns true when saved.
class _RotationMembersSheet extends StatefulWidget {
  final ApiClient api;
  final GearRotationWithMembers rotation;
  final List<Map<String, dynamic>> gearRows;

  const _RotationMembersSheet({
    required this.api,
    required this.rotation,
    required this.gearRows,
  });

  @override
  State<_RotationMembersSheet> createState() => _RotationMembersSheetState();
}

class _RotationMembersSheetState extends State<_RotationMembersSheet> {
  late final Set<String> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.rotation.gearIds.toSet();
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.api.setGearRotationMembers(
          widget.rotation.id, _selected.toList(growable: false));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('gear rotation save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      showTopBanner(
          context, AppLocalizations.of(context).gearRotationSaveFailed(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final mq = MediaQuery.of(context);
    final bottomInset =
        mq.viewInsets.bottom > 0 ? mq.viewInsets.bottom : mq.viewPadding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.gearRotationManageTitle(widget.rotation.name),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (widget.gearRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.gearRotationNoGear,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.gearRows.length,
                itemBuilder: (_, i) {
                  final g = widget.gearRows[i];
                  final id = g['id'] as String;
                  final name = g['name'] as String? ?? '';
                  final brandModel = [g['brand'], g['model']]
                      .whereType<String>()
                      .where((s) => s.isNotEmpty)
                      .join(' ');
                  final retired = g['retired_at'] != null;
                  return CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selected.contains(id),
                    onChanged: _saving ? null : (_) => _toggle(id),
                    secondary: Icon(g['kind'] == 'bike'
                        ? Icons.directions_bike
                        : Icons.directions_run),
                    title: Text(name),
                    subtitle: (brandModel.isNotEmpty || retired)
                        ? Text([
                            if (brandModel.isNotEmpty) brandModel,
                            if (retired) l10n.gearRetired,
                          ].join(' · '))
                        : null,
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
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(l10n.gearCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(l10n.gearRotationDone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
