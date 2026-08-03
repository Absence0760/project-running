/// Longitude arithmetic that survives the antimeridian.
///
/// Every local planar frame on this platform — the along-route projection's
/// per-segment frame, the marker snap, the RDP perpendicular distance, the
/// thumbnail's bounding box, the heatmap's fit box — starts by subtracting two
/// longitudes and calling the result "metres east". That subtraction is wrong
/// by a whole turn whenever the two straddle 180°: 179.99 to -179.97 is 0.04°
/// east, and plain arithmetic reads it as 359.96° west, or ~40,000 km.
///
/// Trigonometric formulae are immune (`sin` and `cos` are periodic, so the
/// haversine lengths and great-circle bearings already come out right) — it is
/// only the planar frames that need this. Applying it is free elsewhere: for
/// any pair within 180° of each other, every function here returns exactly what
/// the plain arithmetic did, bit for bit.
///
/// Dart twin of `apps/web/src/lib/routes/geo.ts`, and a port of the firmware's
/// `watch_core::geo` (decisions §463) — keep all three in lockstep.
library;

/// Shortest signed east-west separation from [fromDeg] to [toDeg], in degrees
/// within [-180, 180). Positive is east. Two exactly opposite meridians resolve
/// west rather than flapping between the two equally-correct answers.
double lonDeltaDeg(double fromDeg, double toDeg) => _foldTurns(toDeg - fromDeg);

/// [lonDeg] shifted by whole turns until it is within 180° of [referenceDeg] —
/// the same meridian, expressed on the reference's side of the line. The result
/// can sit outside [-180, 180]; that is the point, since a bounding box
/// anchored west of the line needs its eastern points to carry on past 180
/// rather than jump to -179.
///
/// Written as [lonDeg] less whole turns (rather than [referenceDeg] plus the
/// delta) so a longitude already within 180° of the reference comes back bit
/// for bit — the floor is exactly zero there, and a round-trip through a
/// subtraction and an addition is not.
double unwrapLonDeg(double referenceDeg, double lonDeg) =>
    lonDeg - 360 * ((lonDeg - referenceDeg + 180) / 360).floorToDouble();

/// A longitude folded back onto the [-180, 180) meridian range.
double wrapLonDeg(double lonDeg) => _foldTurns(lonDeg);

/// [deg] less however many whole turns leave it in [-180, 180). The floor
/// (rather than a round that breaks halves away from zero) is what makes the
/// fold idempotent at exactly 180°, and it returns any [deg] already in range
/// bit for bit — the floor is exactly zero there, so nothing is added back.
double _foldTurns(double deg) =>
    deg - 360 * ((deg + 180) / 360).floorToDouble();
