import {
	createUndoQueue,
	undoWindowSFromPref,
	DEFAULT_UNDO_WINDOW_S,
	type DeferredDestruction,
	type PendingUndo,
} from '$lib/core/undo_queue';

/// Reactive shell around the deferred-commit undo queue. The contract,
/// the one-slot rule, and the WCAG rationale all live in
/// `core/undo_queue.ts`; this file only holds the runes and the browser
/// timer wiring, so the core stays `tsx --test`-runnable.

let pending = $state<PendingUndo | null>(null);
let windowS = $state(DEFAULT_UNDO_WINDOW_S);

const queue = createUndoQueue({
	windowMs: () => windowS * 1000,
	setTimer: (cb, ms) => setTimeout(cb, ms),
	clearTimer: (handle) => clearTimeout(handle as ReturnType<typeof setTimeout>),
	now: () => Date.now(),
	onChange: (next) => {
		pending = next;
	},
});

/// Hydrated from the `undo_window_s` pref by the root layout and by
/// `/settings/preferences` on change. Read at defer time, so changing it
/// never shortens a window already running.
export function setUndoWindowS(raw: unknown): void {
	windowS = undoWindowSFromPref(raw);
}

/// Remove the row from the caller's local list first, then hand the
/// server mutation here. It runs when the undo window closes — never
/// before — so `undo()` only has to cancel a timer.
export function deferDestructive(destruction: DeferredDestruction): void {
	queue.defer(destruction);
}

export const undoStore = {
	get pending() {
		return pending;
	},
	get windowS() {
		return windowS;
	},
	undo: queue.undo,
	flush: queue.flush,
	pause: queue.pause,
	resume: queue.resume,
	hasPending: queue.hasPending,
};
