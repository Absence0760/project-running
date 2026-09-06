import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat native-SDK wrapper for the in-app Pro purchase sheet. Its web
/// counterpart under `billing/` drives a different SDK against a different
/// store, so the two are NOT a lockstep parity pair and neither registry
/// carries them; what they share is the not-configured sentinel contract
/// below. The wrapper has three jobs:
///
/// 1. **Stay compilable on unconfigured builds.** When the platform-
///    appropriate API key isn't in `dotenv.env`, every entry point
///    returns a "not configured" sentinel (`false` / `null` / a
///    [PurchaseResult.notConfigured]). The native SDK is never
///    initialised, so dev / CI builds work without a RevenueCat
///    account.
/// 2. **Be idempotent.** [configureRevenueCat] is safe to call
///    multiple times — it's a no-op when the SDK is already
///    configured for the same user.
/// 3. **Treat user-cancelled purchases as benign.** Tapping
///    "X / cancel" on the RC sheet throws a platform exception; the
///    wrapper maps that to a [PurchaseResult.cancelled] so callers
///    don't surface a red error toast for a normal dismissal.
///
/// The native SDK flips `subscription_tier` server-side via the
/// `revenuecat-webhook` Edge Function, so callers typically refetch
/// `ApiClient.fetchMyProfile()` a couple of seconds after a
/// successful purchase.

/// Env keys read at startup. Mirror the names the deploy pipeline
/// expects; documented in `docs/features/paywall.md` and the deploy plan.
const _kAndroidKey = 'REVENUECAT_API_KEY_ANDROID';
const _kIosKey = 'REVENUECAT_API_KEY_IOS';

@visibleForTesting
String envApiKey() {
  if (Platform.isAndroid) return dotenv.env[_kAndroidKey] ?? '';
  if (Platform.isIOS) return dotenv.env[_kIosKey] ?? '';
  // Desktop / web (unsupported targets here) — never configured.
  return '';
}

/// True when the running build has a platform-appropriate
/// RevenueCat API key in `dotenv.env`. Tests can pass a [keyOverride]
/// to assert against a known value; the other helpers also accept the
/// override so a configured-state test never has to fake `Platform`.
bool isRevenueCatConfigured({String? keyOverride}) {
  final key = keyOverride ?? envApiKey();
  return key.isNotEmpty;
}

bool _configured = false;
String? _configuredUserId;

/// Idempotently configure the native SDK for [userId]. Re-configures
/// when the user changes so tokens don't leak across sign-outs.
/// Returns `false` when no API key is available — caller falls
/// through to the web URL.
Future<bool> configureRevenueCat(
  String userId, {
  String? keyOverride,
}) async {
  final key = keyOverride ?? envApiKey();
  if (key.isEmpty) return false;
  if (_configured && _configuredUserId == userId) return true;
  try {
    final config = PurchasesConfiguration(key)..appUserID = userId;
    await Purchases.configure(config);
    _configured = true;
    _configuredUserId = userId;
    return true;
  } catch (e) {
    debugPrint('RevenueCat configure failed: $e');
    return false;
  }
}

/// Outcome of [startProCheckout]. Distinguishes "purchase went
/// through" from "user cancelled" (benign) from "RC isn't configured
/// on this build" (caller should fall through to the web URL).
enum PurchaseResult { purchased, cancelled, notConfigured, failed }

/// Present the native Pro checkout sheet for [userId]. Prefers a
/// monthly package when one is available, matching the "$9.99 /
/// month" copy on the web settings page.
Future<PurchaseResult> startProCheckout(
  String userId, {
  String? keyOverride,
}) async {
  if (!await configureRevenueCat(userId, keyOverride: keyOverride)) {
    return PurchaseResult.notConfigured;
  }
  try {
    final offerings = await Purchases.getOfferings();
    final pkg = pickProPackage(offerings);
    if (pkg == null) {
      debugPrint('RevenueCat: no Pro offering available');
      return PurchaseResult.failed;
    }
    await Purchases.purchase(PurchaseParams.package(pkg));
    return PurchaseResult.purchased;
  } on PlatformException catch (e) {
    final code = PurchasesErrorHelper.getErrorCode(e);
    if (code == PurchasesErrorCode.purchaseCancelledError) {
      return PurchaseResult.cancelled;
    }
    debugPrint('RevenueCat purchase failed: $code / ${e.message}');
    return PurchaseResult.failed;
  } catch (e) {
    debugPrint('RevenueCat purchase failed: $e');
    return PurchaseResult.failed;
  }
}

/// Pick the "best" package out of the current offering — prefer a
/// monthly identifier, fall back to the first available. Public for
/// unit tests.
@visibleForTesting
Package? pickProPackage(Offerings offerings) {
  final current = offerings.current;
  if (current == null) return null;
  final packages = current.availablePackages;
  if (packages.isEmpty) return null;
  final monthlyPattern = RegExp(r'monthly|month', caseSensitive: false);
  for (final p in packages) {
    if (monthlyPattern.hasMatch(p.identifier)) return p;
  }
  return packages.first;
}

/// Restore purchases — drives RC's restore flow so a user who has
/// already paid (different install, different device, switched
/// store account) gets their entitlements back. Required by Apple
/// App Store Review Guideline 3.1.1 + Play subscription policy:
/// every subscription app must surface a "Restore purchases"
/// button. audit/app-store-privacy (May 2026).
Future<PurchaseResult> restorePurchases(
  String userId, {
  String? keyOverride,
}) async {
  if (!await configureRevenueCat(userId, keyOverride: keyOverride)) {
    return PurchaseResult.notConfigured;
  }
  try {
    final info = await Purchases.restorePurchases();
    // RC restorePurchases returns the latest CustomerInfo. Distinguish
    // "found an active entitlement" from "no entitlement to restore"
    // so the UI can show the right message — both are legitimate
    // outcomes; only the former is a success.
    final hasActive = info.entitlements.active.isNotEmpty;
    return hasActive
        ? PurchaseResult.purchased
        : PurchaseResult.cancelled; // "nothing to restore" — benign
  } catch (e) {
    debugPrint('RevenueCat restorePurchases failed: $e');
    return PurchaseResult.failed;
  }
}

/// Subscription-management URL — RC's hosted portal where the user
/// can change card / cancel. Returns null when the SDK isn't
/// configured or the user has no active subscription.
Future<String?> managementUrl(
  String userId, {
  String? keyOverride,
}) async {
  if (!await configureRevenueCat(userId, keyOverride: keyOverride)) {
    return null;
  }
  try {
    final info = await Purchases.getCustomerInfo();
    return info.managementURL;
  } catch (e) {
    debugPrint('RevenueCat managementUrl failed: $e');
    return null;
  }
}

/// The store-localised monthly Pro price string (e.g. `$9.99`, `9,99 €`,
/// `¥1,200`) from the current RevenueCat offering, or null when the SDK
/// isn't configured / no Pro package is available. Apple Guideline 3.1.1 +
/// Play subscription policy require the displayed price to come from the
/// store — it varies by territory — so the UI shows this when configured and
/// falls back to the USD list price only otherwise. Reuses [pickProPackage]
/// so the priced package matches the one [startProCheckout] purchases.
Future<String?> proMonthlyPriceString(
  String userId, {
  String? keyOverride,
}) async {
  if (!await configureRevenueCat(userId, keyOverride: keyOverride)) {
    return null;
  }
  try {
    final offerings = await Purchases.getOfferings();
    return pickProPackage(offerings)?.storeProduct.priceString;
  } catch (e) {
    debugPrint('RevenueCat price fetch failed: $e');
    return null;
  }
}

/// Test-only reset — clears the cached configuration so a second test
/// run sees `isConfigured == false` again.
@visibleForTesting
void resetRevenueCatStateForTest() {
  _configured = false;
  _configuredUserId = null;
}
