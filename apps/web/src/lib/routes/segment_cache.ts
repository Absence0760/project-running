/**
 * Per-segment routing cache for the route builder's incremental
 * auto-routing. Kept in its own module (no `$app` / `$env` imports) so
 * the pure logic is node:test-runnable — see segment_cache.test.ts.
 */

/**
 * Stable cache key for a routed segment. Order-sensitive (A→B is not
 * the same as B→A — OSRM can return asymmetric geometry on one-way
 * streets) and profile-scoped. Coordinates are matched exactly, not
 * rounded: a dragged waypoint produces different coords → a different
 * key → a cache miss → a re-fetch, which is exactly the invalidation
 * we want for the two segments adjacent to the moved pin.
 */
export function segmentCacheKey(
	from: { lng: number; lat: number },
	to: { lng: number; lat: number },
	profile: 'foot' | 'car' = 'foot',
): string {
	return `${profile}|${from.lng},${from.lat}|${to.lng},${to.lat}`;
}

export interface CachedSegment {
	polyline: [number, number][];
	distanceM: number;
}

/**
 * Bounded, recency-ordered cache of successfully-routed segments. The
 * route builder holds one instance across a planning session so that
 * re-routing after each waypoint placement costs O(1) OSRM calls (just
 * the one new segment) instead of O(n) — this is what lets a 100-point
 * route stay responsive instead of re-running every segment on every
 * click.
 *
 * Only *successful* segments are cached. A straight-line fallback from
 * a transient OSRM hiccup must be re-tried on the next pass, never
 * pinned — caching it would freeze a wrong line in place after the
 * service recovered.
 */
export class SegmentCache {
	private readonly entries = new Map<string, CachedSegment>();

	constructor(private readonly maxEntries = 2000) {}

	get(key: string): CachedSegment | undefined {
		const hit = this.entries.get(key);
		// Re-insert to mark most-recently-used (Map preserves insertion
		// order, so the first key is the oldest — see set()'s eviction).
		if (hit) {
			this.entries.delete(key);
			this.entries.set(key, hit);
		}
		return hit;
	}

	set(key: string, value: CachedSegment): void {
		this.entries.delete(key);
		this.entries.set(key, value);
		if (this.entries.size > this.maxEntries) {
			const oldest = this.entries.keys().next().value;
			if (oldest !== undefined) this.entries.delete(oldest);
		}
	}

	clear(): void {
		this.entries.clear();
	}

	get size(): number {
		return this.entries.size;
	}
}
