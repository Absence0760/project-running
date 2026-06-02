import 'dart:io' show Platform;

import 'package:api_client/api_client.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../widgets/top_banner.dart';

/// Email/password account-creation screen with Google + Apple OAuth.
///
/// Returns `true` from `Navigator.pop` if registration succeeded so the
/// caller can refresh state — same contract as `SignInScreen`.
class SignUpScreen extends StatefulWidget {
  final ApiClient apiClient;
  const SignUpScreen({super.key, required this.apiClient});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  /// GDPR Article 8 — users under 16 require parental consent for
  /// data processing in the EU. We block sign-up at the client until
  /// the user self-affirms 16+. Mirrors web's `confirmAdult` gate
  /// on `/login` (apps/web/src/routes/login/+page.svelte).
  bool _confirmAdult = false;
  /// Terms of Service + Privacy Policy acceptance. Mirrors web's
  /// `acceptTerms` gate. Both gates apply to email/password and to
  /// OAuth sign-in — anyone creating an account through this app
  /// must clear both.
  bool _acceptTerms = false;

  // GDPR Art 7(2): the consent request must let the user read the Terms +
  // Privacy Policy before accepting, so the label carries tappable links.
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => _openLegal('terms');
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => _openLegal('privacy');

  Future<void> _openLegal(String path) async {
    final url = 'https://threkir.com/$path';
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showTopBanner(context, AppLocalizations.of(context).signUpCouldNotOpen(url));
      }
    } catch (e) {
      debugPrint('sign_up: opening $url failed: $e');
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).signUpCouldNotOpen(url));
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_confirmAdult) {
      setState(() =>
          _error = AppLocalizations.of(context).signUpErrorConfirmAge);
      return;
    }
    if (!_acceptTerms) {
      setState(() =>
          _error = AppLocalizations.of(context).signUpErrorAcceptTerms);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Stamps both consent timestamps at the moment the user ticks
      // the checkboxes; ApiClient.signUp persists them server-side
      // via the confirm_age_and_terms RPC. See audit/gdpr Critical.
      final stamp = DateTime.now().toUtc();
      await widget.apiClient.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        ageConfirmedAt: stamp,
        termsAcceptedAt: stamp,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('SignUpScreen._signUp failed: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Shared pre-flight for OAuth sign-up paths — the age + ToS
  /// gates apply to Google / Apple sign-up the same way they apply
  /// to email/password. Web's /login flow uses the same gates on
  /// the sign-up tab regardless of provider. Returns true when
  /// the gates clear; sets [_error] and returns false otherwise.
  bool _checkGates() {
    if (!_confirmAdult) {
      setState(() =>
          _error = AppLocalizations.of(context).signUpErrorConfirmAge);
      return false;
    }
    if (!_acceptTerms) {
      setState(() =>
          _error = AppLocalizations.of(context).signUpErrorAcceptTerms);
      return false;
    }
    return true;
  }

  Future<void> _signInWithGoogle() async {
    if (!_checkGates()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
      if (webClientId == null || webClientId.isEmpty) {
        throw Exception(
          'Google Sign-In not configured — set GOOGLE_WEB_CLIENT_ID in .env.local. '
          'See apps/mobile_android/local_testing.md.',
        );
      }

      // See sign_in_screen.dart for the google_sign_in 7.x notes.
      await _ensureGoogleInitialized(webClientId);
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw Exception('Google sign-in did not return an ID token');
      }

      await widget.apiClient.signInWithGoogleIdToken(idToken: idToken);
      // OAuth-path consent stamp (audit/gdpr Critical). The pre-tap
      // gate (_checkGates) confirmed the user's age + terms intent;
      // record that server-side now the JWT is live. Idempotent —
      // returning Google users are a no-op via first-stamp-wins.
      try {
        await widget.apiClient.confirmAgeAndTerms();
      } catch (_) {
        // Tolerated — next refresh retries; non-blocking for sign-in.
      }
      if (mounted) Navigator.pop(context, true);
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        debugPrint('SignUpScreen._signInWithGoogle failed: $e');
        if (mounted) setState(() => _error = e.toString());
      }
    } catch (e) {
      debugPrint('SignUpScreen._signInWithGoogle failed: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static bool _googleInitialized = false;
  static Future<void> _ensureGoogleInitialized(String serverClientId) async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
    _googleInitialized = true;
  }

  Future<void> _signInWithApple() async {
    if (!_checkGates()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception('Apple sign-in did not return an identity token');
      }
      // Route through ApiClient instead of `Supabase.instance.client`
      // directly — matches the Google path and keeps every auth flow
      // on the ApiClient abstraction.
      await widget.apiClient.signInWithAppleIdToken(idToken: idToken);
      // OAuth-path consent stamp — mirrors the Google branch above.
      try {
        await widget.apiClient.confirmAgeAndTerms();
      } catch (_) {
        // Tolerated — next refresh retries.
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('SignUpScreen._signInWithApple failed: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final appleFirst = Platform.isIOS;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.signUpTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(Icons.directions_run,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                l10n.signUpHeadline,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.signUpSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.authEmailLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.authPasswordLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              // GDPR Art 8 gate — users under 16 require parental
              // consent for data processing in the EU. Self-affirm
              // at signup so we have a record of the user's claim.
              CheckboxListTile(
                value: _confirmAdult,
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _confirmAdult = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.signUpConfirmAge),
              ),
              // Terms + Privacy acceptance — mirrors web `acceptTerms`.
              CheckboxListTile(
                value: _acceptTerms,
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _acceptTerms = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: l10n.signUpAcceptPrefix),
                      TextSpan(
                        text: l10n.signUpTermsLink,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: _termsTap,
                      ),
                      TextSpan(text: l10n.signUpAcceptConjunction),
                      TextSpan(
                        text: l10n.signUpPrivacyLink,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: _privacyTap,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _signUp,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.signUpButton),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      l10n.authOrDivider,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
              if (appleFirst) ...[
                OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithApple,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.apple, size: 18),
                  label: Text(l10n.signUpContinueWithApple),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithGoogle,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.login, size: 18),
                  label: Text(l10n.signUpContinueWithGoogle),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithGoogle,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.login, size: 18),
                  label: Text(l10n.signUpContinueWithGoogle),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithApple,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.apple, size: 18),
                  label: Text(l10n.signUpContinueWithApple),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.signUpSignInPrompt),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
