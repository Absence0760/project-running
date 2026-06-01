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
	distance: number;
	movingTime: number;
	elevation: number;
	avgHr: number;
	media: number;
}

export function indexHeader(header: string[]): HeaderIndex {
	const find = (...names: string[]) => {
		for (const n of names) {
			const i = header.findIndex((h) => h.trim().toLowerCase() === n.toLowerCase());
			if (i >= 0) return i;
		}
		return -1;
	};
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
		distance: find('Distance', 'Distance (km)'),
		movingTime: find('Moving Time', 'Moving Time (seconds)'),
		elevation: find('Elevation Gain', 'Elevation Gain (m)'),
		avgHr: find('Average Heart Rate'),
		media: find('Media'),
	};
}
