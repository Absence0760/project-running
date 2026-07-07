import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../settings_sync.dart';
import '../widgets/top_banner.dart';

/// Settings → Safety contacts (decisions §131). Mirror of the web
/// `/settings/safety` page: add a safety contact by email, see its
/// pending/confirmed status, remove it, and confirm/decline incoming
/// requests where you are the named contact.
///
/// A safety contact is emailed when the owner finishes a run — even a
/// private one — via a double opt-in (the owner adds an email; the
/// contact opts in by email link or, when they're an app user, here).
/// The data layer lives in `ApiClient` (mirrors web `core/data.ts`).
class SettingsSafetyScreen extends StatefulWidget {
  final ApiClient? api;
  final SettingsSyncService? settingsSync;

  const SettingsSafetyScreen({super.key, required this.api, this.settingsSync});

  @override
  State<SettingsSafetyScreen> createState() => _SettingsSafetyScreenState();
}

class _SettingsSafetyScreenState extends State<SettingsSafetyScreen> {
  // Mirror the server-side CHECK so the user gets an inline message before a
  // round trip that would 23514.
  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _emailCtl = TextEditingController();

  bool _loading = true;
  bool _adding = false;
  // In-flight guard for an incoming-request response (confirm/decline) so a
  // double-tap can't fire the RPC twice.
  String? _respondingId;
  List<SafetyContact> _contacts = const [];
  List<PendingSafetyRequest> _pending = const [];

  // Overdue escalation (docs/features/safety.md): the universal pref
  // holding the silence window in minutes; null = escalation off
  // (fail-closed — the backend scan requires the pref). Plus the
  // device-scoped auto-live-share opt-in.
  static const List<int> _overdueChoices = [15, 30, 60, 120];
  int? _overdueMinutes;
  bool _autoLiveShare = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _load();
  }

  /// Mirrors the preferences screen's gating: bag-backed controls are
  /// editable once the sync service reports usable bags (server-loaded,
  /// or cache-backed offline).
  bool get _prefsEditable => widget.settingsSync?.synced == true;

  void _loadPrefs() {
    final service = widget.settingsSync?.service;
    if (service == null) return;
    final overdue = service.effective<num>(SettingsKeys.safetyOverdueMinutes);
    final auto = service.effective<bool>(
      SettingsKeys.autoLiveShare,
      fallback: false,
    );
    _overdueMinutes =
        overdue != null && overdue.isFinite && overdue > 0 ? overdue.toInt() : null;
    _autoLiveShare = auto == true;
  }

  Future<void> _setOverdueMinutes(int? minutes) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _overdueMinutes = minutes);
    try {
      await widget.settingsSync
          ?.updateUniversal({SettingsKeys.safetyOverdueMinutes: minutes});
      _banner(l10n.safetyOverdueSaved);
    } catch (e) {
      _banner(l10n.safetyAddFailed(e.toString()));
    }
  }

  Future<void> _setAutoLiveShare(bool value) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _autoLiveShare = value);
    try {
      await widget.settingsSync
          ?.updateDevice({SettingsKeys.autoLiveShare: value});
    } catch (e) {
      _banner(l10n.safetyAddFailed(e.toString()));
    }
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final api = widget.api;
    if (api == null || api.userId == null) return;
    final results = await Future.wait([
      api.fetchMySafetyContacts(),
      api.fetchPendingSafetyRequests(),
    ]);
    if (!mounted) return;
    setState(() {
      _contacts = results[0] as List<SafetyContact>;
      _pending = results[1] as List<PendingSafetyRequest>;
    });
  }

  Future<void> _load() async {
    await _reload();
    if (mounted) setState(() => _loading = false);
  }

  void _banner(String message) {
    if (!mounted) return;
    showTopBanner(context, message);
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final value = _emailCtl.text.trim();
    if (!_emailRe.hasMatch(value)) {
      _banner(l10n.safetyInvalidEmail);
      return;
    }
    final api = widget.api;
    if (api == null) return;
    setState(() => _adding = true);
    try {
      await api.addSafetyContact(value);
      _emailCtl.clear();
      await _reload();
      _banner(l10n.safetyAddedToast);
    } catch (e) {
      _banner(l10n.safetyAddFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(SafetyContact contact) async {
    final l10n = AppLocalizations.of(context);
    final api = widget.api;
    if (api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.safetyTitle),
        content: Text(l10n.safetyRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.safetyRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.removeSafetyContact(contact.id);
      await _reload();
      _banner(l10n.safetyRemovedToast);
    } catch (e) {
      _banner(l10n.safetyAddFailed(e.toString()));
    }
  }

  Future<void> _confirm(PendingSafetyRequest req) async {
    final l10n = AppLocalizations.of(context);
    final api = widget.api;
    if (api == null || _respondingId != null) return;
    setState(() => _respondingId = req.id);
    try {
      await api.confirmSafetyRequest(req.id);
      await _reload();
      _banner(l10n.safetyConfirmedToast);
    } catch (e) {
      _banner(l10n.safetyAddFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _respondingId = null);
    }
  }

  Future<void> _decline(PendingSafetyRequest req) async {
    final l10n = AppLocalizations.of(context);
    final api = widget.api;
    if (api == null || _respondingId != null) return;
    setState(() => _respondingId = req.id);
    try {
      await api.declineSafetyRequest(req.id);
      await _reload();
      _banner(l10n.safetyDeclinedToast);
    } catch (e) {
      _banner(l10n.safetyAddFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _respondingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.safetyTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text(
                    l10n.safetyIntro,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _emailCtl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enabled: !_adding,
                    decoration: InputDecoration(
                      labelText: l10n.safetyAddLabel,
                      hintText: 'partner@example.com',
                    ),
                    onSubmitted: (_) => _adding ? null : _add(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton(
                      onPressed: _adding ? null : _add,
                      child:
                          Text(_adding ? l10n.safetyAdding : l10n.safetyAddButton),
                    ),
                  ),
                ),
                const Divider(height: 1),
                if (_contacts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      l10n.safetyEmpty,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                else
                  for (final c in _contacts)
                    ListTile(
                      title: Text(c.contactEmail),
                      subtitle: Text(
                        c.isConfirmed
                            ? l10n.safetyStatusConfirmed
                            : l10n.safetyStatusPending,
                        style: TextStyle(
                          color: c.isConfirmed
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () => _remove(c),
                        child: Text(
                          l10n.safetyRemove,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    l10n.safetyOverdueTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    l10n.safetyOverdueIntro,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  title: Text(l10n.safetyOverdueLabel),
                  trailing: DropdownButton<int?>(
                    value: _overdueMinutes,
                    onChanged: _prefsEditable ? (v) => _setOverdueMinutes(v) : null,
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(l10n.safetyOverdueOff),
                      ),
                      for (final minutes in _overdueChoices)
                        DropdownMenuItem<int?>(
                          value: minutes,
                          child: Text(l10n.safetyOverdueMinutesOption(minutes)),
                        ),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: Text(l10n.safetyAutoLiveShareTitle),
                  subtitle: Text(l10n.safetyAutoLiveShareSubtitle),
                  value: _autoLiveShare,
                  onChanged: _prefsEditable ? _setAutoLiveShare : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    l10n.safetyOverdueNote,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (_pending.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      l10n.safetyIncomingTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      l10n.safetyIncomingIntro,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  for (final req in _pending)
                    ListTile(
                      title: Text(
                        l10n.safetyIncomingFrom(
                          req.ownerName.isEmpty
                              ? l10n.safetyUnknownRunner
                              : req.ownerName,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: _respondingId != null
                                ? null
                                : () => _decline(req),
                            child: Text(l10n.safetyDecline),
                          ),
                          const SizedBox(width: 4),
                          FilledButton(
                            onPressed: _respondingId != null
                                ? null
                                : () => _confirm(req),
                            child: Text(l10n.safetyConfirm),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
