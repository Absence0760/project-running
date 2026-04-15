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
	MembershipStatus,
	JoinPolicy,
	Event,
	EventWithMeta,
	EventAttendee,
	RsvpStatus,
	ClubPost,
	ClubPostWithAuthor,
	RecurrenceFreq,
	Weekday,
	TrainingPlan,
	PlanWeek,
	PlanWorkout,
	ActivePlanOverview,
	PlanStatus
} from './types';
import type { GeneratedPlan, GoalEvent } from './training';
import { auth } from './stores/auth.svelte';
import { nextInstanceAfter } from './recurrence';

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

/** Attach member_count + viewer_role + viewer_status to clubs in two queries. */
async function enrichClubs(clubs: Club[]): Promise<ClubWithMeta[]> {
	if (clubs.length === 0) return [];
	const ids = clubs.map((c) => c.id);
	const userId = auth.user?.id;

	const [countsRes, rolesRes] = await Promise.all([
		supabase
			.from('club_members')
			.select('club_id', { count: 'exact' })
			.in('club_id', ids)
			.eq('status', 'active'),
		userId
			? supabase
					.from('club_members')
					.select('club_id, role, status')
					.in('club_id', ids)
					.eq('user_id', userId)
			: Promise.resolve({ data: [] as { club_id: string; role: string; status: string }[] })
	]);

	const counts = new Map<string, number>();
	for (const row of (countsRes.data ?? []) as { club_id: string }[]) {
		counts.set(row.club_id, (counts.get(row.club_id) ?? 0) + 1);
	}
	const roles = new Map<string, ClubRole>();
	const statuses = new Map<string, MembershipStatus>();
	for (const row of (rolesRes.data ?? []) as { club_id: string; role: string; status: string }[]) {
		if (row.status === 'active') roles.set(row.club_id, row.role as ClubRole);
		statuses.set(row.club_id, row.status as MembershipStatus);
	}
	return clubs.map((c) => ({
		...c,
		join_policy: (c.join_policy ?? 'open') as JoinPolicy,
		member_count: counts.get(c.id) ?? 0,
		viewer_role: roles.get(c.id) ?? null,
		viewer_status: statuses.get(c.id) ?? null
	}));
}

export async function createClub(input: {
	name: string;
	description?: string;
	location_label?: string;
	is_public: boolean;
	join_policy: JoinPolicy;
}): Promise<Club> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const baseSlug = slugify(input.name) || 'club';
	const inviteToken = input.join_policy === 'invite' ? genToken() : null;
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
				is_public: input.is_public,
				join_policy: input.join_policy,
				invite_token: inviteToken
			})
			.select()
			.single();
		if (!error && data) {
			return { ...data, join_policy: (data.join_policy ?? 'open') as JoinPolicy };
		}
		if (error && error.code !== '23505') throw error;
	}
	throw new Error(`Could not allocate a slug for "${input.name}" after 4 attempts`);
}

function genToken(): string {
	const bytes = new Uint8Array(16);
	crypto.getRandomValues(bytes);
	return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export async function regenerateInviteToken(clubId: string): Promise<string> {
	const token = genToken();
	const { error } = await supabase.from('clubs').update({ invite_token: token }).eq('id', clubId);
	if (error) throw error;
	return token;
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

export async function joinClub(clubId: string, policy: JoinPolicy = 'open'): Promise<MembershipStatus> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const status: MembershipStatus = policy === 'request' ? 'pending' : 'active';
	const { error } = await supabase
		.from('club_members')
		.insert({ club_id: clubId, user_id: userId, role: 'member', status });
	if (error && error.code !== '23505') throw error;
	return status;
}

/** Redeem a shareable invite token. Returns the joined club id. */
export async function joinClubByToken(token: string): Promise<string> {
	const { data, error } = await supabase.rpc('join_club_by_token', { token });
	if (error) throw error;
	return data as string;
}

export async function fetchPendingRequests(clubId: string): Promise<(ClubMember & {
	display_name: string | null;
	avatar_url: string | null;
})[]> {
	const { data: rows } = await supabase
		.from('club_members')
		.select('*')
		.eq('club_id', clubId)
		.eq('status', 'pending')
		.order('joined_at', { ascending: true });
	if (!rows || rows.length === 0) return [];
	const userIds = (rows as ClubMember[]).map((r) => r.user_id);
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', userIds);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profiles ?? []) byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	return (rows as ClubMember[]).map((r) => ({
		...r,
		display_name: byId.get(r.user_id)?.display_name ?? null,
		avatar_url: byId.get(r.user_id)?.avatar_url ?? null
	}));
}

export async function approveMember(clubId: string, userId: string): Promise<void> {
	const { error } = await supabase
		.from('club_members')
		.update({ status: 'active' })
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw error;
}

export async function rejectMember(clubId: string, userId: string): Promise<void> {
	const { error } = await supabase
		.from('club_members')
		.delete()
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw error;
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
	// For recurring series, `starts_at` can be in the past even though the
	// next instance is in the future. Pull anything that's either (a) one-off
	// in the future OR (b) recurring with an until-date that's still ahead.
	// The client-side enrichment computes `next_instance_start` per event.
	const { data } = await supabase
		.from('events')
		.select('*')
		.eq('club_id', clubId)
		.order('starts_at', { ascending: true });
	const events = (data as Event[]) ?? [];
	const now = new Date();
	const enriched = await enrichEvents(events);
	return enriched
		.filter((e) => new Date(e.next_instance_start) >= now)
		.sort(
			(a, b) =>
				new Date(a.next_instance_start).getTime() - new Date(b.next_instance_start).getTime()
		);
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

	// Compute each event's next instance client-side so counts + RSVPs can be
	// scoped to that instance. One-off events use their starts_at verbatim.
	const nextMap = new Map<string, string>();
	for (const e of events) {
		const evt = normaliseEvent(e);
		const next = evt.recurrence_freq ? nextInstanceAfter(evt) ?? new Date(evt.starts_at) : new Date(evt.starts_at);
		nextMap.set(e.id, next.toISOString());
	}

	const ids = events.map((e) => e.id);
	const userId = auth.user?.id;

	// "Going" count on the next instance of each event.
	const countsPromise: Promise<Array<[string, number]>> = Promise.all(
		ids.map(
			(id) =>
				supabase
					.from('event_attendees')
					.select('event_id', { count: 'exact' })
					.eq('event_id', id)
					.eq('status', 'going')
					.eq('instance_start', nextMap.get(id) as string)
					.then((res) => [id, res.count ?? 0] as [string, number])
		)
	);
	const rsvpPromise: Promise<Array<[string, RsvpStatus | null]>> = userId
		? Promise.all(
				ids.map(
					(id) =>
						supabase
							.from('event_attendees')
							.select('status')
							.eq('event_id', id)
							.eq('user_id', userId)
							.eq('instance_start', nextMap.get(id) as string)
							.maybeSingle()
							.then(
								(res) => [id, (res.data?.status ?? null) as RsvpStatus | null] as [
									string,
									RsvpStatus | null
								]
						)
				)
		  )
		: Promise.resolve([] as Array<[string, RsvpStatus | null]>);

	const [countRows, rsvpRows] = await Promise.all([countsPromise, rsvpPromise]);
	const counts = new Map<string, number>(countRows);
	const rsvps = new Map<string, RsvpStatus | null>(rsvpRows);

	return events.map((e) => ({
		...normaliseEvent(e),
		attendee_count: counts.get(e.id) ?? 0,
		viewer_rsvp: rsvps.get(e.id) ?? null,
		next_instance_start: nextMap.get(e.id)!
	}));
}

/** Coerce server-side string[]/string into typed unions. */
function normaliseEvent(e: Event): Event {
	return {
		...e,
		recurrence_freq: (e.recurrence_freq ?? null) as RecurrenceFreq | null,
		recurrence_byday: (e.recurrence_byday ?? null) as Weekday[] | null
	};
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
	recurrence_freq?: RecurrenceFreq | null;
	recurrence_byday?: Weekday[] | null;
	recurrence_until?: string | null;
	recurrence_count?: number | null;
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
			recurrence_freq: input.recurrence_freq ?? null,
			recurrence_byday: input.recurrence_byday ?? null,
			recurrence_until: input.recurrence_until ?? null,
			recurrence_count: input.recurrence_count ?? null,
			created_by: userId
		})
		.select()
		.single();
	if (error) throw error;
	return normaliseEvent(data as Event);
}

export async function deleteEvent(id: string): Promise<void> {
	const { error } = await supabase.from('events').delete().eq('id', id);
	if (error) throw error;
}

export async function rsvpEvent(
	eventId: string,
	status: RsvpStatus,
	instanceStart: string
): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from('event_attendees')
		.upsert(
			{ event_id: eventId, user_id: userId, status, instance_start: instanceStart },
			{ onConflict: 'event_id,user_id,instance_start' }
		);
	if (error) throw error;
}

export async function clearRsvp(eventId: string, instanceStart: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from('event_attendees')
		.delete()
		.eq('event_id', eventId)
		.eq('user_id', userId)
		.eq('instance_start', instanceStart);
	if (error) throw error;
}

export async function fetchEventAttendees(
	eventId: string,
	instanceStart: string
): Promise<(EventAttendee & {
	display_name: string | null;
	avatar_url: string | null;
})[]> {
	const { data: attendees } = await supabase
		.from('event_attendees')
		.select('*')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
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

// --- Event results (leaderboard) ---

export interface EventResultRow {
	user_id: string;
	run_id: string | null;
	duration_s: number;
	distance_m: number;
	rank: number | null;
	finisher_status: 'finished' | 'dnf' | 'dns';
	age_grade_pct: number | null;
	note: string | null;
	created_at: string;
	organiser_approved: boolean;
	organiser_approved_by: string | null;
	organiser_approved_at: string | null;
}

export interface EventResultWithUser extends EventResultRow {
	display_name: string | null;
	avatar_url: string | null;
}

export async function fetchEventResults(
	eventId: string,
	instanceStart: string
): Promise<EventResultWithUser[]> {
	const { data: results } = await supabase
		.from('event_results')
		.select(
			'user_id, run_id, duration_s, distance_m, rank, finisher_status, age_grade_pct, note, created_at, organiser_approved, organiser_approved_by, organiser_approved_at'
		)
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.order('rank', { ascending: true, nullsFirst: false })
		.order('created_at', { ascending: true });
	if (!results) return [];
	const rows = results as EventResultRow[];
	if (rows.length === 0) return [];
	const userIds = rows.map((r) => r.user_id);
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', userIds);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profiles ?? [])
		byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	return rows.map((r) => ({
		...r,
		display_name: byId.get(r.user_id)?.display_name ?? null,
		avatar_url: byId.get(r.user_id)?.avatar_url ?? null,
	}));
}

export async function submitEventResult(params: {
	eventId: string;
	instanceStart: string;
	durationS: number;
	distanceM: number;
	runId?: string | null;
	finisherStatus?: 'finished' | 'dnf' | 'dns';
	ageGradePct?: number | null;
	note?: string | null;
}): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase.from('event_results').upsert(
		{
			event_id: params.eventId,
			instance_start: params.instanceStart,
			user_id: userId,
			run_id: params.runId ?? null,
			duration_s: params.durationS,
			distance_m: params.distanceM,
			finisher_status: params.finisherStatus ?? 'finished',
			age_grade_pct: params.ageGradePct ?? null,
			note: params.note ?? null,
			updated_at: new Date().toISOString(),
		},
		{ onConflict: 'event_id,instance_start,user_id' }
	);
	if (error) throw error;
	// Best-effort back-link so the run-detail page can show "ran at {event}".
	if (params.runId) {
		await supabase
			.from('runs')
			.update({ event_id: params.eventId })
			.eq('id', params.runId)
			.eq('user_id', userId);
	}
}

export async function removeEventResult(
	eventId: string,
	instanceStart: string
): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from('event_results')
		.delete()
		.eq('event_id', eventId)
		.eq('user_id', userId)
		.eq('instance_start', instanceStart);
	if (error) throw error;
}

export interface RecentRunOption {
	id: string;
	started_at: string;
	duration_s: number;
	distance_m: number;
	activity_type: string;
}

export async function fetchRecentRunsForPicker(limit = 20): Promise<RecentRunOption[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data } = await supabase
		.from('runs')
		.select('id, started_at, duration_s, distance_m, metadata')
		.eq('user_id', userId)
		.order('started_at', { ascending: false })
		.limit(limit);
	if (!data) return [];
	return data.map((r) => ({
		id: r.id,
		started_at: r.started_at,
		duration_s: r.duration_s,
		distance_m: r.distance_m,
		activity_type:
			(r.metadata && typeof r.metadata === 'object' && 'activity_type' in r.metadata
				? ((r.metadata as Record<string, unknown>).activity_type as string)
				: null) ?? 'run',
	}));
}

// --- Race sessions (live race mode) ---

export interface RaceSessionRow {
	event_id: string;
	instance_start: string;
	status: 'armed' | 'running' | 'finished' | 'cancelled';
	started_at: string | null;
	started_by: string | null;
	finished_at: string | null;
	auto_approve: boolean;
	created_at: string;
	updated_at: string;
}

export async function fetchRaceSession(
	eventId: string,
	instanceStart: string
): Promise<RaceSessionRow | null> {
	const { data } = await supabase
		.from('race_sessions')
		.select('*')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.maybeSingle();
	return (data as RaceSessionRow | null) ?? null;
}

export async function armRace(
	eventId: string,
	instanceStart: string,
	autoApprove: boolean
): Promise<RaceSessionRow> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('race_sessions')
		.upsert(
			{
				event_id: eventId,
				instance_start: instanceStart,
				status: 'armed',
				started_at: null,
				started_by: null,
				finished_at: null,
				auto_approve: autoApprove,
				updated_at: new Date().toISOString(),
			},
			{ onConflict: 'event_id,instance_start' }
		)
		.select()
		.single();
	if (error) throw error;
	return data as RaceSessionRow;
}

export async function startRace(
	eventId: string,
	instanceStart: string
): Promise<RaceSessionRow> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('race_sessions')
		.update({
			status: 'running',
			started_at: new Date().toISOString(),
			started_by: userId,
			updated_at: new Date().toISOString(),
		})
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.select()
		.single();
	if (error) throw error;
	return data as RaceSessionRow;
}

export async function endRace(
	eventId: string,
	instanceStart: string,
	status: 'finished' | 'cancelled' = 'finished'
): Promise<RaceSessionRow> {
	const { data, error } = await supabase
		.from('race_sessions')
		.update({
			status,
			finished_at: new Date().toISOString(),
			updated_at: new Date().toISOString(),
		})
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.select()
		.single();
	if (error) throw error;
	return data as RaceSessionRow;
}

export async function approveEventResult(
	eventId: string,
	instanceStart: string,
	userId: string,
	approve: boolean
): Promise<void> {
	const { error } = await supabase.rpc('approve_event_result', {
		p_event_id: eventId,
		p_instance_start: instanceStart,
		p_user_id: userId,
		p_approve: approve,
	});
	if (error) throw error;
}

export interface RacePingRow {
	id: number;
	event_id: string;
	instance_start: string;
	user_id: string;
	at: string;
	lat: number;
	lng: number;
	distance_m: number | null;
	elapsed_s: number | null;
	bpm: number | null;
}

/// Latest ping per runner for the spectator map. One row per user, at ==
/// their most recent sample. Sorted by distance descending so the lead
/// runner is first.
export async function fetchLatestRacePings(
	eventId: string,
	instanceStart: string
): Promise<RacePingRow[]> {
	// Pull recent pings and collapse to the latest-per-user client-side.
	// The index is (event_id, instance_start, at desc) so this is cheap;
	// a `distinct on` RPC would be the next optimisation if this gets
	// hot.
	const { data } = await supabase
		.from('race_pings')
		.select('*')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.order('at', { ascending: false })
		.limit(500);
	const pings = (data as RacePingRow[]) ?? [];
	const byUser = new Map<string, RacePingRow>();
	for (const p of pings) {
		if (!byUser.has(p.user_id)) byUser.set(p.user_id, p);
	}
	return [...byUser.values()].sort(
		(a, b) => (b.distance_m ?? 0) - (a.distance_m ?? 0)
	);
}

export async function postRacePing(params: {
	eventId: string;
	instanceStart: string;
	lat: number;
	lng: number;
	distanceM?: number;
	elapsedS?: number;
	bpm?: number;
}): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase.from('race_pings').insert({
		event_id: params.eventId,
		instance_start: params.instanceStart,
		user_id: userId,
		lat: params.lat,
		lng: params.lng,
		distance_m: params.distanceM ?? null,
		elapsed_s: params.elapsedS ?? null,
		bpm: params.bpm ?? null,
	});
	if (error) throw error;
}

// --- Club posts (owner updates) ---

export async function fetchClubPosts(
	clubId: string,
	limit = 20
): Promise<ClubPostWithAuthor[]> {
	// Top-level posts only; replies are loaded lazily per-post.
	const { data: posts } = await supabase
		.from('club_posts')
		.select('*')
		.eq('club_id', clubId)
		.is('parent_post_id', null)
		.order('created_at', { ascending: false })
		.limit(limit);
	if (!posts) return [];
	return enrichPosts(posts as ClubPost[]);
}

export async function fetchPostReplies(parentId: string): Promise<ClubPostWithAuthor[]> {
	const { data: posts } = await supabase
		.from('club_posts')
		.select('*')
		.eq('parent_post_id', parentId)
		.order('created_at', { ascending: true });
	if (!posts) return [];
	return enrichPosts(posts as ClubPost[]);
}

async function enrichPosts(posts: ClubPost[]): Promise<ClubPostWithAuthor[]> {
	if (posts.length === 0) return [];
	const authorIds = Array.from(new Set(posts.map((p) => p.author_id)));
	const topLevelIds = posts.filter((p) => !p.parent_post_id).map((p) => p.id);

	const [profilesRes, repliesRes] = await Promise.all([
		supabase
			.from('user_profiles')
			.select('id, display_name, avatar_url')
			.in('id', authorIds),
		topLevelIds.length > 0
			? supabase
					.from('club_posts')
					.select('parent_post_id')
					.in('parent_post_id', topLevelIds)
			: Promise.resolve({ data: [] as { parent_post_id: string }[] })
	]);

	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profilesRes.data ?? []) byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });

	const replyCounts = new Map<string, number>();
	for (const row of (repliesRes.data ?? []) as { parent_post_id: string }[]) {
		replyCounts.set(row.parent_post_id, (replyCounts.get(row.parent_post_id) ?? 0) + 1);
	}

	return posts.map((post) => ({
		...post,
		author_display_name: byId.get(post.author_id)?.display_name ?? null,
		author_avatar_url: byId.get(post.author_id)?.avatar_url ?? null,
		reply_count: replyCounts.get(post.id) ?? 0
	}));
}

export async function createClubPost(input: {
	club_id: string;
	body: string;
	event_id?: string | null;
	event_instance_start?: string | null;
	parent_post_id?: string | null;
}): Promise<ClubPost> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('club_posts')
		.insert({
			club_id: input.club_id,
			event_id: input.event_id ?? null,
			event_instance_start: input.event_instance_start ?? null,
			parent_post_id: input.parent_post_id ?? null,
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

// --- Training plans ---

export async function fetchMyPlans(): Promise<TrainingPlan[]> {
	const { data } = await supabase
		.from('training_plans')
		.select('*')
		.order('created_at', { ascending: false });
	return ((data ?? []) as TrainingPlan[]) ?? [];
}

export async function fetchPlan(id: string): Promise<{
	plan: TrainingPlan | null;
	weeks: PlanWeek[];
	workouts: PlanWorkout[];
}> {
	const [planRes, weeksRes] = await Promise.all([
		supabase.from('training_plans').select('*').eq('id', id).maybeSingle(),
		supabase
			.from('plan_weeks')
			.select('*')
			.eq('plan_id', id)
			.order('week_index', { ascending: true })
	]);
	const plan = (planRes.data ?? null) as TrainingPlan | null;
	const weeks = ((weeksRes.data ?? []) as PlanWeek[]) ?? [];
	if (!plan || weeks.length === 0) {
		return { plan, weeks, workouts: [] };
	}
	const weekIds = weeks.map((w) => w.id);
	const { data: woData } = await supabase
		.from('plan_workouts')
		.select('*')
		.in('week_id', weekIds)
		.order('scheduled_date', { ascending: true });
	return {
		plan,
		weeks,
		workouts: ((woData ?? []) as PlanWorkout[]) ?? []
	};
}

export async function fetchWorkout(id: string): Promise<PlanWorkout | null> {
	const { data } = await supabase
		.from('plan_workouts')
		.select('*')
		.eq('id', id)
		.maybeSingle();
	return (data as PlanWorkout | null) ?? null;
}

export async function fetchActivePlanOverview(): Promise<ActivePlanOverview | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data: plan } = await supabase
		.from('training_plans')
		.select('*')
		.eq('user_id', userId)
		.eq('status', 'active')
		.maybeSingle();
	if (!plan) return null;
	const { weeks, workouts } = await fetchPlan(plan.id);
	// Local-tz today — `toISOString().slice(0,10)` returns the UTC date,
	// which rolls a calendar day early/late depending on the viewer's TZ.
	const { todayISO } = await import('./training');
	const today = todayISO();
	const todayWorkout = workouts.find((w) => w.scheduled_date === today) ?? null;
	const completed = workouts.filter((w) => w.completed_run_id).length;
	const total = workouts.filter((w) => w.kind !== 'rest').length;
	const completionPct = total === 0 ? 0 : Math.round((completed / total) * 100);
	return {
		plan: plan as TrainingPlan,
		weeks: weeks ?? [],
		workouts: workouts ?? [],
		todayWorkout,
		completionPct
	};
}

/**
 * Persist a freshly generated plan — plan row, one row per week, and N
 * workouts per week. Runs four sequential inserts (plan → weeks → workouts
 * grouped by week); could be collapsed into a single RPC later but the
 * linear path is easier to reason about while the feature is new.
 */
export async function createTrainingPlan(input: {
	name: string;
	goalEvent: GoalEvent;
	goalDistanceM: number;
	goalTimeSec?: number | null;
	recent5kSec?: number | null;
	startDate: string; // ISO date
	daysPerWeek: number;
	notes?: string;
	generated: GeneratedPlan;
}): Promise<TrainingPlan> {
	// Read the id from the session directly rather than from the auth store.
	// The store's `user` object is populated by a background profile fetch
	// which races with "Create plan" — using the session avoids the
	// spurious "Not authenticated" when the session is valid but the profile
	// hasn't loaded.
	const { data: { session } } = await supabase.auth.getSession();
	const userId = session?.user?.id;
	if (!userId) throw new Error('Please sign in to create a plan.');

	// Pre-flight validation — every client-set invariant the DB enforces
	// echoed here so the user gets a readable error instead of a raw
	// PostgrestError 23xxx code.
	if (!input.name.trim()) throw new Error('Name is required.');
	if (!(input.goalDistanceM > 0)) throw new Error('Goal distance must be positive.');
	if (input.daysPerWeek < 3 || input.daysPerWeek > 7) {
		throw new Error('Days per week must be between 3 and 7.');
	}
	if (input.goalTimeSec != null && input.goalTimeSec <= 0) {
		throw new Error('Goal time must be positive.');
	}
	if (input.recent5kSec != null && input.recent5kSec <= 0) {
		throw new Error('Recent 5K time must be positive.');
	}
	if (!input.generated.weeks.length) {
		throw new Error('Generated plan has no weeks.');
	}
	// Defence in depth for the null-kind bug we fixed in training.ts —
	// if some future change lets a kindless workout escape the generator,
	// catch it here instead of losing the context in a server-side 23502.
	for (const w of input.generated.weeks) {
		for (const wo of w.workouts) {
			if (!wo.kind) {
				throw new Error(
					`Generator produced a workout with no kind (week ${w.week_index}, ${wo.scheduled_date}).`
				);
			}
		}
	}

	// Auto-complete any existing active plan so the partial unique index
	// (one-active-per-user) doesn't reject the insert.
	await supabase
		.from('training_plans')
		.update({ status: 'completed' })
		.eq('user_id', userId)
		.eq('status', 'active');

	const { data: plan, error: planErr } = await supabase
		.from('training_plans')
		.insert({
			user_id: userId,
			name: input.name.trim(),
			goal_event: input.goalEvent,
			goal_distance_m: input.goalDistanceM,
			goal_time_seconds: input.goalTimeSec ?? null,
			start_date: input.startDate,
			end_date: input.generated.endDate,
			days_per_week: input.daysPerWeek,
			vdot: input.generated.vdot ?? null,
			current_5k_seconds: input.recent5kSec ?? null,
			status: 'active' as PlanStatus,
			notes: input.notes?.trim() || null
		})
		.select()
		.single();
	if (planErr || !plan) throw planErr ?? new Error('Plan insert failed');

	const weekRows = input.generated.weeks.map((w) => ({
		plan_id: plan.id,
		week_index: w.week_index,
		phase: w.phase,
		target_volume_m: w.target_volume_m,
		notes: w.notes
	}));
	const { data: weekRes, error: weekErr } = await supabase
		.from('plan_weeks')
		.insert(weekRows)
		.select();
	if (weekErr || !weekRes) throw weekErr ?? new Error('Weeks insert failed');

	const byIndex = new Map<number, string>();
	for (const w of weekRes as { id: string; week_index: number }[]) {
		byIndex.set(w.week_index, w.id);
	}

	const workoutRows = input.generated.weeks.flatMap((w) =>
		w.workouts.map((wo) => ({
			week_id: byIndex.get(w.week_index)!,
			scheduled_date: wo.scheduled_date,
			kind: wo.kind,
			target_distance_m: wo.target_distance_m,
			target_duration_seconds: wo.target_duration_seconds,
			target_pace_sec_per_km: wo.target_pace_sec_per_km,
			target_pace_tolerance_sec: wo.target_pace_tolerance_sec,
			structure: wo.structure,
			notes: wo.notes
		}))
	);
	if (workoutRows.length > 0) {
		const { error: woErr } = await supabase.from('plan_workouts').insert(workoutRows);
		if (woErr) throw woErr;
	}

	return plan as TrainingPlan;
}

export async function updatePlanStatus(
	id: string,
	status: PlanStatus
): Promise<void> {
	const { error } = await supabase
		.from('training_plans')
		.update({ status })
		.eq('id', id);
	if (error) throw error;
}

export async function deletePlan(id: string): Promise<void> {
	const { error } = await supabase.from('training_plans').delete().eq('id', id);
	if (error) throw error;
}

export async function markWorkoutCompleted(
	workoutId: string,
	runId: string | null
): Promise<void> {
	const { error } = await supabase
		.from('plan_workouts')
		.update({
			completed_run_id: runId,
			completed_at: runId ? new Date().toISOString() : null
		})
		.eq('id', workoutId);
	if (error) throw error;
}

/**
 * Best-effort auto-match: link `runId` to a plan workout scheduled for the
 * same calendar date whose target distance is within ±25% of the actual.
 * Returns the matched workout id, or null. Wrong matches are manually
 * clearable via `markWorkoutCompleted(id, null)`.
 */
export async function autoMatchRunToPlanWorkout(
	runId: string,
	runIsoDate: string,
	runDistanceM: number
): Promise<string | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data: candidates } = await supabase
		.from('plan_workouts')
		.select('id, target_distance_m, completed_run_id, week_id')
		.eq('scheduled_date', runIsoDate)
		.is('completed_run_id', null);
	if (!candidates || candidates.length === 0) return null;
	const withDistance = candidates
		.filter((c) => c.target_distance_m != null)
		.map((c) => ({
			id: c.id as string,
			target: c.target_distance_m as number,
			delta: Math.abs((c.target_distance_m as number) - runDistanceM)
		}))
		.filter(
			(c) =>
				c.delta / c.target <= 0.25 // within 25% of target distance
		)
		.sort((a, b) => a.delta - b.delta);
	if (withDistance.length === 0) return null;
	const match = withDistance[0];
	await markWorkoutCompleted(match.id, runId);
	return match.id;
}

/**
 * Patch a single plan workout — supports the inline editor. Only the
 * provided fields are updated; leave others out of the `patch` map to keep
 * them untouched.
 */
export async function updatePlanWorkout(
	id: string,
	patch: Partial<{
		kind: string;
		target_distance_m: number | null;
		target_duration_seconds: number | null;
		target_pace_sec_per_km: number | null;
		target_pace_end_sec_per_km: number | null;
		target_pace_tolerance_sec: number | null;
		pace_zone: string | null;
		notes: string | null;
		scheduled_date: string;
	}>
): Promise<void> {
	const { error } = await supabase.from('plan_workouts').update(patch).eq('id', id);
	if (error) throw error;
}

export async function updatePlanWeek(
	id: string,
	patch: Partial<{ phase: string; target_volume_m: number | null; notes: string | null }>
): Promise<void> {
	const { error } = await supabase.from('plan_weeks').update(patch).eq('id', id);
	if (error) throw error;
}

export async function updatePlanMeta(
	id: string,
	patch: Partial<{ name: string; notes: string | null }>
): Promise<void> {
	const { error } = await supabase.from('training_plans').update(patch).eq('id', id);
	if (error) throw error;
}
