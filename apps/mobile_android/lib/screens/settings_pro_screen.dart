import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../revenuecat.dart';
import '../widgets/top_banner.dart';

class SettingsProScreen extends StatelessWidget {
  const SettingsProScreen({super.key});

  Future<void> _openExternal(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        await Share.share(url);
      }
    } catch (_) {
      if (!context.mounted) return;
      try {
        await Share.share(url);
      } catch (e) {
        if (!context.mounted) return;
        showTopBanner(context, AppLocalizations.of(context).proCouldNotOpen(e));
      }
    }
  }

  Future<void> _startProCheckout(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (!isRevenueCatConfigured() || userId == null) {
      await _openExternal(context, 'https://threkir.com/settings/upgrade');
      return;
    }
    final r = await startProCheckout(userId);
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    switch (r) {
      case PurchaseResult.purchased:
        showTopBanner(context, l10n.proWelcome);
        break;
      case PurchaseResult.cancelled:
        break;
      case PurchaseResult.failed:
        showTopBanner(context, l10n.proPurchaseFailed);
        break;
      case PurchaseResult.notConfigured:
        await _openExternal(context, 'https://threkir.com/settings/upgrade');
        break;
    }
  }

  Future<void> _restorePurchases(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (!isRevenueCatConfigured() || userId == null) {
      if (!context.mounted) return;
      showTopBanner(context, AppLocalizations.of(context).proRestoreNeedsSignIn);
      return;
    }
    final r = await restorePurchases(userId);
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    switch (r) {
      case PurchaseResult.purchased:
        showTopBanner(context, l10n.proRestored);
        break;
      case PurchaseResult.cancelled:
        showTopBanner(context, l10n.proRestoreNone);
        break;
      case PurchaseResult.failed:
        showTopBanner(context, l10n.proRestoreFailed);
        break;
      case PurchaseResult.notConfigured:
        showTopBanner(context, l10n.proRestoreUnavailable);
        break;
    }
  }

  Future<void> _openManageSubscription(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    String? url;
    if (isRevenueCatConfigured() && userId != null) {
      url = await managementUrl(userId);
    }
    final target = url ?? 'https://threkir.com/settings/upgrade';
    await _openExternal(context, target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rcConfigured = isRevenueCatConfigured();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.proTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(l10n.proSubscribeTitle('\$9.99')),
              subtitle: Text(
                rcConfigured
                    ? l10n.proSubscribeSubtitleConfigured
                    : l10n.proSubscribeSubtitleWeb,
              ),
              trailing: Icon(
                rcConfigured ? Icons.chevron_right : Icons.open_in_new,
                size: 18,
              ),
              onTap: () => _startProCheckout(context),
            ),
            // Honesty note mirroring web /settings/upgrade (audit-findings
            // 2026-05-30 Medium [regional]). The $9.99 figure is the USD
            // list price; until a RevenueCat project is provisioned the
            // store-localised price isn't available, so we disclose the
            // billing currency + regional availability rather than imply a
            // local-currency amount. See followups.md § Mobile.
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: Text(
                l10n.proRegionalNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: Text(l10n.proRestorePurchases),
              subtitle: Text(l10n.proRestorePurchasesSubtitle),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _restorePurchases(context),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(l10n.proManageSubscription),
              subtitle: Text(l10n.proManageSubscriptionSubtitle),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openManageSubscription(context),
            ),
            ListTile(
              leading: const Icon(Icons.volunteer_activism_outlined),
              title: Text(l10n.proSupport),
              subtitle: Text(l10n.proSupportSubtitle),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () =>
                  _openExternal(context, 'https://threkir.com/settings/upgrade'),
            ),
          ],
        ),
      ),
    );
  }
}
