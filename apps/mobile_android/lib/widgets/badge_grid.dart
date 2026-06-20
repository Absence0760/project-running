import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../badges.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';

/// Tier ring colours, matching the web `BadgeGrid.svelte` `.tier-*` palette.
Color badgeTierColor(String tier) {
  switch (tier) {
    case 'bronze':
      return const Color(0xFFB08D57);
    case 'silver':
      return const Color(0xFF9AA3AD);
    case 'gold':
      return const Color(0xFFD4AF37);
    case 'platinum':
      return const Color(0xFF7FD3E0);
    default:
      return const Color(0xFF9AA3AD);
  }
}

String badgeTierLabel(AppLocalizations l10n, String tier) {
  switch (tier) {
    case 'bronze':
      return l10n.badgesTierBronze;
    case 'silver':
      return l10n.badgesTierSilver;
    case 'gold':
      return l10n.badgesTierGold;
    case 'platinum':
      return l10n.badgesTierPlatinum;
    default:
      return tier;
  }
}

/// Map a catalogue Material-Symbols ligature name to a Flutter [IconData].
IconData badgeIconData(String name) {
  switch (name) {
    case 'directions_run':
      return Icons.directions_run;
    case 'military_tech':
      return Icons.military_tech;
    case 'workspace_premium':
      return Icons.workspace_premium;
    case 'route':
      return Icons.route;
    case 'public':
      return Icons.public;
    case 'local_fire_department':
      return Icons.local_fire_department;
    case 'whatshot':
      return Icons.whatshot;
    case 'timer':
      return Icons.timer;
    case 'trophy':
    case 'emoji_events':
      return Icons.emoji_events;
    case 'flag':
      return Icons.flag;
    default:
      return Icons.military_tech;
  }
}

/// Resolve a catalogue label/desc ARB key to its localized string. The keys
/// are the camelCase ids carried by [BadgeTier.labelKey] / [BadgeTier.descKey]
/// — gen-l10n exposes getters, not a map, so the resolution is a switch.
String badgeText(AppLocalizations l10n, String key) {
  switch (key) {
    case 'badgesDistanceSingle5kLabel':
      return l10n.badgesDistanceSingle5kLabel;
    case 'badgesDistanceSingle5kDesc':
      return l10n.badgesDistanceSingle5kDesc;
    case 'badgesDistanceSingleHalfLabel':
      return l10n.badgesDistanceSingleHalfLabel;
    case 'badgesDistanceSingleHalfDesc':
      return l10n.badgesDistanceSingleHalfDesc;
    case 'badgesDistanceSingleMarathonLabel':
      return l10n.badgesDistanceSingleMarathonLabel;
    case 'badgesDistanceSingleMarathonDesc':
      return l10n.badgesDistanceSingleMarathonDesc;
    case 'badgesDistanceSingleUltraLabel':
      return l10n.badgesDistanceSingleUltraLabel;
    case 'badgesDistanceSingleUltraDesc':
      return l10n.badgesDistanceSingleUltraDesc;
    case 'badgesDistanceLifetime100Label':
      return l10n.badgesDistanceLifetime100Label;
    case 'badgesDistanceLifetime100Desc':
      return l10n.badgesDistanceLifetime100Desc;
    case 'badgesDistanceLifetime500Label':
      return l10n.badgesDistanceLifetime500Label;
    case 'badgesDistanceLifetime500Desc':
      return l10n.badgesDistanceLifetime500Desc;
    case 'badgesDistanceLifetime1000Label':
      return l10n.badgesDistanceLifetime1000Label;
    case 'badgesDistanceLifetime1000Desc':
      return l10n.badgesDistanceLifetime1000Desc;
    case 'badgesDistanceLifetime5000Label':
      return l10n.badgesDistanceLifetime5000Label;
    case 'badgesDistanceLifetime5000Desc':
      return l10n.badgesDistanceLifetime5000Desc;
    case 'badgesStreak7Label':
      return l10n.badgesStreak7Label;
    case 'badgesStreak7Desc':
      return l10n.badgesStreak7Desc;
    case 'badgesStreak30Label':
      return l10n.badgesStreak30Label;
    case 'badgesStreak30Desc':
      return l10n.badgesStreak30Desc;
    case 'badgesStreak100Label':
      return l10n.badgesStreak100Label;
    case 'badgesStreak100Desc':
      return l10n.badgesStreak100Desc;
    case 'badgesStreak365Label':
      return l10n.badgesStreak365Label;
    case 'badgesStreak365Desc':
      return l10n.badgesStreak365Desc;
    case 'badgesPr1Label':
      return l10n.badgesPr1Label;
    case 'badgesPr1Desc':
      return l10n.badgesPr1Desc;
    case 'badgesPr3Label':
      return l10n.badgesPr3Label;
    case 'badgesPr3Desc':
      return l10n.badgesPr3Desc;
    case 'badgesPr5Label':
      return l10n.badgesPr5Label;
    case 'badgesPr5Desc':
      return l10n.badgesPr5Desc;
    case 'badgesPlan1Label':
      return l10n.badgesPlan1Label;
    case 'badgesPlan1Desc':
      return l10n.badgesPlan1Desc;
    case 'badgesPlan3Label':
      return l10n.badgesPlan3Label;
    case 'badgesPlan3Desc':
      return l10n.badgesPlan3Desc;
    case 'badgesPlan10Label':
      return l10n.badgesPlan10Label;
    case 'badgesPlan10Desc':
      return l10n.badgesPlan10Desc;
    default:
      return key;
  }
}

/// Localized label for a stored award (its catalogue label, else the raw
/// badge_key). Shared by the feed badge strip.
String badgeLabelFor(AppLocalizations l10n, String badgeKey, String tier) {
  final t = tierFor(badgeKey, tier);
  return t != null ? badgeText(l10n, t.labelKey) : badgeKey;
}

/// A tier-coloured grid of earned badges. Mirrors the web `BadgeGrid.svelte`
/// read surface (the read-only mobile twin omits the owner visibility /
/// share controls — those live on web).
class BadgeGrid extends StatelessWidget {
  final List<AchievementRow> badges;
  final bool isOwner;

  const BadgeGrid({super.key, required this.badges, this.isOwner = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (badges.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            isOwner ? l10n.badgesEmpty : l10n.badgesEmptyOther,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisExtent: 210,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: badges.length,
      itemBuilder: (context, i) => _BadgeTile(badge: badges[i]),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final AchievementRow badge;

  const _BadgeTile({required this.badge});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tierColor = badgeTierColor(badge.tier);
    final tier = tierFor(badge.badgeKey, badge.tier);
    final label = tier != null ? badgeText(l10n, tier.labelKey) : badge.badgeKey;
    final desc = tier != null ? badgeText(l10n, tier.descKey) : null;
    final icon = badgeIconData(tier?.icon ?? 'military_tech');
    final earned = formatDateMed(badge.earnedAt, activeLocaleTag);
    return Opacity(
      opacity: badge.isPublic ? 1 : 0.72,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          children: [
            Container(height: 3, color: tierColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 40, color: tierColor),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (desc != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      badgeTierLabel(l10n, badge.tier).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tierColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      l10n.badgesEarnedOn(earned),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
