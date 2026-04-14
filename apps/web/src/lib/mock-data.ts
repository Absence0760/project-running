import type { Run, Route, RunSource } from './types';

// --- Runs ---

function makeRun(overrides: Partial<Run> & { started_at: string; duration_s: number; distance_m: number; source: RunSource }): Run {
	return {
		id: crypto.randomUUID(),
		user_id: 'mock-user',
		track: null,
		track_url: null,
		route_id: null,
		external_id: null,
		is_public: false,
		metadata: null,
		created_at: overrides.started_at,
		updated_at: overrides.started_at,
		...overrides,
	};
}

export const mockRuns: Run[] = [
	makeRun({ started_at: '2026-04-05T07:30:00Z', duration_s: 1620, distance_m: 5120, source: 'app' }),
	makeRun({ started_at: '2026-04-03T06:45:00Z', duration_s: 2940, distance_m: 10030, source: 'app' }),
	makeRun({ started_at: '2026-04-01T18:00:00Z', duration_s: 1505, distance_m: 5000, source: 'parkrun', metadata: { event: 'Richmond', position: 42, age_grade: '54.23%' } }),
	makeRun({ started_at: '2026-03-30T07:00:00Z', duration_s: 3780, distance_m: 12500, source: 'strava' }),
	makeRun({ started_at: '2026-03-28T17:30:00Z', duration_s: 1680, distance_m: 5200, source: 'app' }),
	makeRun({ started_at: '2026-03-26T06:30:00Z', duration_s: 5460, distance_m: 21100, source: 'strava' }),
	makeRun({ started_at: '2026-03-25T07:15:00Z', duration_s: 1500, distance_m: 5000, source: 'parkrun', metadata: { event: 'Bushy Park', position: 38, age_grade: '55.10%' } }),
	makeRun({ started_at: '2026-03-23T06:00:00Z', duration_s: 2700, distance_m: 8800, source: 'app' }),
	makeRun({ started_at: '2026-03-21T07:00:00Z', duration_s: 1860, distance_m: 6100, source: 'healthkit' }),
	makeRun({ started_at: '2026-03-19T18:15:00Z', duration_s: 2400, distance_m: 7600, source: 'app' }),
	makeRun({ started_at: '2026-03-17T06:45:00Z', duration_s: 3300, distance_m: 10100, source: 'strava' }),
	makeRun({ started_at: '2026-03-15T07:30:00Z', duration_s: 1560, distance_m: 5000, source: 'parkrun', metadata: { event: 'Richmond', position: 45, age_grade: '53.80%' } }),
];

// --- Routes ---

function makeRoute(overrides: Partial<Route> & { name: string; distance_m: number }): Route {
	return {
		id: crypto.randomUUID(),
		user_id: 'mock-user',
		waypoints: [],
		elevation_m: null,
		surface: 'road',
		is_public: false,
		slug: null,
		created_at: '2026-03-01T00:00:00Z',
		updated_at: '2026-03-01T00:00:00Z',
		...overrides,
	};
}

export const mockRoutes: Route[] = [
	makeRoute({ name: 'Richmond Park Loop', distance_m: 10200, elevation_m: 85, surface: 'trail' }),
	makeRoute({ name: 'Thames Path 5K', distance_m: 5000, elevation_m: 12 }),
	makeRoute({ name: 'Battersea Park Out & Back', distance_m: 7800, elevation_m: 20 }),
	makeRoute({ name: 'Sunday Long Run', distance_m: 21100, elevation_m: 140, surface: 'mixed' }),
	makeRoute({ name: 'Commute Run', distance_m: 6400, elevation_m: 35 }),
];

// --- Weekly mileage (last 12 weeks) ---

export const mockWeeklyMileage = [
	{ week: 'Jan 27', distance_km: 22.4 },
	{ week: 'Feb 3', distance_km: 31.2 },
	{ week: 'Feb 10', distance_km: 28.5 },
	{ week: 'Feb 17', distance_km: 35.1 },
	{ week: 'Feb 24', distance_km: 18.0 },
	{ week: 'Mar 3', distance_km: 40.3 },
	{ week: 'Mar 10', distance_km: 33.7 },
	{ week: 'Mar 17', distance_km: 29.8 },
	{ week: 'Mar 24', distance_km: 45.2 },
	{ week: 'Mar 31', distance_km: 38.6 },
	{ week: 'Apr 7', distance_km: 15.2 },
];

// --- Personal records ---

export const mockPersonalRecords = [
	{ distance: '5k', time_s: 1440, date: '2026-03-15' },
	{ distance: '10k', time_s: 3060, date: '2026-03-17' },
	{ distance: 'Half Marathon', time_s: 6840, date: '2026-03-26' },
];

// --- Helpers ---

export function formatDuration(seconds: number): string {
	const h = Math.floor(seconds / 3600);
	const m = Math.floor((seconds % 3600) / 60);
	const s = seconds % 60;
	if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
	return `${m}:${String(s).padStart(2, '0')}`;
}

export function formatPace(seconds: number, metres: number): string {
	if (metres === 0) return '--:--';
	const paceSecondsPerKm = seconds / (metres / 1000);
	const m = Math.floor(paceSecondsPerKm / 60);
	const s = Math.round(paceSecondsPerKm % 60);
	return `${m}:${String(s).padStart(2, '0')}`;
}

export function formatDistance(metres: number): string {
	if (metres >= 1000) return `${(metres / 1000).toFixed(2)} km`;
	return `${Math.round(metres)} m`;
}

export function formatDate(iso: string): string {
	return new Date(iso).toLocaleDateString('en-GB', {
		day: 'numeric',
		month: 'short',
		year: 'numeric',
	});
}

export function formatDateShort(iso: string): string {
	return new Date(iso).toLocaleDateString('en-GB', {
		day: 'numeric',
		month: 'short',
	});
}

export function sourceLabel(source: RunSource): string {
	const labels: Record<RunSource, string> = {
		app: 'Recorded',
		healthkit: 'HealthKit',
		healthconnect: 'Health Connect',
		strava: 'Strava',
		garmin: 'Garmin',
		parkrun: 'parkrun',
		race: 'Race',
	};
	return labels[source];
}

export function sourceColor(source: RunSource): string {
	const colors: Record<RunSource, string> = {
		app: '#1E88E5',
		healthkit: '#E91E63',
		healthconnect: '#4CAF50',
		strava: '#FC4C02',
		garmin: '#007CC3',
		parkrun: '#D6255B',
		race: '#9C27B0',
	};
	return colors[source];
}
