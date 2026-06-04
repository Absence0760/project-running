package internal

import (
	"encoding/json"
	"time"
)

// Job is the row shape returned by claim_next_job. The function returns
// (id, kind, payload, attempts) — we don't need the rest of the row for
// the handler path.
type Job struct {
	ID       int64           `json:"id"`
	Kind     string          `json:"kind"`
	Payload  json.RawMessage `json:"payload"`
	Attempts int16           `json:"attempts"`
}

// MapMatchPayload is the payload shape the runs trigger writes for
// kind='map_match'. Defined in
// apps/backend/supabase/migrations/20260609_001_run_match_pipeline.sql.
type MapMatchPayload struct {
	RunID  string `json:"run_id"`
	UserID string `json:"user_id"`
}

// TrackPoint mirrors the Dart / TypeScript TrackPoint shape uploaded by
// every recorder. The watch_wear and mobile recorders write
// {lat, lng, ele, ts}; older imports may omit ele or ts; Strava-imported
// tracks add `bpm` when the activity had a HR stream (mirrored from
// apps/web/src/lib/types.ts).
type TrackPoint struct {
	Lat       float64    `json:"lat"`
	Lng       float64    `json:"lng"`
	Elevation *float64   `json:"ele,omitempty"`
	Timestamp *time.Time `json:"ts,omitempty"`
	Bpm       *int       `json:"bpm,omitempty"`
}

// MatchOutput is what a Matcher hands back to the worker. The matched
// track is uploaded under matched_track_url; the algorithm name + version
// land on the run_matched_tracks row so re-matching can be triggered
// when the engine improves.
type MatchOutput struct {
	Points           []TrackPoint
	Algorithm        string
	AlgorithmVersion string
}

// MatchedTrackRow is the subset of run_matched_tracks the worker writes
// after a successful match. PATCH'd via PostgREST.
type MatchedTrackRow struct {
	Status           string     `json:"status"`
	MatchedTrackURL  string     `json:"matched_track_url"`
	MatchedAt        *time.Time `json:"matched_at,omitempty"`
	Algorithm        string     `json:"algorithm"`
	AlgorithmVersion string     `json:"algorithm_version"`
	ErrorMessage     *string    `json:"error_message"`
}

// RouteMatchCandidate is a row returned by the
// routes_intersecting_track RPC (migration 20260610_001). Same shape
// as the Dart core_models class — keeping the names in sync helps
// when the worker logs hint at a client-side discrepancy.
type RouteMatchCandidate struct {
	ID           string  `json:"id"`
	Name         string  `json:"name"`
	DistanceM    float64 `json:"distance_m"`
	StartOffsetM float64 `json:"start_offset_m"`
	EndOffsetM   float64 `json:"end_offset_m"`
}

// IntegrationRow is the minimal projection of `integrations` the
// token-refresh handler needs. Real tokens live in Vault and are
// fetched via the `get_integration_tokens` SECURITY DEFINER RPC —
// the row itself never holds plaintext.
type IntegrationRow struct {
	ID     int64  `json:"id"`
	UserID string `json:"user_id"`
}

// TokenPair mirrors the `get_integration_tokens` RPC return — a
// single-row table of decrypted (access, refresh) values.
type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	// TokenExpiry is the integration row's separate `token_expiry`
	// column — useful when the worker needs to decide whether to
	// proactively refresh ahead of a hot path call (Strava webhook
	// activity fetch). The `get_integration_tokens` RPC returns
	// this; older callers can ignore it.
	TokenExpiry *time.Time `json:"token_expiry,omitempty"`
}

// PhotoProcessPayload is the payload shape the `run_photos` AFTER
// INSERT trigger writes for `kind='photo_process'` jobs (migration
// `20260825_001_jobs_kind_allowlist_photo_process.sql`). The handler
// downloads the photo from the `run-photos` Storage bucket, strips
// JPEG EXIF / XMP / ICC metadata via `internal/exif`, and re-uploads
// in place. `owner_id` isn't strictly needed for the strip — the
// `storage_path` already encodes it as the leading folder — but it's
// carried for log-line breadcrumbs and future per-owner rate limits.
type PhotoProcessPayload struct {
	PhotoID     string `json:"photo_id"`
	StoragePath string `json:"storage_path"`
	OwnerID     string `json:"owner_id"`
}

// StravaEventPayload is the payload shape the Go webhook endpoint
// enqueues for `kind='strava_event'` jobs. Mirrors the wire shape
// Strava POSTs to the subscription URL — see
// `apps/job_worker/internal/stravahook/server.go` for the
// validation gate and `handler_strava_event.go` for the ingest
// dispatch.
type StravaEventPayload struct {
	ObjectType string `json:"object_type"` // "activity" — anything else is ignored
	ObjectID   int64  `json:"object_id"`   // Strava activity id
	AspectType string `json:"aspect_type"` // "create" | "update" | "delete"
	OwnerID    int64  `json:"owner_id"`    // Strava athlete id (== integrations.external_id for the user)
	EventTime  int64  `json:"event_time"`  // unix seconds
}

// NotificationEmailPayload is the payload the notifications AFTER INSERT
// trigger writes for `kind='notification_email'` jobs (migration
// `20261130_001_notification_email_channel.sql`). The handler loads the
// referenced notification, checks the recipient's channel preference,
// resolves their address, and sends.
type NotificationEmailPayload struct {
	NotificationID string `json:"notification_id"`
}

// NotificationRow is the projection of `notifications` the email handler
// reads. The source-link FKs (run_id / event_id / club_id / comment_id)
// are nullable — only the one relevant to the kind is populated — and
// drive the deep link in the rendered mail. EmailSentAt is the idempotency
// guard: non-NULL means a prior attempt already sent or deliberately
// skipped this row.
type NotificationRow struct {
	ID          string  `json:"id"`
	UserID      string  `json:"user_id"`
	Kind        string  `json:"kind"`
	RunID       *string `json:"run_id"`
	EventID     *string `json:"event_id"`
	ClubID      *string `json:"club_id"`
	CommentID   *string `json:"comment_id"`
	EmailSentAt *string `json:"email_sent_at"`
}

// LifecycleEmailPayload is the payload for `kind='lifecycle_email'` jobs
// (migration 20261202_001). Unlike notification_email, there's no
// notifications row — the job names a template the worker renders for the
// user. The first template is `welcome`, enqueued by the AFTER INSERT
// trigger on user_profiles. Future scheduled mail (weekly digest,
// re-engagement) reuses this kind with its own template + opt-in gate.
type LifecycleEmailPayload struct {
	UserID   string `json:"user_id"`
	Template string `json:"template"`
}

// SafetyEmailPayload is the payload for `kind='safety_email'` jobs
// (migration 20261218_001). Safety-contact mail is neither channel: it has
// no notifications row (so not notification_email) and the recipient may be
// a non-user identified only by an email + the copy carries per-finish
// context (so not lifecycle_email). Two templates:
//   - "confirm": the opt-in request, enqueued by the safety_contacts AFTER
//     INSERT trigger; carries the confirm_token for the email-link confirm.
//   - "finish": the finish alert, enqueued by the runs AFTER INSERT trigger
//     for every CONFIRMED contact regardless of is_public; carries the run
//     facts (distance/time).
//
// ContactEmail is always set (the address the alert goes to). ContactUserID
// is set only for a contact linked to an app account — used purely to
// localize the mail to their language; it is NOT a preference gate (a safety
// contact opted in explicitly and must not be silenced by the runner's
// email_notifications setting). decisions §131.
type SafetyEmailPayload struct {
	Template      string  `json:"template"`
	ContactUserID *string `json:"contact_user_id"`
	ContactEmail  string  `json:"contact_email"`
	OwnerName     string  `json:"owner_name"`
	RunID         *string `json:"run_id"`
	DistanceM     float64 `json:"distance_m"`
	DurationS     int     `json:"duration_s"`
	ConfirmToken  string  `json:"confirm_token"`
}

// StravaActivity is the subset of Strava's `/api/v3/activities/{id}`
// response the ingest path consumes. Mirrors the EF shape at
// `apps/backend/supabase/functions/_shared/strava.ts` — keep these
// in lockstep so a webhook-ingested run looks byte-identical to
// one from the strava-import EF.
type StravaActivity struct {
	ID                 int64   `json:"id"`
	Name               string  `json:"name"`
	Distance           float64 `json:"distance"`             // metres
	MovingTime         int     `json:"moving_time"`          // seconds
	ElapsedTime        int     `json:"elapsed_time"`         // seconds
	TotalElevationGain float64 `json:"total_elevation_gain"` // metres
	StartDate          string  `json:"start_date"`           // ISO 8601
	Type               string  `json:"type"`                 // "Run" / "Walk" / "Hike" / "Ride" / ...
	SportType          string  `json:"sport_type"`           // newer, more granular field
	AverageHeartrate   float64 `json:"average_heartrate"`
	HasHeartrate       bool    `json:"has_heartrate"`
}

// StravaFetchOutcome bands the three categorical outcomes the
// webhook handler must distinguish (so a 429 from Strava produces
// a defer + retry, while a 404 produces a finish-done that doesn't
// retry forever).
type StravaFetchOutcome int

const (
	StravaFetchOK StravaFetchOutcome = iota
	StravaFetchRateLimited
	StravaFetchNotFound
	// StravaFetchTransient = 5xx (500/502/503/504) or network-level
	// failure. The caller defers + retries the same way as
	// RateLimited. /audit/strava May 2026 High #5 — pre-fix, every
	// non-2xx-non-429/503 silently dropped the user's activity on a
	// transient Strava-side outage (multi-hour 5xx incidents at
	// least quarterly).
	StravaFetchTransient
)

// StravaActivityResult is the return type of
// StravaClient.FetchActivity. Status carries the categorical
// outcome; Activity is non-nil only when Status == StravaFetchOK.
type StravaActivityResult struct {
	Status   StravaFetchOutcome
	Activity *StravaActivity
}

// IngestedRunInfo is the projection of an inserted run row the
// strava_event handler needs to know in order to upload the
// gzipped track to Storage afterwards. Returned by
// `Backend.InsertStravaRun`.
type IngestedRunInfo struct {
	ID     string `json:"id"`
	UserID string `json:"user_id"`
}
