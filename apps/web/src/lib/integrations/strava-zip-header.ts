// Pure header-mapping for the Strava bulk-export `activities.csv`.
// Extracted from strava-zip.ts so it can be unit-tested without dragging
// in the supabase / $env import chain (same reason strava-zip-classify.ts
// and strava-zip-dedupe.ts are standalone).

export interface HeaderIndex {
	id: number;
	name: number;
	type: number;
	stravaType: number;
	date: number;
	filename: number;
	// Display-unit "Distance" column (summary block). Its unit follows the
	// athlete's measurement preference at export time — km OR miles. Used as
	// a fallback only; prefer `distanceMetres` when present.
	distance: number;
	// Raw-block "Distance" column (the SECOND `Distance`, ~col 18) which
	// Strava always emits in metres regardless of the athlete's unit pref.
	// -1 when the export carries only the single display-unit column.
	distanceMetres: number;
	// True only when the chosen `distance` column's header explicitly names
	// miles. Bare "Distance" is assumed km (legacy behaviour).
	distanceIsMiles: boolean;
	movingTime: number;
	// "Elevation Gain" only ever appears in the raw SI block, so it is always
	// metres — there is no imperial elevation column to branch on.
	elevation: number;
	avgHr: number;
	media: number;
}

const MILES_TO_METRES = 1609.344;

// Strava's `activities.csv` has TWO numeric blocks. The first (summary) block
// carries a "Distance" in the athlete's DISPLAY unit — km for a metric athlete,
// miles for an imperial one — a documented Strava export quirk. The second
// (raw) block repeats "Distance" in SI metres. Detecting the second column
// lets us import the true metric distance without guessing the athlete's unit.
export function indexHeader(header: string[]): HeaderIndex {
	const norm = header.map((h) => h.trim().toLowerCase());
	const find = (...names: string[]) => {
		for (const n of names) {
			const i = norm.indexOf(n.toLowerCase());
			if (i >= 0) return i;
		}
		return -1;
	};

	const plainDistance: number[] = [];
	norm.forEach((h, i) => {
		if (h === 'distance') plainDistance.push(i);
	});

	let distance = -1;
	let distanceMetres = -1;
	let distanceIsMiles = false;
	if (plainDistance.length >= 2) {
		distance = plainDistance[0];
		distanceMetres = plainDistance[1];
	} else {
		const metresIdx = find('distance (m)', 'distance in meters', 'distance in metres');
		if (metresIdx >= 0) distanceMetres = metresIdx;
		if (plainDistance.length === 1) {
			distance = plainDistance[0];
		} else {
			const kmIdx = find('distance (km)', 'distance in kilometers', 'distance in kilometres');
			const miIdx = find('distance (mi)', 'distance in miles');
			if (kmIdx >= 0) {
				distance = kmIdx;
			} else if (miIdx >= 0) {
				distance = miIdx;
				distanceIsMiles = true;
			}
		}
	}

	return {
		id: find('Activity ID'),
		name: find('Activity Name'),
		type: find('Activity Type'),
		// Prefer Strava's finer-grained "Sport Type" (TrailRun, VirtualRun,
		// etc.) for provenance, falling back to the coarse "Activity Type"
		// on legacy exports that predate the Sport Type column. `type` above
		// stays coarse — it only drives run/walk/hike classification.
		stravaType: find('Sport Type', 'Activity Type'),
		date: find('Activity Date'),
		filename: find('Filename'),
		distance,
		distanceMetres,
		distanceIsMiles,
		movingTime: find('Moving Time', 'Moving Time (seconds)'),
		elevation: find('Elevation Gain', 'Elevation Gain (m)'),
		avgHr: find('Average Heart Rate'),
		media: find('Media'),
	};
}

// Resolve a row's distance to metres. Prefers the always-metric raw-block
// column so an imperial athlete's export imports the correct distance;
// falls back to the display-unit column (miles→metres or the legacy
// km-assumption) only when the raw column is absent.
export function stravaDistanceMetres(row: string[], idx: HeaderIndex): number {
	const parse = (s: string | undefined): number => {
		if (!s) return 0;
		const n = parseFloat(String(s).replace(/,/g, ''));
		return Number.isFinite(n) ? n : 0;
	};
	if (idx.distanceMetres >= 0) return parse(row[idx.distanceMetres]);
	if (idx.distance < 0) return 0;
	return parse(row[idx.distance]) * (idx.distanceIsMiles ? MILES_TO_METRES : 1000);
}
