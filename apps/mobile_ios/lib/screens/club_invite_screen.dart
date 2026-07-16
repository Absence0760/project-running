import 'package:flutter/material.dart';

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../social_service.dart';
import '../training_service.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import 'club_detail_screen.dart';

/// Redeem a club invite token. Mirrors the web
/// `/clubs/join/[token]` landing page. The web version is a public
/// route — anyone with the link gets the redemption form, sign-in
/// happens inline if needed. On mobile, the screen is reached via
/// the "Join with code" entry on the Social → Clubs tab, OR via a
/// deep link (universal link / app intent) that drops the user
/// here with [initialToken] pre-filled.
///
/// On success, redirects to the club's detail screen so the user
/// sees the club they just joined immediately. On failure, the
/// exception is routed through [friendlyError] so the error slot
/// shows actionable copy (offline / rate-limited / generic) rather
/// than a raw `PostgrestException(...)` / `SocketException` toString;
/// the raw string is kept in `debugPrint` only.
class ClubInviteScreen extends StatefulWidget {
  final SocialService social;
  final TrainingService training;
  final String? initialToken;

  const ClubInviteScreen({
    super.key,
    required this.social,
    required this.training,
    this.initialToken,
  });

  @override
  State<ClubInviteScreen> createState() => _ClubInviteScreenState();
}

class _ClubInviteScreenState extends State<ClubInviteScreen> {
  late final TextEditingController _tokenCtl;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tokenCtl = TextEditingController(text: widget.initialToken ?? '');
    // If we arrived with a token from a deep-link, fire the
    // redemption immediately so the user lands on the club detail
    // page without a manual tap. They can still see the form +
    // error state if redemption fails.
    if ((widget.initialToken ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _redeem());
    }
  }

  @override
  void dispose() {
    _tokenCtl.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final token = _tokenCtl.text.trim();
    if (token.isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context).clubInviteEnterCodeError,
      );
      return;
    }
    if (!await ensureSignedIn(context,
        viewerId: widget.social.currentUserId)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final slug = await widget.social.joinClubByToken(token);
      if (!mounted) return;
      showTopBanner(context, AppLocalizations.of(context).clubInviteJoinedBanner);
      // Replace the invite screen with the club detail so a back-tap
      // returns the user to where they were before redemption (not
      // back into the redemption form).
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ClubDetailScreen(
            social: widget.social,
            training: widget.training,
            slug: slug,
          ),
        ),
      );
    } catch (e) {
      debugPrint('ClubInviteScreen._redeem failed: $e');
      if (mounted) {
        setState(() => _error = friendlyError(AppLocalizations.of(context), e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.clubInviteTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.clubInviteIntro,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenCtl,
              decoration: InputDecoration(
                labelText: l10n.clubInviteCodeLabel,
                border: const OutlineInputBorder(),
              ),
              autocorrect: false,
              enableSuggestions: false,
              autofocus: widget.initialToken == null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _redeem,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.clubInviteJoinButton),
            ),
          ],
        ),
      ),
    );
  }
}
