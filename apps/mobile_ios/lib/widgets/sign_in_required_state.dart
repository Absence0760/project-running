import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../screens/sign_in_screen.dart';

/// Shared signed-out state for auth-required surfaces. Renders "sign in to
/// do this" with a working sign-in CTA instead of a generic error + a Retry
/// that can never succeed. When the backend itself is unavailable
/// (Supabase init failed at launch), sign-in can't fix anything either, so
/// it renders the unavailable copy with no affordance at all.
class SignInRequiredState extends StatelessWidget {
  final ApiClient? api;
  final String? message;
  final VoidCallback? onSignedIn;

  const SignInRequiredState({
    super.key,
    this.api,
    this.message,
    this.onSignedIn,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final api = resolveApiForSignIn(this.api);
    final unavailable = api == null;
    final text = message ??
        (unavailable
            ? l10n.backendUnavailableMessage
            : l10n.signInRequiredMessage);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                unavailable ? Icons.cloud_off : Icons.lock_outline,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (!unavailable) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () => _signIn(context, api),
                  icon: const Icon(Icons.login),
                  label: Text(l10n.signInRequiredAction),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signIn(BuildContext context, ApiClient api) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SignInScreen(apiClient: api)),
    );
    if (ok == true) onSignedIn?.call();
  }
}

/// Gate for auth-only action sites (RSVP, join, follow, bookmark, publish).
/// Returns true when the viewer is signed in; otherwise routes into the
/// sign-in flow and returns false. [onSignedIn] fires after a successful
/// sign-in so the caller can reload and let the user retry the action.
///
/// [viewerId] is the caller's OWN view of the signed-in user — pass the
/// handle the screen already renders from (`social.currentUserId`,
/// `api?.userId`). It's required so no call site silently falls back to
/// a global read: the gate must agree with the identity the surrounding
/// screen is showing, and a screen driven by an injected service can
/// then be exercised signed-in or signed-out under test.
Future<bool> ensureSignedIn(
  BuildContext context, {
  required String? viewerId,
  ApiClient? api,
  VoidCallback? onSignedIn,
}) async {
  if (viewerId != null) return true;
  final resolved = resolveApiForSignIn(api);
  if (resolved == null) return false;
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => SignInScreen(apiClient: resolved)),
  );
  if (ok == true) onSignedIn?.call();
  return false;
}

/// The client the sign-in flow should use: the caller's handle when it has
/// one, else a fresh instance — but only when Supabase actually
/// initialized, so a no-backend launch can never manufacture the doomed
/// every-method-throws client (issue #238).
ApiClient? resolveApiForSignIn(ApiClient? api) =>
    api ?? (ApiClient.isInitialized ? ApiClient() : null);
