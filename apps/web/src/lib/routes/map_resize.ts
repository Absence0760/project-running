// Shared `map.resize()` wiring for every MapLibre mount on the site.
//
// MapLibre reads the container's bounding rect at construction time
// and never re-checks unless `.resize()` is called. Two real failure
// modes the audit caught:
//
//   1. **Initial-mount mismeasurement.** A flexbox layout (or any
//      `flex: 1` container) doesn't always have its final dimensions
//      synchronously — the map gets a stale rect at mount time and
//      the right edge stays clipped until the user pokes the layout
//      (e.g. drags a SplitPane). This is reproducible on
//      `/routes/new` even with no resizer in the page.
//
//   2. **SplitPane drag mid-session.** When the user drags the split
//      handle, the map container's width changes pixel-by-pixel.
//      Without a `.resize()` per frame the map renders at the OLD
//      size + lets the new pixels show as background bleed.
//
// Both are covered by a single `ResizeObserver` per mount: any size
// change of the container fires `map.resize()`. Caller gets back a
// disposer to wire into `onDestroy`.

import type maplibregl from 'maplibre-gl';

/// Attach a ResizeObserver to [container] that calls
/// `map.resize()` on every dimension change. Returns a disposer
/// the caller must invoke in `onDestroy` (otherwise the observer
/// keeps the map reference alive past the component lifecycle and
/// `map.resize()` fires on a removed map, which throws inside
/// MapLibre's internals).
///
/// **Initial-resize:** the first observation fires synchronously
/// once the observer starts watching, so callers don't need to
/// call `map.resize()` manually after mount.
export function watchMapResize(
	container: HTMLElement,
	map: maplibregl.Map,
): () => void {
	// SSR safety: ResizeObserver isn't defined during prerender.
	// Caller usually guards via `if (typeof window === 'undefined')
	// return` already, but a defensive bail keeps the helper
	// callable from contexts that don't.
	if (typeof ResizeObserver === 'undefined') return () => {};

	const ro = new ResizeObserver(() => {
		// Defensive: if the map has been removed between the
		// observation firing and the callback running, `resize()`
		// throws. The destroyed check uses MapLibre's documented
		// `_removed` flag — undocumented but stable since v3.
		const removed = (map as unknown as { _removed?: boolean })._removed;
		if (removed) return;
		map.resize();
	});
	ro.observe(container);
	return () => ro.disconnect();
}
