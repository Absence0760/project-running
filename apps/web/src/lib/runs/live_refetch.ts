/// Coalescing refetcher for a high-cadence live-subscription handler.
///
/// The race spectator page (`/live/event/[id]/[instance]`) subscribes to
/// INSERTs on `race_pings` filtered only by event + instance, so its handler
/// fires once per ping from EVERY runner — ~N pings every 5 s for an N-runner
/// field. Each fire used to launch a fresh `select('*').limit(1000)` + a
/// leaderboard RPC and unconditionally reassign state, so the work was O(N)
/// per ping and O(N^2) as the field grew, and out-of-order promise resolution
/// could overwrite fresh state with a stale snapshot (the board flickered
/// backward).
///
/// This wraps the fetch behind three guards so a burst of pings costs one
/// refetch pair and can never regress the applied state:
///   - a trailing-edge debounce coalesces a burst into ONE fetch;
///   - an in-flight guard never stacks a second concurrent fetch — a trigger
///     that arrives mid-fetch marks a single owed re-run instead;
///   - a monotonic sequence number gates `apply`, so a slower earlier fetch
///     resolving after a newer one is discarded rather than applied.
///
/// Pure and framework-free (no Svelte runes) so it is unit-testable with
/// `npx tsx --test`; the reactive `$state` assignment stays in the `.svelte`
/// caller's `apply` callback. Web-only — the live spectator surface is web +
/// the recording clients, no Dart parity twin.

export const DEFAULT_REFETCH_DEBOUNCE_MS = 750;

export interface CoalescingRefetcherOptions<T> {
	/// The (potentially expensive) fetch to coalesce. Re-invoked at most once
	/// per debounce window, and never concurrently with itself.
	fetch: () => Promise<T>;
	/// Applies a fetched result to state. Called only for the newest fetch
	/// that has started — a stale resolution never reaches it.
	apply: (value: T) => void;
	/// Handles a rejected fetch. Called only for the newest fetch, so a stale
	/// rejection can't surface over a fresher success. Layered-resilience
	/// contract: keep this side-effect-only (log) so a failed background
	/// refetch never blanks the last good snapshot.
	onError?: (err: unknown) => void;
	debounceMs?: number;
	/// Timer seam so tests can drive the debounce deterministically.
	setTimeoutFn?: (fn: () => void, ms: number) => ReturnType<typeof setTimeout>;
	clearTimeoutFn?: (handle: ReturnType<typeof setTimeout>) => void;
}

export class CoalescingRefetcher<T> {
	readonly #fetch: () => Promise<T>;
	readonly #apply: (value: T) => void;
	readonly #onError?: (err: unknown) => void;
	readonly #debounceMs: number;
	readonly #setTimeout: (fn: () => void, ms: number) => ReturnType<typeof setTimeout>;
	readonly #clearTimeout: (handle: ReturnType<typeof setTimeout>) => void;

	#timer: ReturnType<typeof setTimeout> | null = null;
	#running = false;
	#pending = false;
	#latestSeq = 0;

	constructor(opts: CoalescingRefetcherOptions<T>) {
		this.#fetch = opts.fetch;
		this.#apply = opts.apply;
		this.#onError = opts.onError;
		this.#debounceMs = opts.debounceMs ?? DEFAULT_REFETCH_DEBOUNCE_MS;
		this.#setTimeout = opts.setTimeoutFn ?? ((fn, ms) => setTimeout(fn, ms));
		this.#clearTimeout = opts.clearTimeoutFn ?? ((h) => clearTimeout(h));
	}

	/// Schedule a trailing-edge coalesced refetch. Any number of calls inside
	/// one debounce window collapse to a single fetch.
	trigger(): void {
		if (this.#timer !== null) this.#clearTimeout(this.#timer);
		this.#timer = this.#setTimeout(() => {
			this.#timer = null;
			void this.#flush();
		}, this.#debounceMs);
	}

	async #flush(): Promise<void> {
		if (this.#running) {
			this.#pending = true;
			return;
		}
		await this.runNow();
		if (this.#pending) {
			this.#pending = false;
			await this.#flush();
		}
	}

	/// Run the fetch now, bypassing the debounce. Tags the run with a
	/// monotonic sequence so a resolution from a superseded fetch is
	/// discarded — the sequence guard is exercised directly by tests under
	/// forced concurrency, and is the last line of defence even if the
	/// in-flight guard is ever bypassed.
	async runNow(): Promise<void> {
		this.#running = true;
		const seq = ++this.#latestSeq;
		try {
			const value = await this.#fetch();
			if (seq === this.#latestSeq) this.#apply(value);
		} catch (err) {
			if (seq === this.#latestSeq) this.#onError?.(err);
		} finally {
			// Only the newest in-flight fetch clears the latch, so an earlier
			// out-of-order resolution can't reopen it under a newer one.
			if (seq === this.#latestSeq) this.#running = false;
		}
	}

	/// Cancel any scheduled refetch. Call on teardown.
	dispose(): void {
		if (this.#timer !== null) this.#clearTimeout(this.#timer);
		this.#timer = null;
	}
}
