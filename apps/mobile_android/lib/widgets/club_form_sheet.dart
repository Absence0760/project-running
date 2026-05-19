import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../rate_limit_errors.dart';
import '../social_service.dart';

/// Modal bottom sheet for creating a new club. Mirrors the web
/// `ClubEditor.svelte`: name + description + location + visibility
/// + join policy. Returns the new slug on success.
Future<String?> showClubFormSheet(
  BuildContext context, {
  required SocialService social,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ClubForm(social: social),
  );
}

class _ClubForm extends StatefulWidget {
  final SocialService social;
  const _ClubForm({required this.social});

  @override
  State<_ClubForm> createState() => _ClubFormState();
}

class _ClubFormState extends State<_ClubForm> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  bool _isPublic = true;
  String _joinPolicy = 'open';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  String _slugify(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(
            RegExp(r'(^-|-$)'),
            '',
          );

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    final slug = _slugify(name);
    if (slug.isEmpty) {
      setState(() => _error = 'Name needs at least one letter or digit.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final club = await widget.social.createClub(
        name: name,
        slug: slug,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        locationLabel: _location.text.trim().isEmpty
            ? null
            : _location.text.trim(),
        isPublic: _isPublic,
        joinPolicy: _joinPolicy,
      );
      if (!mounted) return;
      Navigator.of(context).pop<String?>(club.slug);
    } catch (e) {
      if (!mounted) return;
      // Recognise the create_club rate-limit P0001 (migration
      // 20260907_001) and surface the friendly "wait N minutes"
      // message instead of the raw PostgrestException toString.
      // Mirror of the web fix in apps/web/src/lib/data.ts +
      // ClubEditor.svelte. Unknown errors fall through to the raw
      // toString so debugging information isn't hidden.
      String message = e.toString();
      if (e is PostgrestException) {
        final friendly = rateLimitErrorMessage(code: e.code, message: e.message);
        if (friendly != null) message = friendly;
      }
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New club', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _location,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Location (optional)',
              hintText: 'Edinburgh, UK',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Public'), icon: Icon(Icons.public)),
              ButtonSegment(value: false, label: Text('Private'), icon: Icon(Icons.lock_outline)),
            ],
            selected: {_isPublic},
            onSelectionChanged: (s) => setState(() {
              _isPublic = s.first;
              if (!_isPublic && _joinPolicy != 'invite') _joinPolicy = 'invite';
              if (_isPublic && _joinPolicy == 'invite') _joinPolicy = 'open';
            }),
          ),
          const SizedBox(height: 12),
          Text('Join policy', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              if (_isPublic) ...[
                ChoiceChip(
                  label: const Text('Open — anyone joins'),
                  selected: _joinPolicy == 'open',
                  onSelected: (_) => setState(() => _joinPolicy = 'open'),
                ),
                ChoiceChip(
                  label: const Text('Request — admins approve'),
                  selected: _joinPolicy == 'request',
                  onSelected: (_) => setState(() => _joinPolicy = 'request'),
                ),
              ] else
                ChoiceChip(
                  label: const Text('Invite only'),
                  selected: _joinPolicy == 'invite',
                  onSelected: (_) => setState(() => _joinPolicy = 'invite'),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
