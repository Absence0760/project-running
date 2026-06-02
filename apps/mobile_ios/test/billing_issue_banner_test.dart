import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_android/l10n/gen/app_localizations.dart';
import 'package:mobile_android/l10n/gen/app_localizations_en.dart';
import 'package:mobile_android/widgets/billing_issue_banner.dart';

/// Pure-logic tests for the BillingIssueBanner visibility predicate
/// and the relative-days helper. The widget itself is not exercised
/// here — it pulls a real `ApiClient.fetchMyProfile` and `url_launcher`
/// which both need integration plumbing. The visibility rule is the
/// only thing that can drift independently between web and mobile,
/// so pinning it as a pure helper is the load-bearing piece.
///
/// Mirrors web's shape:
///   `auth.isPro && !!auth.user?.billing_issue_at`
///
/// where web's `auth.isPro` is `subscription_tier in ('pro', 'lifetime')`.
void main() {
  group('shouldShowBillingIssueBanner', () {
    test('null billing_issue_at always hides the banner regardless of tier', () {
      expect(
        shouldShowBillingIssueBanner(
          subscriptionTier: 'pro',
          billingIssueAt: null,
        ),
        isFalse,
      );
      expect(
        shouldShowBillingIssueBanner(
          subscriptionTier: 'lifetime',
          billingIssueAt: null,
        ),
        isFalse,
      );
      expect(
        shouldShowBillingIssueBanner(
          subscriptionTier: 'free',
          billingIssueAt: null,
        ),
        isFalse,
      );
    });

    test('free tier with a stale flag still hides the banner (defence in depth)', () {
      // The webhook clears the flag on EXPIRATION / CANCELLATION, but
      // a missed delivery shouldn't strand the banner on a free
      // account. Mirrors the web component's `visible = !!since &&
      // isProTier` guard.
      expect(
        shouldShowBillingIssueBanner(
          subscriptionTier: 'free',
          billingIssueAt: DateTime(2026, 4, 1),
        ),
        isFalse,
      );
    });

    test('pro / lifetime + non-null billing_issue_at shows the banner', () {
      final flag = DateTime(2026, 4, 1);
      expect(
        shouldShowBillingIssueBanner(
          subscriptionTier: 'pro',
          billingIssueAt: flag,
        ),
        isTrue,
      );
      expect(
        shouldShowBillingIssueBanner(
          subscriptionTier: 'lifetime',
          billingIssueAt: flag,
        ),
        isTrue,
      );
    });

    test('null subscription_tier (un-fetched) hides the banner', () {
      // First render before the profile fetch resolves — must not
      // flash the banner. Mirrors the web `auth.user == null` early
      // return.
      expect(
        shouldShowBillingIssueBanner(
          subscriptionTier: null,
          billingIssueAt: DateTime(2026, 4, 1),
        ),
        isFalse,
      );
    });

    test('unknown tier value (forward compat) hides the banner', () {
      // A future tier name not yet known to the client (e.g. 'team')
      // should NOT enable the banner — opt-in by listing the tier
      // explicitly, not opt-out by listing exclusions.
      expect(
        shouldShowBillingIssueBanner(
          subscriptionTier: 'team',
          billingIssueAt: DateTime(2026, 4, 1),
        ),
        isFalse,
      );
    });
  });

  group('relativeDaysSince', () {
    final ref = DateTime(2026, 5, 1, 12, 0, 0);
    final AppLocalizations l10n = AppLocalizationsEn();

    test('< 24 h ago → "today"', () {
      // The same calendar day from the user's POV. Difference.inDays
      // truncates to 0.
      expect(
        relativeDaysSince(l10n, DateTime(2026, 5, 1, 6, 0, 0), ref),
        'today',
      );
      // 23h59m ago — still 0 calendar days under inDays.
      expect(
        relativeDaysSince(l10n, DateTime(2026, 4, 30, 12, 0, 1), ref),
        'today',
      );
    });

    test('exactly 24 h ago → "yesterday"', () {
      expect(
        relativeDaysSince(l10n, DateTime(2026, 4, 30, 12, 0, 0), ref),
        'yesterday',
      );
    });

    test('48 h+ → "N days ago"', () {
      expect(
        relativeDaysSince(l10n, DateTime(2026, 4, 29, 12, 0, 0), ref),
        '2 days ago',
      );
      expect(
        relativeDaysSince(l10n, DateTime(2026, 4, 1, 12, 0, 0), ref),
        '30 days ago',
      );
    });

    test('future timestamp (clock skew) → "today" (clamped at 0)', () {
      // If the server's billing_issue_at is slightly ahead of local
      // wall clock, don't show "-1 days ago". Clamp to today.
      expect(
        relativeDaysSince(l10n, DateTime(2026, 5, 2, 12, 0, 0), ref),
        'today',
      );
    });

    test('default `now` parameter resolves to wall clock', () {
      // Smoke test that the optional second arg defaults sensibly.
      // We check the shape of the output, not the value, since
      // wall clock makes assertions brittle.
      final out = relativeDaysSince(l10n, DateTime.now());
      expect(out, anyOf('today', startsWith('1'), startsWith('0')));
    });
  });
}
