/**
 * Data access layer — all Supabase queries in one place.
 * Falls back to mock data when Supabase returns nothing (e.g. empty tables).
 */
import { supabase } from './supabase';
import { mockRuns, mockRoutes, mockWeeklyMileage, mockPersonalRecords } from './mock-data';
import type { Run, Route, Integration } from './types';
import { auth } from './stores/auth.svelte';

// --- Runs ---

export async function fetchRuns(): Promise<Run[]> {
	const { data, error } = await supabase
		.from('runs')
		.select('*')
		.order('started_at', { ascending: false });

	if (error || !data || data.length === 0) return mockRuns;
	return data;
}

export async function fetchRunById(id: string): Promise<Run | null> {
	const { data } = await supabase
		.from('runs')
		.select('*')
		.eq('id', id)
		.single();

	if (data) return data;
	// Fall back to mock
	return mockRuns.find((r) => r.id === id) ?? mockRuns[0];
}

// --- Routes ---

export async function fetchRoutes(): Promise<Route[]> {
	const { data, error } = await supabase
		.from('routes')
		.select('*')
		.order('created_at', { ascending: false });

	if (error || !data || data.length === 0) return mockRoutes;
	return data;
}

export async function fetchRouteById(id: string): Promise<Route | null> {
	const { data } = await supabase
		.from('routes')
		.select('*')
		.eq('id', id)
		.single();

	if (data) return data;
	return mockRoutes.find((r) => r.id === id) ?? mockRoutes[0];
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

	if (!runs || runs.length === 0) return mockWeeklyMileage;

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

	if (!runs || runs.length === 0) return mockPersonalRecords;

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

	return records.length > 0 ? records : mockPersonalRecords;
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
