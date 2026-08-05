import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../basemap_credits.dart';
import '../l10n/gen/app_localizations.dart';
import 'top_banner.dart';

/// The credit strip every map surface owes its basemap.
///
/// `flutter_map` renders no attribution of its own — unlike web's MapLibre,
/// which reads it out of the style.json — so without this widget the app
/// showed MapTiler and OpenStreetMap tiles on seven surfaces with nothing
/// naming either. MapTiler Cloud's terms require "© MapTiler" on screen
/// whenever a map is displayed, and OSM data is ODbL, which requires
/// "© OpenStreetMap contributors". Both must be links.
///
/// Which credits appear follows the RESOLVED basemap, not a fixed string:
/// since `decisions.md § 489` the basemap varies with the user's map-style
/// preference, the app theme, and whether a `TILE_URL_TEMPLATE` override is
/// in play, and crediting MapTiler while the OSM fallback is on screen
/// would be as wrong as crediting nobody.
///
/// Mount it as the last child of a `FlutterMap` so it draws above the
/// layers. Ink and scrim key off the resolved basemap for the same reason
/// the track casing does — the OSM fallback is light whatever the app
/// theme is.
class MapAttribution extends StatelessWidget {
  /// Whether the basemap underneath is dark, from `currentBasemapIsDark`.
  final bool darkBasemap;

  /// Logical pixels of the map's bottom edge covered by an overlay panel.
  /// The strip lifts clear of it rather than hiding behind it.
  final double bottomInset;

  /// Overrides the env probe. Tests only — production resolves through
  /// dotenv.
  @visibleForTesting
  final List<MapCredit>? creditsOverride;

  const MapAttribution({
    super.key,
    required this.darkBasemap,
    this.bottomInset = 0,
    this.creditsOverride,
  });

  Future<void> _open(BuildContext context, MapCredit credit) async {
    try {
      final ok = await launchUrl(
        Uri.parse(credit.url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        showTopBanner(
          context,
          AppLocalizations.of(context).legalCouldNotOpen(credit.url),
        );
      }
    } catch (e) {
      debugPrint('map_attribution: opening ${credit.url} failed: $e');
      if (context.mounted) {
        showTopBanner(
          context,
          AppLocalizations.of(context).legalCouldNotOpen(credit.url),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final credits = creditsOverride ?? currentBasemapCredits();
    if (credits.isEmpty) return const SizedBox.shrink();

    final ink = attributionInk(darkBasemap: darkBasemap);
    final scrim = attributionScrim(darkBasemap: darkBasemap);

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.only(right: 4, bottom: 4 + bottomInset),
        child: Semantics(
          container: true,
          label: l10n.mapAttributionSemantics,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scrim,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < credits.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Semantics(
                      link: true,
                      child: GestureDetector(
                        onTap: () => _open(context, credits[i]),
                        child: Text(
                          credits[i].osmData
                              ? l10n.mapAttributionOsmContributors(
                                  credits[i].name)
                              : l10n.mapAttributionProvider(credits[i].name),
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                            color: ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Credit text colour. Same pair as the track casing: white over a dark
/// basemap, the deep indigo ink over a light one.
@visibleForTesting
Color attributionInk({required bool darkBasemap}) =>
    darkBasemap ? Colors.white : const Color(0xFF1E1B4B);

/// Translucent slab behind the credit text. Its job is to hold the text
/// legible over whatever the basemap happens to paint underneath — a
/// basemap is many colours, and a snow field or a motorway shield can sit
/// anywhere. Opaque enough that even the worst-case patch (a white field
/// under the dark scrim, a black one under the light) keeps the text above
/// 4.5:1.
@visibleForTesting
Color attributionScrim({required bool darkBasemap}) => darkBasemap
    ? Colors.black.withValues(alpha: 0.62)
    : Colors.white.withValues(alpha: 0.78);
