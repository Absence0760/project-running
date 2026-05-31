// Decides which polyline a route-builder save should persist into
// `routes.waypoints`. The builder tracks two distinct arrays:
//
//   * `clicks`  — the 2-10 waypoints the user dropped on the map. Sparse.
//   * `coords`  — the OSRM-snapped polyline returned by Calculate Route.
//                 Dense (often 100+ points). [lng, lat] tuples.
//
// Persisting the click points instead of the snapped polyline was a
// long-standing bug: list-card thumbnails (TrackPreview) rendered the
// route as a near-straight line between dots, and the route detail map
// had nothing real to draw. Imported GPX routes already saved the
// dense polyline; this brings builder routes into parity.
//
// We fall back to the click points only when Calculate Route wasn't
// run (defensive — the Save button is gated on `routed`, so this
// branch shouldn't hit in normal use).
export function pickSavePolyline(
	clicks: { lat: number; lng: number }[],
	coords: [number, number][],
): { lat: number; lng: number }[] {
	if (coords.length >= 2) {
		return coords.map(([lng, lat]) => ({ lat, lng }));
	}
	return clicks;
}
