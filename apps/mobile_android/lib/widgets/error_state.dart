import 'package:flutter/material.dart';

/// Hard cap on `await`s that hit Supabase / an Edge Function. When the
/// backend is unreachable, supabase-dart's HTTP calls don't resolve on
/// their own for minutes — the timeout converts that into a visible
/// error state the user can retry.
const kBackendLoadTimeout = Duration(seconds: 15);

/// Shared empty-but-errored state for any list/detail screen whose
/// primary data fetch hit a backend failure or timeout. Keeps copy and
/// layout consistent across tabs so users learn one recovery affordance.
///
/// Callers render this instead of the normal list when their `_error`
/// field is non-null, and wire `onRetry` to the same load function.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final IconData icon;

  const ErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.icon = Icons.cloud_off,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
