import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

import '../fundraiser_progress.dart';
import '../l10n/gen/app_localizations.dart';
import '../social_service.dart';

/// Read-only charity-fundraiser card for run-detail / event-detail
/// (fundraising.md). Mobile is read + web-handoff only: the thermometer + feed
/// render here, but donating routes to the web `/fundraisers/[id]` page in an
/// external browser (mirroring how paid-event registration is web-checkout-only
/// on mobile — `club_events.md` P3). There is no in-app donation flow.
class FundraiserSection extends StatefulWidget {
  final SocialService social;

  /// Exactly one of [runId] / [eventId] is set (mirrors the fundraisers CHECK).
  final String? runId;
  final String? eventId;

  const FundraiserSection({
    super.key,
    required this.social,
    this.runId,
    this.eventId,
  });

  @override
  State<FundraiserSection> createState() => _FundraiserSectionState();
}

class _FundraiserSectionState extends State<FundraiserSection> {
  bool _loading = true;
  FundraiserView? _fundraiser;
  FundraiserTotalsView? _totals;
  List<DonationFeedEntry> _feed = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.social.isReady) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final f = widget.runId != null
          ? await widget.social.fetchFundraiserForRun(widget.runId!)
          : widget.eventId != null
          ? await widget.social.fetchFundraiserForEvent(widget.eventId!)
          : null;
      FundraiserTotalsView? totals;
      List<DonationFeedEntry> feed = const [];
      if (f != null) {
        totals = await widget.social.fetchFundraiserTotals(f.id);
        feed = await widget.social.fetchFundraiserFeed(f.id);
      }
      if (!mounted) return;
      setState(() {
        _fundraiser = f;
        _totals = totals;
        _feed = feed;
        _loading = false;
      });
    } catch (_) {
      // L4: a fundraiser read failure must not break the detail screen.
      if (mounted) setState(() => _loading = false);
    }
  }

  String _webBase() => (dotenv.env['WEB_BASE_URL'] ?? 'https://threkir.com')
      .replaceAll(RegExp(r'/$'), '');

  Future<void> _donateOnWeb() async {
    final f = _fundraiser;
    if (f == null) return;
    final uri = Uri.parse('${_webBase()}/fundraisers/${f.id}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _money(int cents, String currency) {
    final symbol = currency.toLowerCase() == 'usd' ? '\$' : '';
    return '$symbol${(cents / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final f = _fundraiser;
    if (_loading || f == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final raised = _totals?.raisedCents ?? 0;
    final goal = _totals?.goalCents ?? f.goalCents;
    final donors = _totals?.donorCount ?? 0;
    final progress = fundraiserProgress(raised, goal);
    final raisedStr = _money(raised, f.currency);
    final goalStr = _money(goal, f.currency);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              f.charityName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.fillPct / 100,
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: progress.state == ThermometerState.exceeded
                    ? Colors.green
                    : theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    l10n.fundraiserRaisedOfGoal(raisedStr, goalStr),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text('${progress.rawPct.round()}%'),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.fundraiserDonorCount(donors),
                  style: theme.textTheme.bodySmall,
                ),
                if (progress.state == ThermometerState.exceeded)
                  Text(
                    l10n.fundraiserOverGoal,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (f.isClosed) ...[
              const SizedBox(height: 12),
              Text(
                l10n.fundraiserClosed,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _donateOnWeb,
                child: Text(l10n.fundraiserDonateOnWeb),
              ),
            ],
            const SizedBox(height: 16),
            Text(l10n.fundraiserFeedTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_feed.isEmpty)
              Text(
                l10n.fundraiserFeedEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ..._feed.map((e) => _DonationRow(entry: e, money: _money)),
          ],
        ),
      ),
    );
  }
}

class _DonationRow extends StatelessWidget {
  final DonationFeedEntry entry;
  final String Function(int, String) money;

  const _DonationRow({required this.entry, required this.money});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = entry.isAnonymous || entry.displayName == null
        ? l10n.fundraiserAnonymous
        : entry.displayName!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                money(entry.amountCents, entry.currency),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (entry.message != null && entry.message!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                entry.message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
