import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../race_match.dart';
import '../race_service.dart';
import '../screens/races_screen.dart' show showRaceImportSheet;
import 'top_banner.dart';

/// Run-detail race section (race_calendar.md). Owner-only. When the run already
/// carries an official result it renders it; otherwise it runs the inform-tier
/// auto-match check — a same-day, same-distance-band listing surfaces a
/// non-blocking "Was this the {race}?" prompt that never writes without a tap.
///
/// Layered-resilience: every fetch is best-effort + swallowed (an L4 auxiliary
/// effect) so a race lookup can never break the rest of run detail.
class RunRaceSection extends StatefulWidget {
  final RaceService service;
  final String runId;
  final String startedAt;
  final double? distanceM;

  const RunRaceSection({
    super.key,
    required this.service,
    required this.runId,
    required this.startedAt,
    required this.distanceM,
  });

  @override
  State<RunRaceSection> createState() => _RunRaceSectionState();
}

class _RunRaceSectionState extends State<RunRaceSection> {
  bool _loading = true;
  RaceResultForRun? _result;
  RaceListingView? _candidate;
  bool _runSignUpAvailable = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.service.fetchRaceResultForRun(widget.runId);
      RaceListingView? candidate;
      if (result == null || !result.hasResult) {
        try {
          final listings =
              await widget.service.findRaceMatchCandidates(widget.runId);
          candidate = _bestCandidate(listings);
          if (candidate != null) {
            _runSignUpAvailable = await widget.service.isRunSignUpConfigured();
          }
        } catch (_) {
          candidate = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        _candidate = candidate;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  RaceListingView? _bestCandidate(List<RaceListingView> listings) {
    final run = RunMatchInput(
      runDate: widget.startedAt,
      runStartLatLng: null,
      runDistanceM: widget.distanceM,
    );
    RaceListingView? best;
    double bestScore = 0;
    for (final l in listings) {
      final listing = ListingMatchInput(
        raceDate: l.raceDate,
        distanceM: l.distanceM,
        distanceMAway: l.distanceMAway,
      );
      final score = raceMatchScore(run, listing);
      if (isRaceMatchCandidate(run, listing) && score > bestScore) {
        best = l;
        bestScore = score;
      }
    }
    return best;
  }

  Future<void> _confirmMatch() async {
    final candidate = _candidate;
    if (candidate == null) return;
    final done = await showRaceImportSheet(
      context,
      service: widget.service,
      race: candidate,
      runSignUpAvailable: _runSignUpAvailable,
      matchRunId: widget.runId,
    );
    if (done == true && mounted) {
      showTopBanner(context, AppLocalizations.of(context).racesImported);
      setState(() => _candidate = null);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final result = _result;
    if (result != null && result.hasResult) {
      final rows = <Widget>[
        if (result.raceName != null) _row(l.racesTitle, result.raceName!),
        if (result.chipTime != null) _row(l.racesChipTime, result.chipTime!),
        if (result.gunTime != null) _row(l.racesGunTime, result.gunTime!),
        if (result.overallPlace != null)
          _row(l.racesOverallPlace, '${result.overallPlace}'),
        if (result.ageGroupPlace != null)
          _row(
            l.racesAgeGroupPlace,
            result.ageGroup != null
                ? '${result.ageGroupPlace} (${result.ageGroup})'
                : '${result.ageGroupPlace}',
          ),
        if (result.bib != null) _row(l.racesBib, result.bib!),
      ];
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.racesOfficialResult, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      );
    }

    final candidate = _candidate;
    if (candidate != null && !_dismissed) {
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.racesMatchPrompt(candidate.name)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _dismissed = true),
                    child: Text(l.racesMatchDismiss),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _confirmMatch,
                    child: Text(l.racesMatchConfirm),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
