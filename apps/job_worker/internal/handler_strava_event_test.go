package internal

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

// stravaEventPayload marshals a StravaEventPayload as the job
// queue would store it (json.RawMessage).
func stravaEventPayload(t *testing.T, p StravaEventPayload) json.RawMessage {
	t.Helper()
	b, err := json.Marshal(p)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func newStravaWorker(be Backend, st StravaIngestor) *Worker {
	w := newTestWorker(be, nil)
	w.Strava = st
	return w
}

func TestStravaEvent_DropsNonCreateAspects(t *testing.T) {
	be := newFakeBackend()
	st := &fakeStrava{}
	be.jobs = []*Job{{
		ID: 1, Kind: "strava_event",
		Payload: stravaEventPayload(t, StravaEventPayload{
			ObjectType: "activity", AspectType: "update",
			ObjectID: 100, OwnerID: 200, EventTime: time.Now().Unix(),
		}),
	}}
	w := newStravaWorker(be, st)
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 1 || be.finished[0].Status != "done" {
		t.Fatalf("update aspect should finish done; got %v", be.finished)
	}
	if len(st.activityCalls) != 0 {
		t.Errorf("non-create must not hit Strava; got %d activity fetches", len(st.activityCalls))
	}
	if len(be.insertedStravaRuns) != 0 {
		t.Errorf("non-create must not insert a runs row; got %d", len(be.insertedStravaRuns))
	}
}

func TestStravaEvent_DropsUnknownAthlete(t *testing.T) {
	be := newFakeBackend()
	// integrationByAthlete empty → owner 200 has no integration
	st := &fakeStrava{}
	be.jobs = []*Job{{
		ID: 1, Kind: "strava_event",
		Payload: stravaEventPayload(t, StravaEventPayload{
			ObjectType: "activity", AspectType: "create",
			ObjectID: 100, OwnerID: 200, EventTime: time.Now().Unix(),
		}),
	}}
	w := newStravaWorker(be, st)
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 1 || be.finished[0].Status != "done" {
		t.Fatalf("unknown athlete should finish done (Strava stops retry); got %v", be.finished)
	}
	if len(st.activityCalls) != 0 {
		t.Errorf("unknown athlete must short-circuit before the activity fetch")
	}
}

func TestStravaEvent_SkipsAlreadyImported(t *testing.T) {
	be := newFakeBackend()
	be.integrationByAthlete[200] = "user-A"
	be.alreadyImported[importedKey{"user-A", 100}] = true
	st := &fakeStrava{}
	be.jobs = []*Job{{
		ID: 1, Kind: "strava_event",
		Payload: stravaEventPayload(t, StravaEventPayload{
			ObjectType: "activity", AspectType: "create",
			ObjectID: 100, OwnerID: 200, EventTime: time.Now().Unix(),
		}),
	}}
	w := newStravaWorker(be, st)
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 1 || be.finished[0].Status != "done" {
		t.Fatalf("already-imported short-circuits to done; got %v", be.finished)
	}
	if len(st.activityCalls) != 0 {
		t.Errorf("already-imported must not refetch activity")
	}
}

func TestStravaEvent_HappyPathInsertsRunAndUploadsTrack(t *testing.T) {
	be := newFakeBackend()
	be.integrationByAthlete[200] = "user-A"
	be.tokensByUser["user-A"] = TokenPair{AccessToken: "at-A", RefreshToken: "rt-A"}

	ele := 12.5
	st := &fakeStrava{
		byActivity: map[int64]StravaActivityResult{
			100: {Status: StravaFetchOK, Activity: &StravaActivity{
				ID: 100, Name: "Morning Run", Distance: 5000, MovingTime: 1500,
				ElapsedTime: 1600, TotalElevationGain: 50, StartDate: "2026-05-11T10:00:00Z",
				Type: "Run", SportType: "Run",
			}},
		},
		streamsByActivity: map[int64]map[string]StravaStream{
			100: {
				"latlng":   {Data: []json.RawMessage{json.RawMessage(`[51.5,-0.1]`), json.RawMessage(`[51.6,-0.2]`)}},
				"altitude": {Data: []json.RawMessage{json.RawMessage(`12.5`), json.RawMessage(`13.0`)}},
				"time":     {Data: []json.RawMessage{json.RawMessage(`0`), json.RawMessage(`5`)}},
			},
		},
	}
	_ = ele

	be.jobs = []*Job{{
		ID: 1, Kind: "strava_event",
		Payload: stravaEventPayload(t, StravaEventPayload{
			ObjectType: "activity", AspectType: "create",
			ObjectID: 100, OwnerID: 200, EventTime: time.Now().Unix(),
		}),
	}}
	// Seed the dedupe row so the rollback path has something to delete
	// (mirrors what the HTTP endpoint did before enqueueing the job).
	be.webhookEvents[stravaEventID(StravaEventPayload{
		OwnerID: 200, ObjectID: 100, AspectType: "create",
	})] = true

	w := newStravaWorker(be, st)
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 1 || be.finished[0].Status != "done" {
		t.Fatalf("happy path must finish done; got %v", be.finished)
	}
	if len(be.insertedStravaRuns) != 1 {
		t.Fatalf("expected 1 runs row inserted; got %d", len(be.insertedStravaRuns))
	}
	row := be.insertedStravaRuns[0]
	if row.UserID != "user-A" || row.ActivityID != 100 {
		t.Errorf("inserted row=%+v", row)
	}
	if len(be.uploaded) != 1 {
		t.Errorf("expected 1 Storage upload (gzipped track); got %d", len(be.uploaded))
	}
	if len(be.trackURLPatches) != 1 {
		t.Errorf("expected 1 track_url PATCH; got %d", len(be.trackURLPatches))
	}
	if !strings.HasSuffix(be.trackURLPatches[0].URL, "/run-100.json.gz") {
		t.Errorf("track_url path=%q does not match {userId}/{runId}.json.gz",
			be.trackURLPatches[0].URL)
	}
}

func TestStravaEvent_DropsNonRunnableSport(t *testing.T) {
	be := newFakeBackend()
	be.integrationByAthlete[200] = "user-A"
	be.tokensByUser["user-A"] = TokenPair{AccessToken: "at-A", RefreshToken: "rt-A"}
	st := &fakeStrava{
		byActivity: map[int64]StravaActivityResult{
			100: {Status: StravaFetchOK, Activity: &StravaActivity{
				ID: 100, Name: "Bike ride", Distance: 20000, MovingTime: 3000,
				StartDate: "2026-05-11T10:00:00Z", Type: "Ride", SportType: "Ride",
			}},
		},
	}
	be.jobs = []*Job{{
		ID: 1, Kind: "strava_event",
		Payload: stravaEventPayload(t, StravaEventPayload{
			ObjectType: "activity", AspectType: "create",
			ObjectID: 100, OwnerID: 200, EventTime: time.Now().Unix(),
		}),
	}}
	w := newStravaWorker(be, st)
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 1 || be.finished[0].Status != "done" {
		t.Fatalf("ride should finish done (silently drop); got %v", be.finished)
	}
	if len(be.insertedStravaRuns) != 0 {
		t.Errorf("ride must not insert a runs row")
	}
}

func TestStravaEvent_RateLimitDefersAndRollsBackDedupe(t *testing.T) {
	be := newFakeBackend()
	be.integrationByAthlete[200] = "user-A"
	be.tokensByUser["user-A"] = TokenPair{AccessToken: "at-A", RefreshToken: "rt-A"}
	st := &fakeStrava{
		byActivity: map[int64]StravaActivityResult{
			100: {Status: StravaFetchRateLimited},
		},
	}
	// Seed the dedupe row.
	dedupeKey := stravaEventID(StravaEventPayload{
		OwnerID: 200, ObjectID: 100, AspectType: "create", EventTime: 1700000000,
	})
	be.webhookEvents["strava:"+dedupeKey] = true

	be.jobs = []*Job{{
		ID: 1, Kind: "strava_event",
		Payload: stravaEventPayload(t, StravaEventPayload{
			ObjectType: "activity", AspectType: "create",
			ObjectID: 100, OwnerID: 200, EventTime: 1700000000,
		}),
	}}
	w := newStravaWorker(be, st)
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	// 503 is transient — defer, not fail-permanent.
	if len(be.deferred) != 1 {
		t.Fatalf("rate-limited fetch should defer; got finished=%v deferred=%v",
			be.finished, be.deferred)
	}
	// Dedupe rollback so the retry isn't suppressed.
	if len(be.webhookDeletes) != 1 {
		t.Fatalf("expected the dedupe row to be deleted on retry; got deletes=%v", be.webhookDeletes)
	}
}

func TestStravaEvent_NoStravaClientFailsPermanent(t *testing.T) {
	be := newFakeBackend()
	be.jobs = []*Job{{
		ID: 1, Kind: "strava_event",
		Payload: stravaEventPayload(t, StravaEventPayload{
			ObjectType: "activity", AspectType: "create",
			ObjectID: 100, OwnerID: 200, EventTime: time.Now().Unix(),
		}),
	}}
	w := newTestWorker(be, nil) // Strava intentionally left nil
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 1 || be.finished[0].Status != "failed" {
		t.Fatalf("unconfigured worker must fail permanent; got %v", be.finished)
	}
}

func TestStravaEvent_ProactiveRefreshOnExpiringToken(t *testing.T) {
	be := newFakeBackend()
	be.integrationByAthlete[200] = "user-A"
	soon := time.Now().Add(2 * time.Minute) // expires inside the 5-min refresh window
	be.tokensByUser["user-A"] = TokenPair{
		AccessToken:  "at-old",
		RefreshToken: "rt-A",
		TokenExpiry:  &soon,
	}
	freshExpiry := time.Now().Add(6 * time.Hour).Unix()
	st := &fakeStrava{
		byToken: map[string]StravaTokenResponse{
			"rt-A": {AccessToken: "at-new", RefreshToken: "rt-A2", ExpiresAt: freshExpiry},
		},
		byActivity: map[int64]StravaActivityResult{
			100: {Status: StravaFetchOK, Activity: &StravaActivity{
				ID: 100, Distance: 100, StartDate: "2026-05-11T10:00:00Z", Type: "Run",
			}},
		},
	}

	be.jobs = []*Job{{
		ID: 1, Kind: "strava_event",
		Payload: stravaEventPayload(t, StravaEventPayload{
			ObjectType: "activity", AspectType: "create",
			ObjectID: 100, OwnerID: 200, EventTime: time.Now().Unix(),
		}),
	}}
	w := newStravaWorker(be, st)
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(st.calls) != 1 {
		t.Fatalf("expected one proactive refresh call; got %d", len(st.calls))
	}
	if len(be.setTokenCalls) != 1 || be.setTokenCalls[0].AccessToken != "at-new" {
		t.Fatalf("rotated token wasn't persisted: %+v", be.setTokenCalls)
	}
}

func TestBuildTrackFromStreams_HappyPathWithHr(t *testing.T) {
	streams := map[string]StravaStream{
		"latlng":    {Data: []json.RawMessage{json.RawMessage(`[51.5,-0.1]`), json.RawMessage(`[51.6,-0.2]`)}},
		"altitude":  {Data: []json.RawMessage{json.RawMessage(`12.5`), json.RawMessage(`13.0`)}},
		"time":      {Data: []json.RawMessage{json.RawMessage(`0`), json.RawMessage(`5`)}},
		"heartrate": {Data: []json.RawMessage{json.RawMessage(`140`), json.RawMessage(`145`)}},
	}
	track := BuildTrackFromStreams(streams, "2026-05-11T10:00:00Z")
	if len(track) != 2 {
		t.Fatalf("expected 2 points; got %d", len(track))
	}
	if track[0].Lat != 51.5 || *track[0].Bpm != 140 {
		t.Errorf("first point wrong: %+v", track[0])
	}
}

func TestBuildTrackFromStreams_DropsOutOfRangeBpm(t *testing.T) {
	streams := map[string]StravaStream{
		"latlng":    {Data: []json.RawMessage{json.RawMessage(`[51.5,-0.1]`)}},
		"heartrate": {Data: []json.RawMessage{json.RawMessage(`250`)}}, // out of range
	}
	track := BuildTrackFromStreams(streams, "2026-05-11T10:00:00Z")
	if len(track) != 1 || track[0].Bpm != nil {
		t.Errorf("out-of-range bpm must be dropped; got %+v", track)
	}
}

func TestBuildTrackFromStreams_EmptyLatLngYieldsEmpty(t *testing.T) {
	track := BuildTrackFromStreams(map[string]StravaStream{}, "2026-05-11T10:00:00Z")
	if len(track) != 0 {
		t.Errorf("expected empty track; got %d points", len(track))
	}
}
