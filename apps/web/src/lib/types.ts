// Database row types are generated from the Supabase schema. Regenerate with
// `npm run gen:types` after every migration. The aliases below add the narrow
// unions and lazy-loaded client-side fields that the schema alone can't express.
import type { Database } from './database.types';

type RunRow = Database['public']['Tables']['runs']['Row'];
type RouteRow = Database['public']['Tables']['routes']['Row'];
type IntegrationRow = Database['public']['Tables']['integrations']['Row'];
type UserProfileRow = Database['public']['Tables']['user_profiles']['Row'];
type ClubRow = Database['public']['Tables']['clubs']['Row'];
type ClubMemberRow = Database['public']['Tables']['club_members']['Row'];
type EventRow = Database['public']['Tables']['events']['Row'];
type EventAttendeeRow = Database['public']['Tables']['event_attendees']['Row'];
type ClubPostRow = Database['public']['Tables']['club_posts']['Row'];
type TrainingPlanRow = Database['public']['Tables']['training_plans']['Row'];
type PlanWeekRow = Database['public']['Tables']['plan_weeks']['Row'];
type PlanWorkoutRow = Database['public']['Tables']['plan_workouts']['Row'];

export interface TrackPoint {
	lat: number;
	lng: number;
	ele?: number;
	ts?: string;
	/// Per-point heart rate in BPM when the recorder captured HR
	/// samples alongside GPS. Optional: most historical runs only
	/// carry scalar `metadata.avg_bpm`. When every point has `bpm`
	/// the run-detail zone breakdown computes real zones; otherwise
	/// it falls back to a "No HR samples on this run" message. See
	/// `docs/metadata.md`.
	bpm?: number;
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

// The string columns below ARE enforced by CHECK constraints in the database
// (see apps/backend/supabase/migrations/20260505_001_narrow_union_check_constraints.sql
// and 20260429_001_subscription_paywall.sql), so postgres rejects any value
// outside these unions at write time. The generated types still see them as
// plain `string` because Supabase's gen-types pass doesn't read CHECK
// constraints; we narrow here so callers get autocomplete / exhaustiveness
// checks. The TS union and the SQL CHECK must stay in lockstep.
export type RunSource =
	| 'app'
	| 'watch'
	| 'healthkit'
	| 'healthconnect'
	| 'strava'
	| 'garmin'
	| 'parkrun'
	| 'race';

/// Defensive narrow on read. The DB rejects bad values via a CHECK
/// constraint, but a stale TS union (added later than a new DB value) or a
/// row imported during a migration could still surface a string outside
/// the union. Returning `'app'` for unknowns matches the Dart-side
/// `parseRunSource` fallback semantics in
/// `apps/mobile_android/lib/watch_ingest_queue.dart` (defaults to
/// `RunSource.watch` there because that file is the watch-ingest path;
/// for the web we default to `'app'` since web never originates a watch
/// run). Callers that want stricter handling can compare equality.
export function parseRunSource(raw: string | null | undefined): RunSource {
	switch (raw) {
		case 'app':
		case 'watch':
		case 'healthkit':
		case 'healthconnect':
		case 'strava':
		case 'garmin':
		case 'parkrun':
		case 'race':
			return raw;
		default:
			return 'app';
	}
}

export type RouteSurface = 'road' | 'trail' | 'mixed';
export type IntegrationProvider = 'strava' | 'garmin' | 'parkrun' | 'runsignup';
export type PreferredUnit = 'km' | 'mi';
export type SubscriptionTier = 'free' | 'pro' | 'lifetime';

export type ClubRole = 'owner' | 'admin' | 'event_organiser' | 'race_director' | 'member';
export type RsvpStatus = 'going' | 'maybe' | 'declined';
export type MembershipStatus = 'active' | 'pending';
export type JoinPolicy = 'open' | 'request' | 'invite';
export type RecurrenceFreq = 'weekly' | 'biweekly' | 'monthly';
export type Weekday = 'MO' | 'TU' | 'WE' | 'TH' | 'FR' | 'SA' | 'SU';

// `invite_token` is excluded from the base type because the column-
// level grant lockdown (migrations 20260801_001 + 20260818_001 redo)
// revokes SELECT on it from anon + authenticated. Reads use
// CLUB_SELECT_COLS which omits it; admin reads go through the
// `get_club_invite_token` SECURITY DEFINER RPC and decorate the
// result inline. A previous version of this type included
// invite_token, which masked the column-mismatch when `.select(<col
// list>)` was typed as `string` (no inference); after the dependabot
// bump that tightened supabase-js's literal inference, the
// mismatch surfaces as a real svelte-check error.
export type Club = Omit<ClubRow, 'join_policy' | 'invite_token'> & { join_policy: JoinPolicy };
export type ClubMember = Omit<ClubMemberRow, 'role' | 'status'> & {
	role: ClubRole;
	status: MembershipStatus;
};
export type Event = Omit<EventRow, 'recurrence_freq' | 'recurrence_byday'> & {
	recurrence_freq: RecurrenceFreq | null;
	recurrence_byday: Weekday[] | null;
};
export type EventAttendee = Omit<EventAttendeeRow, 'status'> & { status: RsvpStatus };
export type ClubPost = Omit<ClubPostRow, never>;

/** Shape returned by club list/detail queries — member count + current-user membership. */
export type ClubWithMeta = Club & {
	member_count: number;
	viewer_role: ClubRole | null;
	viewer_status: MembershipStatus | null;
	// Decorated by `fetchClubBySlug` when the viewer is owner/admin —
	// the `get_club_invite_token` SECURITY DEFINER RPC returns the
	// value the column-grant lockdown hides from regular SELECT.
	// Optional + nullable so list endpoints that don't decorate the
	// field still satisfy the type.
	invite_token?: string | null;
};

/** `viewer_rsvp` is always for the *next* instance of a recurring series; per-instance RSVPs are queried separately. */
export type EventWithMeta = Event & {
	attendee_count: number;
	viewer_rsvp: RsvpStatus | null;
	next_instance_start: string; // ISO — equals starts_at for one-offs
};

export type ClubPostWithAuthor = ClubPost & {
	author_display_name: string | null;
	author_avatar_url: string | null;
	reply_count: number;
};

// ─────────────────────── Training plans ───────────────────────

export type PlanStatus = 'active' | 'completed' | 'abandoned';

export type TrainingPlan = Omit<TrainingPlanRow, 'status'> & { status: PlanStatus };
export type PlanWeek = PlanWeekRow;
export type PlanWorkout = PlanWorkoutRow;

/** View-model returned by `fetchActivePlanOverview` — plan + current week +
 * next few workouts. Used by the dashboard card + the plan detail page. */
export type ActivePlanOverview = {
	plan: TrainingPlan;
	weeks: PlanWeek[];
	workouts: PlanWorkout[];
	todayWorkout: PlanWorkout | null;
	completionPct: number;
};
