/// The load signal for a runner who has just come back from a break.
///
/// `self_load.dart` grades the runner's acute:chronic workload ratio and
/// refuses to say anything below [kMinActiveWeeks] of the chronic window —
/// correctly, because dividing a comeback week by a near-empty month
/// manufactures a terrifying ratio out of thin air. But that refusal is silent
/// exactly where the runner is most exposed: someone back from three months
/// off, logging a 30 km first week, sees no card at all.
///
/// The gap is the *instrument*, not the threshold. ACWR asks "how does this
/// week compare with the month you just trained", and a comeback runner has no
/// such month. This asks a question their history can actually answer: "how
/// does this week compare with the weeks you were running before the break".
/// Their own pre-break average is real data; the near-zero month is not.
///
/// It fires only where `selfLoad` is silent — the same `activeWeeks` gate,
/// read the other way round — so the two cards are mutually exclusive by
/// construction rather than by the dashboard remembering to choose.
///
/// Dart twin of `apps/web/src/lib/training/comeback.ts` — keep the algorithm,
/// thresholds, gates, and test counts in lockstep.
library;

import 'plan_ramp.dart';
import 'training_load.dart' show kLayoffResetDays;

const int _dayMs = 86400000;
const int _weekMs = 7 * _dayMs;

/// How long a run-less stretch has to be before it counts as a break rather
/// than a rest week. Deliberately `training_load`'s own layoff constant: that
/// is already the point at which the app writes the runner's fitness EWMAs
/// down to zero, and a break big enough to erase their modelled fitness is
/// the same break this card is about. Two numbers for one idea would drift.
const int kLayoffMinDays = kLayoffResetDays;

/// Past this, the pre-break average stops being a usable anchor and the card
/// says nothing. A base two years stale describes a body that no longer
/// exists, and grading a return against it would produce a *reassuring*
/// number for a runner who is effectively starting over — over-reporting
/// safety is the failure that hurts here.
const int kLayoffMaxDays = 365;

/// The share of the pre-break weekly average above which a first week back is
/// called steep. An editorial line, not a clinical one: the widely-taught
/// return-to-running shape is to resume at around half of what you were doing
/// and rebuild from there. It is deliberately one flat threshold rather than a
/// curve decaying with layoff length — a decay function would invent precision
/// the underlying evidence does not have, and a runner can reason about "half".
const double kReturnWeekShare = 0.5;

enum ComebackVerdict { insufficient, easingIn, steep }

class ComebackLoad {
  /// [ComebackVerdict.insufficient] whenever there is no break, no usable
  /// pre-break base, or no running this week — the caller renders nothing
  /// rather than a claim it cannot stand behind.
  final ComebackVerdict verdict;

  /// Whole days between the last run before the break and the first run after
  /// it. 0 when the verdict is insufficient.
  final int layoffDays;

  /// [layoffDays] as whole weeks, rounded to nearest — the figure the copy
  /// renders. Rounded rather than floored because overstating a break is the
  /// conservative direction for a safety claim. Never below 4, since
  /// [kLayoffMinDays] is 28.
  final int layoffWeeks;

  /// Last 7 days' running distance, metres.
  final double thisWeekM;

  /// Mean weekly running distance over the four windows before the break.
  final double preLayoffWeeklyM;

  /// [thisWeekM] / [preLayoffWeeklyM]. 0 when the verdict is insufficient.
  final double share;

  const ComebackLoad({
    required this.verdict,
    required this.layoffDays,
    required this.layoffWeeks,
    required this.thisWeekM,
    required this.preLayoffWeeklyM,
    required this.share,
  });
}

const ComebackLoad _ungraded = ComebackLoad(
  verdict: ComebackVerdict.insufficient,
  layoffDays: 0,
  layoffWeeks: 0,
  thisWeekM: 0,
  preLayoffWeeklyM: 0,
  share: 0,
);

/// Grade the runner's first weeks back against the weeks they were running
/// before the break.
///
/// Fail-closed at every step. No run this week, no break in the history, a
/// break too old to anchor against, or too thin a pre-break base all return
/// insufficient — the caller shows nothing, exactly as it does today, rather
/// than a number derived from a history that cannot carry it.
ComebackLoad comebackLoad(List<RunForVolume> runs, int nowMs) {
  final recent = recentRunVolume(runs, nowMs);
  // The ratio card owns any runner whose recent history can carry it; this
  // one exists for the hole that refusal leaves, and two load cards claiming
  // the same week would be worse than either alone.
  if (recent.activeWeeks >= kMinActiveWeeks) return _ungraded;
  // A week with no running has no load to grade, and an "easing in" verdict
  // off zero kilometres would read as praise for not running.
  if (recent.acuteM <= 0) return _ungraded;

  // A device whose clock runs ahead stamps a just-finished run in the future.
  // `recentRunVolume` absorbs that by clamping the age to zero; the same clamp
  // has to happen here, because an unclamped future stamp opens a gap to the
  // run before it and would be read as a layoff that never happened.
  final samples = <VolumeSample>[];
  for (final run in runs) {
    final sample = volumeSample(run);
    if (sample == null) continue;
    samples.add(VolumeSample(
      startedMs: sample.startedMs < nowMs ? sample.startedMs : nowMs,
      distanceM: sample.distanceM,
    ));
  }
  samples.sort((a, b) => b.startedMs.compareTo(a.startedMs));

  // The most recent run-less stretch long enough to count, walking back from
  // today. Later breaks are the ones the runner is living through; an older
  // one is history they have already trained past.
  var gapIndex = -1;
  for (var i = 0; i < samples.length - 1; i++) {
    if (samples[i].startedMs - samples[i + 1].startedMs >= kLayoffMinDays * _dayMs) {
      gapIndex = i;
      break;
    }
  }
  if (gapIndex < 0) return _ungraded;

  final layoffDays =
      (samples[gapIndex].startedMs - samples[gapIndex + 1].startedMs) ~/ _dayMs;
  if (layoffDays > kLayoffMaxDays) return _ungraded;

  // The base is reduced over the same rolling 7-day windows as the acute week,
  // anchored on the last run before the break instead of on today.
  final anchorMs = samples[gapIndex + 1].startedMs;
  var baseTotalM = 0.0;
  final baseWeeks = <int>{};
  for (final sample in samples) {
    final age = anchorMs - sample.startedMs;
    if (age < 0) continue;
    final week = age ~/ _weekMs;
    if (week >= kChronicWindowWeeks) continue;
    baseTotalM += sample.distanceM;
    baseWeeks.add(week);
  }
  // The same evidence bar `plan_ramp` sets, applied where the history is real:
  // a single run before the break is not a base to come back to.
  if (baseWeeks.length < kMinActiveWeeks) return _ungraded;
  final preLayoffWeeklyM = baseTotalM / kChronicWindowWeeks;
  if (preLayoffWeeklyM <= 0) return _ungraded;

  final share = recent.acuteM / preLayoffWeeklyM;
  return ComebackLoad(
    verdict: share > kReturnWeekShare
        ? ComebackVerdict.steep
        : ComebackVerdict.easingIn,
    layoffDays: layoffDays,
    layoffWeeks: (layoffDays / 7).round(),
    thisWeekM: recent.acuteM,
    preLayoffWeeklyM: preLayoffWeeklyM,
    share: share,
  );
}

/// Whether the dashboard has a comeback worth showing.
///
/// Web returns a type predicate, narrowing the verdict to the two the card has
/// copy for; Dart has no analogue, so this is a plain bool and the caller's
/// `switch` over the two is what the analyzer checks instead.
bool shouldSurfaceComeback(ComebackLoad load) {
  return load.verdict != ComebackVerdict.insufficient;
}
