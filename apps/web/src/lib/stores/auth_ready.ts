/**
 * Pure, rune-free core for the auth store's `ready()` primitive.
 *
 * The auth store can't await its own reactive `$state` from a plain
 * function, and the recurring "auth-race" bug (a page's onMount fetched
 * before `auth.user` resolved) was papered over on many pages with a
 * copy-pasted bounded poll loop. This module is the durable
 * replacement: a tiny resolver registry the store drives from its
 * existing Supabase lifecycle hooks, plus a bounded timeout so a caller
 * can never hang if settlement somehow never fires.
 *
 * Kept here (no `$state`) so it is `tsx --test`-runnable — see
 * auth_ready.test.ts. The reactive wiring stays in auth.svelte.ts.
 */

/// Has auth reached a terminal state for the purposes of an
/// owner-gated fetch? Settled means the initial session check finished
/// AND either a user row resolved or the session is definitively anon.
/// Mirrors the `!(auth.loading || !auth.user)` exit condition of the
/// old poll, but also treats a definitively-anon session as settled so
/// anon pages don't wait the full timeout.
export function isAuthSettled(state: {
	loading: boolean;
	user: unknown;
	loggedIn: boolean;
}): boolean {
	if (state.loading) return false;
	if (state.user != null) return true;
	// loading === false && no user: only settled once we also know the
	// session is anon (loggedIn === false). A logged-in session whose
	// profile fetch is still in flight is NOT settled yet.
	return !state.loggedIn;
}

/// A resolver registry the auth store drives. `markSettled()` flushes
/// every pending `ready()` waiter exactly once per settle; new waiters
/// after a settle resolve immediately (the gate re-checks `isSettled`).
/// The timeout is a safety net: if settlement never fires (e.g. a wedged
/// network during the initial session check), a waiter still resolves
/// rather than hanging the page forever — the same bound the old poll
/// loops gave (~1–3 s).
export function createReadyGate(opts: {
	isSettled: () => boolean;
	timeoutMs: number;
	setTimeoutFn?: (cb: () => void, ms: number) => unknown;
}) {
	const setTimeoutFn = opts.setTimeoutFn ?? ((cb, ms) => setTimeout(cb, ms));
	let waiters: Array<() => void> = [];
	/// Bumped by every auth lifecycle event that fires while still
	/// unsettled (e.g. the session check landed but the profile fetch is
	/// in flight). A pending waiter whose timeout fires re-arms instead
	/// of resolving when the epoch moved — so `timeoutMs` bounds a
	/// WEDGED init (no events at all), not a slow-but-progressing one.
	/// A gate that bails mid-progress hands pages an unsettled auth
	/// state their mount-time `if (auth.user)` fetch gates then treat as
	/// anon forever (the recurring CI flake class, e.g. run 28689014328).
	let progressEpoch = 0;

	function flush() {
		if (waiters.length === 0) return;
		const pending = waiters;
		waiters = [];
		for (const resolve of pending) resolve();
	}

	/// Called by the store after any state mutation that might have
	/// reached a settled state. Re-checks `isSettled` so callers can fire
	/// it liberally from every lifecycle hook without having to prove
	/// settlement at the call site — only a genuinely-settled state
	/// flushes waiters.
	function markSettled() {
		if (opts.isSettled()) {
			flush();
			return;
		}
		progressEpoch++;
	}

	function ready(): Promise<void> {
		if (opts.isSettled()) return Promise.resolve();
		return new Promise<void>((resolve) => {
			waiters.push(resolve);
			const arm = () => {
				const armedAt = progressEpoch;
				setTimeoutFn(() => {
					// Already flushed by a genuine settle — nothing to do.
					const idx = waiters.indexOf(resolve);
					if (idx === -1) return;
					// Lifecycle progress since this timer was armed —
					// extend the deadline instead of bailing unsettled.
					if (progressEpoch !== armedAt) {
						arm();
						return;
					}
					waiters.splice(idx, 1);
					resolve();
				}, opts.timeoutMs);
			};
			arm();
		});
	}

	return { ready, markSettled };
}
