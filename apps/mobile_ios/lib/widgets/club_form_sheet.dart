import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../l10n/gen/app_localizations.dart';
import '../rate_limit_errors.dart';
import '../social_service.dart';

/// Show the "New club" form as a full-screen page with a back arrow.
/// Returns the new slug on success.
///
/// **History:** This used to be a `showModalBottomSheet`. The user
/// reported three real bugs against that layout:
///
///   1. The bottom sheet's content overflowed by ~54 px when the
///      software keyboard came up + when the inline error banner was
///      visible — the column couldn't shrink under the keyboard so
///      the bottom of the form went off-screen with the yellow
///      RenderFlex "BOTTOM OVERFLOWED" stripe.
///   2. Create / Cancel buttons sat under the system navigation
///      gesture bar (Samsung One UI, gesture-nav devices) because the
///      sheet didn't account for `viewPadding.bottom`.
///   3. The modal hid the rest of the app behind a dim layer; the
///      user wanted a proper page with a back button so they could
///      tap-out the keyboard or back-out without dismissing the
///      modal accidentally.
///
/// Full-screen `MaterialPageRoute` solves all three — `Scaffold`
/// auto-handles bottom-inset for the keyboard via
/// `resizeToAvoidBottomInset: true`, `SafeArea` clears the system
/// nav bar, and the back button matches the rest of the app's
/// navigation pattern.
Future<String?> showClubFormSheet(
  BuildContext context, {
  required SocialService social,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => _ClubFormScreen(social: social),
      fullscreenDialog: false,
    ),
  );
}

class _ClubFormScreen extends StatefulWidget {
  final SocialService social;
  const _ClubFormScreen({required this.social});

  @override
  State<_ClubFormScreen> createState() => _ClubFormScreenState();
}

class _ClubFormScreenState extends State<_ClubFormScreen> {
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
    final l10n = AppLocalizations.of(context);
    final slug = _slugify(name);
    if (slug.isEmpty) {
      setState(() => _error = l10n.clubFormErrSlug);
      return;
    }
    // Pre-flight readiness check — without this the createClub call
    // hits SocialService._c which throws StateError "called before
    // Supabase.initialize() resolved." The user surfaced this as a
    // crash when their build came up without Supabase env vars / the
    // init failed silently. Surface a friendly inline error instead.
    if (!widget.social.isReady) {
      setState(() {
        _error = l10n.clubFormErrUnreachable;
      });
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
      // Defensive catch for the late-init StateError — if for any
      // reason the readiness probe above was stale by the time the
      // request fired, we still surface the friendly message
      // instead of the raw "Bad state:" toString.
      if (e is StateError &&
          e.message.contains('Supabase.initialize')) {
        message = l10n.clubFormErrUnreachable;
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      // resizeToAvoidBottomInset=true (the default) means the body
      // shrinks when the keyboard slides up so the SingleChildScrollView
      // can scroll its contents — no more 54-px RenderFlex overflow.
      appBar: AppBar(
        title: Text(l10n.clubFormTitle),
      ),
      body: SafeArea(
        // Clears the bottom system nav bar so Create / Cancel
        // aren't covered by Samsung's gesture handle.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: l10n.clubFormNameLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _description,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: l10n.clubFormDescriptionLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _location,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: l10n.clubFormLocationLabel,
                  hintText: l10n.clubFormLocationHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text(l10n.clubFormPublic),
                    icon: const Icon(Icons.public),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text(l10n.clubFormPrivate),
                    icon: const Icon(Icons.lock_outline),
                  ),
                ],
                selected: {_isPublic},
                onSelectionChanged: (s) => setState(() {
                  _isPublic = s.first;
                  if (!_isPublic && _joinPolicy != 'invite') {
                    _joinPolicy = 'invite';
                  }
                  if (_isPublic && _joinPolicy == 'invite') {
                    _joinPolicy = 'open';
                  }
                }),
              ),
              const SizedBox(height: 12),
              Text(l10n.clubFormJoinPolicy, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  if (_isPublic) ...[
                    ChoiceChip(
                      label: Text(l10n.clubFormJoinOpen),
                      selected: _joinPolicy == 'open',
                      onSelected: (_) =>
                          setState(() => _joinPolicy = 'open'),
                    ),
                    ChoiceChip(
                      label: Text(l10n.clubFormJoinRequest),
                      selected: _joinPolicy == 'request',
                      onSelected: (_) =>
                          setState(() => _joinPolicy = 'request'),
                    ),
                  ] else
                    ChoiceChip(
                      label: Text(l10n.clubFormJoinInvite),
                      selected: _joinPolicy == 'invite',
                      onSelected: (_) =>
                          setState(() => _joinPolicy = 'invite'),
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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.pop(context),
                    child: Text(l10n.clubFormCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.clubFormCreate),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

