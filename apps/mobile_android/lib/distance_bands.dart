/// Race-distance bands for route discovery.
///
/// Dart twin of `apps/web/src/lib/routes/distance_bands.ts` — keep both
/// in lockstep (same windows, same edge handling). This is the single
/// source of truth for the band ranges; the `discoverable_routes_in_bbox`
/// RPC is generic over whatever `[lo, hi)` windows it is handed
/// (migration `20261114_001`), so the numbers live here.
///
/// Windows are deliberately tolerant (a "5K" route is rarely exactly
/// 5.00 km) and leave gaps between bands (a 15 km route is no race
/// distance and matches nothing). Bounds are in metres: [minM] inclusive,
/// [maxM] exclusive, `maxM == null` open-ended (ultra).
///
/// Pure functions, no Flutter / Supabase deps.
library;

class DistanceBand {
  final String key;
  final String label;
  final double minM;
  final double? maxM;
  const DistanceBand(this.key, this.label, this.minM, this.maxM);
}

const distanceBands = <DistanceBand>[
  DistanceBand('5k', '5K', 4000, 6000),
  DistanceBand('10k', '10K', 8000, 12000),
  DistanceBand('half', 'Half', 19000, 23000),
  DistanceBand('marathon', 'Marathon', 40000, 44500),
  DistanceBand('ultra', 'Ultra', 44500, null),
];

/// The band a given route distance falls into, or null if it sits in a
/// gap between bands. Used to badge route rows in the list.
DistanceBand? bandForDistance(double distanceM) {
  for (final b in distanceBands) {
    if (distanceM >= b.minM && (b.maxM == null || distanceM < b.maxM!)) {
      return b;
    }
  }
  return null;
}

/// Parallel min/max bound arrays for the RPC, built from selected band
/// keys. Both null when nothing is selected so the RPC skips the
/// distance predicate. A null element in [max] is an open-ended upper
/// bound (ultra). Output order always follows [distanceBands],
/// independent of the order keys were passed in.
class BandRanges {
  final List<double>? min;
  final List<double?>? max;
  const BandRanges(this.min, this.max);
}

BandRanges bandsToRanges(List<String> keys) {
  if (keys.isEmpty) return const BandRanges(null, null);
  final sel = distanceBands.where((b) => keys.contains(b.key)).toList();
  if (sel.isEmpty) return const BandRanges(null, null);
  return BandRanges(
    sel.map((b) => b.minM).toList(),
    sel.map((b) => b.maxM).toList(),
  );
}
