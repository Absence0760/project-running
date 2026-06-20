import 'dart:math' as math;

/// Pure race auto-match scoring. Twin of
/// `apps/web/src/lib/integrations/race_match.ts` — keep in lockstep
/// (algorithm, bands, thresholds, edge cases, test count). No I/O.
///
/// The auto-match-on-record seam (race_calendar.md) offers, after a run is
/// saved, to import the official race result when the recorded run looks like
/// a listed race: same calendar day + start near the race location + distance
/// in the race's band. INFORM-tier — nothing writes without confirmation.

enum RaceDistanceBand { fiveK, tenK, half, marathon, ultra }

/// Confidence at or above which a candidate is worth offering.
const double raceMatchThreshold = 0.5;

/// Start within this radius of the listing's location counts as "at the race".
const double raceMatchRadiusM = 5000;

/// Bucket a distance in metres into a race-distance band with tolerance, or
/// null when it is too short / between bands. Matches the SQL
/// search_race_listings p_distance windows + the web twin.
RaceDistanceBand? raceDistanceBand(num? distanceM) {
  if (distanceM == null || distanceM.isNaN || distanceM < 4500) return null;
  if (distanceM <= 5500) return RaceDistanceBand.fiveK;
  if (distanceM >= 9000 && distanceM <= 11000) return RaceDistanceBand.tenK;
  if (distanceM >= 20000 && distanceM <= 22000) return RaceDistanceBand.half;
  if (distanceM >= 41000 && distanceM <= 43000) return RaceDistanceBand.marathon;
  if (distanceM > 43000) return RaceDistanceBand.ultra;
  return null;
}

class RunMatchInput {
  /// Run start as an ISO timestamp or date — only the calendar day is used.
  final String runDate;

  /// Recorded GPS start; null when the run has no track (indoor / manual).
  final LatLng? runStartLatLng;
  final num? runDistanceM;

  const RunMatchInput({
    required this.runDate,
    required this.runStartLatLng,
    required this.runDistanceM,
  });
}

class ListingMatchInput {
  final String raceDate; // ISO date (YYYY-MM-DD)
  final num? distanceM;

  /// Metres from the run start to the listing location, when known (the RPC
  /// returns distance_m_away). Null when neither side has a geocoded point.
  final num? distanceMAway;

  const ListingMatchInput({
    required this.raceDate,
    required this.distanceM,
    this.distanceMAway,
  });
}

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);
}

/// 0..1 confidence that [run] is the race in [listing]. Same-day is required;
/// remaining signal is split between proximity + a matching distance band,
/// normalised over the signals that could be evaluated.
double raceMatchScore(RunMatchInput run, ListingMatchInput listing) {
  if (!_sameCalendarDay(run.runDate, listing.raceDate)) return 0;

  double score = 0;
  double weight = 0;

  score += 0.5;
  weight += 0.5;

  final away = listing.distanceMAway;
  if (away != null && away.isFinite) {
    weight += 0.3;
    if (away <= raceMatchRadiusM) {
      score += 0.3 * (1 - away / raceMatchRadiusM);
    }
  }

  final runBand = raceDistanceBand(run.runDistanceM);
  final listingBand = raceDistanceBand(listing.distanceM);
  if (runBand != null && listingBand != null) {
    weight += 0.2;
    if (runBand == listingBand) score += 0.2;
  }

  return weight == 0 ? 0 : score / weight;
}

/// Whether a listing is a confident-enough candidate to offer.
bool isRaceMatchCandidate(RunMatchInput run, ListingMatchInput listing) {
  return raceMatchScore(run, listing) >= raceMatchThreshold;
}

/// Great-circle distance in metres between two points (haversine). Exposed so
/// a caller can compute distance_m_away when the RPC didn't.
double haversineMetres(LatLng a, LatLng b) {
  const r = 6371000.0;
  double toRad(double d) => d * math.pi / 180;
  final dLat = toRad(b.lat - a.lat);
  final dLng = toRad(b.lng - a.lng);
  final lat1 = toRad(a.lat);
  final lat2 = toRad(b.lat);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(h)));
}

bool _sameCalendarDay(String a, String b) => _dayKey(a) == _dayKey(b);

String _dayKey(String ts) {
  final t = ts.trim();
  return t.length >= 10 ? t.substring(0, 10) : t;
}
