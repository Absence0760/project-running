import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../pro_sellable.dart';
import '../revenuecat.dart';
import '../share_sheet.dart';
import '../widgets/top_banner.dart';

class SettingsProScreen extends StatefulWidget {
  /// Injection seam for the live-perk lookup so widget tests can drive
  /// both storefront states without a network.
  final Future<ProPerks> Function()? loadPerks;

  const SettingsProScreen({super.key, this.loadPerks});

  @override
  State<SettingsProScreen> createState() => _SettingsProScreenState();
}

class _SettingsProScreenState extends State<SettingsProScreen> {
  // USD list price — the fallback shown only until/unless RevenueCat returns
  // the territory-localised price. Apple Guideline 3.1.1 / Play subscription
  // policy require the displayed amount to come from the store (it varies by
  // region), so this constant is a last resort for unconfigured builds and
  // the brief window before the offering loads.
  static const String _usdListPrice = r'$9.99';

  // The store-localised monthly price once RevenueCat resolves the offering;
  // null until then (and on unconfigured builds).
  String? _storePrice;

  // In-flight guard for the IAP actions (checkout / restore / manage). A
  // double-tap on a payment tile must not open two checkout sheets or fire
  // two restore round-trips. Web guards its CTA with `disabled={purchasing}`.
  bool _proBusy = false;

  // Which Pro perks this deploy can actually deliver. Null until the
  // manifest resolves, and `sellable` reads false until then — the
  // storefront must never offer a purchase it can't justify, so the
  // teaser is what shows while we don't know (decisions §466).
  ProPerks? _perks;

  @override
  void initState() {
    super.initState();
    _loadStorePrice();
    _loadPerks();
  }

  Future<void> _loadPerks() async {
    final perks = await (widget.loadPerks ?? fetchProPerks)();
    if (!mounted) return;
    setState(() => _perks = perks);
  }

  Future<void> _loadStorePrice() async {
    // Check configuration first: on unconfigured builds (dev / CI / tests)
    // this returns before touching Supabase.instance, so the screen mounts
    // without a live Supabase — matching the lazy access in the tap handlers.
    if (!isRevenueCatConfigured()) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final price = await proMonthlyPriceString(userId);
    if (!mounted || price == null) return;
    setState(() => _storePrice = price);
  }

  Future<void> _openExternal(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        await shareTextFrom(context, text: url);
      }
    } catch (_) {
      if (!context.mounted) return;
      try {
        await shareTextFrom(context, text: url);
      } catch (e) {
        if (!context.mounted) return;
        showTopBanner(context, AppLocalizations.of(context).proCouldNotOpen(e));
      }
    }
  }

  Future<void> _startProCheckout(BuildContext context) async {
    if (_proBusy) return;
    // Second gate behind the hidden CTA: no caller may reach checkout
    // while the deploy has no live perk to sell.
    if (!(_perks?.sellable ?? false)) return;
    setState(() => _proBusy = true);
    try {
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
    } finally {
      if (mounted) setState(() => _proBusy = false);
    }
  }

  Future<void> _restorePurchases(BuildContext context) async {
    if (_proBusy) return;
    setState(() => _proBusy = true);
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (!isRevenueCatConfigured() || userId == null) {
        if (!context.mounted) return;
        showTopBanner(
            context, AppLocalizations.of(context).proRestoreNeedsSignIn);
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
    } finally {
      if (mounted) setState(() => _proBusy = false);
    }
  }

  Future<void> _openManageSubscription(BuildContext context) async {
    if (_proBusy) return;
    setState(() => _proBusy = true);
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      String? url;
      if (isRevenueCatConfigured() && userId != null) {
        url = await managementUrl(userId);
      }
      final target = url ?? 'https://threkir.com/settings/upgrade';
      await _openExternal(context, target);
    } finally {
      if (mounted) setState(() => _proBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rcConfigured = isRevenueCatConfigured();
    // Prefer the store-localised price; fall back to the USD list price until
    // (or unless) the offering resolves. When we have the real localised
    // price the USD-disclaimer note below is redundant + misleading, so it
    // only shows on the fallback.
    final priceLabel = _storePrice ?? _usdListPrice;
    final showRegionalNote = _storePrice == null;
    // Mirrors web's proSellable branch: a purchase CTA only where a perk
    // is live, else the coming-soon teaser with donations as the way to
    // help. Unknown counts as not sellable.
    final sellable = _perks?.sellable ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.proTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            if (sellable)
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text(l10n.proSubscribeTitle(priceLabel)),
                subtitle: Text(
                  rcConfigured
                      ? l10n.proSubscribeSubtitleConfigured
                      : l10n.proSubscribeSubtitleWeb,
                ),
                trailing: Icon(
                  rcConfigured ? Icons.chevron_right : Icons.open_in_new,
                  size: 18,
                ),
                enabled: !_proBusy,
                onTap: () => _startProCheckout(context),
              )
            else
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text(l10n.proComingSoonTitle),
                subtitle: Text(l10n.proComingSoon),
              ),
            // Honesty note mirroring web /settings/upgrade (audit-findings
            // 2026-05-30 Medium [regional]). Shown only when we're falling
            // back to the $9.99 USD list price (RevenueCat unconfigured or
            // offering not yet loaded); once the store returns a localised
            // price the note is dropped. See followups.md § Mobile.
            if (sellable && showRegionalNote)
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
              enabled: !_proBusy,
              onTap: () => _restorePurchases(context),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(l10n.proManageSubscription),
              subtitle: Text(l10n.proManageSubscriptionSubtitle),
              trailing: const Icon(Icons.open_in_new, size: 18),
              enabled: !_proBusy,
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
