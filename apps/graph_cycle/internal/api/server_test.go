package api

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Absence0760/project-running/apps/graph_cycle/internal/graph"
)

// testServer builds a 9×9 grid foot graph (loop-rich) behind the API. The
// graph package's exported Build path needs a PBF, so the API tests lean on the
// in-process search over a hand-built graph via a tiny exported test seam.
func testServer(t *testing.T) (*Server, float64, float64) {
	t.Helper()
	g, stats := graph.BuildTestGrid(9, 9, 100, 40.0, -77.0)
	cLat := 40.0 + 4*0.000898 // ~4 cells north; approximate, only used as a query point
	cLng := -77.0 + 4*0.001173
	return New(g, stats, slog.New(slog.NewTextHandler(io.Discard, nil))), cLat, cLng
}

func do(t *testing.T, s *Server, method, target, body string) *httptest.ResponseRecorder {
	t.Helper()
	mux := http.NewServeMux()
	s.RegisterRoutes(mux)
	req := httptest.NewRequest(method, target, strings.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}

func TestHealth(t *testing.T) {
	s, _, _ := testServer(t)
	rec := do(t, s, http.MethodGet, "/health", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("health status = %d", rec.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["status"] != "ok" {
		t.Fatalf("health body = %v", body)
	}
	if body["nodes"].(float64) <= 0 {
		t.Fatalf("health nodes = %v, want > 0", body["nodes"])
	}
}

func TestCycleHappyPath(t *testing.T) {
	s, cLat, cLng := testServer(t)
	body := `{"start":{"lat":` + ftoa(cLat) + `,"lng":` + ftoa(cLng) + `},"targetDistanceM":800}`
	rec := do(t, s, http.MethodPost, "/cycle", body)
	if rec.Code != http.StatusOK {
		t.Fatalf("cycle status = %d body=%s", rec.Code, rec.Body.String())
	}
	var body2 struct {
		Found       bool         `json:"found"`
		Coordinates [][2]float64 `json:"coordinates"`
		DistanceM   float64      `json:"distanceM"`
		AreaEff     float64      `json:"areaEfficiency"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body2); err != nil {
		t.Fatal(err)
	}
	if !body2.Found {
		t.Fatal("expected found=true in a dense grid")
	}
	if len(body2.Coordinates) < 4 {
		t.Fatalf("coords len = %d", len(body2.Coordinates))
	}
	if body2.DistanceM < 600 || body2.DistanceM > 1000 {
		t.Fatalf("distance = %.0f, want ~800", body2.DistanceM)
	}
	// Wire order is [lng, lat].
	if body2.Coordinates[0][0] > 0 {
		t.Fatalf("first coord lng = %v, expected negative (around -77)", body2.Coordinates[0][0])
	}
}

func TestCycleLoopPoor(t *testing.T) {
	g, stats := graph.BuildTestLine(30, 100, 40.0, -77.0)
	s := New(g, stats, slog.New(slog.NewTextHandler(io.Discard, nil)))
	body := `{"start":{"lat":40.0,"lng":-77.0},"targetDistanceM":1000}`
	rec := do(t, s, http.MethodPost, "/cycle", body)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var body2 struct {
		Found bool `json:"found"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body2)
	if body2.Found {
		t.Fatal("line graph must report found=false (loop-poor)")
	}
}

func TestCycleValidation(t *testing.T) {
	s, _, _ := testServer(t)
	cases := []struct {
		name, body string
	}{
		{"empty body", ``},
		{"bad json", `{`},
		{"unknown field", `{"start":{"lat":40,"lng":-77},"targetDistanceM":800,"x":1}`},
		{"nan target via missing", `{"start":{"lat":40,"lng":-77}}`},
		{"zero target", `{"start":{"lat":40,"lng":-77},"targetDistanceM":0}`},
		{"absurd target", `{"start":{"lat":40,"lng":-77},"targetDistanceM":99999999}`},
		{"out-of-range lat", `{"start":{"lat":120,"lng":-77},"targetDistanceM":800}`},
	}
	for _, c := range cases {
		rec := do(t, s, http.MethodPost, "/cycle", c.body)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: status = %d, want 400", c.name, rec.Code)
		}
	}
}

func TestCycleMethodNotAllowed(t *testing.T) {
	s, _, _ := testServer(t)
	rec := do(t, s, http.MethodGet, "/cycle", "")
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", rec.Code)
	}
}

func TestRoute(t *testing.T) {
	s, _, _ := testServer(t)
	body := `{"from":{"lat":40.0,"lng":-77.0},"to":{"lat":40.003592,"lng":-77.004692}}`
	rec := do(t, s, http.MethodPost, "/route", body)
	if rec.Code != http.StatusOK {
		t.Fatalf("route status = %d", rec.Code)
	}
	var body2 struct {
		Found     bool    `json:"found"`
		DistanceM float64 `json:"distanceM"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body2)
	if !body2.Found || body2.DistanceM <= 0 {
		t.Fatalf("route found=%v dist=%.0f", body2.Found, body2.DistanceM)
	}
}

func TestNearest(t *testing.T) {
	s, _, _ := testServer(t)
	rec := do(t, s, http.MethodGet, "/nearest?lat=40.0&lng=-77.0", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("nearest status = %d", rec.Code)
	}
	var body struct {
		Found bool `json:"found"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if !body.Found {
		t.Fatal("nearest should find a node")
	}

	rec = do(t, s, http.MethodGet, "/nearest?lat=abc&lng=-77.0", "")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("bad nearest status = %d, want 400", rec.Code)
	}
}

func ftoa(f float64) string {
	return strings.TrimRight(strings.TrimRight(strconvFmt(f), "0"), ".")
}

func strconvFmt(f float64) string {
	b, _ := json.Marshal(f)
	return string(b)
}
