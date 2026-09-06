import 'package:core_models/core_models.dart' show ClubRow;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:ui_kit/ui_kit.dart' show ChoiceChipOption, ChoiceChipRow;

import '../club_slug.dart';
import '../l10n/gen/app_localizations.dart';
import '../rate_limit_message.dart';
import '../social_service.dart';
import '../text_limits.dart';
import 'full_screen_form.dart';

/// Show the "New club" form (or an edit form when [existing] is set) as a
/// full-screen dialog. Returns the slug on a create, or `true` on a saved
/// edit.
///
/// Presentation goes through [showFullScreenForm], the shared
/// create/edit-entity wrapper: the hosting `Scaffold` clears the soft
/// keyboard via `resizeToAvoidBottomInset`, `SafeArea` clears the system
/// nav bar, and the body's `SingleChildScrollView` prevents the
/// "BOTTOM OVERFLOWED" stripe the earlier bottom-sheet layout hit.
Future<String?> showClubFormSheet(
  BuildContext context, {
  required SocialService social,
  ClubRow? existing,
}) {
  final formKey = GlobalKey<_ClubFormScreenState>();
  return showFullScreenForm<String>(
    context,
    title: existing == null
        ? AppLocalizations.of(context).clubFormTitle
        : AppLocalizations.of(context).clubFormEditTitle,
    isDirty: () => formKey.currentState?.isDirty ?? false,
    builder: (_) =>
        _ClubFormScreen(key: formKey, social: social, existing: existing),
  );
}

class _ClubFormScreen extends StatefulWidget {
  final SocialService social;
  final ClubRow? existing;
  const _ClubFormScreen({super.key, required this.social, this.existing});

  @override
  State<_ClubFormScreen> createState() => _ClubFormScreenState();
}

class _ClubFormScreenState extends State<_ClubFormScreen> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _location =
      TextEditingController(text: widget.existing?.locationLabel ?? '');
  late final _website =
      TextEditingController(text: widget.existing?.websiteUrl ?? '');
  late final _instagram =
      TextEditingController(text: widget.existing?.instagramUrl ?? '');
  late final _strava =
      TextEditingController(text: widget.existing?.stravaUrl ?? '');
  late final _facebook =
      TextEditingController(text: widget.existing?.facebookUrl ?? '');
  late bool _isPublic = widget.existing?.isPublic ?? true;
  String _joinPolicy = 'open';
  bool _busy = false;
  // Name validation renders inline on the name field; _error stays for
  // failures not attributable to a single field (unreachable backend,
  // save failure).
  String? _nameError;
  String? _error;

  bool get _isEdit => widget.existing != null;

  late final String _initialSnapshot;

  @override
  void initState() {
    super.initState();
    _initialSnapshot = _snapshot();
  }

  // The join-policy chips only render on create; edit mode leaves the value
  // untouched so it stays out of the edit snapshot (toggling visibility can
  // shuffle it without any visible change).
  String _snapshot() => [
        _name.text,
        _description.text,
        _location.text,
        _website.text,
        _instagram.text,
        _strava.text,
        _facebook.text,
        _isPublic.toString(),
        if (!_isEdit) _joinPolicy,
      ].join('\u0000');

  bool get isDirty => _snapshot() != _initialSnapshot;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _location.dispose();
    _website.dispose();
    _instagram.dispose();
    _strava.dispose();
    _facebook.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    // Empty name used to return silently — Save looked dead. Flag the
    // field instead (sign_up_screen idiom); the no-usable-characters
    // case is name-attributable too.
    final slug = clubSlug(name);
    // The refusal tests the NAME for a nameable character, not the slug for
    // emptiness. A club called `Бегуны Москвы` folds to no `[a-z0-9]` at all,
    // so the old test refused to create it — with a message claiming the name
    // had no letter or digit, about a name made entirely of letters — while
    // the web created it happily under the shared fallback slug. Every
    // non-Latin script was unreachable on the phone (decisions § 1281).
    // The predicate now lives in `club_slug.dart` beside the slug it guards,
    // so the web editor runs the same one rather than accepting a name this
    // side refuses (decisions § 1338).
    final nameError = name.isEmpty
        ? l10n.clubFormErrName
        : clubNameNamesSomething(name)
            ? null
            : l10n.clubFormErrSlug;
    setState(() => _nameError = nameError);
    if (nameError != null) return;
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
      if (_isEdit) {
        await widget.social.updateClub(
          widget.existing!.id,
          name: name,
          description: _description.text,
          locationLabel: _location.text,
          isPublic: _isPublic,
          websiteUrl: _website.text,
          instagramUrl: _instagram.text,
          stravaUrl: _strava.text,
          facebookUrl: _facebook.text,
        );
        if (!mounted) return;
        Navigator.of(context).pop<String?>(widget.existing!.slug);
        return;
      }
      final club = await widget.social.createClub(
        name: name,
        slug: slug.isEmpty ? kClubSlugFallback : slug,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        locationLabel: _location.text.trim().isEmpty
            ? null
            : _location.text.trim(),
        isPublic: _isPublic,
        joinPolicy: _joinPolicy,
        websiteUrl: _website.text,
        instagramUrl: _instagram.text,
        stravaUrl: _strava.text,
        facebookUrl: _facebook.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop<String?>(club.slug);
    } catch (e) {
      if (!mounted) return;
      // Recognise the create_club rate-limit P0001 (migration
      // 20260907_001) and surface the localized "wait N minutes"
      // message instead of the raw PostgrestException toString.
      // Mirror of the web fix in apps/web/src/lib/core/data.ts +
      // ClubEditor.svelte. Unknown errors fall through to the raw
      // toString so debugging information isn't hidden.
      String message = e.toString();
      if (e is PostgrestException) {
        final friendly =
            rateLimitErrorMessage(l10n, code: e.code, message: e.message);
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
    // Heading + Scaffold/SafeArea come from the host showFullScreenForm.
    return FullScreenFormBody(
      children: [
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: kClubNameMaxLength,
                decoration: InputDecoration(
                  labelText: l10n.clubFormNameLabel,
                  errorText: _nameError,
                ),
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _description,
                maxLines: 3,
                maxLength: kClubDescriptionMaxLength,
                decoration: InputDecoration(
                  labelText: l10n.clubFormDescriptionLabel,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _location,
                maxLength: kClubLocationLabelMaxLength,
                decoration: InputDecoration(
                  labelText: l10n.clubFormLocationLabel,
                  hintText: l10n.clubFormLocationHint,
                ),
              ),
              const SizedBox(height: 8),
              _LinkField(controller: _website, label: l10n.clubEditorWebsite, hint: 'https://example.com'),
              const SizedBox(height: 8),
              _LinkField(controller: _instagram, label: l10n.clubEditorInstagram, hint: 'https://instagram.com/yourclub'),
              const SizedBox(height: 8),
              _LinkField(controller: _strava, label: l10n.clubEditorStrava, hint: 'https://strava.com/clubs/yourclub'),
              const SizedBox(height: 8),
              _LinkField(controller: _facebook, label: l10n.clubEditorFacebook, hint: 'https://facebook.com/yourclub'),
              const SizedBox(height: 12),
              ChoiceChipRow<bool>(
                options: [
                  ChoiceChipOption(
                    value: true,
                    label: l10n.clubFormPublic,
                    icon: Icons.public,
                  ),
                  ChoiceChipOption(
                    value: false,
                    label: l10n.clubFormPrivate,
                    icon: Icons.lock_outline,
                  ),
                ],
                selected: _isPublic,
                onChanged: (v) => setState(() {
                  _isPublic = v;
                  if (!_isPublic && _joinPolicy != 'invite') {
                    _joinPolicy = 'invite';
                  }
                  if (_isPublic && _joinPolicy == 'invite') {
                    _joinPolicy = 'open';
                  }
                }),
              ),
              if (!_isEdit) ...[
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
              ],
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
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.maybePop(context),
                    child: Text(l10n.clubFormCancel),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isEdit ? l10n.clubEditorSaveChanges : l10n.clubFormCreate),
                  ),
                ],
              ),
            ],
          );
  }
}

class _LinkField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  const _LinkField({required this.controller, required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: 500,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
      ),
    );
  }
}

