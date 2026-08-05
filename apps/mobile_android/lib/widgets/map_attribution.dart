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
///
/// Deliberately theme-FREE, unlike the rest of the app's micro-labels: the
/// widget is mounted inside the rasterised share cards as well as on live
/// maps, and its ink has to follow the resolved basemap (§ 491), not the app
/// theme. So it carries a bespoke [TextStyle] rather than `labelSmall` — but
/// pinned to [kMapAttributionFontSize], the same 11 px micro-label floor
/// § 482 declared. It shipped at 10 px, under that floor, on a target that is
/// also a link.
///
/// Anchored to the bottom START, not the bottom-right MapLibre defaults to
/// on web: every locate / re-centre control in the app is a `FloatingAction
/// Button`, which Material also anchors to the end, and a credit a floating
/// button sits on top of is not a credit. Directional so the two stay on
/// opposite corners if an RTL locale is ever added.
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final credits = creditsOverride ?? currentBasemapCredits();
    if (credits.isEmpty) return const SizedBox.shrink();

    final ink = attributionInk(darkBasemap: darkBasemap);
    final scrim = attributionScrim(darkBasemap: darkBasemap);

    return Align(
      alignment: AlignmentDirectional.bottomStart,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: 4, bottom: 4 + bottomInset),
        child: Semantics(
          container: true,
          label: l10n.mapAttributionSemantics,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scrim,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < credits.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Semantics(
                      link: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => openMapCredit(context, credits[i]),
                        child: SizedBox(
                          height: kMapAttributionTapTarget,
                          child: Center(
                            widthFactor: 1,
                            child: Text(
                              mapCreditLabel(l10n, credits[i]),
                              style: TextStyle(
                                fontSize: kMapAttributionFontSize,
                                height: 1.3,
                                fontWeight: FontWeight.w500,
                                color: ink,
                              ),
                            ),
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

/// The localized credit line for [credit] — the proper noun untranslated
/// inside a sentence that is.
String mapCreditLabel(AppLocalizations l10n, MapCredit credit) =>
    credit.osmData
        ? l10n.mapAttributionOsmContributors(credit.name)
        : l10n.mapAttributionProvider(credit.name);

/// Opens a credit's copyright page. Attribution has to be *linked*, and a
/// link that silently does nothing is not one — a launcher failure surfaces
/// a banner rather than dying inside the map's build.
Future<void> openMapCredit(BuildContext context, MapCredit credit) async {
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

/// The 11 px micro-label floor § 482 declared. Held here rather than read off
/// `textTheme.labelSmall` so the strip stays theme-free for the share cards.
@visibleForTesting
const double kMapAttributionFontSize = 11;

/// WCAG 2.2 SC 2.5.8 minimum target size. Each credit is a link, and two of
/// them sit 6 dp apart, so the undersized-target spacing exception does not
/// apply — the target itself has to reach 24 dp.
@visibleForTesting
const double kMapAttributionTapTarget = 24;

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
