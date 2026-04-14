/**
 * Data access layer — all Supabase queries in one place.
 */
import { supabase } from './supabase';
import type { Run, Route, Integration } from './types';
import { auth } from './stores/auth.svelte';

// --- Runs ---

export async function fetchRuns(): Promise<Run[]> {
	const { data, error } = await supabase
		.from('runs')
		.select('*')
		.order('started_at', { ascending: false });

	if (error || !data) return [];
	return data.map((r: any) => ({ ...r, track: null }));
}

export async function fetchRunById(id: string): Promise<Run | null> {
	const { data } = await supabase
		.from('runs')
		.select('*')
		.eq('id', id)
		.single();

	if (!data) return null;

	// Lazy-load the GPS track from Storage when the run has one.
	let track = null;
	if (data.track_url) {
		try {
			track = await fetchTrack(data.track_url);
		} catch (e) {
			console.warn('Failed to fetch track', e);
		}
	}
	return { ...data, track };
}

/**
 * Download a gzipped GPS track from the `runs` Storage bucket.
 * Throws if the path is invalid or the user can't read it.
 */
async function fetchTrack(path: string) {
	const { data, error } = await supabase.storage.from('runs').download(path);
	if (error || !data) throw error ?? new Error('No data');
	const buf = await data.arrayBuffer();
	const decompressed = await decompressGzip(buf);
	const json = new TextDecoder().decode(decompressed);
	return JSON.parse(json);
}

/** Decompress a gzipped ArrayBuffer using the browser's DecompressionStream. */
async function decompressGzip(buf: ArrayBuffer): Promise<Uint8Array> {
	const ds = new (globalThis as any).DecompressionStream('gzip');
	const stream = new Response(buf).body!.pipeThrough(ds);
	const chunks: Uint8Array[] = [];
	const reader = stream.getReader();
	while (true) {
		const { done, value } = await reader.read();
		if (done) break;
		chunks.push(value as Uint8Array);
	}
	const total = chunks.reduce((a, c) => a + c.length, 0);
	const out = new Uint8Array(total);
	let offset = 0;
	for (const c of chunks) {
		out.set(c, offset);
		offset += c.length;
	}
	return out;
}

export async function fetchPublicRun(id: string): Promise<Run | null> {
	const { data } = await supabase
		.from('runs')
		.select('*')
		.eq('id', id)
		.eq('is_public', true)
		.single();

	if (!data) return null;

	let track = null;
	if (data.track_url) {
		try {
			track = await fetchTrack(data.track_url);
		} catch (e) {
			console.warn('Failed to fetch public run track', e);
		}
	}
	return { ...data, track };
}

export async function deleteRun(id: string): Promise<void> {
	// Delete the track file from Storage first (best-effort).
	const { data: run } = await supabase
		.from('runs')
		.select('track_url')
		.eq('id', id)
		.single();
	if (run?.track_url) {
		try {
			await supabase.storage.from('runs').remove([run.track_url]);
		} catch (_) {}
	}
	const { error } = await supabase.from('runs').delete().eq('id', id);
	if (error) throw error;
}

export async function makeRunPublic(id: string): Promise<void> {
	const { error } = await supabase
		.from('runs')
		.update({ is_public: true })
		.eq('id', id);
	if (error) throw error;
}

export async function updateRunMetadata(
	id: string,
	fields: { title?: string; notes?: string },
): Promise<void> {
	const { data: run } = await supabase
		.from('runs')
		.select('metadata')
		.eq('id', id)
		.single();
	if (!run) throw new Error('Run not found');
	const metadata = { ...(run.metadata as Record<string, unknown> ?? {}), ...fields };
	const { error } = await supabase
		.from('runs')
		.update({ metadata })
		.eq('id', id);
	if (error) throw error;
}

// --- Route reviews ---

export async function getRouteReviews(routeId: string) {
	const { data, error } = await supabase
		.from('route_reviews')
		.select('*')
		.eq('route_id', routeId)
		.order('created_at', { ascending: false });
	if (error) throw error;
	return data ?? [];
}

export async function upsertRouteReview(review: {
	route_id: string;
	rating: number;
	comment?: string | null;
}): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase.from('route_reviews').upsert(
		{ ...review, user_id: userId },
		{ onConflict: 'route_id,user_id' },
	);
	if (error) throw error;
}

// --- Routes ---

export async function nearbyPublicRoutes(options: {
	lat: number;
	lng: number;
	radiusM?: number;
	limit?: number;
}): Promise<Route[]> {
	const { lat, lng, radiusM = 50000, limit = 50 } = options;
	const { data, error } = await supabase.rpc('nearby_routes', {
		lat,
		lng,
		radius_m: radiusM,
		max_results: limit,
	});
	if (error || !data) return [];
	return data as Route[];
}

export async function searchPublicRoutes(options?: {
	query?: string;
	minDistanceM?: number;
	maxDistanceM?: number;
	surface?: string;
	limit?: number;
	offset?: number;
}): Promise<Route[]> {
	const { query, minDistanceM, maxDistanceM, surface, limit = 50, offset = 0 } = options ?? {};

	let q = supabase
		.from('routes')
		.select('*')
		.eq('is_public', true);

	if (query && query.trim()) {
		q = q.textSearch('name', `'${query.trim()}'`);
	}
	if (minDistanceM != null) {
		q = q.gte('distance_m', minDistanceM);
	}
	if (maxDistanceM != null) {
		q = q.lte('distance_m', maxDistanceM);
	}
	if (surface) {
		q = q.eq('surface', surface);
	}

	const { data, error } = await q
		.order('created_at', { ascending: false })
		.range(offset, offset + limit - 1);

	if (error || !data) return [];
	return data;
}

export async function fetchRoutes(): Promise<Route[]> {
	const { data, error } = await supabase
		.from('routes')
		.select('*')
		.order('created_at', { ascending: false });

	if (error || !data) return [];
	return data;
}

export async function fetchRouteById(id: string): Promise<Route | null> {
	const { data } = await supabase
		.from('routes')
		.select('*')
		.eq('id', id)
		.single();

	if (data) return data;
	return null;
}

export async function fetchPublicRoute(id: string): Promise<Route | null> {
	const { data } = await supabase
		.from('routes')
		.select('*')
		.eq('id', id)
		.eq('is_public', true)
		.single();

	return data;
}

export async function saveRoute(route: {
	name: string;
	waypoints: { lat: number; lng: number }[];
	distance_m: number;
	elevation_m: number | null;
	surface: 'road' | 'trail' | 'mixed';
	is_public: boolean;
}): Promise<Route> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const { data, error } = await supabase
		.from('routes')
		.insert({
			user_id: userId,
			name: route.name,
			waypoints: route.waypoints,
			distance_m: route.distance_m,
			elevation_m: route.elevation_m,
			surface: route.surface,
			is_public: route.is_public,
		})
		.select()
		.single();

	if (error) throw error;
	return data;
}

export async function deleteRoute(id: string): Promise<void> {
	const { error } = await supabase.from('routes').delete().eq('id', id);
	if (error) throw error;
}

// --- Dashboard stats ---

export async function fetchWeeklyMileage() {
	// Try to compute from real runs
	const { data: runs } = await supabase
		.from('runs')
		.select('started_at, distance_m')
		.order('started_at', { ascending: true });

	if (!runs || runs.length === 0) return [];

	// Group by ISO week
	const weeks = new Map<string, number>();
	for (const run of runs) {
		const d = new Date(run.started_at);
		const weekStart = new Date(d);
		weekStart.setDate(d.getDate() - d.getDay());
		const key = weekStart.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
		weeks.set(key, (weeks.get(key) ?? 0) + run.distance_m / 1000);
	}

	return Array.from(weeks.entries())
		.slice(-12)
		.map(([week, distance_km]) => ({ week, distance_km: Math.round(distance_km * 10) / 10 }));
}

export async function fetchPersonalRecords() {
	const { data: runs } = await supabase
		.from('runs')
		.select('started_at, duration_s, distance_m')
		.order('started_at', { ascending: false });

	if (!runs || runs.length === 0) return [];

	const distances = [
		{ label: '5k', target: 5000, tolerance: 200 },
		{ label: '10k', target: 10000, tolerance: 500 },
		{ label: 'Half Marathon', target: 21097, tolerance: 500 },
		{ label: 'Marathon', target: 42195, tolerance: 1000 },
	];

	const records: { distance: string; time_s: number; date: string }[] = [];

	for (const d of distances) {
		const qualifying = runs.filter(
			(r) => r.distance_m >= d.target - d.tolerance && r.distance_m <= d.target + d.tolerance
		);
		if (qualifying.length > 0) {
			const best = qualifying.reduce((a, b) => (a.duration_s < b.duration_s ? a : b));
			records.push({
				distance: d.label,
				time_s: best.duration_s,
				date: best.started_at.slice(0, 10),
			});
		}
	}

	return records;
}

// --- Integrations ---

export async function fetchIntegrations(): Promise<Integration[]> {
	const userId = auth.user?.id;
	if (!userId) return [];

	const { data } = await supabase
		.from('integrations')
		.select('*')
		.eq('user_id', userId);

	return data ?? [];
}

export async function connectIntegration(provider: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const { error } = await supabase.from('integrations').upsert(
		{ user_id: userId, provider },
		{ onConflict: 'user_id,provider' }
	);
	if (error) throw error;
}

export async function disconnectIntegration(provider: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const { error } = await supabase
		.from('integrations')
		.delete()
		.eq('user_id', userId)
		.eq('provider', provider);
	if (error) throw error;
}
