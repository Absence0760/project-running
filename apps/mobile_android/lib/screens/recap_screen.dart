import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../recap.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';

/// Which calendar window the recap covers.
enum RecapPeriod { year, month }

/// Year-in-running / month-in-running recap. Mobile mirror of web
/// `/recap/[year]` and `/recap/[year]/[month]` — the two web routes collapse
/// into one screen here with a period toggle, matching how
/// `period_summary_screen` already lets one surface walk week / month /
/// all-time.
///
/// Reads runs from the local store (no extra Supabase round-trip) and builds
/// the hero numbers via `buildYearInRunningRecap` / `buildMonthInRunningRecap`.
/// Includes a share CTA that hands a one-line summary to the OS share sheet,
/// plus a "Publish & share link" action (when `api` is wired) that freezes a
/// public snapshot via the web `public_recaps` table and shares the web
/// /recap/share/[id] link — the device OS-share-sheet is the mobile-additive
/// part; the page it links to is web-canonical.
class RecapScreen extends StatefulWidget {
  final LocalRunStore runStore;
  final Preferences preferences;
  final int? year;

  /// 1-based. When set the screen opens on the monthly recap.
  final int? month;

  /// Optional — when wired, enables the "Publish & share link" action.
  final ApiClient? api;

  const RecapScreen({
    super.key,
    required this.runStore,
    required this.preferences,
    this.year,
    this.month,
    this.api,
  });

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  late RecapPeriod _period;
  late int _year;
  late int _month;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = widget.year ?? now.year;
    _month = widget.month ?? now.month;
    _period = widget.month == null ? RecapPeriod.year : RecapPeriod.month;
    widget.runStore.addListener(_onChanged);
    widget.preferences.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.runStore.removeListener(_onChanged);
    widget.preferences.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  YearInRunningRecap _buildRecap() {
    // Reads the full-history index (distance / duration / elevation_m /
    // activity_type) — no track, so the lightweight summaries are exact and
    // stay correct once `runs` becomes a resident window.
    final runs = widget.runStore.summaryRuns;
    return _period == RecapPeriod.year
        ? buildYearInRunningRecap(runs, _year)
        : buildMonthInRunningRecap(runs, _year, _month);
  }

  bool get _outOfRange => _year < 2000 || _year > DateTime.now().year + 1;

  bool get _atLatestPeriod {
    final now = DateTime.now();
    if (_period == RecapPeriod.year) return _year >= now.year;
    return _year > now.year || (_year == now.year && _month >= now.month);
  }

  String _periodLabel(String localeTag) => _period == RecapPeriod.year
      ? '$_year'
      : '${formatMonthName(DateTime(_year, _month), localeTag)} $_year';

  /// `public_recaps.period_kind` / `period_key` — the same wire pair the web
  /// routes upsert on, so a recap published from either client refreshes the
  /// one share link instead of minting a second.
  String get _periodKind => _period == RecapPeriod.year ? 'year' : 'month';

  String get _periodKey => _period == RecapPeriod.year
      ? '$_year'
      : '$_year-${_month.toString().padLeft(2, '0')}';

  void _shiftPeriod(int delta) {
    setState(() {
      if (_period == RecapPeriod.year) {
        _year += delta;
        return;
      }
      // DateTime normalises a month of 0 or 13 into the adjacent year.
      final shifted = DateTime(_year, _month + delta);
      _year = shifted.year;
      _month = shifted.month;
    });
  }

  void _selectPeriod(RecapPeriod period) {
    if (period != _period) setState(() => _period = period);
  }

  String get _webBase {
    final raw = (dotenv.maybeGet('WEB_BASE_URL') ?? 'https://threkir.com').trim();
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  Future<void> _publishAndShare(YearInRunningRecap recap, String label) async {
    final api = widget.api;
    if (api == null || _publishing) return;
    if (!await ensureSignedIn(context, viewerId: api.userId, api: api)) {
      return;
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _publishing = true);
    try {
      final id = await api.publishRecap(
        periodKind: _periodKind,
        periodKey: _periodKey,
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
          subject: _shareSubject(l10n, label),
        ),
      );
    } catch (e) {
      debugPrint('publishAndShare failed: $e');
      if (mounted) showTopBanner(context, l10n.recapPublishFailed);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  String _shareSubject(AppLocalizations l10n, String label) =>
      _period == RecapPeriod.year
          ? l10n.recapShareSubject(_year)
          : l10n.recapMonthShareSubject(label);

  Future<void> _share(YearInRunningRecap recap, String label) async {
    final l10n = AppLocalizations.of(context);
    final total = UnitFormat.distance(recap.totalDistanceM, widget.preferences.unit);
    final lines = <String>[
      _period == RecapPeriod.year
          ? l10n.recapShareHeadline(_year)
          : l10n.recapMonthShareHeadline(label),
      l10n.recapShareTotals(total, recap.runCount),
      if (recap.longestRunM > 0)
        l10n.recapShareLongestRun(
            UnitFormat.distance(recap.longestRunM, widget.preferences.unit)),
      if (recap.bestStreakDays > 0)
        l10n.recapShareBestStreak(recap.bestStreakDays),
    ];
    await SharePlus.instance.share(
      ShareParams(text: lines.join('\n'), subject: _shareSubject(l10n, label)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    final localeTag = localeToTag(Localizations.localeOf(context));
    final label = _periodLabel(localeTag);
    final recap = _buildRecap();

    return Scaffold(
      appBar: AppBar(
        title: Text(_period == RecapPeriod.year
            ? l10n.recapTitle
            : l10n.recapMonthTitle),
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
                  : () => _publishAndShare(recap, label),
            ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: l10n.recapShareTooltip,
            onPressed:
                recap.runCount == 0 ? null : () => _share(recap, label),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: SegmentedButton<RecapPeriod>(
                segments: [
                  ButtonSegment(
                      value: RecapPeriod.year,
                      label: Text(l10n.recapPeriodYear)),
                  ButtonSegment(
                      value: RecapPeriod.month,
                      label: Text(l10n.recapPeriodMonth)),
                ],
                selected: {_period},
                onSelectionChanged: (s) => _selectPeriod(s.first),
                showSelectedIcon: false,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: _period == RecapPeriod.year
                      ? l10n.recapPrevYear
                      : l10n.recapPrevMonth,
                  onPressed: () => _shiftPeriod(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(label, style: theme.textTheme.headlineMedium),
                IconButton(
                  tooltip: _period == RecapPeriod.year
                      ? l10n.recapNextYear
                      : l10n.recapNextMonth,
                  onPressed: _atLatestPeriod ? null : () => _shiftPeriod(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_outOfRange) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.recapNoRunsForPeriod(label),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ] else if (recap.runCount == 0) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.recapNoRunsYetInPeriod(label),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ] else ...[
              // Hero distance
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
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
