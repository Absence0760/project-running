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
	| 'watch'
	| 'healthkit'
	| 'healthconnect'
	| 'strava'
	| 'garmin'
	| 'parkrun'
	| 'race';

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

export type Club = Omit<ClubRow, 'join_policy'> & { join_policy: JoinPolicy };
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

export type TrainingPlan = TrainingPlanRow & { status: PlanStatus };
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
