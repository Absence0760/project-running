import 'dart:io' show Platform;

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../apple_auth.dart';
import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../widgets/top_banner.dart';
import 'sign_up_screen.dart';

/// Email/password sign-in screen with Google + Apple OAuth alongside.
///
/// Returns `true` from `Navigator.pop` when sign-in succeeds. The optional
/// `onSignedIn` callback fires before pop so a top-level `MaterialApp`
/// owner that drives its own routing can re-render in response.
class SignInScreen extends StatefulWidget {
  final ApiClient apiClient;
  final VoidCallback? onSignedIn;
  const SignInScreen({super.key, required this.apiClient, this.onSignedIn});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  /// Classified kind of the auth failure behind [_error], when it came
  /// from [friendlyAuthError]. Drives kind-specific affordances — the
  /// "Resend confirmation email" button on `email_not_confirmed`.
  AuthErrorKind? _errorKind;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorKind = null;
    });
    try {
      await widget.apiClient.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      widget.onSignedIn?.call();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('SignInScreen._signIn failed: $e');
      if (mounted) {
        setState(() {
          _errorKind = classifyAuthError(e);
          _error = friendlyAuthError(AppLocalizations.of(context), e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Re-send the signup confirmation email to the address in the email
  /// field. Only reachable from the `email_not_confirmed` error state.
  /// Same privacy-preserving copy contract as [_sendPasswordReset].
  Future<void> _resendConfirmation() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = AppLocalizations.of(context).signInResetNeedEmail;
        _errorKind = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _errorKind = null;
    });
    try {
      await widget.apiClient.resendSignUpConfirmation(email: email);
      if (!mounted) return;
      showTopBanner(
        context,
        AppLocalizations.of(context).signInConfirmationResent,
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint('SignInScreen._resendConfirmation failed: $e');
      if (mounted) {
        setState(() {
          _errorKind = classifyAuthError(e);
          _error = friendlyAuthError(AppLocalizations.of(context), e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Send a password-reset email to the address currently in the
  /// email field. Mirrors the web `/login?reset=1` surface. The
  /// reset-link in the email points at web's `/auth/reset` page —
  /// mobile doesn't host the password-edit form. Privacy-preserving
  /// confirmation toast says "If that email is registered…" rather
  /// than leaking account existence.
  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = AppLocalizations.of(context).signInResetNeedEmail;
        _errorKind = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _errorKind = null;
    });
    try {
      var webBase =
          (dotenv.isInitialized ? dotenv.maybeGet('WEB_BASE_URL') : null)
                  ?.trim() ??
              '';
      if (webBase.isEmpty) webBase = 'https://threkir.com';
      if (webBase.endsWith('/')) {
        webBase = webBase.substring(0, webBase.length - 1);
      }
      await widget.apiClient.sendPasswordResetEmail(
        email: email,
        redirectTo: '$webBase/auth/reset',
      );
      if (!mounted) return;
      // Show the privacy-preserving copy via the canonical top-banner
      // primitive (see docs/architecture/conventions.md § "Mobile in-app
      // notifications"). The architecture-guards test pins this to
      // catch a regression that reaches for ScaffoldMessenger.
      showTopBanner(
        context,
        AppLocalizations.of(context).signInResetSent,
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint('SignInScreen._sendPasswordReset failed: $e');
      if (mounted) {
        setState(() {
          _errorKind = classifyAuthError(e);
          _error = friendlyAuthError(AppLocalizations.of(context), e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Google Sign-In via the native flow. On Android, requires
  /// `GOOGLE_WEB_CLIENT_ID` in `.env.local` and an Android OAuth 2.0
  /// client configured with the app's SHA-1 fingerprint. See
  /// `apps/mobile_android/local_testing.md`.
  Future<void> _signInWithGoogle() async {
    final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
    if (webClientId == null || webClientId.isEmpty) {
      // Google OAuth provider isn't wired up on this build yet — show a
      // friendly coming-soon notice instead of a raw configuration error.
      // Mirrors web's PUBLIC_GOOGLE_AUTH_ENABLED fail-closed gate.
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).googleSignInSoon;
          _errorKind = null;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _errorKind = null;
    });
    try {
      // google_sign_in 7.x: singleton + one-time initialize() before any
      // other call. _ensureGoogleInitialized makes that idempotent so
      // multiple sign-in attempts in one session don't trip "undefined
      // behaviour" warnings from the plugin.
      await _ensureGoogleInitialized(webClientId);
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw Exception('Google sign-in did not return an ID token');
      }

      // 7.x split: idToken is on the account immediately after
      // authenticate(), but accessToken now requires an explicit
      // authorizationClient call. Supabase's signInWithIdToken accepts
      // a null access token, so we skip that round-trip — the OAuth
      // grant is verified by the idToken alone.
      await widget.apiClient.signInWithGoogleIdToken(idToken: idToken);
      widget.onSignedIn?.call();
      if (mounted) Navigator.pop(context, true);
    } on GoogleSignInException catch (e) {
      // User cancelled — silent return, no error toast.
      if (e.code != GoogleSignInExceptionCode.canceled) {
        debugPrint('SignInScreen._signInWithGoogle failed: $e');
        if (mounted) {
          setState(() => _error =
              friendlyAuthError(AppLocalizations.of(context), e));
        }
      }
    } catch (e) {
      debugPrint('SignInScreen._signInWithGoogle failed: $e');
      if (mounted) {
        setState(() {
          _errorKind = classifyAuthError(e);
          _error = friendlyAuthError(AppLocalizations.of(context), e);
        });
      }
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

  /// Apple Sign-In via the native flow on iOS, web fallback on Android.
  /// The Android web flow hard-requires `webAuthenticationOptions` (an
  /// Apple Services ID + allow-listed return URL, env-provisioned — see
  /// `apple_auth.dart`); until they're configured the button fails
  /// closed with the same coming-soon notice as the Google gate. The
  /// flow returns an Apple identity token that we hand to
  /// `Supabase.auth.signInWithIdToken` directly.
  Future<void> _signInWithApple() async {
    if (!appleSignInAvailable()) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).appleSignInSoon;
          _errorKind = null;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _errorKind = null;
    });
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: appleWebAuthOptions(),
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception('Apple sign-in did not return an identity token');
      }
      // Route through ApiClient instead of `Supabase.instance.client`
      // directly, matching the Google path. Keeps every auth flow on
      // the ApiClient abstraction so the SDK-version + bootstrap
      // guards in `_client` apply uniformly.
      await widget.apiClient.signInWithAppleIdToken(idToken: idToken);
      widget.onSignedIn?.call();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('SignInScreen._signInWithApple failed: $e');
      if (mounted) {
        setState(() {
          _errorKind = classifyAuthError(e);
          _error = friendlyAuthError(AppLocalizations.of(context), e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Show Apple as the primary OAuth on iOS (App Store guideline 4.8 — apps
    // that offer third-party login must offer Sign in with Apple alongside).
    // Android keeps Google as the primary; Apple is still available via the
    // package's web fallback for users who'd prefer it.
    final appleFirst = Platform.isIOS;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.signInTitle)),
      // Scaffold already inherits resizeToAvoidBottomInset: true, so the
      // body gets shrunk by the keyboard — the Column inside has to be
      // scrollable to absorb the remaining content, otherwise Flutter's
      // debug overlay shows "BOTTOM OVERFLOWED BY N PIXELS".
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
                l10n.signInHeadline,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.signInSubtitle,
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
                if (_errorKind == AuthErrorKind.emailNotConfirmed)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _loading ? null : _resendConfirmation,
                      child: Text(l10n.signInResendConfirmation),
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _signIn,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.signInButton),
              ),
              // Forgot-password link — sends a reset email to the
              // address in the field above. Mirrors web /login?reset=1.
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _sendPasswordReset,
                  child: Text(l10n.signInForgotPassword),
                ),
              ),
              const SizedBox(height: 4),
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
                  label: Text(l10n.signInWithApple),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithGoogle,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.login, size: 18),
                  label: Text(l10n.signInWithGoogle),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithGoogle,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.login, size: 18),
                  label: Text(l10n.signInWithGoogle),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithApple,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.apple, size: 18),
                  label: Text(l10n.signInWithApple),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.signInContinueOffline),
              ),
              TextButton(
                onPressed: () async {
                  final signedUp = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SignUpScreen(apiClient: widget.apiClient),
                    ),
                  );
                  if (mounted && signedUp == true) {
                    widget.onSignedIn?.call();
                    Navigator.pop(context, true);
                  }
                },
                child: Text(l10n.signInCreateAccountPrompt),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
