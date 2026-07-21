package internal

// HTTP-level coverage for the live-ping Bridge's Supabase methods:
// InsertLivePing (hub→Realtime persist) and ReadLivePingsSince /
// MaxLivePingID (the Realtime→hub poll's reader). Same httptest idiom
// as supabase_matchedtrack_test.go.

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"testing"

	"github.com/Absence0760/project-running/apps/job_worker/internal/livehub"
)

func TestInsertLivePing_WireShape(t *testing.T) {
	var capturedPath, capturedPrefer string
	var capturedBody map[string]any
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path
		capturedPrefer = r.Header.Get("Prefer")
		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &capturedBody)
		w.WriteHeader(http.StatusCreated)
	})

	ele := 42.5
	bpm := 150
	p := livehub.Ping{Lat: 51.5, Lng: -0.1, DistanceM: 500, ElapsedS: 120, BPM: &bpm, Elevation: &ele}
	if err := client.InsertLivePing(context.Background(), "run-1", "user-A", p); err != nil {
		t.Fatalf("InsertLivePing: %v", err)
	}

	if want := "/rest/v1/live_run_pings"; capturedPath != want {
		t.Errorf("path=%q, want %q", capturedPath, want)
	}
	if capturedPrefer != "return=minimal" {
		t.Errorf("Prefer=%q, want return=minimal", capturedPrefer)
	}
	if capturedBody["run_id"] != "run-1" || capturedBody["user_id"] != "user-A" {
		t.Errorf("run_id/user_id = %v/%v, want run-1/user-A", capturedBody["run_id"], capturedBody["user_id"])
	}
	// JSON numbers decode as float64.
	if capturedBody["lat"] != 51.5 || capturedBody["lng"] != -0.1 || capturedBody["distance_m"] != 500.0 || capturedBody["elapsed_s"] != 120.0 {
		t.Errorf("core fields wrong: %+v", capturedBody)
	}
	if capturedBody["bpm"] != 150.0 || capturedBody["ele"] != 42.5 {
		t.Errorf("optional fields wrong: bpm=%v ele=%v", capturedBody["bpm"], capturedBody["ele"])
	}
}

func TestInsertLivePing_OmitsAbsentOptionalFields(t *testing.T) {
	var capturedBody map[string]any
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &capturedBody)
		w.WriteHeader(http.StatusCreated)
	})
	// No BPM / elevation → those keys must be absent (not null).
	p := livehub.Ping{Lat: 1, Lng: 2, DistanceM: 0, ElapsedS: 0}
	if err := client.InsertLivePing(context.Background(), "run-1", "user-A", p); err != nil {
		t.Fatalf("InsertLivePing: %v", err)
	}
	if _, ok := capturedBody["bpm"]; ok {
		t.Errorf("bpm should be omitted when absent, body=%+v", capturedBody)
	}
	if _, ok := capturedBody["ele"]; ok {
		t.Errorf("ele should be omitted when absent, body=%+v", capturedBody)
	}
	// distance_m / elapsed_s are always sent — 0 at the start line is real.
	if _, ok := capturedBody["distance_m"]; !ok {
		t.Errorf("distance_m must always be sent, body=%+v", capturedBody)
	}
}

func TestMaxLivePingID_And_ReadSince(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Query().Get("order") == "id.desc" {
			_, _ = w.Write([]byte(`[{"id":77}]`))
			return
		}
		// ReadLivePingsSince: assert the cursor + ordering are on the query.
		if got := r.URL.Query().Get("id"); got != "gt.5" {
			t.Errorf("id filter=%q, want gt.5", got)
		}
		if got := r.URL.Query().Get("order"); got != "id.asc" {
			t.Errorf("order=%q, want id.asc", got)
		}
		_, _ = w.Write([]byte(`[
			{"id":6,"run_id":"run-1","lat":51.5,"lng":-0.1,"ele":10,"elapsed_s":60,"distance_m":100,"bpm":140,"coarse":false},
			{"id":7,"run_id":"run-2","lat":1,"lng":2,"coarse":true}
		]`))
	})

	max, err := client.MaxLivePingID(context.Background())
	if err != nil || max != 77 {
		t.Fatalf("MaxLivePingID = %d, %v; want 77, nil", max, err)
	}

	rows, err := client.ReadLivePingsSince(context.Background(), 5, 500)
	if err != nil {
		t.Fatalf("ReadLivePingsSince: %v", err)
	}
	if len(rows) != 2 {
		t.Fatalf("rows=%d, want 2", len(rows))
	}
	if rows[0].ID != 6 || rows[0].RunID != "run-1" || rows[0].Ele == nil || *rows[0].Ele != 10 || rows[0].BPM == nil || *rows[0].BPM != 140 {
		t.Errorf("row0 decoded wrong: %+v", rows[0])
	}
	if rows[1].ID != 7 || !rows[1].Coarse {
		t.Errorf("row1 coarse flag not decoded: %+v", rows[1])
	}
	if rows[1].Ele != nil || rows[1].BPM != nil {
		t.Errorf("row1 absent optionals should be nil: %+v", rows[1])
	}
}
