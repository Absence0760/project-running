import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../hr_zones.dart';
import '../l10n/gen/app_localizations.dart';
import '../run_intensity.dart';
import '../settings_sync.dart';

/// Dashboard card surfacing how much of the runner's recent training
/// has been spent in each HR zone — easy / moderate / hard at a glance.
/// Mirrors web's intensity-breakdown card on `/dashboard`.
///
/// Self-hides when the user has no HR zones configured (zones == null)
/// OR has no HR-tracked runs in the window. Additive — never load-
/// blocks the page; never throws back at the caller.
class IntensityCard extends StatelessWidget {
  final List<Run> runs;
  /// Resolved HR zones; null when the user hasn't configured them. The
  /// dashboard resolves these once via [parseHrZones] on
  /// `settings_sync.service.effective<Map>(SettingsKeys.hrZones)`.
  final HrZones? hrZones;
  final DateTime now;
  /// Window in days. Default 30 — matches the web card's "weekly /
  /// monthly view → 30 d" cadence.
  final int windowDays;

  /// Optional settings service. When wired, the card falls back to
  /// age-estimated zones (max_hr_bpm → Tanaka age → 190 bpm) if no explicit
  /// [hrZones] were passed, and shows the same age-estimated / medication
  /// caveat run-detail shows (#268). Null → only explicitly-passed zones
  /// render, and no caveat (they're never age-estimated).
  final SettingsSyncService? settingsSync;

  const IntensityCard({
    super.key,
    required this.runs,
    required this.hrZones,
    required this.now,
    this.windowDays = 30,
    this.settingsSync,
  });

  @override
  Widget build(BuildContext context) {
    // Prefer explicitly-passed zones; else derive age-estimated fallback
    // cutoffs from the synced HR settings so a max-HR-only / age-only runner
    // still sees the breakdown (mirroring run-detail).
    final zones = hrZones ?? _deriveZonesFromSettings();
    // No zones at all → card is invisible. The Settings → HR Zones tile is
    // the canonical configuration surface; we don't want a dashboard nag in
    // the meantime.
    if (zones == null) return const SizedBox.shrink();

    final breakdown = computeIntensityBreakdown(
      runs,
      zones,
      windowDays: windowDays,
      now: now,
    );
    // Nothing to show.
    if (breakdown.hrTrackedRuns == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l10n.intensityTitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.06,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.intensityWindow(windowDays),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _SegmentedBar(breakdown: breakdown),
            const SizedBox(height: 12),
            _ZoneLegend(breakdown: breakdown),
            const SizedBox(height: 8),
            Text(
              l10n.intensityBasedOn(breakdown.hrTrackedRuns),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (_zonesAreAgeEstimated()) ...[
              const SizedBox(height: 6),
              Text(
                l10n.runDetailHrDisclaimer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Resolve age-estimated fallback zone cutoffs from the synced HR settings
  /// when no explicit [hrZones] were passed. Mirrors run-detail's precedence
  /// (max_hr_bpm override → Tanaka from date_of_birth → the 190-bpm default)
  /// so the dashboard card and the run-detail panel agree. Null when the
  /// settings service isn't wired.
  HrZones? _deriveZonesFromSettings() {
    final svc = settingsSync?.service;
    if (svc == null) return null;
    final explicit = parseHrZones(svc.effective<Map>(SettingsKeys.hrZones));
    if (explicit != null) return explicit;
    final maxHr = svc.effective<num>(SettingsKeys.maxHrBpm)?.round();
    return defaultZoneCutoffs(
      maxHrBpm: maxHr,
      ageYears: _ageFromDob(svc.effective<String>(SettingsKeys.dateOfBirth)),
    );
  }

  /// Whether the zones shown fall back to an age-estimated max HR — the user
  /// set neither an explicit hr_zones override nor a max_hr_bpm. Replicated
  /// (a few lines, per house style) from run_detail_screen's identical check
  /// so a runner on HR medication (beta-blockers) is told the zones may be
  /// off. False when the settings service isn't wired (then only
  /// explicitly-passed zones render, which are never age-estimated).
  bool _zonesAreAgeEstimated() {
    final svc = settingsSync?.service;
    if (svc == null) return false;
    final hasExplicit =
        parseHrZones(svc.effective<Map>(SettingsKeys.hrZones)) != null;
    final hasMaxHr = svc.effective<num>(SettingsKeys.maxHrBpm) != null;
    return !hasExplicit && !hasMaxHr;
  }

  /// Whole years from a `YYYY-MM-DD` date_of_birth bag value, or null when
  /// absent / unparseable / out of range.
  static int? _ageFromDob(String? dob) {
    if (dob == null) return null;
    final born = DateTime.tryParse(dob);
    if (born == null) return null;
    final now = DateTime.now();
    var age = now.year - born.year;
    if (now.month < born.month ||
        (now.month == born.month && now.day < born.day)) {
      age--;
    }
    return (age >= 0 && age < 120) ? age : null;
  }
}

class _SegmentedBar extends StatelessWidget {
  final IntensityBreakdown breakdown;
  const _SegmentedBar({required this.breakdown});

  // Zone palette — green easy, yellow / orange moderate, red hard.
  // Matches the web `--zone-*` CSS vars + the run-detail HR-zone band.
  static const _zoneColors = <Color>[
    Color(0xFF2E7D32), // z1 easy
    Color(0xFF66BB6A), // z2 endurance
    Color(0xFFF59E0B), // z3 tempo
    Color(0xFFFB8C00), // z4 threshold
    Color(0xFFD32F2F), // z5 vo2 / sprint
  ];

  @override
  Widget build(BuildContext context) {
    final total = breakdown.totalSeconds;
    if (total <= 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 12,
        child: Row(
          children: [
            for (var i = 0; i < 5; i++)
              if (breakdown.zoneSeconds[i] > 0)
                Expanded(
                  flex: breakdown.zoneSeconds[i],
                  child: Container(color: _zoneColors[i]),
                ),
          ],
        ),
      ),
    );
  }
}

class _ZoneLegend extends StatelessWidget {
  final IntensityBreakdown breakdown;
  const _ZoneLegend({required this.breakdown});

  static const _labels = <String>['Z1', 'Z2', 'Z3', 'Z4', 'Z5'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = breakdown.totalSeconds;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (var i = 0; i < 5; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _SegmentedBar._zoneColors[i],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _labels[i],
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _pctLabel(breakdown.zoneSeconds[i], total),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
      ],
    );
  }

  static String _pctLabel(int s, int total) {
    if (s == 0 || total <= 0) return '0%';
    final pct = (s / total) * 100;
    // Don't show "0%" for a non-zero zone — that misreads as "didn't
    // do any of that". The cliff: anything under 1 % renders as the
    // explicit <1% marker so the runner sees it counted.
    if (pct < 1) return '<1%';
    return '${pct.round()}%';
  }
}
