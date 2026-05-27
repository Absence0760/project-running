import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
        showTopBanner(context, 'Could not open: $e');
      }
    }
  }

  Future<void> _startProCheckout(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (!isRevenueCatConfigured() || userId == null) {
      await _openExternal(context, 'https://run.app/settings/upgrade');
      return;
    }
    final r = await startProCheckout(userId);
    if (!context.mounted) return;
    switch (r) {
      case PurchaseResult.purchased:
        showTopBanner(context, 'Welcome to Pro! Pulling your benefits…');
        break;
      case PurchaseResult.cancelled:
        break;
      case PurchaseResult.failed:
        showTopBanner(context, 'Purchase failed. Try again later.');
        break;
      case PurchaseResult.notConfigured:
        await _openExternal(context, 'https://run.app/settings/upgrade');
        break;
    }
  }

  Future<void> _restorePurchases(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (!isRevenueCatConfigured() || userId == null) {
      if (!context.mounted) return;
      showTopBanner(
        context,
        'Restore needs you to be signed in with RevenueCat configured. '
        'Manage your subscription on the web upgrade page instead.',
      );
      return;
    }
    final r = await restorePurchases(userId);
    if (!context.mounted) return;
    switch (r) {
      case PurchaseResult.purchased:
        showTopBanner(context, 'Restored your Pro subscription.');
        break;
      case PurchaseResult.cancelled:
        showTopBanner(context, 'No active purchases found on this store account.');
        break;
      case PurchaseResult.failed:
        showTopBanner(context, 'Restore failed. Try again later.');
        break;
      case PurchaseResult.notConfigured:
        showTopBanner(context, 'Restore unavailable in this build.');
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
    final target = url ?? 'https://run.app/settings/upgrade';
    await _openExternal(context, target);
  }

  @override
  Widget build(BuildContext context) {
    final rcConfigured = isRevenueCatConfigured();
    return Scaffold(
      appBar: AppBar(title: const Text('Pro & support')),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('Subscribe to Pro — \$9.99/month'),
              subtitle: Text(
                rcConfigured
                    ? 'Unlimited AI coach + priority processing. Auto-renews monthly until cancelled in Settings → Subscriptions.'
                    : 'Opens the subscription portal in your browser. Auto-renews monthly until cancelled.',
              ),
              trailing: Icon(
                rcConfigured ? Icons.chevron_right : Icons.open_in_new,
                size: 18,
              ),
              onTap: () => _startProCheckout(context),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore purchases'),
              subtitle: const Text(
                'Re-link purchases from a previous install or another device',
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _restorePurchases(context),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Manage subscription'),
              subtitle: const Text(
                'Cancel, change plan, or update payment method',
              ),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openManageSubscription(context),
            ),
            ListTile(
              leading: const Icon(Icons.volunteer_activism_outlined),
              title: const Text('Support the app'),
              subtitle: const Text('One-off donation in your browser'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () =>
                  _openExternal(context, 'https://run.app/settings/upgrade'),
            ),
          ],
        ),
      ),
    );
  }
}
