import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../settings_sync.dart';
import '../trusted_contacts.dart';
import '../widgets/top_banner.dart';

/// Settings → Account → Safety surface. Persona-hunt Round 3 finding
/// Woman #4. Lets the runner manage their trusted-contact list ahead
/// of the planned notify-on-overdue / panic-button surface (no
/// delivery logic ships with the scaffold; this screen just gives
/// the data a home).
///
/// Mirrors the web `/settings/account` Safety section. Storage shape
/// + cap live in `lib/trusted_contacts.dart` (kept in lockstep with
/// the TS twin).
class TrustedContactsScreen extends StatefulWidget {
  final SettingsSyncService settingsSync;
  const TrustedContactsScreen({super.key, required this.settingsSync});

  @override
  State<TrustedContactsScreen> createState() => _TrustedContactsScreenState();
}

class _TrustedContactsScreenState extends State<TrustedContactsScreen> {
  late List<_EditableContact> _contacts;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final raw =
        widget.settingsSync.service?.effective<List>(SettingsKeys.trustedContacts);
    final loaded = normaliseTrustedContacts(
      raw
          ?.whereType<Map>()
          .map((m) => TrustedContact.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
    );
    _contacts = loaded.map(_EditableContact.from).toList();
  }

  void _add() {
    if (_contacts.length >= kMaxTrustedContacts) return;
    setState(() => _contacts = [..._contacts, _EditableContact.empty()]);
  }

  void _remove(int idx) {
    setState(() => _contacts = [..._contacts]..removeAt(idx));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final cleaned = normaliseTrustedContacts(
        _contacts.map((e) => e.toContact()).toList(),
      );
      await widget.settingsSync
          .updateUniversal({SettingsKeys.trustedContacts: cleaned.map((c) => c.toJson()).toList()});
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _contacts = cleaned.map(_EditableContact.from).toList();
      });
      showTopBanner(
        context,
        cleaned.isEmpty
            ? l10n.trustedContactsClearedBanner
            : l10n.trustedContactsSavedBanner(cleaned.length),
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, AppLocalizations.of(context).trustedContactsSaveFailedBanner(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.trustedContactsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.trustedContactsIntro(kMaxTrustedContacts),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < _contacts.length; i++) ...[
            _ContactCard(
              key: ValueKey(_contacts[i].id),
              contact: _contacts[i],
              onRemove: () => _remove(i),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _contacts.length >= kMaxTrustedContacts ? null : _add,
                icon: const Icon(Icons.person_add_outlined),
                label: Text(l10n.trustedContactsAddButton),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? l10n.trustedContactsSavingButton
                    : l10n.trustedContactsSaveButton),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditableContact {
  final String id;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController relCtrl;

  _EditableContact._({
    required this.id,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.relCtrl,
  });

  factory _EditableContact.from(TrustedContact c) => _EditableContact._(
        id: UniqueKey().toString(),
        nameCtrl: TextEditingController(text: c.name),
        phoneCtrl: TextEditingController(text: c.phone ?? ''),
        emailCtrl: TextEditingController(text: c.email ?? ''),
        relCtrl: TextEditingController(text: c.relationship ?? ''),
      );

  factory _EditableContact.empty() => _EditableContact._(
        id: UniqueKey().toString(),
        nameCtrl: TextEditingController(),
        phoneCtrl: TextEditingController(),
        emailCtrl: TextEditingController(),
        relCtrl: TextEditingController(),
      );

  TrustedContact toContact() => TrustedContact(
        name: nameCtrl.text,
        phone: phoneCtrl.text.isEmpty ? null : phoneCtrl.text,
        email: emailCtrl.text.isEmpty ? null : emailCtrl.text,
        relationship: relCtrl.text.isEmpty ? null : relCtrl.text,
      );
}

class _ContactCard extends StatelessWidget {
  final _EditableContact contact;
  final VoidCallback onRemove;
  const _ContactCard({super.key, required this.contact, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: contact.nameCtrl,
              decoration: InputDecoration(
                labelText: l10n.trustedContactsNameLabel,
                hintText: l10n.trustedContactsNameHint,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: contact.phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l10n.trustedContactsPhoneLabel,
                hintText: l10n.trustedContactsPhoneHint,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: contact.emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l10n.trustedContactsEmailLabel,
                hintText: l10n.trustedContactsEmailHint,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: contact.relCtrl,
              decoration: InputDecoration(
                labelText: l10n.trustedContactsRelationshipLabel,
                hintText: l10n.trustedContactsRelationshipHint,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.trustedContactsRemoveButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
