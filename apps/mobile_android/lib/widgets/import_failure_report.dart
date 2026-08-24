import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../import_failures.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/date_format.dart';
import '../l10n/locale_support.dart';
import '../share_sheet.dart';
import 'top_banner.dart';

/// What did not import, named and classified — the mobile twin of web's
/// `ImportFailureReport.svelte`. A bare "40 failed" tells a runner nothing
/// about whether re-running the import would land the missing activities.
class ImportFailureReport extends StatelessWidget {
  final ImportFailureLog log;

  /// Used to name the shared CSV file (`strava-import-failures.csv`).
  final String provider;
  final VoidCallback onDismiss;

  const ImportFailureReport({
    super.key,
    required this.log,
    required this.provider,
    required this.onDismiss,
  });

  static String reasonLabel(AppLocalizations l10n, ImportFailureReason r) {
    switch (r) {
      case ImportFailureReason.network:
        return l10n.importFailuresReasonNetwork;
      case ImportFailureReason.auth:
        return l10n.importFailuresReasonAuth;
      case ImportFailureReason.rateLimited:
        return l10n.importFailuresReasonRateLimited;
      case ImportFailureReason.tooLarge:
        return l10n.importFailuresReasonTooLarge;
      case ImportFailureReason.unparseable:
        return l10n.importFailuresReasonUnparseable;
      case ImportFailureReason.rejected:
        return l10n.importFailuresReasonRejected;
      case ImportFailureReason.unknown:
        return l10n.importFailuresReasonUnknown;
    }
  }

  String _formatStart(AppLocalizations l10n, String tag, String? iso) {
    if (iso == null) return l10n.importFailuresNoDate;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return l10n.importFailuresNoDate;
    return formatDateMed(parsed, tag);
  }

  Future<void> _share(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$provider-import-failures.csv');
      await file.writeAsString(importFailureReportCsv(log));
      await shareFilesFrom(
        context,
        files: [XFile(file.path, mimeType: 'text/csv')],
        text: '$provider import failures',
      );
    } catch (e) {
      debugPrint('Import failure report share failed: $e');
      if (context.mounted) showTopBanner(context, l10n.importFailuresShareFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final groups = groupImportFailures(log);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.importFailuresHeading(log.total),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.importFailuresIntro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in groups)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${reasonLabel(l10n, g.reason)} ${g.count}'),
                  ),
              ],
            ),
            if (log.truncated > 0) ...[
              const SizedBox(height: 8),
              Text(
                l10n.importFailuresTruncated(log.truncated),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (log.items.isNotEmpty)
              ExpansionTile(
                // No enclosing rule lines: the card already bounds this.
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(l10n.importFailuresShowDetail,
                    style: theme.textTheme.bodyMedium),
                children: [
                  for (final f in log.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name, style: theme.textTheme.bodyMedium),
                          Text(
                            '${_formatStart(l10n, tag, f.startedAt)} · '
                            '${reasonLabel(l10n, f.reason)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (f.detail.isNotEmpty)
                            Text(
                              f.detail,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _share(context),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: Text(l10n.importFailuresShare),
                ),
                TextButton(
                  onPressed: onDismiss,
                  child: Text(l10n.importFailuresDismiss),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
