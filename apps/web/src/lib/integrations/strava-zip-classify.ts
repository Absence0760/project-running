/// Classify a per-activity member of a Strava export by extension, so the
/// importer knows which parser to route it through and whether it needs
/// gunzipping first. `route` covers the gpx/tcx/kml/geojson/json family
/// (handled by `parseRouteFile`); `fit` routes through the shared
/// `garmin-fit` binary parser (persona round-5 F4). `null` means the member
/// isn't a track file we can read — the CSV row still imports trackless.
///
/// Pure (no `$app` / store imports) so it's unit-testable with raw tsx.
export function classifyStravaMember(filename: string): {
	parser: 'route' | 'fit' | null;
	gzipped: boolean;
} {
	if (/\.(gpx|tcx|kml|geojson|json)$/i.test(filename)) return { parser: 'route', gzipped: false };
	if (/\.(gpx|tcx|kml|geojson|json)\.gz$/i.test(filename))
		return { parser: 'route', gzipped: true };
	if (/\.fit$/i.test(filename)) return { parser: 'fit', gzipped: false };
	if (/\.fit\.gz$/i.test(filename)) return { parser: 'fit', gzipped: true };
	return { parser: null, gzipped: false };
}
