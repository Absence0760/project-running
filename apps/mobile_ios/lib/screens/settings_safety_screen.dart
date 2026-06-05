import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
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

  const SettingsSafetyScreen({super.key, required this.api});

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
  List<SafetyContact> _contacts = const [];
  List<PendingSafetyRequest> _pending = const [];

  @override
  void initState() {
    super.initState();
    _load();
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
    if (api == null) return;
    try {
      await api.confirmSafetyRequest(req.id);
      await _reload();
      _banner(l10n.safetyConfirmedToast);
    } catch (e) {
      _banner(l10n.safetyAddFailed(e.toString()));
    }
  }

  Future<void> _decline(PendingSafetyRequest req) async {
    final l10n = AppLocalizations.of(context);
    final api = widget.api;
    if (api == null) return;
    try {
      await api.declineSafetyRequest(req.id);
      await _reload();
      _banner(l10n.safetyDeclinedToast);
    } catch (e) {
      _banner(l10n.safetyAddFailed(e.toString()));
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
                            onPressed: () => _decline(req),
                            child: Text(l10n.safetyDecline),
                          ),
                          const SizedBox(width: 4),
                          FilledButton(
                            onPressed: () => _confirm(req),
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
