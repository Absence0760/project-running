package internal

// HTTP-level coverage for the queued Art 20 rail's durable state
// (supabase_dataexport_jobs.go, migration 20270603_001, decisions.md
// § 717 / § 724 / § 729).
//
// Every one of these methods runs as the SERVICE ROLE, which bypasses
// RLS, and `data_export_jobs` deliberately carries no policies at all —
// so the `user_id=eq.` filter these methods put on the wire is the ONLY
// thing scoping one subject's export state from another's. That is why
// the request shape is asserted here rather than only the decode: a
// filter that goes missing reads as a working endpoint right up to the
// moment it hands subject A a signed URL for subject B's archive.
//
// Same httptest shape as supabase_dataexport_test.go.

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

func exportJobsPath() string { return "/rest/v1/data_export_jobs" }

// ─────────────────── EnqueueDataExport ───────────────────

func TestEnqueueDataExport_CallsTheRpcWithTheSubjectAndFormat(t *testing.T) {
	var path, body, auth, apikey string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		path = r.URL.Path
		b, _ := io.ReadAll(r.Body)
		body = string(b)
		auth = r.Header.Get("Authorization")
		apikey = r.Header.Get("apikey")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[{"id":"exp-1","status":"queued","format":"backup","created_at":"2026-08-25T10:00:00Z","reused":false}]`))
	})

	ref, err := client.EnqueueDataExport(context.Background(), "user-A", "backup")
	if err != nil {
		t.Fatal(err)
	}
	if path != "/rest/v1/rpc/enqueue_data_export" {
		t.Errorf("path=%q, want the enqueue RPC", path)
	}
	var params map[string]any
	if err := json.Unmarshal([]byte(body), &params); err != nil {
		t.Fatalf("body is not JSON: %v (%s)", err, body)
	}
	if params["p_user_id"] != "user-A" || params["p_format"] != "backup" {
		t.Errorf("params=%v, want p_user_id + p_format", params)
	}
	if ref.ID != "exp-1" || ref.Status != "queued" || ref.Format != "backup" || ref.Reused {
		t.Errorf("ref=%+v", ref)
	}
	if !strings.Contains(auth, testServiceKey) || apikey != testServiceKey {
		t.Errorf("service-role headers missing: auth=%q apikey=%q", auth, apikey)
	}
}

func TestEnqueueDataExport_ReusedRowRoundTrips(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[{"id":"exp-9","status":"running","format":"csv","reused":true}]`))
	})
	ref, err := client.EnqueueDataExport(context.Background(), "user-A", "csv")
	if err != nil {
		t.Fatal(err)
	}
	if !ref.Reused || ref.ID != "exp-9" {
		t.Fatalf("ref=%+v, want the in-flight row reported as a reuse", ref)
	}
}

func TestEnqueueDataExport_NoRowIsAnErrorNotAnEmptyJobId(t *testing.T) {
	// A zero-value ref would be answered to the client as
	// `{"job_id":"","status":""}` — a page that then polls for a job
	// that was never queued, for ever.
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[]`))
	})
	ref, err := client.EnqueueDataExport(context.Background(), "user-A", "csv")
	if err == nil {
		t.Fatalf("an empty RPC result must be an error; got ref=%+v", ref)
	}
	if ref.ID != "" {
		t.Errorf("ref=%+v, want the zero value alongside the error", ref)
	}
}

func TestEnqueueDataExport_ServerErrorSurfaces(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"message":"boom"}`))
	})
	if _, err := client.EnqueueDataExport(context.Background(), "user-A", "csv"); err == nil {
		t.Fatal("a 500 from the enqueue RPC must surface")
	}
}

// ─────────────────── LatestDataExportJob ───────────────────

func TestLatestDataExportJob_ScopesTheReadToTheSubject(t *testing.T) {
	var q string
	var path string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		path, q = r.URL.Path, r.URL.Query().Encode()
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[{"id":"exp-1","user_id":"user-A","status":"ready","format":"backup","object_path":"user-A/exports/x.zip"}]`))
	})

	row, err := client.LatestDataExportJob(context.Background(), "user-A")
	if err != nil {
		t.Fatal(err)
	}
	if path != exportJobsPath() {
		t.Errorf("path=%q, want %q", path, exportJobsPath())
	}
	// service_role bypasses RLS and the table has no policies, so this
	// filter is the whole access control on the status read.
	if !strings.Contains(q, "user_id=eq.user-A") {
		t.Fatalf("query=%q, want a user_id=eq. filter — without it the "+
			"service-role read returns every subject's export row", q)
	}
	if !strings.Contains(q, "order=created_at.desc") {
		t.Errorf("query=%q, want newest-first ordering", q)
	}
	if !strings.Contains(q, "limit=1") {
		t.Errorf("query=%q, want limit=1", q)
	}
	if row == nil || row.ID != "exp-1" || row.ObjectPath != "user-A/exports/x.zip" {
		t.Fatalf("row=%+v", row)
	}
}

func TestLatestDataExportJob_EscapesTheSubjectIdIntoTheFilterValue(t *testing.T) {
	// The id reaches this method as a JWT `sub`. A value carrying an
	// ampersand must not be able to open a second query parameter and
	// widen the read past its own subject.
	var raw string
	var seen string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		raw = r.URL.RawQuery
		seen = r.URL.Query().Get("user_id")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[]`))
	})

	hostile := "user-A&limit=100&user_id=neq.zzz"
	if _, err := client.LatestDataExportJob(context.Background(), hostile); err != nil {
		t.Fatal(err)
	}
	if seen != "eq."+hostile {
		t.Fatalf("user_id decoded to %q, want the whole hostile string inside one filter value", seen)
	}
	if strings.Count(raw, "user_id=") != 1 {
		t.Fatalf("raw query %q carries more than one user_id filter", raw)
	}
	if strings.Contains(raw, "limit=100") {
		t.Fatalf("raw query %q let the subject id inject a second parameter", raw)
	}
}

func TestLatestDataExportJob_NeverAskedIsNilNil(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[]`))
	})
	row, err := client.LatestDataExportJob(context.Background(), "user-A")
	if err != nil {
		t.Fatalf("a subject who never exported is not an error: %v", err)
	}
	if row != nil {
		t.Fatalf("row=%+v, want nil", row)
	}
}

func TestLatestDataExportJob_DecodesTheWholeRowIncludingNullables(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[{
			"id":"exp-1","user_id":"user-A","format":"backup","status":"ready",
			"object_path":"user-A/exports/x.zip",
			"run_count":41,"total_runs":42,"complete":false,
			"error_code":"","started_at":"2026-08-25T10:00:00Z",
			"finished_at":"2026-08-25T10:02:00Z",
			"created_at":"2026-08-25T09:59:00Z","updated_at":"2026-08-25T10:02:00Z"
		}]`))
	})
	row, err := client.LatestDataExportJob(context.Background(), "user-A")
	if err != nil {
		t.Fatal(err)
	}
	if row.RunCount == nil || *row.RunCount != 41 {
		t.Errorf("run_count=%v", row.RunCount)
	}
	if row.TotalRuns == nil || *row.TotalRuns != 42 {
		t.Errorf("total_runs=%v", row.TotalRuns)
	}
	// A short export must decode as an explicit false, not as "unknown":
	// the status endpoint only publishes `complete` when it is non-nil,
	// and both clients gate their truncation notice on an explicit false.
	if row.Complete == nil || *row.Complete {
		t.Errorf("complete=%v, want an explicit false", row.Complete)
	}
	if row.UpdatedAt == "" || row.CreatedAt == "" {
		t.Errorf("the staleness derivation reads these: %+v", row)
	}
}

func TestLatestDataExportJob_NullCountsStayUnknown(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[{"id":"exp-1","status":"queued","run_count":null,"total_runs":null,"complete":null}]`))
	})
	row, err := client.LatestDataExportJob(context.Background(), "user-A")
	if err != nil {
		t.Fatal(err)
	}
	if row.RunCount != nil || row.TotalRuns != nil || row.Complete != nil {
		t.Fatalf("a job with no result yet must decode as nil, not as zero: %+v", row)
	}
}

func TestLatestDataExportJob_MalformedBodyIsAnError(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{not json`))
	})
	if _, err := client.LatestDataExportJob(context.Background(), "user-A"); err == nil {
		t.Fatal("a malformed status body must not read as `never exported`")
	}
}

func TestLatestDataExportJob_ServerErrorIsAnErrorNotAnEmptyStatus(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
	})
	row, err := client.LatestDataExportJob(context.Background(), "user-A")
	if err == nil {
		t.Fatal("a 502 must surface; reporting `none` would tell a subject their export never happened")
	}
	if row != nil {
		t.Errorf("row=%+v, want nil beside the error", row)
	}
}

func TestLatestDataExportJob_HonoursContextCancellation(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[]`))
	})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := client.LatestDataExportJob(ctx, "user-A"); err == nil {
		t.Fatal("a cancelled context must not produce a status read")
	}
}

// ─────────────────── GetDataExportJob ───────────────────

func TestGetDataExportJob_ReadsOneRowById(t *testing.T) {
	var q, path string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		path, q = r.URL.Path, r.URL.Query().Encode()
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[{"id":"exp-1","user_id":"user-A","status":"queued","format":"gpx"}]`))
	})
	row, err := client.GetDataExportJob(context.Background(), "exp-1")
	if err != nil {
		t.Fatal(err)
	}
	if path != exportJobsPath() {
		t.Errorf("path=%q", path)
	}
	if !strings.Contains(q, "id=eq.exp-1") || !strings.Contains(q, "limit=1") {
		t.Errorf("query=%q, want id=eq. + limit=1", q)
	}
	// The handler builds for the payload's user id; the row carries its
	// own, which is what makes a mismatch detectable at all.
	if row.UserID != "user-A" {
		t.Errorf("user_id=%q, want the row's own owner to decode", row.UserID)
	}
}

func TestGetDataExportJob_MissingRowIsTheGoneSentinel(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[]`))
	})
	_, err := client.GetDataExportJob(context.Background(), "exp-1")
	if err == nil {
		t.Fatal("a vanished row must be reported")
	}
	if err != ErrExportJobGone {
		t.Fatalf("err=%v, want ErrExportJobGone — the handler drops the job "+
			"quietly on that sentinel and only on that sentinel", err)
	}
}

func TestGetDataExportJob_TransportFailureIsNotTheGoneSentinel(t *testing.T) {
	// Getting this backwards is how a subject's export is dropped: the
	// handler treats ErrExportJobGone as "the account was deleted, stop"
	// and returns nil, so a 503 reported as Gone would abandon a live
	// export with nothing retrying it.
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	})
	_, err := client.GetDataExportJob(context.Background(), "exp-1")
	if err == nil {
		t.Fatal("a 503 must surface")
	}
	if err == ErrExportJobGone {
		t.Fatal("a Storage/REST outage must not read as a deleted account")
	}
}

func TestGetDataExportJob_MalformedBodyIsNotTheGoneSentinel(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{`))
	})
	_, err := client.GetDataExportJob(context.Background(), "exp-1")
	if err == nil || err == ErrExportJobGone {
		t.Fatalf("err=%v, want a plain decode error", err)
	}
}

// ─────────────────── MarkDataExportRunning ───────────────────

func TestMarkDataExportRunning_PatchesOnlyTheStatusAndStart(t *testing.T) {
	var method, q, prefer, contentType string
	var payload map[string]any
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		method, q = r.Method, r.URL.Query().Encode()
		prefer, contentType = r.Header.Get("Prefer"), r.Header.Get("Content-Type")
		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &payload)
		w.WriteHeader(http.StatusNoContent)
	})

	if err := client.MarkDataExportRunning(context.Background(), "exp-1", "2026-08-25T10:00:00Z"); err != nil {
		t.Fatal(err)
	}
	if method != http.MethodPatch {
		t.Errorf("method=%q, want PATCH", method)
	}
	if !strings.Contains(q, "id=eq.exp-1") {
		t.Fatalf("query=%q — an unfiltered PATCH would stamp every subject's export row", q)
	}
	if payload["status"] != "running" || payload["started_at"] != "2026-08-25T10:00:00Z" {
		t.Errorf("payload=%v", payload)
	}
	// A retry stamps `running` over a row that may already carry a path
	// from a previous attempt; sending anything else here would blank it.
	if len(payload) != 2 {
		t.Errorf("payload=%v, want exactly status + started_at", payload)
	}
	if prefer != "return=minimal" || contentType != "application/json" {
		t.Errorf("prefer=%q content-type=%q", prefer, contentType)
	}
}

func TestMarkDataExportRunning_ErrorSurfaces(t *testing.T) {
	// The handler returns this error rather than building, so the job
	// retries. Swallowing it would build an archive against a row that
	// still says `queued`.
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusConflict)
	})
	if err := client.MarkDataExportRunning(context.Background(), "exp-1", "t"); err == nil {
		t.Fatal("a failed running-stamp must surface")
	}
}

// ─────────────────── FinishDataExportJob ───────────────────

func TestFinishDataExportJob_ReadyCarriesThePathAndTheCounts(t *testing.T) {
	var q string
	var payload map[string]any
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		q = r.URL.Query().Encode()
		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &payload)
		w.WriteHeader(http.StatusNoContent)
	})

	path, runs, total, complete := "user-A/exports/x.zip", 41, 42, false
	err := client.FinishDataExportJob(context.Background(), "exp-1", ExportJobResult{
		Status: "ready", ObjectPath: &path, RunCount: &runs, TotalRuns: &total,
		Complete: &complete, FinishedAt: "2026-08-25T10:02:00Z",
	})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(q, "id=eq.exp-1") {
		t.Fatalf("query=%q", q)
	}
	if payload["status"] != "ready" || payload["object_path"] != path {
		t.Errorf("payload=%v", payload)
	}
	if payload["run_count"] != float64(41) || payload["total_runs"] != float64(42) {
		t.Errorf("payload=%v", payload)
	}
	// An explicit false, not an omitted key: the status endpoint only
	// publishes `complete` when the column is non-null, so dropping a
	// false here would present a short archive as making no claim.
	got, present := payload["complete"]
	if !present || got != false {
		t.Errorf("complete=%v present=%v, want an explicit false", got, present)
	}
	if _, present := payload["error_code"]; present {
		t.Errorf("a successful build must not write an error code: %v", payload)
	}
}

func TestFinishDataExportJob_FailureCarriesTheCodeAndNoPath(t *testing.T) {
	var payload map[string]any
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &payload)
		w.WriteHeader(http.StatusNoContent)
	})
	code := "upload_failed"
	err := client.FinishDataExportJob(context.Background(), "exp-1", ExportJobResult{
		Status: "failed", ErrorCode: &code, FinishedAt: "2026-08-25T10:02:00Z",
	})
	if err != nil {
		t.Fatal(err)
	}
	if payload["status"] != "failed" || payload["error_code"] != code {
		t.Errorf("payload=%v", payload)
	}
	// A failed build materialised no object; writing a path would make
	// the row offer a download for something that does not exist.
	if _, present := payload["object_path"]; present {
		t.Errorf("a failed build must record no artifact path: %v", payload)
	}
	if _, present := payload["complete"]; present {
		t.Errorf("a failed build claims no completeness: %v", payload)
	}
}

func TestFinishDataExportJob_ZeroCountsAreWrittenNotDropped(t *testing.T) {
	// A subject with no runs at all still gets an archive, and 0 is the
	// true count. Dropping it would leave the column null and the status
	// endpoint silent about a number it knows.
	var payload map[string]any
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &payload)
		w.WriteHeader(http.StatusNoContent)
	})
	path, zero, complete := "user-A/exports/x.zip", 0, true
	err := client.FinishDataExportJob(context.Background(), "exp-1", ExportJobResult{
		Status: "ready", ObjectPath: &path, RunCount: &zero, TotalRuns: &zero,
		Complete: &complete, FinishedAt: "t",
	})
	if err != nil {
		t.Fatal(err)
	}
	if payload["run_count"] != float64(0) || payload["total_runs"] != float64(0) {
		t.Fatalf("payload=%v, want an explicit zero on both counts", payload)
	}
}

func TestFinishDataExportJob_ErrorSurfaces(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
	})
	code := "build_failed"
	err := client.FinishDataExportJob(context.Background(), "exp-1", ExportJobResult{
		Status: "failed", ErrorCode: &code, FinishedAt: "t",
	})
	if err == nil {
		t.Fatal("a failed result write must surface so the handler can log it")
	}
}

// ─────────────────── NotifyDataExportReady ───────────────────

func TestNotifyDataExportReady_CallsTheRpcAndReportsTheStamp(t *testing.T) {
	var path string
	var params map[string]any
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		path = r.URL.Path
		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &params)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`true`))
	})

	announced, err := client.NotifyDataExportReady(context.Background(), "exp-1")
	if err != nil {
		t.Fatal(err)
	}
	if path != "/rest/v1/rpc/notify_data_export_ready" {
		t.Errorf("path=%q", path)
	}
	if params["p_export_job_id"] != "exp-1" {
		t.Errorf("params=%v", params)
	}
	if !announced {
		t.Error("announced=false, want the RPC's own verdict")
	}
}

func TestNotifyDataExportReady_AlreadyStampedReportsFalse(t *testing.T) {
	// Idempotency lives in the RPC: a redelivery of the same job must
	// see `false` and say nothing more.
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`false`))
	})
	announced, err := client.NotifyDataExportReady(context.Background(), "exp-1")
	if err != nil {
		t.Fatal(err)
	}
	if announced {
		t.Fatal("a second delivery must not report an announcement")
	}
}

func TestNotifyDataExportReady_EmptyBodyDoesNotClaimAnAnnouncement(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	announced, err := client.NotifyDataExportReady(context.Background(), "exp-1")
	if err != nil {
		t.Fatal(err)
	}
	if announced {
		t.Fatal("an empty RPC body must not read as `the subject was told`")
	}
}

func TestNotifyDataExportReady_ErrorSurfaces(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	})
	announced, err := client.NotifyDataExportReady(context.Background(), "exp-1")
	if err == nil {
		t.Fatal("an RPC failure must surface so the handler can log it")
	}
	if announced {
		t.Error("a failed announcement must not report success")
	}
}

func TestDataExportJobMethods_AllCarryServiceRoleHeaders(t *testing.T) {
	for _, tc := range []struct {
		name string
		call func(*SupabaseClient) error
	}{
		{"EnqueueDataExport", func(c *SupabaseClient) error {
			_, err := c.EnqueueDataExport(context.Background(), "user-A", "csv")
			return err
		}},
		{"LatestDataExportJob", func(c *SupabaseClient) error {
			_, err := c.LatestDataExportJob(context.Background(), "user-A")
			return err
		}},
		{"GetDataExportJob", func(c *SupabaseClient) error {
			_, err := c.GetDataExportJob(context.Background(), "exp-1")
			return err
		}},
		{"MarkDataExportRunning", func(c *SupabaseClient) error {
			return c.MarkDataExportRunning(context.Background(), "exp-1", "t")
		}},
		{"FinishDataExportJob", func(c *SupabaseClient) error {
			p := "user-A/exports/x.zip"
			return c.FinishDataExportJob(context.Background(), "exp-1", ExportJobResult{Status: "ready", ObjectPath: &p})
		}},
		{"NotifyDataExportReady", func(c *SupabaseClient) error {
			_, err := c.NotifyDataExportReady(context.Background(), "exp-1")
			return err
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var auth, apikey string
			client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
				auth, apikey = r.Header.Get("Authorization"), r.Header.Get("apikey")
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(`[{"id":"exp-1","status":"queued","format":"csv"}]`))
			})
			_ = tc.call(client)
			if apikey != testServiceKey || !strings.Contains(auth, testServiceKey) {
				t.Fatalf("auth=%q apikey=%q, want the service-role headers", auth, apikey)
			}
		})
	}
}
