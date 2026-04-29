import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../widgets/error_state.dart';

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
    final ctrl = TextEditingController(text: d.label ?? '');
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rename failed: $e')),
      );
    }
  }

  Future<void> _remove(UserDeviceSettingRow d) async {
    final isCurrent = d.deviceId == widget.currentDeviceId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove device?'),
        content: Text(
          isCurrent
              ? 'This is the device you\'re using. Removing it wipes the per-device preference overrides; the device stays signed in.'
              : 'Removes the device entry and any per-device preference overrides. The device stays signed in until it next opens the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Remove failed: $e')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorState(message: 'Could not load devices.', onRetry: _load)
              : _devices.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No devices yet — they\'re registered the first time '
                          'a device opens the app while signed in.',
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
                                        'This device',
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
                                'Last seen ${_fmtRelative(d.lastSeenAt)}'
                                '${overrideCount > 0 ? '  •  $overrideCount override${overrideCount == 1 ? '' : 's'}' : ''}',
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
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'rename', child: Text('Rename')),
                                  PopupMenuItem(
                                      value: 'overrides',
                                      child: Text('Edit overrides…')),
                                  PopupMenuItem(
                                      value: 'remove', child: Text('Remove')),
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

  static String _fmtRelative(DateTime d) {
    final ms = DateTime.now().toUtc().difference(d.toUtc()).inMilliseconds;
    final mins = ms ~/ 60000;
    if (mins < 1) return 'just now';
    if (mins < 60) return '${mins}m ago';
    final hrs = mins ~/ 60;
    if (hrs < 24) return '${hrs}h ago';
    final days = hrs ~/ 24;
    if (days < 30) return '${days}d ago';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

/// Modal for the override-editor — shows the existing keys with a
/// per-row delete. The "add a key" affordance is intentionally
/// out-of-scope for v1 — most overrides land via the per-screen
/// settings UI on the device itself.
class _OverridesSheet extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _OverridesSheet({required this.initial});

  @override
  State<_OverridesSheet> createState() => _OverridesSheetState();
}

class _OverridesSheetState extends State<_OverridesSheet> {
  late Map<String, dynamic> _current = Map.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Per-device overrides', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'These keys override the universal settings on this device only.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (_current.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No overrides on this device.',
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
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, _current),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
