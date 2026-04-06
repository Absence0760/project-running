export interface Run {
	id: string;
	user_id: string;
	started_at: string;
	duration_s: number;
	distance_m: number;
	track: TrackPoint[] | null;
	route_id: string | null;
	source: RunSource;
	external_id: string | null;
	metadata: Record<string, unknown> | null;
	created_at: string;
}

export interface Route {
	id: string;
	user_id: string;
	name: string;
	waypoints: TrackPoint[];
	distance_m: number;
	elevation_m: number | null;
	surface: 'road' | 'trail' | 'mixed';
	is_public: boolean;
	slug: string | null;
	created_at: string;
}

export interface TrackPoint {
	lat: number;
	lng: number;
	ele?: number;
	ts?: string;
}

export interface Integration {
	id: string;
	user_id: string;
	provider: 'strava' | 'garmin' | 'parkrun' | 'runsignup';
	external_id: string | null;
	last_sync_at: string | null;
}

export interface UserProfile {
	id: string;
	display_name: string | null;
	avatar_url: string | null;
	parkrun_number: string | null;
	preferred_unit: 'km' | 'mi';
	subscription_tier: 'free' | 'premium';
}

export type RunSource =
	| 'app'
	| 'healthkit'
	| 'healthconnect'
	| 'strava'
	| 'garmin'
	| 'parkrun'
	| 'race';
