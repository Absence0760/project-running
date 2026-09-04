/// What a run's `metadata.hr_coverage` lets the run-detail page say about the
/// run's heart rate.
///
/// The key is the fraction of ACTIVE elapsed time during which the sensor was
/// delivering samples (decisions § 1083), and the Wear recorder that writes it
/// SUPPRESSES `avg_bpm` below 0.5 — a mean over less of the run than not is
/// not the run's average. So the state this resolves is the one nothing read
/// until § 1088: `avg_bpm` absent WITH coverage present is a suppressed
/// average, and it rendered identically to a run recorded with no strap at
/// all. The two are different facts and the page now says which it has.
///
/// Absent is not zero. A run from a build predating the field, or one
/// recovered from a checkpoint that never carried it, omits the key — so an
/// unusable value resolves to null and the page keeps its old copy, rather
/// than claiming a sensor duty cycle nobody measured.
///
/// Web-only. The mobile half of the same reading is `run_detail_screen.dart`'s
/// own; this is not a registered parity pair and neither registry names it.
export function hrCoveragePercent(value: unknown): number | null {
	if (typeof value !== 'number' || !Number.isFinite(value)) return null;
	// The writer's contract is a fraction. A value outside it is a number this
	// build cannot interpret, and rendering "covered 4200% of this run" is
	// worse than saying nothing.
	if (value < 0 || value > 1) return null;
	if (value === 0) return 0;
	// A nonzero coverage never reads as 0 %: 0 is reserved for the sensor that
	// was enabled and delivered nothing, which is a different sentence.
	return Math.min(100, Math.max(1, Math.round(value * 100)));
}
