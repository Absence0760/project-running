import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/gen/app_localizations.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../recap.dart';
import '../widgets/top_banner.dart';

/// Year-in-running recap. Mobile mirror of web `/recap/[year]`.
/// Reads runs from the local store + the LocalRunStore's already-
/// fetched cache (no extra Supabase round-trip) and builds the
/// hero numbers via `buildYearInRunningRecap`. Includes a share
/// CTA that hands a one-line summary to the OS share sheet, plus a
/// "Publish & share link" action (when `api` is wired) that freezes a
/// public snapshot via the web `public_recaps` table and shares the
/// web /recap/share/[id] link — the device OS-share-sheet is the
/// mobile-additive part; the page it links to is web-canonical.
class RecapScreen extends StatefulWidget {
  final LocalRunStore runStore;
  final Preferences preferences;
  final int? year;

  /// Optional — when wired, enables the "Publish & share link" action.
  final ApiClient? api;

  const RecapScreen({
    super.key,
    required this.runStore,
    required this.preferences,
    this.year,
    this.api,
  });

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  late int _year;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _year = widget.year ?? DateTime.now().year;
  }

  void _shiftYear(int delta) {
    setState(() => _year = _year + delta);
  }

  String get _webBase {
    final raw = (dotenv.maybeGet('WEB_BASE_URL') ?? 'https://threkir.com').trim();
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  Future<void> _publishAndShare(YearInRunningRecap recap) async {
    final api = widget.api;
    if (api == null || _publishing) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _publishing = true);
    try {
      final id = await api.publishRecap(
        periodKind: 'year',
        periodKey: '${recap.year}',
        snapshot: recapSnapshotJson(recap),
      );
      if (!mounted) return;
      if (id == null) {
        showTopBanner(context, l10n.recapPublishFailed);
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          text: '$_webBase/recap/share/$id',
          subject: l10n.recapShareSubject(recap.year),
        ),
      );
    } catch (e) {
      debugPrint('publishAndShare failed: $e');
      if (mounted) showTopBanner(context, l10n.recapPublishFailed);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _share(YearInRunningRecap recap) async {
    final l10n = AppLocalizations.of(context);
    final total = UnitFormat.distance(recap.totalDistanceM, widget.preferences.unit);
    final lines = <String>[
      l10n.recapShareHeadline(recap.year),
      l10n.recapShareTotals(total, recap.runCount),
      if (recap.longestRunM > 0)
        l10n.recapShareLongestRun(
            UnitFormat.distance(recap.longestRunM, widget.preferences.unit)),
      if (recap.bestStreakDays > 0)
        l10n.recapShareBestStreak(recap.bestStreakDays),
    ];
    await SharePlus.instance.share(
      ShareParams(
          text: lines.join('\n'), subject: l10n.recapShareSubject(recap.year)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    // Reads the full-history index (distance / duration / elevation_m /
    // activity_type) — no track, so the lightweight summaries are exact and
    // stay correct once `runs` becomes a resident window.
    final recap = buildYearInRunningRecap(widget.runStore.summaryRuns, _year);
    final earliestPossible = _year < 2000 || _year > DateTime.now().year + 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.recapTitle),
        actions: [
          if (widget.api != null)
            IconButton(
              icon: _publishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              tooltip: l10n.recapPublishAndShare,
              onPressed: recap.runCount == 0 || _publishing
                  ? null
                  : () => _publishAndShare(recap),
            ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: l10n.recapShareTooltip,
            onPressed: recap.runCount == 0 ? null : () => _share(recap),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Year switcher
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: l10n.recapPrevYear,
                  onPressed: () => _shiftYear(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$_year', style: theme.textTheme.headlineMedium),
                IconButton(
                  tooltip: l10n.recapNextYear,
                  onPressed: _year >= DateTime.now().year
                      ? null
                      : () => _shiftYear(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (earliestPossible) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    l10n.recapNoRunsForYear(_year),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ] else if (recap.runCount == 0) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    l10n.recapNoRunsYet(_year),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ] else ...[
              // Hero distance
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        UnitFormat.distance(recap.totalDistanceM, unit),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.recapAcrossRuns(recap.runCount,
                            recap.runCount == 1 ? 'run' : 'runs'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: l10n.recapLongestRunLabel,
                      value: UnitFormat.distance(recap.longestRunM, unit),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: l10n.recapBestStreakLabel,
                      value: l10n.recapStreakDays(recap.bestStreakDays,
                          recap.bestStreakDays == 1 ? 'day' : 'days'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: l10n.recapTopWeekLabel,
                      value: recap.topWeek == null
                          ? '—'
                          : UnitFormat.distance(
                              recap.topWeek!.distanceM, unit),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: l10n.recapUniqueRoutesLabel,
                      value: '${recap.uniqueRouteCount}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: l10n.recapEarliestStartLabel,
                      value: recap.earliestStartLocal ?? '—',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: l10n.recapLatestStartLabel,
                      value: recap.latestStartLocal ?? '—',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
