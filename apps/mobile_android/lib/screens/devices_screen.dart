import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';

/// Localized display label for an [OverrideKeySpec] — the const registry
/// can't carry localized strings, so the key drives a lookup at render
/// time. Falls back to the registry's English label for unknown keys.
String overrideKeyLabel(AppLocalizations l10n, OverrideKeySpec spec) {
  switch (spec.key) {
    case 'preferred_unit':
      return l10n.devicesKeyPreferredUnitLabel;
    case 'default_activity_type':
      return l10n.devicesKeyDefaultActivityLabel;
    case 'map_style':
      return l10n.devicesKeyMapStyleLabel;
    case 'units_pace_format':
      return l10n.devicesKeyPaceFormatLabel;
    case 'voice_feedback_enabled':
      return l10n.devicesKeyVoiceFeedbackLabel;
    case 'voice_feedback_interval_km':
      return l10n.devicesKeyVoiceIntervalLabel;
    case 'haptic_feedback_enabled':
      return l10n.devicesKeyHapticLabel;
    case 'keep_screen_on':
      return l10n.devicesKeyKeepScreenOnLabel;
    default:
      return spec.label;
  }
}

/// Localized hint for an [OverrideKeySpec]; see [overrideKeyLabel].
String overrideKeyHint(AppLocalizations l10n, OverrideKeySpec spec) {
  switch (spec.key) {
    case 'preferred_unit':
      return l10n.devicesKeyPreferredUnitHint;
    case 'default_activity_type':
      return l10n.devicesKeyDefaultActivityHint;
    case 'map_style':
      return l10n.devicesKeyMapStyleHint;
    case 'units_pace_format':
      return l10n.devicesKeyPaceFormatHint;
    case 'voice_feedback_enabled':
      return l10n.devicesKeyVoiceFeedbackHint;
    case 'voice_feedback_interval_km':
      return l10n.devicesKeyVoiceIntervalHint;
    case 'haptic_feedback_enabled':
      return l10n.devicesKeyHapticHint;
    case 'keep_screen_on':
      return l10n.devicesKeyKeepScreenOnHint;
    default:
      return spec.hint;
  }
}

/// Settings → Devices: the list of devices the current user has signed
/// in on, with rename + remove + per-device override-editor surfaces.
/// Mirrors the web `/settings/devices` screen.
class DevicesScreen extends StatefulWidget {
  final ApiClient api;
  final String currentDeviceId;

  const DevicesScreen({
    super.key,
    required this.api,
    required this.currentDeviceId,
  });

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool _loading = true;
  Object? _loadError;
  List<UserDeviceSettingRow> _devices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final list = await widget.api.fetchMyDevices();
      if (!mounted) return;
      setState(() {
        _devices = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _rename(UserDeviceSettingRow d) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: d.label ?? '');
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.devicesRenameTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.devicesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(l10n.devicesSave),
          ),
        ],
      ),
    );
    if (next == null) return;
    try {
      await widget.api.updateDeviceLabel(deviceId: d.deviceId, label: next);
      _load();
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.devicesRenameFailed(e));
    }
  }

  Future<void> _remove(UserDeviceSettingRow d) async {
    final l10n = AppLocalizations.of(context);
    final isCurrent = d.deviceId == widget.currentDeviceId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.devicesRemoveTitle),
        content: Text(
          isCurrent
              ? l10n.devicesRemoveBodyCurrent
              : l10n.devicesRemoveBodyOther,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.devicesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.devicesRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.removeDevice(d.deviceId);
      _load();
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.devicesRemoveFailed(e));
    }
  }

  Future<void> _editOverrides(UserDeviceSettingRow d) async {
    final prefs = Map<String, dynamic>.from(
        (d.prefs as Map?) ?? const <String, dynamic>{});
    final next = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OverridesSheet(initial: prefs),
    );
    if (next == null) return;
    try {
      // Diff-based write: any key dropped on the client clears the
      // server-side override; any key with a new value sets it.
      final changed = <String>{...prefs.keys, ...next.keys};
      for (final k in changed) {
        if (next[k] != prefs[k]) {
          await widget.api.setDeviceOverride(
            deviceId: d.deviceId,
            key: k,
            value: next[k],
          );
        }
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, AppLocalizations.of(context).devicesSaveFailed(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.devicesTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorState(message: l10n.devicesLoadError, onRetry: _load)
              : _devices.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l10n.devicesEmpty,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _devices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final d = _devices[i];
                          final isCurrent =
                              d.deviceId == widget.currentDeviceId;
                          final overrideCount =
                              ((d.prefs as Map?) ?? const {}).length;
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                _iconFor(d.platform),
                                color: theme.colorScheme.primary,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(d.label ?? d.platform),
                                  ),
                                  if (isCurrent)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primaryContainer,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        l10n.devicesThisDevice,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                l10n.devicesLastSeen(_fmtRelative(d.lastSeenAt,
                                        l10n,
                                        localeToTag(Localizations.localeOf(context)))) +
                                    (overrideCount > 0
                                        ? '  •  ${l10n.devicesOverrideCount(overrideCount)}'
                                        : ''),
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) async {
                                  switch (v) {
                                    case 'rename':
                                      await _rename(d);
                                      break;
                                    case 'overrides':
                                      await _editOverrides(d);
                                      break;
                                    case 'remove':
                                      await _remove(d);
                                      break;
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                      value: 'rename',
                                      child: Text(l10n.devicesRename)),
                                  PopupMenuItem(
                                      value: 'overrides',
                                      child: Text(l10n.devicesEditOverrides)),
                                  PopupMenuItem(
                                      value: 'remove',
                                      child: Text(l10n.devicesRemove)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  IconData _iconFor(String platform) {
    switch (platform) {
      case 'ios':
        return Icons.phone_iphone;
      case 'android':
        return Icons.phone_android;
      case 'wear':
      case 'watchos':
        return Icons.watch;
      case 'web':
        return Icons.public;
      default:
        return Icons.devices_other;
    }
  }

  static String _fmtRelative(DateTime d, AppLocalizations l10n, String localeTag) {
    final ms = DateTime.now().toUtc().difference(d.toUtc()).inMilliseconds;
    final mins = ms ~/ 60000;
    if (mins < 1) return l10n.devicesJustNow;
    if (mins < 60) return l10n.devicesMinutesAgo(mins);
    final hrs = mins ~/ 60;
    if (hrs < 24) return l10n.devicesHoursAgo(hrs);
    final days = hrs ~/ 24;
    if (days < 30) return l10n.devicesDaysAgo(days);
    return formatDateMed(d, localeTag);
  }
}

/// Spec for an override-eligible key. Mirrors the device (`D`) and
/// universal-default-with-device-override (`UD`) entries in
/// [docs/backend/settings.md § Keys] — purely-universal keys (hr_zones, dob,
/// weekly_mileage_goal_m, etc.) aren't exposed here because they have
/// no device-scope semantics.
///
/// `kind` drives the value-editor in [_AddOverrideSheet]:
///   - `bool`  → SwitchListTile
///   - `enum`  → radio list of [options]
///   - `int` / `double` → text input parsed to the declared type
@visibleForTesting
class OverrideKeySpec {
  final String key;
  final String label;
  final String hint;
  final String kind; // 'bool' | 'enum' | 'int' | 'double'
  final List<String>? options;

  const OverrideKeySpec({
    required this.key,
    required this.label,
    required this.hint,
    required this.kind,
    this.options,
  });
}

/// The D + UD-scoped keys from docs/backend/settings.md that admit a per-device
/// override. Keep in lockstep with `SettingsKeys` + the doc table.
@visibleForTesting
const overrideKeyRegistry = <OverrideKeySpec>[
  // UD — universal default, optional per-device override.
  OverrideKeySpec(
    key: 'preferred_unit',
    label: 'Preferred unit',
    hint: 'Distance unit for all displays.',
    kind: 'enum',
    options: ['km', 'mi'],
  ),
  OverrideKeySpec(
    key: 'default_activity_type',
    label: 'Default activity type',
    hint: 'Pre-selected activity on the start screen.',
    kind: 'enum',
    options: ['run', 'walk', 'hike', 'cycle'],
  ),
  OverrideKeySpec(
    key: 'map_style',
    label: 'Map style',
    hint: 'MapLibre style for the map view.',
    kind: 'enum',
    options: ['streets', 'satellite', 'outdoors', 'dark'],
  ),
  OverrideKeySpec(
    key: 'units_pace_format',
    label: 'Pace format',
    hint: 'Display format for pace.',
    kind: 'enum',
    options: ['min_per_km', 'min_per_mi', 'kph', 'mph'],
  ),
  // D — device-only.
  OverrideKeySpec(
    key: 'voice_feedback_enabled',
    label: 'Voice feedback',
    hint: 'Speak pace / distance callouts during a run.',
    kind: 'bool',
  ),
  OverrideKeySpec(
    key: 'voice_feedback_interval_km',
    label: 'Voice feedback interval (km)',
    hint: 'Distance between spoken callouts.',
    kind: 'double',
  ),
  OverrideKeySpec(
    key: 'haptic_feedback_enabled',
    label: 'Haptic feedback',
    hint: 'Vibration on lap + pace-zone changes.',
    kind: 'bool',
  ),
  OverrideKeySpec(
    key: 'keep_screen_on',
    label: 'Keep screen on',
    hint: 'Disable OS auto-dim while recording.',
    kind: 'bool',
  ),
];

/// Modal for the override-editor — lists existing keys with a per-row
/// delete and exposes an "+ Add override" sheet that picks an
/// eligible D / UD key from [overrideKeyRegistry] and prompts the
/// user for a value with the appropriate type-aware editor.
class _OverridesSheet extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _OverridesSheet({required this.initial});

  @override
  State<_OverridesSheet> createState() => _OverridesSheetState();
}

class _OverridesSheetState extends State<_OverridesSheet> {
  late Map<String, dynamic> _current = Map.of(widget.initial);

  Future<void> _addOverride() async {
    // Eligible keys = the registry minus anything already overridden.
    final taken = _current.keys.toSet();
    final eligible =
        overrideKeyRegistry.where((s) => !taken.contains(s.key)).toList();
    if (eligible.isEmpty) {
      showTopBanner(context, AppLocalizations.of(context).devicesEveryKeySet);
      return;
    }
    final entry = await showModalBottomSheet<MapEntry<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddOverrideSheet(eligible: eligible),
    );
    if (entry == null) return;
    setState(() => _current[entry.key] = entry.value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.devicesOverridesSheetTitle,
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            l10n.devicesOverridesSheetDesc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (_current.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                l10n.devicesNoOverrides,
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            for (final entry in _current.entries.toList())
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.key),
                subtitle: Text('${entry.value}'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _current.remove(entry.key)),
                ),
              ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addOverride,
              icon: const Icon(Icons.add),
              label: Text(l10n.devicesAddOverride),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.devicesCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, _current),
                child: Text(l10n.devicesSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet that drives the two-step "pick a key, then a value"
/// flow. Returns the new (key, value) entry on Save, or `null` on
/// Cancel.
class _AddOverrideSheet extends StatefulWidget {
  final List<OverrideKeySpec> eligible;
  const _AddOverrideSheet({required this.eligible});

  @override
  State<_AddOverrideSheet> createState() => _AddOverrideSheetState();
}

class _AddOverrideSheetState extends State<_AddOverrideSheet> {
  OverrideKeySpec? _picked;
  // Editor state — only the shape that matches `_picked!.kind` is read.
  bool _boolValue = false;
  String? _enumValue;
  final TextEditingController _numCtrl = TextEditingController();
  String? _numError;

  @override
  void dispose() {
    _numCtrl.dispose();
    super.dispose();
  }

  void _commit() {
    final l10n = AppLocalizations.of(context);
    final spec = _picked;
    if (spec == null) return;
    dynamic value;
    switch (spec.kind) {
      case 'bool':
        value = _boolValue;
      case 'enum':
        if (_enumValue == null) return;
        value = _enumValue;
      case 'int':
        final parsed = int.tryParse(_numCtrl.text.trim());
        if (parsed == null) {
          setState(() => _numError = l10n.devicesEnterWholeNumber);
          return;
        }
        value = parsed;
      case 'double':
        final parsed = double.tryParse(_numCtrl.text.trim());
        if (parsed == null) {
          setState(() => _numError = l10n.devicesEnterNumber);
          return;
        }
        value = parsed;
      default:
        return;
    }
    Navigator.pop(context, MapEntry(spec.key, value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spec = _picked;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(spec == null ? l10n.devicesPickKey : overrideKeyLabel(l10n, spec),
              style: theme.textTheme.titleLarge),
          if (spec != null) ...[
            const SizedBox(height: 4),
            Text(overrideKeyHint(l10n, spec), style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          if (spec == null)
            // Key-picker pass — list the eligible registry entries.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.eligible.length,
                itemBuilder: (_, i) {
                  final s = widget.eligible[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(overrideKeyLabel(l10n, s)),
                    subtitle: Text(s.key,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _picked = s),
                  );
                },
              ),
            )
          else
            // Value-editor pass — switch on the spec's declared kind.
            _buildEditor(spec, theme, l10n),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  if (spec != null) {
                    setState(() {
                      _picked = null;
                      _enumValue = null;
                      _boolValue = false;
                      _numCtrl.clear();
                      _numError = null;
                    });
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: Text(spec == null ? l10n.devicesCancel : l10n.devicesBack),
              ),
              if (spec != null) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _commit,
                  child: Text(l10n.devicesAdd),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(
      OverrideKeySpec spec, ThemeData theme, AppLocalizations l10n) {
    switch (spec.kind) {
      case 'bool':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(overrideKeyLabel(l10n, spec)),
          value: _boolValue,
          onChanged: (v) => setState(() => _boolValue = v),
        );
      case 'enum':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final opt in spec.options ?? const <String>[])
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: Text(opt),
                value: opt,
                groupValue: _enumValue,
                onChanged: (v) => setState(() => _enumValue = v),
              ),
          ],
        );
      case 'int':
      case 'double':
        return TextField(
          controller: _numCtrl,
          keyboardType: TextInputType.numberWithOptions(
            decimal: spec.kind == 'double',
          ),
          decoration: InputDecoration(
            labelText: l10n.devicesValue,
            errorText: _numError,
            border: const OutlineInputBorder(),
          ),
        );
    }
    return const SizedBox.shrink();
  }
}
