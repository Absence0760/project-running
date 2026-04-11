// Database row types are generated from the Supabase schema. Regenerate with
// `npm run gen:types` after every migration. The aliases below add the narrow
// unions and lazy-loaded client-side fields that the schema alone can't express.
import type { Database } from './database.types';

type RunRow = Database['public']['Tables']['runs']['Row'];
type RouteRow = Database['public']['Tables']['routes']['Row'];
type IntegrationRow = Database['public']['Tables']['integrations']['Row'];
type UserProfileRow = Database['public']['Tables']['user_profiles']['Row'];

export interface TrackPoint {
	lat: number;
	lng: number;
	ele?: number;
	ts?: string;
}

// `track` is populated on-demand by `data.ts#fetchRunById` from the gzipped
// Storage object pointed to by `track_url`. It is not a column on the table.
// `metadata` is overridden to a looser map so consumers can index dynamic
// keys (activity_type, steps, event, position, etc.) — the generated `Json`
// type is too strict for that pattern.
export type Run = Omit<RunRow, 'source' | 'metadata'> & {
	source: RunSource;
	metadata: Record<string, unknown> | null;
	track: TrackPoint[] | null;
};

export type Route = Omit<RouteRow, 'waypoints' | 'surface'> & {
	waypoints: TrackPoint[];
	surface: RouteSurface | null;
};

export type Integration = Omit<IntegrationRow, 'provider'> & {
	provider: IntegrationProvider;
};

export type UserProfile = Omit<UserProfileRow, 'preferred_unit' | 'subscription_tier'> & {
	preferred_unit: PreferredUnit | null;
	subscription_tier: SubscriptionTier | null;
};

// The string columns below have no CHECK constraint in the database, so the
// generated types see them as plain `string`. Narrow to the values the clients
// actually write. If the schema ever gains a CHECK constraint or enum, delete
// these unions and let the generated types flow through.
export type RunSource =
	| 'app'
	| 'healthkit'
	| 'healthconnect'
	| 'strava'
	| 'garmin'
	| 'parkrun'
	| 'race';

export type RouteSurface = 'road' | 'trail' | 'mixed';
export type IntegrationProvider = 'strava' | 'garmin' | 'parkrun' | 'runsignup';
export type PreferredUnit = 'km' | 'mi';
export type SubscriptionTier = 'free' | 'premium';
