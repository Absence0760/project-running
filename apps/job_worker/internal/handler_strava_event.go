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
	case StravaFetchRateLimited:
		// Roll back the dedupe row so the next retry reopens the
		// gate. Without this the retried event would 23505 on the
		// webhook side and silently skip the activity.
		eventID := stravaEventID(p)
		if delErr := w.Backend.DeleteWebhookEvent(ctx, "strava", eventID); delErr != nil {
			w.Log.Warn("strava_event: failed to roll back dedupe row before retry",
				"err", delErr, "event_id", eventID)
		}
		return &HTTPError{StatusCode: 503, Body: "strava rate-limited"}
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

	info, err := w.Backend.InsertStravaRun(ctx, userID, act)
	if err != nil {
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

	out := make([]TrackPoint, 0, len(latlng))
	for i, raw := range latlng {
		var pair []float64
		if err := json.Unmarshal(raw, &pair); err != nil || len(pair) < 2 {
			continue
		}
		lat, lng := pair[0], pair[1]
		if !isFiniteFloat(lat) || !isFiniteFloat(lng) {
			continue
		}
		pt := TrackPoint{Lat: lat, Lng: lng}
		if i < len(altitude) {
			var ele float64
			if json.Unmarshal(altitude[i], &ele) == nil {
				pt.Elevation = &ele
			}
		}
		if i < len(time_) && !startMs.IsZero() {
			var sec int64
			if json.Unmarshal(time_[i], &sec) == nil {
				ts := time.UnixMilli(startUnix + sec*1000).UTC()
				pt.Timestamp = &ts
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
