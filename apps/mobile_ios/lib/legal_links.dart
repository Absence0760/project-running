import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n/gen/app_localizations.dart';
import 'widgets/top_banner.dart';

/// The legal documents the web app links from its settings nav footer
/// (`apps/web/src/routes/settings/+layout.svelte`). Mobile has no offline
/// copy of any of them — each is the web page, opened in the browser.
enum LegalDoc { privacy, terms, cookieNotice, healthDataNotice }

String legalDocPath(LegalDoc doc) => switch (doc) {
      LegalDoc.privacy => 'privacy',
      LegalDoc.terms => 'terms',
      LegalDoc.cookieNotice => 'cookie-notice',
      LegalDoc.healthDataNotice => 'health-data-notice',
    };

String legalDocLabel(AppLocalizations l10n, LegalDoc doc) => switch (doc) {
      LegalDoc.privacy => l10n.legalPrivacy,
      LegalDoc.terms => l10n.legalTerms,
      LegalDoc.cookieNotice => l10n.legalCookieNotice,
      LegalDoc.healthDataNotice => l10n.legalHealthDataNotice,
    };

/// Absolute URL of a legal document. The host comes from `WEB_BASE_URL`
/// (set at build time, e.g. the preview host) and falls back to production,
/// the same resolution every other web-link surface uses. Pure so it can be
/// unit-tested without a launcher.
String legalDocUrl(LegalDoc doc, {String? webBase}) {
  var base = (webBase ??
          (dotenv.isInitialized ? dotenv.maybeGet('WEB_BASE_URL') : null) ??
          '')
      .trim();
  if (base.isEmpty) base = 'https://threkir.com';
  if (base.endsWith('/')) base = base.substring(0, base.length - 1);
  return '$base/${legalDocPath(doc)}';
}

/// Opens [doc] in the external browser, surfacing a banner rather than
/// failing silently when no browser can take it.
Future<void> openLegalDoc(BuildContext context, LegalDoc doc) async {
  final url = legalDocUrl(doc);
  try {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      showTopBanner(context, AppLocalizations.of(context).legalCouldNotOpen(url));
    }
  } catch (e) {
    debugPrint('legal_links: opening $url failed: $e');
    if (context.mounted) {
      showTopBanner(context, AppLocalizations.of(context).legalCouldNotOpen(url));
    }
  }
}
