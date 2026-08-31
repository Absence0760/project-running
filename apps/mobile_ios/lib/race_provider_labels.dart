import 'package:flutter/material.dart';

import 'l10n/gen/app_localizations.dart';

/// What a race-results provider is called on screen, keyed by the same token
/// [raceImportProviders] uses.
///
/// Split from that catalogue so `race_service.dart` stays clear of the widget
/// layer: the wire facts (probe, scope, fail-closed exception) live beside the
/// calls that need them, the icon and the sentences live here, and
/// `settings_integrations_race_calendar_test.dart` renders a tile per catalogue
/// entry so a provider added without a row here fails a test rather than
/// shipping an unnamed tile.
class RaceProviderLabels {
  final IconData icon;
  final String name;
  final String connect;
  final String unavailable;
  final String open;

  const RaceProviderLabels({
    required this.icon,
    required this.name,
    required this.connect,
    required this.unavailable,
    required this.open,
  });
}

Map<String, RaceProviderLabels> raceProviderLabels(AppLocalizations l10n) => {
      'runsignup': RaceProviderLabels(
        icon: Icons.flag_outlined,
        name: l10n.integrationsRunsignup,
        connect: l10n.integrationsRunsignupConnect,
        unavailable: l10n.integrationsRunsignupUnavailable,
        open: l10n.integrationsRunsignupOpen,
      ),
      'ultrasignup': RaceProviderLabels(
        icon: Icons.terrain,
        name: l10n.integrationsUltrasignup,
        connect: l10n.integrationsUltrasignupConnect,
        unavailable: l10n.integrationsUltrasignupUnavailable,
        open: l10n.integrationsUltrasignupOpen,
      ),
      'chronotrack': RaceProviderLabels(
        icon: Icons.timer,
        name: l10n.integrationsChronotrack,
        connect: l10n.integrationsChronotrackConnect,
        unavailable: l10n.integrationsChronotrackUnavailable,
        open: l10n.integrationsChronotrackOpen,
      ),
    };
