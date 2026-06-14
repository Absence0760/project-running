/// Race roadbook — the crew sheet a route's course markers + a goal time imply.
///
/// Given a route's waypoints, its course markers (aid stations / cutoffs / crew
/// access), and a goal finish time, [buildRoadbook] produces the per-checkpoint
/// schedule ultra crews currently build by hand: cumulative distance, projected
/// arrival (elapsed + wall clock), cutoff margin, and per-leg vert.
///
/// The differentiator over even splits: goal time is allocated by
/// **grade-adjusted effort** ([gradeFactor], Minetti) — the climbs get
/// proportionally more time than the flats — not by even distance. With no
/// elevation data the effort model degrades cleanly to even pace.
///
/// Twin of `apps/web/src/lib/routes/roadbook.ts` — keep the allocation, cutoff
/// rules, edge cases, and test count in lockstep.
library;

import 'dart:math' as math;

import 'grade_adjusted_pace.dart' show gradeFactor, minSegmentM;
import 'route_markers.dart' show parseCutoff;

class RoadbookWaypoint {
  final double lat;
  final double lng;
  final double? ele;
  const RoadbookWaypoint({required this.lat, required this.lng, this.ele});
}

class RoadbookMarker {
  /// Distance along the route from the start, metres. Null = no geom yet.
  final double? positionM;
  final String kind;
  final String label;
  final dynamic meta;
  const RoadbookMarker({
    required this.positionM,
    required this.kind,
    required this.label,
    this.meta,
  });
}

enum PacingModel { effort, even }

enum CutoffStatus { safe, tight, miss }

class RoadbookCutoff {
  final int limitElapsedS;
  final double marginS;
  final CutoffStatus status;
  const RoadbookCutoff({
    required this.limitElapsedS,
    required this.marginS,
    required this.status,
  });
}

class RoadbookLeg {
  /// 'start' / 'finish', or a marker `{kind, label}`.
  final String? kind; // null for start/finish
  final String label; // 'start' / 'finish' / marker label
  final double cumDistM;
  final double legDistM;
  final double legGainM;
  final double legLossM;
  final double projectedElapsedS;

  /// Wall-clock arrival, minutes past midnight (mod 1440). Null if no start.
  final double? projectedClockMin;
  final RoadbookCutoff? cutoff;
  final List<String> services;

  const RoadbookLeg({
    required this.kind,
    required this.label,
    required this.cumDistM,
    required this.legDistM,
    required this.legGainM,
    required this.legLossM,
    required this.projectedElapsedS,
    this.projectedClockMin,
    this.cutoff,
    this.services = const [],
  });

  bool get isStart => kind == null && label == 'start';
  bool get isFinish => kind == null && label == 'finish';
}

class Roadbook {
  final List<RoadbookLeg> legs;
  final double totalDistM;
  final double totalGainM;
  final double totalSeconds;
  final bool hasElevation;
  const Roadbook({
    required this.legs,
    required this.totalDistM,
    required this.totalGainM,
    required this.totalSeconds,
    required this.hasElevation,
  });
}

/// A cutoff within this many seconds of the projection is "tight", not "safe".
const int cutoffTightS = 30 * 60;
const int _minutesPerDay = 1440;

double _haversineM(RoadbookWaypoint a, RoadbookWaypoint b) {
  const r = 6371000.0;
  const deg = math.pi / 180;
  final dLat = (b.lat - a.lat) * deg;
  final dLng = (b.lng - a.lng) * deg;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(a.lat * deg) *
          math.cos(b.lat * deg) *
          math.pow(math.sin(dLng / 2), 2);
  return r * 2 * math.asin(math.min(1, math.sqrt(h)));
}

class _Cumulative {
  final List<double> dist;
  final List<double> gap;
  final List<double> gain;
  final List<double> loss;
  final bool hasElevation;
  _Cumulative(this.dist, this.gap, this.gain, this.loss, this.hasElevation);
}

_Cumulative _walk(List<RoadbookWaypoint> waypoints) {
  final dist = <double>[0];
  final gap = <double>[0];
  final gain = <double>[0];
  final loss = <double>[0];
  final eles = <double>{};
  for (final w in waypoints) {
    if (w.ele != null) eles.add(w.ele!);
  }
  for (var i = 1; i < waypoints.length; i++) {
    final a = waypoints[i - 1];
    final b = waypoints[i];
    final horiz = _haversineM(a, b);
    final dEle = (a.ele != null && b.ele != null) ? b.ele! - a.ele! : 0.0;
    final grade = horiz >= minSegmentM ? dEle / horiz : 0.0;
    dist.add(dist[i - 1] + horiz);
    gap.add(gap[i - 1] + horiz * gradeFactor(grade));
    gain.add(gain[i - 1] + math.max(0.0, dEle));
    loss.add(loss[i - 1] + math.max(0.0, -dEle));
  }
  return _Cumulative(dist, gap, gain, loss, eles.length >= 2);
}

double _valueAt(List<double> cum, List<double> dist, double target) {
  final total = dist.last;
  if (target <= 0) return cum.first;
  if (target >= total) return cum.last;
  for (var i = 1; i < dist.length; i++) {
    if (target <= dist[i]) {
      final span = dist[i] - dist[i - 1];
      final t = span <= 0 ? 0.0 : (target - dist[i - 1]) / span;
      return cum[i - 1] + (cum[i] - cum[i - 1]) * t;
    }
  }
  return cum.last;
}

class _Stop {
  final double pos;
  final String? kind;
  final String label;
  final List<String> services;
  final dynamic cutoffMeta;
  final bool isCutoff;
  _Stop(this.pos, this.kind, this.label, this.services, this.cutoffMeta,
      this.isCutoff);
}

/// Build the roadbook. Checkpoints are: synthetic start (0), each marker with a
/// non-null `positionM` (ordered by distance), and synthetic finish (total).
Roadbook buildRoadbook(
  List<RoadbookWaypoint> waypoints,
  List<RoadbookMarker> markers, {
  required double goalSeconds,
  double? startClockMin,
  required PacingModel model,
}) {
  final cum = _walk(waypoints);
  final totalDistM = cum.dist.isEmpty ? 0.0 : cum.dist.last;
  final totalGainM = cum.gain.isEmpty ? 0.0 : cum.gain.last;
  final goal = math.max(0.0, goalSeconds);

  final placed = markers
      .where((m) => m.positionM != null)
      .map((m) => _Stop(
            math.min(totalDistM, math.max(0.0, m.positionM!)),
            m.kind,
            m.label,
            (m.meta is Map && (m.meta as Map)['services'] is List)
                ? ((m.meta as Map)['services'] as List).cast<String>()
                : const <String>[],
            m.meta,
            m.kind == 'cutoff',
          ))
      .toList()
    ..sort((a, b) => a.pos.compareTo(b.pos));

  final stops = <_Stop>[
    _Stop(0, null, 'start', const [], null, false),
    ...placed,
    _Stop(totalDistM, null, 'finish', const [], null, false),
  ];

  final useEffort = model == PacingModel.effort && cum.hasElevation;
  double metricAt(double pos) =>
      useEffort ? _valueAt(cum.gap, cum.dist, pos) : pos;
  final totalMetric = metricAt(totalDistM);

  final legs = <RoadbookLeg>[];
  var prevPos = 0.0;
  var prevGain = 0.0;
  var prevLoss = 0.0;
  var prevMetric = 0.0;
  var elapsed = 0.0;

  for (final stop in stops) {
    final cumGain = _valueAt(cum.gain, cum.dist, stop.pos);
    final cumLoss = _valueAt(cum.loss, cum.dist, stop.pos);
    final metric = metricAt(stop.pos);
    final legTime = totalMetric > 0 ? goal * (metric - prevMetric) / totalMetric : 0.0;
    elapsed += legTime;

    double? clockMin;
    if (startClockMin != null) {
      clockMin = (((startClockMin + elapsed / 60) % _minutesPerDay) +
              _minutesPerDay) %
          _minutesPerDay;
    }

    RoadbookCutoff? cutoff;
    if (stop.isCutoff) {
      final limit = _cutoffLimitS(stop.cutoffMeta, startClockMin);
      if (limit != null) {
        final margin = limit - elapsed;
        cutoff = RoadbookCutoff(
          limitElapsedS: limit,
          marginS: margin,
          status: margin < 0
              ? CutoffStatus.miss
              : margin < cutoffTightS
                  ? CutoffStatus.tight
                  : CutoffStatus.safe,
        );
      }
    }

    legs.add(RoadbookLeg(
      kind: stop.kind,
      label: stop.label,
      cumDistM: stop.pos,
      legDistM: stop.pos - prevPos,
      legGainM: cumGain - prevGain,
      legLossM: cumLoss - prevLoss,
      projectedElapsedS: elapsed,
      projectedClockMin: clockMin,
      cutoff: cutoff,
      services: stop.services,
    ));

    prevPos = stop.pos;
    prevGain = cumGain;
    prevLoss = cumLoss;
    prevMetric = metric;
  }

  return Roadbook(
    legs: legs,
    totalDistM: totalDistM,
    totalGainM: totalGainM,
    totalSeconds: goal,
    hasElevation: cum.hasElevation,
  );
}

int? _cutoffLimitS(dynamic meta, double? startClockMin) {
  final cutoff = parseCutoff(meta);
  if (cutoff == null) return null;
  if (cutoff.elapsedS != null) return cutoff.elapsedS;
  if (cutoff.clock != null && startClockMin != null) {
    final parts = cutoff.clock!.split(':');
    var cutoffMin = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    if (cutoffMin < startClockMin) cutoffMin += _minutesPerDay;
    return ((cutoffMin - startClockMin) * 60).round();
  }
  return null;
}
