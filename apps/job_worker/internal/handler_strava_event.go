package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// handleStravaEvent ingests a single Strava webhook event that was
// enqueued by `internal/stravahook/server.go`. Mirrors the
// `apps/backend/supabase/functions/strava-webhook` Edge Function it
// replaces — the runs row, dedupe key, and metadata keys are
// byte-identical so dashboard reads across the EF and Go paths see
// one consistent shape.
//
// Error semantics:
//
//   - Aspect != "create" → finish_job(done). Updates / deletes are
//     a no-op for now (mobile import handles edits on the next
//     manual sync); ack and move on.
//   - Integration row missing (user disconnected since the webhook
//     fired) → finish_job(done). Strava would retry forever on
//     non-200; we'd rather drop the event than have it bounce.
//   - Activity already imported (`metadata.strava_id` dedupe) →
//     finish_job(done). A webhook firing during a backfill is the
//     common cause.
//   - Strava 429 / 503 on the activity fetch → defer + retry. The
//     `webhook_events` dedupe row is rolled back so the next
//     attempt isn't suppressed.
//   - Activity is a Ride / sport we don't surface → finish_job(done).
//   - Token-refresh failures + ingest failures bubble through the
//     classifier; 5xx defers, 4xx + parse errors fail permanent.
//
// The activity-fetch happens after the dedupe insert is committed so
// the worker can rely on at-most-once ingest semantics — a parallel
// re-claim of the same job (process restart mid-run) sees the
// dedupe row and exits cleanly.
func (w *Worker) handleStravaEvent(ctx context.Context, job *Job) error {
	if w.Strava == nil {
		return errors.New("strava_event: Strava client not configured (missing STRAVA_CLIENT_ID/SECRET)")
	}

	var p StravaEventPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("strava_event: bad payload: %w", err)
	}
	if p.ObjectType != "activity" || p.AspectType != "create" {
		// Strava ack'd 200 already at the webhook endpoint for these;
		// the job exists only because we enqueued before filtering.
		// Drop cleanly.
		w.Log.Info("strava_event: skip non-create aspect", "aspect", p.AspectType)
		return nil
	}
	if p.ObjectID <= 0 || p.OwnerID <= 0 {
		return fmt.Errorf("strava_event: invalid object_id=%d owner_id=%d", p.ObjectID, p.OwnerID)
	}

	userID, err := w.Backend.FindIntegrationUserByAthlete(ctx, "strava", p.OwnerID)
	if err != nil {
		return fmt.Errorf("strava_event: integration lookup: %w", err)
	}
	if userID == "" {
		w.Log.Info("strava_event: no integration for athlete; dropping", "owner_id", p.OwnerID)
		return nil
	}

	already, err := w.Backend.IsStravaActivityImported(ctx, userID, p.ObjectID)
	if err != nil {
		return fmt.Errorf("strava_event: dedupe check: %w", err)
	}
	if already {
		w.Log.Info("strava_event: already imported (backfill won the race)", "activity_id", p.ObjectID)
		return nil
	}

	tokens, err := w.Backend.GetIntegrationTokens(ctx, userID, "strava")
	if err != nil {
		return fmt.Errorf("strava_event: token fetch: %w", err)
	}
	if tokens == nil || tokens.AccessToken == "" {
		// User disconnected Strava but the integration row outlived
		// the disconnect, or Vault returned nothing. Either way we
		// can't act on this event — ack as done so Strava stops
		// retrying.
		w.Log.Info("strava_event: no access token in vault; dropping", "user_id", userID)
		return nil
	}

	accessToken := tokens.AccessToken
	// Proactive refresh: if the token expires within 5 minutes of now,
	// rotate it before the activity fetch. Webhooks can fire hours
	// after the user last touched the app, so the "live" access token
	// at handler time is frequently stale.
	if tokens.TokenExpiry != nil && time.Now().Add(5*time.Minute).After(*tokens.TokenExpiry) {
		fresh, refreshErr := w.Strava.Refresh(ctx, tokens.RefreshToken)
		if refreshErr == nil && fresh != nil && fresh.AccessToken != "" {
			accessToken = fresh.AccessToken
			expiry := time.Unix(fresh.ExpiresAt, 0).UTC()
			if setErr := w.Backend.SetIntegrationTokens(ctx, userID, "strava",
				fresh.AccessToken, fresh.RefreshToken, expiry); setErr != nil {
				w.Log.Warn("strava_event: token persist after refresh failed",
					"err", setErr, "user_id", userID)
			}
		} else if refreshErr != nil {
			// A failed refresh doesn't block the ingest — the existing
			// token may still have a few minutes left. If the activity
			// fetch lands on the same expiry boundary, the upstream
			// 401 surfaces through the classifier as fail-permanent
			// (4xx), which is the right outcome: the user must
			// re-connect.
			w.Log.Warn("strava_event: proactive refresh failed; trying with old token",
				"err", refreshErr, "user_id", userID)
		}
	}

	result, err := w.Strava.FetchActivity(ctx, accessToken, p.ObjectID)
	if err != nil {
		return fmt.Errorf("strava_event: fetch activity: %w", err)
	}
	switch result.Status {
	case StravaFetchRateLimited, StravaFetchTransient:
		// Roll back the dedupe row so the next retry reopens the
		// gate. Without this the retried event would 23505 on the
		// webhook side and silently skip the activity.
		// Transient covers Strava 5xx + network-layer failures —
		// audit/strava H5. Pre-fix every non-2xx-non-429/503
		// silently dropped the user's activity on a Strava outage.
		eventID := stravaEventID(p)
		if delErr := w.Backend.DeleteWebhookEvent(ctx, "strava", eventID); delErr != nil {
			w.Log.Warn("strava_event: failed to roll back dedupe row before retry",
				"err", delErr, "event_id", eventID)
		}
		reason := "strava rate-limited"
		if result.Status == StravaFetchTransient {
			reason = "strava transient (5xx/network)"
		}
		return &HTTPError{StatusCode: 503, Body: reason}
	case StravaFetchNotFound:
		w.Log.Info("strava_event: activity vanished or fetch unauthorised; dropping",
			"activity_id", p.ObjectID)
		return nil
	}
	act := result.Activity
	if act == nil {
		return errors.New("strava_event: fetch ok but activity nil")
	}

	// Activity-type gate — only ingest run / walk / hike. Mirrors the
	// EF check at strava-webhook/index.ts line 256-263.
	sport := strings.ToLower(act.SportType)
	if sport == "" {
		sport = strings.ToLower(act.Type)
	}
	if !strings.Contains(sport, "run") &&
		!strings.Contains(sport, "walk") &&
		!strings.Contains(sport, "hike") {
		w.Log.Info("strava_event: dropping non-runnable activity",
			"activity_id", p.ObjectID, "type", act.Type, "sport_type", act.SportType)
		return nil
	}

	// Cross-provider near-duplicate guard. The strava_id dedupe above only
	// catches a re-import of THIS Strava activity; a dual-connected runner
	// (Garmin watch auto-uploading to Strava, then the same run pulled from a
	// Garmin bulk-export ZIP or Apple HealthKit) lands the effort under a
	// different source with no shared provider id. Pull the runs starting
	// within the tolerance window across all sources and skip if this effort
	// already exists under any of them — this is the LIVE webhook path the
	// e03a349b import fix never covered. Fail-open: a lookup error must not
	// drop the activity (the DB external_id unique index is still a backstop).
	if startMs, perr := time.Parse(time.RFC3339, act.StartDate); perr == nil {
		near, nearErr := w.Backend.FetchRunIdentitiesNear(
			ctx, userID, startMs.UnixMilli(), CrossProviderStartToleranceS)
		if nearErr != nil {
			w.Log.Warn("strava_event: cross-provider dedupe lookup failed; proceeding",
				"err", nearErr, "activity_id", p.ObjectID)
		} else if IsCrossProviderDuplicate(
			RunIdentity{StartedAtMs: startMs.UnixMilli(), DistanceM: act.Distance}, near) {
			w.Log.Info("strava_event: skip — same effort already present under another source",
				"activity_id", p.ObjectID, "user_id", userID)
			return nil
		}
	}

	info, err := w.Backend.InsertStravaRun(ctx, userID, act)
	if err != nil {
		// A concurrent backfill (strava-import EF) can insert the same
		// activity between our dedupe check and this insert, colliding on the
		// per-user external_id unique index (23505 → PostgREST 409). That's a
		// benign duplicate — the activity is imported, just by the other
		// writer — so ack done rather than flip the job to permanent-failed.
		var hErr *HTTPError
		if errors.As(err, &hErr) && hErr.StatusCode == 409 && strings.Contains(hErr.Body, "23505") {
			w.Log.Info("strava_event: insert raced a concurrent import (23505); treating as already imported",
				"activity_id", p.ObjectID, "user_id", userID)
			return nil
		}
		return fmt.Errorf("strava_event: insert run: %w", err)
	}

	// Best-effort track upload — short / indoor activities have no
	// streams and Strava returns 404, which we treat as success
	// (the row is valid without a track).
	if act.Distance >= 200 {
		streams, streamErr := w.Strava.FetchStreams(ctx, accessToken, p.ObjectID)
		if streamErr != nil {
			w.Log.Warn("strava_event: stream fetch failed (row inserted, track skipped)",
				"err", streamErr, "activity_id", p.ObjectID)
		} else if streams != nil {
			track := BuildTrackFromStreams(streams, act.StartDate)
			if len(track) >= 2 {
				path := fmt.Sprintf("%s/%s.json.gz", info.UserID, info.ID)
				if err := w.Backend.UploadMatchedTrack(ctx, path, track); err != nil {
					w.Log.Warn("strava_event: track upload failed (row kept, track_url unset)",
						"err", err, "activity_id", p.ObjectID)
				} else if err := w.Backend.UpdateRunTrackURL(ctx, info.ID, path); err != nil {
					w.Log.Warn("strava_event: track_url patch failed",
						"err", err, "activity_id", p.ObjectID)
				}
			}
		}
	}

	w.Log.Info("strava_event: ingested",
		"activity_id", p.ObjectID, "user_id", userID, "run_id", info.ID)
	return nil
}

// stravaEventID reconstructs the dedupe key the webhook endpoint
// computed when it inserted the `webhook_events` row. Kept in this
// file so the rollback path doesn't need to round-trip the key
// through the job payload.
func stravaEventID(p StravaEventPayload) string {
	return fmt.Sprintf("%d:%d:%s:%d", p.OwnerID, p.ObjectID, p.AspectType, p.EventTime)
}

// BuildTrackFromStreams walks Strava's per-stream JSON arrays into a
// TrackPoint slice the run's Storage upload can consume. Mirrors the
// EF helper of the same name (apps/backend/supabase/functions/
// _shared/strava.ts) — fields, point shape, dropped-sample policy
// all in lockstep so a webhook-ingested track loads identically to
// one from the strava-import EF.
func BuildTrackFromStreams(streams map[string]StravaStream, startIso string) []TrackPoint {
	latlng := streams["latlng"].Data
	if len(latlng) == 0 {
		return nil
	}
	altitude := streams["altitude"].Data
	time_ := streams["time"].Data
	hr := streams["heartrate"].Data

	startMs, _ := time.Parse(time.RFC3339, startIso)
	startUnix := startMs.UnixMilli()

	// audit/strava May 2026 High #4 — bounds-check every sample.
	// Pre-fix, lat/lng outside the legal [-90,90]/[-180,180] window
	// (corrupted Strava stream from a third-party uploader, operator
	// error) was persisted as-is and rendered an unmappable run.
	// Also enforce a monotonic-time guard: a sample whose timestamp
	// goes backwards more than 1 second from the previous one is
	// dropped (a 1 s wobble is allowed for upstream clock jitter).
	out := make([]TrackPoint, 0, len(latlng))
	var lastTs int64 = -1 // ms since epoch of the previous accepted sample
	for i, raw := range latlng {
		var pair []float64
		if err := json.Unmarshal(raw, &pair); err != nil || len(pair) < 2 {
			continue
		}
		lat, lng := pair[0], pair[1]
		if !isFiniteFloat(lat) || !isFiniteFloat(lng) {
			continue
		}
		if lat < -90 || lat > 90 || lng < -180 || lng > 180 {
			continue
		}
		pt := TrackPoint{Lat: lat, Lng: lng}
		if i < len(altitude) {
			var ele float64
			if json.Unmarshal(altitude[i], &ele) == nil && isFiniteFloat(ele) && ele >= -500 && ele <= 9000 {
				pt.Elevation = &ele
			}
		}
		if i < len(time_) && !startMs.IsZero() {
			var sec int64
			if json.Unmarshal(time_[i], &sec) == nil {
				ts := startUnix + sec*1000
				// Reject a sample whose ms-since-epoch goes backwards
				// more than 1s from the prior accepted sample. Tolerate
				// 1s wobble for upstream clock jitter.
				if lastTs >= 0 && ts < lastTs-1000 {
					continue
				}
				lastTs = ts
				t := time.UnixMilli(ts).UTC()
				pt.Timestamp = &t
			}
		}
		if i < len(hr) {
			var bpm int
			if json.Unmarshal(hr[i], &bpm) == nil && bpm >= 30 && bpm <= 230 {
				b := bpm
				pt.Bpm = &b
			}
		}
		out = append(out, pt)
	}
	return out
}

func isFiniteFloat(f float64) bool {
	return !(f != f) && f > -1e308 && f < 1e308
}
