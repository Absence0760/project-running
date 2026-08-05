/**
 * Deferred-commit undo — the rune-free core of the web app's undo contract.
 *
 * The app had no undo anywhere: every destructive action was
 * confirm-then-gone. Three contracts were on the table and only one of
 * them can be honest for the actions we adopt it on:
 *
 *   1. A compensating inverse (re-insert what was deleted) mints a NEW
 *      server id, and anything the original row owned — cascaded
 *      replies, a Storage object's bytes — is already unrecoverable. An
 *      "Undo" that hands back a different row is a lie.
 *   2. A soft delete + restore is the honest answer for a *trash*
 *      feature, but it costs a `deleted_at` column on every adopting
 *      table, an RLS/read-path filter everywhere, and a retention story.
 *   3. Deferring the mutation until the undo window closes means
 *      **nothing is destroyed while undo is on offer**, so undo cannot
 *      fail. That is this module.
 *
 * The row leaves the caller's local list immediately (the action feels
 * done) while `commit` is held. Undo cancels the pending commit and
 * calls `restore`; the server was never touched. A commit that later
 * fails also calls `restore`, so a list never claims a row is gone
 * while the server still holds it.
 *
 * One slot, deliberately: a second destruction commits the first
 * immediately rather than stacking bars whose ordering the user would
 * have to reason about.
 *
 * Kept rune-free so it is `tsx --test`-runnable (see undo_queue.test.ts);
 * the reactive wrapper lives in stores/undo.svelte.ts.
 */

/// The undo window in seconds, keyed by the `undo_window_s` pref.
/// `0` turns the time limit off entirely — the WCAG 2.2.1 "Turn off"
/// route, so a screen-reader or motor-impaired user is never racing a
/// countdown to reach the only undo affordance.
export const UNDO_WINDOW_CHOICES_S = [8, 30, 0] as const;
export const DEFAULT_UNDO_WINDOW_S = 8;

/// Normalises a stored `undo_window_s` bag value. An absent, corrupt, or
/// unrecognised value falls back to the default rather than to `0` — a
/// garbage bag must not silently pin every destructive action open
/// forever, which would leave the user's list disagreeing with the
/// server until they navigate.
export function undoWindowSFromPref(raw: unknown): number {
	if (typeof raw !== 'number' || !Number.isFinite(raw)) return DEFAULT_UNDO_WINDOW_S;
	return (UNDO_WINDOW_CHOICES_S as readonly number[]).includes(raw) ? raw : DEFAULT_UNDO_WINDOW_S;
}

export interface DeferredDestruction {
	/// Already-localized sentence for the undo bar ("Porridge removed").
	message: string;
	/// The server mutation. Runs when the window closes — never at the
	/// moment the user clicks delete.
	commit: () => Promise<void>;
	/// Puts the caller's local state back exactly as it was. Run on undo
	/// and on a commit failure.
	restore: () => void;
	/// Surfaces a commit failure at the call site (a toast, a banner).
	onCommitError?: (error: unknown) => void;
}

export interface PendingUndo {
	id: number;
	message: string;
	/// How long the bar has to run, in ms. `0` means there is no time
	/// limit at all — the user's chosen "until I dismiss it" window.
	windowMs: number;
	paused: boolean;
}

type TimerHandle = unknown;

export interface UndoQueueDeps {
	/// The undo window in ms, read at defer time. `0` or less disables
	/// the timer entirely (WCAG 2.2.1 "turn off").
	windowMs: () => number;
	setTimer: (cb: () => void, ms: number) => TimerHandle;
	clearTimer: (handle: TimerHandle) => void;
	now: () => number;
	onChange: (pending: PendingUndo | null) => void;
}

export interface UndoQueue {
	defer: (destruction: DeferredDestruction) => void;
	undo: () => void;
	/// Commit the pending destruction now — the dismiss button, a
	/// navigation, or a second destruction arriving.
	flush: () => Promise<void>;
	pause: () => void;
	resume: () => void;
	hasPending: () => boolean;
}

export function createUndoQueue(deps: UndoQueueDeps): UndoQueue {
	let nextId = 1;
	let current: {
		id: number;
		destruction: DeferredDestruction;
		windowMs: number;
		remainingMs: number;
		startedAt: number;
		paused: boolean;
		timer: TimerHandle | null;
		settled: boolean;
	} | null = null;

	function publish(): void {
		deps.onChange(
			current === null
				? null
				: {
						id: current.id,
						message: current.destruction.message,
						windowMs: current.windowMs,
						paused: current.paused,
					},
		);
	}

	function disarm(): void {
		if (current?.timer != null) {
			deps.clearTimer(current.timer);
			current.timer = null;
		}
	}

	function arm(): void {
		if (current === null || current.windowMs <= 0) return;
		current.startedAt = deps.now();
		current.timer = deps.setTimer(() => void flush(), current.remainingMs);
	}

	/// Detaches the pending entry so a concurrent flush/undo/defer can't
	/// act on it twice. Returns null when there was nothing pending.
	function take(): DeferredDestruction | null {
		const c = current;
		if (c === null || c.settled) return null;
		c.settled = true;
		disarm();
		current = null;
		publish();
		return c.destruction;
	}

	async function flush(): Promise<void> {
		const destruction = take();
		if (destruction === null) return;
		try {
			await destruction.commit();
		} catch (error) {
			destruction.restore();
			destruction.onCommitError?.(error);
		}
	}

	function defer(destruction: DeferredDestruction): void {
		void flush();
		const windowMs = Math.max(0, deps.windowMs());
		current = {
			id: nextId++,
			destruction,
			windowMs,
			remainingMs: windowMs,
			startedAt: deps.now(),
			paused: false,
			timer: null,
			settled: false,
		};
		arm();
		publish();
	}

	function undo(): void {
		const destruction = take();
		if (destruction === null) return;
		destruction.restore();
	}

	function pause(): void {
		const c = current;
		if (c === null || c.paused || c.windowMs <= 0) return;
		const elapsed = deps.now() - c.startedAt;
		c.remainingMs = Math.max(0, c.remainingMs - elapsed);
		disarm();
		c.paused = true;
		publish();
	}

	function resume(): void {
		const c = current;
		if (c === null || !c.paused || c.windowMs <= 0) return;
		c.paused = false;
		arm();
		publish();
	}

	return { defer, undo, flush, pause, resume, hasPending: () => current !== null };
}
