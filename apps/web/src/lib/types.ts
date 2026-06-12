// Database row types are generated from the Supabase schema. Regenerate with
// `npm run gen:types` after every migration. The aliases below add the narrow
// unions and lazy-loaded client-side fields that the schema alone can't express.
import type { Database } from './database.types';
import type { EventGymTemplate } from './social/event_gym_template';

type RunRow = Database['public']['Tables']['runs']['Row'];
type RouteRow = Database['public']['Tables']['routes']['Row'];
type IntegrationRow = Database['public']['Tables']['integrations']['Row'];
type UserProfileRow = Database['public']['Tables']['user_profiles']['Row'];
type ClubRow = Database['public']['Tables']['clubs']['Row'];
type ClubMemberRow = Database['public']['Tables']['club_members']['Row'];
type EventRow = Database['public']['Tables']['events']['Row'];
type EventAttendeeRow = Database['public']['Tables']['event_attendees']['Row'];
type ClubPostRow = Database['public']['Tables']['club_posts']['Row'];
type EventPricingRow = Database['public']['Tables']['event_pricing']['Row'];
type EventOrderRow = Database['public']['Tables']['event_orders']['Row'];
type InstructorPayoutAccountRow = Database['public']['Tables']['instructor_payout_accounts']['Row'];
type TrainingPlanRow = Database['public']['Tables']['training_plans']['Row'];
type PlanWeekRow = Database['public']['Tables']['plan_weeks']['Row'];
type PlanWorkoutRow = Database['public']['Tables']['plan_workouts']['Row'];
type CoachAthleteRow = Database['public']['Tables']['coach_athletes']['Row'];

// Coach-athlete link lifecycle (persona #46). Enforced by the
// `coach_athletes_status_check` CHECK in 20261102_001_coach_athletes.sql;
// the apps/web/scripts/check_constraint_unions.mjs guard keeps the two in
// lockstep. 'pending' = an unredeemed invite token (athlete_id null),
// 'active' = a redeemed live link, 'ended' = severed by either party.
export type CoachAthleteStatus = 'pending' | 'active' | 'ended';

export type CoachAthlete = Omit<CoachAthleteRow, 'status'> & {
	status: CoachAthleteStatus;
};

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
	/// `docs/backend/metadata.md`.
	bpm?: number;
}

// `track` is populated on-demand by `data.ts#fetchRunById` from the gzipped
// Storage object pointed to by `track_url`. It is not a column on the table.
// `metadata` is overridden to a looser map so consumers can index dynamic
// keys (activity_type, steps, event, position, etc.) — the generated `Json`
// type is too strict for that pattern.
export type Run = Omit<RunRow, 'source' | 'metadata' | 'activity_type'> & {
	source: RunSource;
	activity_type: ActivityType;
	metadata: Record<string, unknown> | null;
	track: TrackPoint[] | null;
	// View-only boolean from `public_runs` (migration 20261105_001):
	// whether a GPS trace exists, without exposing the Storage path. Set on
	// rows read through the public view (feed, profile); absent on owner
	// reads from the base table (use `track_url != null` there). Drives the
	// feed / profile map-thumbnail gate.
	has_track?: boolean;
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

// Promoted out of `runs.metadata` into a real `runs.activity_type` column by
// migration 20261207_001 (CHECK in ('run','walk','hike','cycle','stroller')).
// The CHECK ↔ this union lockstep is enforced by check_constraint_unions.mjs.
export type ActivityType = 'run' | 'walk' | 'hike' | 'cycle' | 'stroller';

export type RouteSurface = 'road' | 'trail' | 'mixed';
export type IntegrationProvider = 'strava' | 'garmin' | 'parkrun' | 'runsignup';
export type PreferredUnit = 'km' | 'mi';
export type SubscriptionTier = 'free' | 'pro' | 'lifetime';

export type ClubRole = 'owner' | 'admin' | 'event_organiser' | 'race_director' | 'member';
// 'waitlisted' is assigned server-side by the event-capacity trigger
// (migration 20261018_001) when a 'going' RSVP exceeds events.capacity; the
// client never writes it directly. No DB CHECK exists on event_attendees.status.
export type RsvpStatus = 'going' | 'maybe' | 'declined' | 'waitlisted';
// Attendance is orthogonal to RSVP status (instructor_business.md M6): a
// host marks who actually showed up, NULL until then. Host-written via the
// mark_attendance RPC, attendee-readable. Enforced by the
// event_attendees_attendance_check CHECK (migration 20261231_006) — keep this
// union in lockstep (check_constraint_unions.mjs PAIRS).
export type EventAttendance = 'attended' | 'no_show';
export type MembershipStatus = 'active' | 'pending';
export type JoinPolicy = 'open' | 'request' | 'invite';
export type RecurrenceFreq = 'weekly' | 'biweekly' | 'monthly';
export type Weekday = 'MO' | 'TU' | 'WE' | 'TH' | 'FR' | 'SA' | 'SU';
// Names track ActivityType ('cycle', not 'ride') so the app keeps one type
// vocabulary. `run`/`cycle` are distance-based athletic events (route, pace,
// race mode, results); `class` is an instructor-led session (yoga/pilates —
// no route/results); `social` is a meetup. Enforced by the events_category_check
// CHECK constraint (migration 20261227_001) — keep this union in lockstep.
export type EventCategory = 'run' | 'cycle' | 'class' | 'social';
// Paid registration (club_events.md slice P1). Each is enforced by a CHECK
// constraint (migration 20261229_001) — keep these unions in lockstep
// (check_constraint_unions.mjs PAIRS).
// event_orders.status — the order ledger lifecycle, written only by the
// stripe-events webhook (service role).
export type OrderStatus =
	| 'pending'
	| 'paid'
	| 'refunded'
	| 'partially_refunded'
	| 'failed'
	| 'canceled';
// event_pricing.refund_policy — buyer self-cancel terms (honoured in P2).
export type RefundPolicy = 'full_until_start' | 'full_until_24h' | 'no_refund';
// event_pricing.modality — in_person only in P1; 'virtual' is a digital good
// that re-opens the app-store IAP rule (reserved for P4).
export type EventModality = 'in_person';
export type NotificationKind =
	| 'kudos'
	| 'comment'
	| 'comment_reply'
	| 'follow'
	| 'event_rsvp'
	| 'event_cancel'
	| 'plan_update'
	| 'message'
	| 'club_post'
	| 'run_completed'
	| 'event_reminder';

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
//
// `location_point` (geography(Point, 4326), migration 20260905_001)
// is omitted from the base shape because supabase-js can't usefully
// type a PostGIS column — it's `unknown` in the generated row type,
// and clients never read it directly (the `searchClubs` RPC consumes
// it server-side). The column is grantable to anon/authenticated; if
// a future client surface ever needs to render the point (a map pin
// on a club's page), reintroduce it here + extend CLUB_SELECT_COLS.
export type Club = Omit<ClubRow, 'join_policy' | 'invite_token' | 'location_point'> & {
	join_policy: JoinPolicy;
};
export type ClubMember = Omit<ClubMemberRow, 'role' | 'status'> & {
	role: ClubRole;
	status: MembershipStatus;
};
export type Event = Omit<
	EventRow,
	'recurrence_freq' | 'recurrence_byday' | 'category' | 'gym_template'
> & {
	recurrence_freq: RecurrenceFreq | null;
	recurrence_byday: Weekday[] | null;
	category: EventCategory;
	// The class -> gym seam hint, parsed from the loose jsonb bag into the
	// typed shape (event_gym_template.ts). Null for a non-class event or a
	// class the host didn't template.
	gym_template: EventGymTemplate | null;
};
export type EventAttendee = Omit<EventAttendeeRow, 'status' | 'attendance'> & {
	status: RsvpStatus;
	attendance: EventAttendance | null;
};
export type ClubPost = Omit<ClubPostRow, never>;

export type EventPricing = Omit<EventPricingRow, 'modality' | 'refund_policy'> & {
	modality: EventModality;
	refund_policy: RefundPolicy;
};
export type EventOrder = Omit<EventOrderRow, 'status'> & { status: OrderStatus };
export type InstructorPayoutAccount = InstructorPayoutAccountRow;

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
