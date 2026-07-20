// Wall-clock-anchored stopwatch for capturing the ACTUAL elapsed hold time of a
// time-modality gym set (e.g. a plank) in GymExecutionBand. Web-only; not a
// parity pair — execution is web-canonical (mobile drives GymWorkoutRunner
// directly).
//
// Elapsed time is always derived from a stored wall-clock anchor and the caller
// -supplied `nowMs` — never accumulated by decrementing a counter on a timer
// tick. A tab that is backgrounded or throttled loses interval ticks, so a
// tick-counting timer (see RestTimer) drifts; recomputing from `Date.now()`
// against the anchor stays correct across a suspend/resume.

export interface StopwatchState {
	/// Elapsed time banked from prior running spans (i.e. before the last pause).
	accumMs: number;
	/// Wall-clock start of the current running span, or null when paused/stopped.
	anchorMs: number | null;
}

export function idleStopwatch(): StopwatchState {
	return { accumMs: 0, anchorMs: null };
}

export function isRunning(s: StopwatchState): boolean {
	return s.anchorMs != null;
}

export function elapsedMs(s: StopwatchState, nowMs: number): number {
	const live = s.anchorMs == null ? 0 : Math.max(0, nowMs - s.anchorMs);
	return s.accumMs + live;
}

export function elapsedSeconds(s: StopwatchState, nowMs: number): number {
	return Math.round(elapsedMs(s, nowMs) / 1000);
}

export function startStopwatch(s: StopwatchState, nowMs: number): StopwatchState {
	if (s.anchorMs != null) return s;
	return { accumMs: s.accumMs, anchorMs: nowMs };
}

export function stopStopwatch(s: StopwatchState, nowMs: number): StopwatchState {
	if (s.anchorMs == null) return s;
	return { accumMs: elapsedMs(s, nowMs), anchorMs: null };
}

/// Parse the duration input a runner sees on a timed set into the seconds value
/// logged as the set's ACTUAL duration. Empty / blank / non-finite / negative
/// input yields null — never the prescribed target — so an untracked hold logs
/// no actual rather than a fake full hit. Accepts a `number` because a bound
/// `<input type="number">` coerces its value to a number the moment it's edited.
export function parseDurationInput(raw: string | number | null | undefined): number | null {
	if (raw == null) return null;
	const str = typeof raw === 'number' ? String(raw) : raw;
	if (str.trim() === '') return null;
	const n = Math.round(parseFloat(str));
	return Number.isFinite(n) && n >= 0 ? n : null;
}
