import 'dart:math' as math;

/// Share of the detail viewport the hero map takes.
///
/// Derived from the shipped portrait figure rather than picked: on the
/// reference 360x800 phone a 24dp status bar and a 56dp app bar leave a 720dp
/// viewport, and the four map-bearing detail screens had settled on 280-320dp
/// of it — 0.39 to 0.44. 0.45 reproduces the largest of those at the reference
/// size and derives the rest, so the map is the same share of the screen on a
/// tall phone, a short one, and a landscape one.
const double kDetailMapFraction = 0.45;

/// The body the map may never eat into: enough for one whole row plus its
/// section gap and header, so the surface still reads as scrollable.
///
/// This is the invariant, applied last — a 320dp map on a 667x375 landscape
/// phone (a 295dp viewport) filled the body outright, leaving no signal that
/// anything followed it.
const double kDetailMapMinPeek = 24 + 24 + 72;

/// Below this the map stops being a map, so a very short viewport gives up
/// peek rather than legibility — until [kDetailMapMinPeek] outbids it.
const double kDetailMapMinHeight = 160;

/// Above this a taller viewport spends its extra height on content, not on
/// more map: a tablet in portrait does not need a 540dp hero.
const double kDetailMapMaxHeight = 400;

/// Height of the hero map on a detail surface whose scroll viewport is
/// [viewportHeight] tall.
///
/// Take [viewportHeight] from the `BoxConstraints` of a `LayoutBuilder` wrapped
/// around the scroll view, not from `MediaQuery` arithmetic: a `Scaffold` with
/// an app bar has already removed the status bar and the toolbar from its
/// body's constraints, so subtracting either again double-counts it, and which
/// insets a `SafeArea` above the caller has consumed is not knowable from the
/// leaf. The constraints are the answer both of those are approximating.
double detailMapHeight(double viewportHeight) {
  if (viewportHeight.isNaN || viewportHeight <= 0) return kDetailMapMinHeight;
  final share = math.min(
    viewportHeight * kDetailMapFraction,
    kDetailMapMaxHeight,
  );
  final legible = math.max(share, kDetailMapMinHeight);
  return math.max(0, math.min(legible, viewportHeight - kDetailMapMinPeek));
}
