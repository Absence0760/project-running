/// Readiness-to-run score. Combines training balance (form / TSB),
/// last night's sleep, and resting-HR drift vs a baseline into a
/// single 0–100 number the dashboard can show.
///
/// Mirrors `apps/web/src/lib/readiness.ts`. Keep in lockstep — the
/// shared-library-syncer agent watches the pair.

class ReadinessInputs {
  /// Training Stress Balance (Form). Positive = fresh, negative = fatigued.
  final double? tsb;
  final double? sleepHours;
  final int? restingHrBpm;
  final int? baselineRestingHrBpm;

  const ReadinessInputs({
    this.tsb,
    this.sleepHours,
    this.restingHrBpm,
    this.baselineRestingHrBpm,
  });
}

enum ReadinessBand { low, moderate, high }

class ReadinessContribution {
  final String name;
  final int delta;
  final String note;
  const ReadinessContribution({
    required this.name,
    required this.delta,
    required this.note,
  });
}

class Readiness {
  final int score;
  final ReadinessBand band;
  final String advice;
  final List<ReadinessContribution> contributors;
  const Readiness({
    required this.score,
    required this.band,
    required this.advice,
    required this.contributors,
  });
}

const int _baselineScore = 75;

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

ReadinessBand _bandFor(int score) {
  if (score >= 70) return ReadinessBand.high;
  if (score >= 40) return ReadinessBand.moderate;
  return ReadinessBand.low;
}

ReadinessContribution? _scoreTsb(double? tsb) {
  if (tsb == null) return null;
  int delta;
  String note;
  if (tsb < -20) {
    delta = -20;
    note = 'Heavy fatigue — recent training stress is well above your fitness';
  } else if (tsb < -10) {
    delta = -12;
    note = 'Fatigued from recent training';
  } else if (tsb < -5) {
    delta = -6;
    note = 'Slight fatigue';
  } else if (tsb <= 5) {
    delta = 0;
    note = 'Form is neutral';
  } else if (tsb <= 15) {
    delta = 8;
    note = 'Fresh and well-recovered';
  } else if (tsb <= 25) {
    delta = 5;
    note = 'Very fresh — borderline tapered';
  } else {
    delta = -3;
    note = 'Over-tapered — edge may be blunted';
  }
  return ReadinessContribution(name: 'Form (TSB)', delta: delta, note: note);
}

ReadinessContribution? _scoreSleep(double? hours) {
  if (hours == null) return null;
  int delta;
  String note;
  if (hours < 5) {
    delta = -25;
    note = 'Very little sleep — recovery is compromised';
  } else if (hours < 6.5) {
    delta = -12;
    note = 'Short on sleep';
  } else if (hours < 7.5) {
    delta = -3;
    note = 'A little under target sleep';
  } else if (hours <= 9) {
    delta = 5;
    note = 'Well rested';
  } else {
    delta = 0;
    note = 'Extended sleep — recovery should be solid';
  }
  return ReadinessContribution(name: 'Sleep', delta: delta, note: note);
}

ReadinessContribution? _scoreRestingHr(int? resting, int? baseline) {
  if (resting == null || baseline == null) return null;
  final diff = resting - baseline;
  int delta;
  String note;
  if (diff > 10) {
    delta = -18;
    note = 'Resting HR $diff bpm above baseline — strong sign of illness or under-recovery';
  } else if (diff > 5) {
    delta = -10;
    note = 'Resting HR $diff bpm above baseline';
  } else if (diff > 2) {
    delta = -4;
    note = 'Resting HR slightly elevated';
  } else if (diff >= -2) {
    delta = 0;
    note = 'Resting HR at baseline';
  } else {
    delta = 3;
    note = 'Resting HR below baseline — well recovered';
  }
  return ReadinessContribution(name: 'Resting HR', delta: delta, note: note);
}

String _dominantAdvice(
    List<ReadinessContribution> contributors, ReadinessBand band) {
  if (contributors.isEmpty) {
    return band == ReadinessBand.high
        ? 'Looks like a good day to push the pace.'
        : 'Connect sleep + HR data for a real readiness picture.';
  }
  final sorted = [...contributors]
    ..sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
  final dom = sorted.first;
  final tail = switch (band) {
    ReadinessBand.low => 'Consider an easy day or a rest day.',
    ReadinessBand.moderate => 'A steady or moderate effort fits today.',
    ReadinessBand.high => 'You’re primed for a harder effort if planned.',
  };
  return '${dom.note}. $tail';
}

Readiness computeReadiness(ReadinessInputs inputs) {
  final contributors = <ReadinessContribution>[];
  final tsb = _scoreTsb(inputs.tsb);
  if (tsb != null) contributors.add(tsb);
  final sleep = _scoreSleep(inputs.sleepHours);
  if (sleep != null) contributors.add(sleep);
  final hr = _scoreRestingHr(inputs.restingHrBpm, inputs.baselineRestingHrBpm);
  if (hr != null) contributors.add(hr);

  final sum = contributors.fold<int>(0, (s, c) => s + c.delta);
  final score = _clamp(_baselineScore + sum, 0, 100);
  final band = _bandFor(score);
  return Readiness(
    score: score,
    band: band,
    advice: _dominantAdvice(contributors, band),
    contributors: contributors,
  );
}
