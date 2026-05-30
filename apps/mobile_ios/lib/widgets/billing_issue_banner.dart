import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Persistent banner shown when the signed-in Pro user has a recent
/// `BILLING_ISSUE` event from RevenueCat — a renewal payment failed
/// but the entitlement is still active during the store's grace
/// period (~16 days App Store, up to 30 days Play). Mirrors web's
/// `apps/web/src/lib/components/BillingIssueBanner.svelte`.
///
/// Mounted at the top of `HomeScreen`'s Scaffold body so it surfaces
/// on every authed tab until the user resolves the card issue or the
/// `revenuecat-webhook` clears the flag (`RENEWAL` / `UNCANCELLATION`
/// recovered, `EXPIRATION` / `CANCELLATION` ended).
///
/// Fetches profile on mount + on app foreground so a webhook delivery
/// while the app was backgrounded still surfaces the next time the
/// user looks. L4 resilience: a fetch error is silently swallowed —
/// the banner is a hint, not a hard requirement, and the recording
/// + sync paths must not fail because of it.

/// Pure-logic visibility predicate, extracted so the rule that
/// gates the banner can be unit-tested without a Flutter widget
/// tree. Mirrors the web shape `auth.isPro && !!auth.user?.billing_issue_at`.
bool shouldShowBillingIssueBanner({
  required String? subscriptionTier,
  required DateTime? billingIssueAt,
}) {
  if (billingIssueAt == null) return false;
  return subscriptionTier == 'pro' || subscriptionTier == 'lifetime';
}

/// "today" / "yesterday" / "N days ago" relative-time helper.
/// Pure for testability; wall-clock `now` is injectable so the
/// boundary cases ("just now" + 23h59m, "1 day" + 24h00m) are
/// pinnable without sleeping.
String relativeDaysSince(DateTime since, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final days = n.difference(since).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}

class BillingIssueBanner extends StatefulWidget {
  final ApiClient? apiClient;

  /// Override target the banner CTA navigates to. Defaults to the
  /// hosted upgrade page (matches the existing "Manage subscription"
  /// tile in `settings_screen.dart`). Tests inject a no-op so the
  /// `url_launcher` plugin isn't reached.
  final Future<void> Function(String url)? onOpenExternal;

  const BillingIssueBanner({
    super.key,
    required this.apiClient,
    this.onOpenExternal,
  });

  @override
  State<BillingIssueBanner> createState() => _BillingIssueBannerState();
}

class _BillingIssueBannerState extends State<BillingIssueBanner>
    with WidgetsBindingObserver {
  static const _manageUrl = 'https://threkir.com/settings/upgrade';

  String? _subscriptionTier;
  DateTime? _billingIssueAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final api = widget.apiClient;
    if (api == null) return;
    try {
      final profile = await api.fetchMyProfile();
      if (!mounted) return;
      setState(() {
        _subscriptionTier = profile?.subscriptionTier;
        _billingIssueAt = profile?.billingIssueAt;
      });
    } catch (_) {
      // L4: silent. The banner is decorative — never crash the app
      // because of a refresh failure.
    }
  }

  Future<void> _openManage() async {
    final opener =
        widget.onOpenExternal ?? (url) => launchUrl(Uri.parse(url));
    try {
      await opener(_manageUrl);
    } catch (_) {
      // L4: silent. Same rationale — banner is decorative.
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = shouldShowBillingIssueBanner(
      subscriptionTier: _subscriptionTier,
      billingIssueAt: _billingIssueAt,
    );
    if (!visible) return const SizedBox.shrink();

    final since = _billingIssueAt!;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.credit_card_off,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pro renewal failed ${relativeDaysSince(since)}.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Update your card or you\'ll be downgraded to Free.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _openManage,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Manage'),
            ),
          ],
        ),
      ),
    );
  }
}
