// Database row types are generated from the Supabase schema. Regenerate with
// `npm run gen:types` after every migration. The aliases below add the narrow
// unions and lazy-loaded client-side fields that the schema alone can't express.
import type { Database } from './database.types';
import type { EventGymTemplate } from './social/event_gym_template';

type RunRow = Database['public']['Tables']['runs']['Row'];
type RouteRow = Database['public']['Tables']['routes']['Row'];
type RouteMarkerRow = Database['public']['Tables']['route_markers']['Row'];
type RaceListingRow = Database['public']['Tables']['race_listings']['Row'];
type RouteConditionRow = Database['public']['Tables']['route_conditions']['Row'];
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
type FundraiserRow = Database['public']['Tables']['fundraisers']['Row'];
type DonationRow = Database['public']['Tables']['donations']['Row'];
type SessionPlanRow = Database['public']['Tables']['session_plans']['Row'];
type SessionPlanBlockRow = Database['public']['Tables']['session_plan_blocks']['Row'];
type SessionPlanItemRow = Database['public']['Tables']['session_plan_items']['Row'];
type TrainingPlanRow = Database['public']['Tables']['training_plans']['Row'];
type PlanWeekRow = Database['public']['Tables']['plan_weeks']['Row'];
type PlanWorkoutRow = Database['public']['Tables']['plan_workouts']['Row'];
type CoachAthleteRow = Database['public']['Tables']['coach_athletes']['Row'];
type ChallengeRow = Database['public']['Tables']['challenges']['Row'];
type ChallengeParticipantRow = Database['public']['Tables']['challenge_participants']['Row'];
type ChallengeBadgeRow = Database['public']['Tables']['challenge_badges']['Row'];
type ExerciseRow = Database['public']['Tables']['exercises']['Row'];

// Coach-athlete link lifecycle (persona #46). Enforced by the
// `coach_athletes_status_check` CHECK in 20261102_001_coach_athletes.sql;
// the apps/web/scripts/check_constraint_unions.mjs guard keeps the two in
// lockstep. 'pending' = an unredeemed invite token (athlete_id null),
// 'active' = a redeemed live link, 'ended' = severed by either party.
export type CoachAthleteStatus = 'pending' | 'active' | 'ended';

export type CoachAthlete = Omit<CoachAthleteRow, 'status'> & {
	status: CoachAthleteStatus;
};

type AchievementRow = Database['public']['Tables']['achievements']['Row'];

// Achievement badge awards (docs/features/achievements.md). Both narrow
// columns are enforced by CHECK constraints in 20270208_001_achievements.sql;
// the check_constraint_unions.mjs guard keeps each in lockstep. The catalogue
// (which badge_keys exist + their thresholds) lives in social/badges.ts.
export type AchievementTier = 'bronze' | 'silver' | 'gold' | 'platinum';
export type AchievementSourceKind = 'pr' | 'segment' | 'streak' | 'distance' | 'plan';

export type Achievement = Omit<AchievementRow, 'tier' | 'source_kind'> & {
	tier: AchievementTier;
	source_kind: AchievementSourceKind;
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

// Course markers on a route (migration 20270129_001). `kind` is the narrow
// union enforced by the CHECK constraint + check_constraint_unions.mjs;
// `meta` is a loose bag whose per-kind keys (services, cutoff_clock,
// cutoff_elapsed_s, note, …) are documented in docs/features/route_markers.md.
export type RouteMarkerKind =
	| 'aid_station'
	| 'cutoff'
	| 'crew_access'
	| 'hazard'
	| 'note'
	| 'climb'
	| 'custom';

export type RouteMarker = Omit<RouteMarkerRow, 'kind' | 'meta'> & {
	kind: RouteMarkerKind;
	meta: Record<string, unknown>;
};

// A discoverable race calendar entry (migration 20270214_001). `provider` is
// the narrow union enforced by the CHECK constraint + check_constraint_unions.mjs.
export type RaceProvider =
	| 'runsignup'
	| 'parkrun'
	| 'manual'
	| 'chronotrack'
	| 'raceresult'
	| 'ultrasignup';

export type RaceListing = Omit<RaceListingRow, 'provider'> & {
	provider: RaceProvider;
};

// Community condition reports on a route (migration 20270212_001). `condition`
// + `severity` are narrow unions enforced by CHECK constraints +
// check_constraint_unions.mjs. Distinct from RouteMarker: any viewer (not just
// the owner) can file a report, and the anchor (lat/lng) is optional.
export type RouteConditionKind =
	| 'clear'
	| 'muddy'
	| 'flooded'
	| 'snow_ice'
	| 'overgrown'
	| 'closed'
	| 'hazard'
	| 'other';

export type RouteConditionSeverity = 'info' | 'caution' | 'impassable';

export type RouteCondition = Omit<RouteConditionRow, 'condition' | 'severity'> & {
	condition: RouteConditionKind;
	severity: RouteConditionSeverity;
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

/// Defensive narrow on read, mirroring `parseRunSource`. The DB rejects
/// bad values via a CHECK constraint, but a stale TS union or a row
/// imported during a migration could surface a string outside the union.
/// A surface-less route (GPX/KML imports that don't know) is the common
/// case, so `null` passes through unchanged; only an unrecognised
/// non-null string collapses to `null`.
export function parseRouteSurface(raw: string | null | undefined): RouteSurface | null {
	switch (raw) {
		case 'road':
		case 'trail':
		case 'mixed':
			return raw;
		default:
			return null;
	}
}

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
// event_attendees_attendance_check CHECK (migration 20270102_001) — keep this
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
// public_recaps.period_kind — a published "Wrapped" recap is either a whole
// year or one calendar month. Enforced by a CHECK constraint (migration
// 20270207_001) — keep this union in lockstep (check_constraint_unions.mjs PAIRS).
export type RecapPeriodKind = 'year' | 'month';
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
// Charity fundraising (fundraising.md, migration 20270213_001). Two
// narrow-union ↔ CHECK pairs; the Dart side treats both as raw String. Keep
// each in lockstep with the migration (check_constraint_unions.mjs PAIRS).
// fundraisers.status — open until the owner closes it.
export type FundraiserStatus = 'open' | 'closed';
// donations.status — the donation ledger lifecycle, written only by the
// stripe-events webhook donation branch (service role).
export type DonationStatus = 'pending' | 'paid' | 'refunded' | 'failed' | 'canceled';
// session_plan_items.kind — a yoga/pilates movement is a timed hold, a counted
// set of reps, or a continuous flow. Enforced by the session_plan_items_kind_check
// CHECK constraint (migration 20270103_001) — keep this union in lockstep
// (check_constraint_unions.mjs PAIRS). session_planner.md P1.
export type SessionItemKind = 'hold' | 'reps' | 'flow';
// Gym programming engine (gym_programming.md, migration 20270101_001). Four
// narrow-union ↔ CHECK pairs; the Dart side treats all four as raw String.
// Keep each in lockstep with the migration (check_constraint_unions.mjs PAIRS).
// gym_routines.periodisation — routine-level periodisation model (P1 leaves
// every routine at 'none'; the column is wired by P4).
export type GymPeriodisation = 'none' | 'linear' | 'block' | 'conjugate';
// gym_routine_exercises.modality — what axis the exercise is measured on.
export type GymExerciseModality = 'weight_reps' | 'time' | 'distance' | 'bodyweight_reps';
// gym_routine_exercises.progression — per-exercise progression scheme (wired by P4).
export type GymProgressionScheme =
	| 'none'
	| 'linear'
	| 'double_progression'
	| 'five_by_five'
	| 'percent_cycle'
	| 'rpe_autoreg';
// gym_routine_sets.set_type — set role within an exercise.
export type GymSetType = 'warmup' | 'working' | 'dropset' | 'amrap' | 'failure' | 'backoff';
// exercises.category — catalogue muscle-group / category (migration 20270222_001).
export type ExerciseCategory =
	| 'chest'
	| 'back'
	| 'shoulders'
	| 'legs'
	| 'arms'
	| 'core'
	| 'cardio'
	| 'full_body'
	| 'other';
// exercises — the structured exercise catalogue. author_id null = a seeded
// global (read-only); set = an owner-created custom. modality reuses
// GymExerciseModality so a catalogue pick can seed a gym_routine_exercise.
export type Exercise = Omit<ExerciseRow, 'category' | 'modality'> & {
	category: ExerciseCategory;
	modality: GymExerciseModality;
};
// Polymorphic report target. Kept in lockstep with the `reports.target_kind`
// CHECK constraint (migrations 20260908_001 / 20261117_001 / 20270115_001)
// via apps/web/scripts/check_constraint_unions.mjs.
export type ReportTargetKind = 'user' | 'club' | 'route' | 'comment' | 'club_post' | 'run';
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
	| 'event_reminder'
	| 'plan_assigned'
	| 'achievement'
	| 'challenge_complete'
	| 'content_hidden';

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

// Charity fundraising (fundraising.md). A fundraiser is polymorphic over
// (run | event) — exactly one anchor FK is set (CHECK-enforced). DonationRow's
// donor_user_id / owner_user_id / stripe ids / platform_fee_cents are revoked
// from client roles in the migration, so a base-table read never surfaces them;
// the public feed is served by the fundraiser_feed RPC (FundraiserFeedEntry).
export type Fundraiser = Omit<FundraiserRow, 'status'> & { status: FundraiserStatus };
export type Donation = Omit<DonationRow, 'status'> & { status: DonationStatus };

/** Public donation-feed row — the fundraiser_feed RPC projection (public-safe
 * columns only; donor identity / Stripe ids never surface). */
export interface FundraiserFeedEntry {
	display_name: string | null;
	message: string | null;
	amount_cents: number;
	currency: string;
	is_anonymous: boolean;
	paid_at: string | null;
}

/** Thermometer totals — the fundraiser_totals RPC projection. */
export interface FundraiserTotals {
	raised_cents: number;
	donor_count: number;
	goal_cents: number;
	currency: string;
}

export type SessionPlan = SessionPlanRow;
export type SessionPlanBlock = SessionPlanBlockRow;
export type SessionPlanItem = Omit<SessionPlanItemRow, 'kind'> & { kind: SessionItemKind };

/** A plan with its blocks + items, the shape the editor + read view consume. */
export type SessionPlanWithItems = SessionPlan & {
	blocks: SessionPlanBlock[];
	items: SessionPlanItem[];
};

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

// ─────────────────────── Challenges & competitions ───────────────────────

export type ChallengeMetric = 'distance' | 'duration' | 'vert' | 'activity_count' | 'streak_days';
export type ChallengeScope = 'individual' | 'club_vs_club' | 'group_goal';

export type Challenge = Omit<ChallengeRow, 'metric' | 'scope' | 'activity_type'> & {
	metric: ChallengeMetric;
	scope: ChallengeScope;
	activity_type: ActivityType | null;
};
export type ChallengeParticipant = ChallengeParticipantRow;
export type ChallengeBadge = ChallengeBadgeRow;

/** A row from the `challenge_leaderboard` RPC — not a table, so hand-typed. */
export type ChallengeLeaderboardRow = {
	user_id: string | null;
	display_name: string | null;
	team_club_id: string | null;
	value: number;
	rank: number;
};

/** Challenge plus the caller-relative meta the list + detail surfaces need. */
export type ChallengeWithMeta = Challenge & {
	participant_count: number;
	my_value: number | null;
	my_rank: number | null;
	joined: boolean;
	completed_at: string | null;
};
