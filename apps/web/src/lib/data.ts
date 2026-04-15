/**
 * Data access layer — all Supabase queries in one place.
 */
import { supabase } from './supabase';
import type {
	Run,
	Route,
	Integration,
	Club,
	ClubWithMeta,
	ClubMember,
	ClubRole,
	Event,
	EventWithMeta,
	EventAttendee,
	RsvpStatus,
	ClubPost,
	ClubPostWithAuthor
} from './types';
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

// --- Clubs ---

function slugify(name: string): string {
	return name
		.toLowerCase()
		.trim()
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-|-$/g, '')
		.slice(0, 48);
}

/** Browse public clubs. Most recently created first. */
export async function browseClubs(search?: string): Promise<ClubWithMeta[]> {
	let query = supabase.from('clubs').select('*').eq('is_public', true);
	if (search && search.trim()) {
		const term = search.trim();
		query = query.or(`name.ilike.%${term}%,location_label.ilike.%${term}%`);
	}
	const { data } = await query.order('created_at', { ascending: false }).limit(60);
	if (!data) return [];
	return enrichClubs(data);
}

/** Clubs the current user belongs to (owner or member). */
export async function fetchMyClubs(): Promise<ClubWithMeta[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data } = await supabase
		.from('club_members')
		.select('club_id, role, clubs!inner(*)')
		.eq('user_id', userId)
		.order('joined_at', { ascending: false });
	if (!data) return [];
	const clubs = data.map((row: any) => row.clubs).filter(Boolean);
	return enrichClubs(clubs);
}

export async function fetchClubBySlug(slug: string): Promise<ClubWithMeta | null> {
	const { data } = await supabase.from('clubs').select('*').eq('slug', slug).maybeSingle();
	if (!data) return null;
	const [enriched] = await enrichClubs([data]);
	return enriched;
}

/** Attach member_count + viewer_role to an array of clubs in a small number of queries. */
async function enrichClubs(clubs: Club[]): Promise<ClubWithMeta[]> {
	if (clubs.length === 0) return [];
	const ids = clubs.map((c) => c.id);
	const userId = auth.user?.id;

	const [countsRes, rolesRes] = await Promise.all([
		supabase.from('club_members').select('club_id', { count: 'exact' }).in('club_id', ids),
		userId
			? supabase
					.from('club_members')
					.select('club_id, role')
					.in('club_id', ids)
					.eq('user_id', userId)
			: Promise.resolve({ data: [] as { club_id: string; role: string }[] })
	]);

	const counts = new Map<string, number>();
	for (const row of (countsRes.data ?? []) as { club_id: string }[]) {
		counts.set(row.club_id, (counts.get(row.club_id) ?? 0) + 1);
	}
	const roles = new Map<string, ClubRole>();
	for (const row of (rolesRes.data ?? []) as { club_id: string; role: string }[]) {
		roles.set(row.club_id, row.role as ClubRole);
	}
	return clubs.map((c) => ({
		...c,
		member_count: counts.get(c.id) ?? 0,
		viewer_role: roles.get(c.id) ?? null
	}));
}

export async function createClub(input: {
	name: string;
	description?: string;
	location_label?: string;
	is_public: boolean;
}): Promise<Club> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const baseSlug = slugify(input.name) || 'club';
	let slug = baseSlug;
	// Retry with a short random suffix up to 3 times if the slug is taken —
	// simpler than a SQL trigger and acceptable for the expected volume.
	for (let attempt = 0; attempt < 4; attempt++) {
		const candidate =
			attempt === 0 ? baseSlug : `${baseSlug}-${Math.random().toString(36).slice(2, 6)}`;
		const { data, error } = await supabase
			.from('clubs')
			.insert({
				owner_id: userId,
				name: input.name.trim(),
				slug: candidate,
				description: input.description?.trim() || null,
				location_label: input.location_label?.trim() || null,
				is_public: input.is_public
			})
			.select()
			.single();
		if (!error && data) {
			slug = candidate;
			return data;
		}
		if (error && error.code !== '23505') throw error;
	}
	throw new Error(`Could not allocate a slug for "${input.name}" after 4 attempts`);
}

export async function updateClub(
	id: string,
	patch: Partial<Pick<Club, 'name' | 'description' | 'location_label' | 'is_public' | 'avatar_url'>>
): Promise<void> {
	const { error } = await supabase.from('clubs').update(patch).eq('id', id);
	if (error) throw error;
}

export async function deleteClub(id: string): Promise<void> {
	const { error } = await supabase.from('clubs').delete().eq('id', id);
	if (error) throw error;
}

export async function joinClub(clubId: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from('club_members')
		.insert({ club_id: clubId, user_id: userId, role: 'member' });
	if (error && error.code !== '23505') throw error; // already a member is fine
}

export async function leaveClub(clubId: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from('club_members')
		.delete()
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw error;
}

export async function fetchClubMembers(clubId: string): Promise<(ClubMember & {
	display_name: string | null;
	avatar_url: string | null;
})[]> {
	const { data: members } = await supabase
		.from('club_members')
		.select('*')
		.eq('club_id', clubId)
		.order('joined_at', { ascending: true });
	if (!members) return [];
	const userIds = (members as ClubMember[]).map((m) => m.user_id);
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', userIds);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profiles ?? []) byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	return (members as ClubMember[]).map((m) => ({
		...m,
		display_name: byId.get(m.user_id)?.display_name ?? null,
		avatar_url: byId.get(m.user_id)?.avatar_url ?? null
	}));
}

// --- Events ---

export async function fetchUpcomingEvents(clubId: string): Promise<EventWithMeta[]> {
	const nowIso = new Date().toISOString();
	const { data } = await supabase
		.from('events')
		.select('*')
		.eq('club_id', clubId)
		.gte('starts_at', nowIso)
		.order('starts_at', { ascending: true });
	return enrichEvents((data as Event[]) ?? []);
}

export async function fetchPastEvents(clubId: string, limit = 12): Promise<EventWithMeta[]> {
	const nowIso = new Date().toISOString();
	const { data } = await supabase
		.from('events')
		.select('*')
		.eq('club_id', clubId)
		.lt('starts_at', nowIso)
		.order('starts_at', { ascending: false })
		.limit(limit);
	return enrichEvents((data as Event[]) ?? []);
}

export async function fetchEventById(id: string): Promise<EventWithMeta | null> {
	const { data } = await supabase.from('events').select('*').eq('id', id).maybeSingle();
	if (!data) return null;
	const [enriched] = await enrichEvents([data as Event]);
	return enriched ?? null;
}

async function enrichEvents(events: Event[]): Promise<EventWithMeta[]> {
	if (events.length === 0) return [];
	const ids = events.map((e) => e.id);
	const userId = auth.user?.id;

	const [countsRes, rsvpRes] = await Promise.all([
		supabase
			.from('event_attendees')
			.select('event_id', { count: 'exact' })
			.in('event_id', ids)
			.eq('status', 'going'),
		userId
			? supabase
					.from('event_attendees')
					.select('event_id, status')
					.in('event_id', ids)
					.eq('user_id', userId)
			: Promise.resolve({ data: [] as { event_id: string; status: string }[] })
	]);

	const counts = new Map<string, number>();
	for (const row of (countsRes.data ?? []) as { event_id: string }[]) {
		counts.set(row.event_id, (counts.get(row.event_id) ?? 0) + 1);
	}
	const rsvps = new Map<string, RsvpStatus>();
	for (const row of (rsvpRes.data ?? []) as { event_id: string; status: string }[]) {
		rsvps.set(row.event_id, row.status as RsvpStatus);
	}
	return events.map((e) => ({
		...e,
		attendee_count: counts.get(e.id) ?? 0,
		viewer_rsvp: rsvps.get(e.id) ?? null
	}));
}

export async function createEvent(input: {
	club_id: string;
	title: string;
	description?: string;
	starts_at: string; // ISO
	duration_min?: number;
	meet_label?: string;
	meet_lat?: number;
	meet_lng?: number;
	route_id?: string | null;
	distance_m?: number;
	pace_target_sec?: number;
	capacity?: number;
}): Promise<Event> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('events')
		.insert({
			club_id: input.club_id,
			title: input.title.trim(),
			description: input.description?.trim() || null,
			starts_at: input.starts_at,
			duration_min: input.duration_min ?? null,
			meet_label: input.meet_label?.trim() || null,
			meet_lat: input.meet_lat ?? null,
			meet_lng: input.meet_lng ?? null,
			route_id: input.route_id ?? null,
			distance_m: input.distance_m ?? null,
			pace_target_sec: input.pace_target_sec ?? null,
			capacity: input.capacity ?? null,
			created_by: userId
		})
		.select()
		.single();
	if (error) throw error;
	return data as Event;
}

export async function deleteEvent(id: string): Promise<void> {
	const { error } = await supabase.from('events').delete().eq('id', id);
	if (error) throw error;
}

export async function rsvpEvent(eventId: string, status: RsvpStatus): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from('event_attendees')
		.upsert(
			{ event_id: eventId, user_id: userId, status },
			{ onConflict: 'event_id,user_id' }
		);
	if (error) throw error;
}

export async function clearRsvp(eventId: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from('event_attendees')
		.delete()
		.eq('event_id', eventId)
		.eq('user_id', userId);
	if (error) throw error;
}

export async function fetchEventAttendees(eventId: string): Promise<(EventAttendee & {
	display_name: string | null;
	avatar_url: string | null;
})[]> {
	const { data: attendees } = await supabase
		.from('event_attendees')
		.select('*')
		.eq('event_id', eventId)
		.order('joined_at', { ascending: true });
	if (!attendees) return [];
	const userIds = (attendees as EventAttendee[]).map((a) => a.user_id);
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', userIds);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profiles ?? []) byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	return (attendees as EventAttendee[]).map((a) => ({
		...a,
		display_name: byId.get(a.user_id)?.display_name ?? null,
		avatar_url: byId.get(a.user_id)?.avatar_url ?? null
	}));
}

// --- Club posts (owner updates) ---

export async function fetchClubPosts(
	clubId: string,
	limit = 20
): Promise<ClubPostWithAuthor[]> {
	const { data: posts } = await supabase
		.from('club_posts')
		.select('*')
		.eq('club_id', clubId)
		.order('created_at', { ascending: false })
		.limit(limit);
	if (!posts) return [];
	const authorIds = Array.from(new Set((posts as ClubPost[]).map((p) => p.author_id)));
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', authorIds);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profiles ?? []) byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	return (posts as ClubPost[]).map((post) => ({
		...post,
		author_display_name: byId.get(post.author_id)?.display_name ?? null,
		author_avatar_url: byId.get(post.author_id)?.avatar_url ?? null
	}));
}

export async function createClubPost(input: {
	club_id: string;
	body: string;
	event_id?: string | null;
}): Promise<ClubPost> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('club_posts')
		.insert({
			club_id: input.club_id,
			event_id: input.event_id ?? null,
			author_id: userId,
			body: input.body.trim()
		})
		.select()
		.single();
	if (error) throw error;
	return data as ClubPost;
}

export async function deleteClubPost(id: string): Promise<void> {
	const { error } = await supabase.from('club_posts').delete().eq('id', id);
	if (error) throw error;
}
