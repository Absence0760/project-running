package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"

	"github.com/Absence0760/project-running/apps/job_worker/internal/schema"
)

// The durable state of a queued Art 20 export (migration 20270603_001).
//
// `internal` keeps its own mirror types rather than importing
// `dataexport`, the same leaf-package rule ExportRun / ExportRoute /
// ExportCompleteness already follow; main.go's adapter translates.

// ExportJobRef is what `enqueue_data_export` answers with.
type ExportJobRef struct {
	ID        string `json:"id"`
	Status    string `json:"status"`
	Format    string `json:"format"`
	CreatedAt string `json:"created_at"`
	Reused    bool   `json:"reused"`
}

// ExportJobRow is one row of `data_export_jobs`.
type ExportJobRow struct {
	ID         string `json:"id"`
	UserID     string `json:"user_id"`
	Format     string `json:"format"`
	Status     string `json:"status"`
	ObjectPath string `json:"object_path"`
	RunCount   *int   `json:"run_count"`
	TotalRuns  *int   `json:"total_runs"`
	Complete   *bool  `json:"complete"`
	ErrorCode  string `json:"error_code"`
	StartedAt  string `json:"started_at"`
	FinishedAt string `json:"finished_at"`
	CreatedAt  string `json:"created_at"`
	UpdatedAt  string `json:"updated_at"`
}

// ExportJobResult is what the handler writes back when a build ends.
// A `ready` result must carry an ObjectPath — that is the whole claim
// the row makes — and a `failed` one must carry an ErrorCode.
type ExportJobResult struct {
	Status     string  `json:"status"`
	ObjectPath *string `json:"object_path,omitempty"`
	RunCount   *int    `json:"run_count,omitempty"`
	TotalRuns  *int    `json:"total_runs,omitempty"`
	Complete   *bool   `json:"complete,omitempty"`
	ErrorCode  *string `json:"error_code,omitempty"`
	FinishedAt string  `json:"finished_at"`
}

// ErrExportJobGone means the export row named by a job payload is not
// there any more — the subject deleted their account between the
// enqueue and the claim, and the FK cascade took it. Permanent, so the
// handler must not spend the retry budget on it.
var ErrExportJobGone = errors.New("data_export_jobs row not found")

// EnqueueDataExport calls the SECURITY DEFINER RPC that inserts the
// state row and its queue entry together, or returns the export already
// in flight for this subject.
func (c *SupabaseClient) EnqueueDataExport(ctx context.Context, userID, format string) (ExportJobRef, error) {
	params := map[string]any{"p_user_id": userID, "p_format": format}
	var rows []ExportJobRef
	if err := c.rpc(ctx, "enqueue_data_export", params, &rows); err != nil {
		return ExportJobRef{}, err
	}
	if len(rows) == 0 {
		return ExportJobRef{}, errors.New("enqueue_data_export returned no row")
	}
	return rows[0], nil
}

// LatestDataExportJob returns the subject's most recent export request,
// or (nil, nil) when they have never asked for one.
func (c *SupabaseClient) LatestDataExportJob(ctx context.Context, userID string) (*ExportJobRow, error) {
	q := url.Values{}
	q.Set("user_id", "eq."+userID)
	q.Set("order", "created_at.desc")
	q.Set("limit", "1")
	u := c.BaseURL + "/rest/v1/" + schema.TableDataExportJobs + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []ExportJobRow
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, nil
	}
	return &rows[0], nil
}

// GetDataExportJob reads one export row by id.
func (c *SupabaseClient) GetDataExportJob(ctx context.Context, exportJobID string) (*ExportJobRow, error) {
	q := url.Values{}
	q.Set("id", "eq."+exportJobID)
	q.Set("limit", "1")
	u := c.BaseURL + "/rest/v1/" + schema.TableDataExportJobs + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []ExportJobRow
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrExportJobGone
	}
	return &rows[0], nil
}

// MarkDataExportRunning stamps the row at the start of an attempt. It
// also refreshes `updated_at` through the table's trigger, which is what
// the status reader measures staleness against — a live worker keeps
// the row warm, a crashed one does not.
func (c *SupabaseClient) MarkDataExportRunning(ctx context.Context, exportJobID, startedAt string) error {
	return c.patchDataExportJob(ctx, exportJobID, map[string]any{
		"status":     "running",
		"started_at": startedAt,
	})
}

// FinishDataExportJob records the outcome of a build.
func (c *SupabaseClient) FinishDataExportJob(ctx context.Context, exportJobID string, res ExportJobResult) error {
	payload := map[string]any{
		"status":      res.Status,
		"finished_at": res.FinishedAt,
	}
	if res.ObjectPath != nil {
		payload["object_path"] = *res.ObjectPath
	}
	if res.RunCount != nil {
		payload["run_count"] = *res.RunCount
	}
	if res.TotalRuns != nil {
		payload["total_runs"] = *res.TotalRuns
	}
	if res.Complete != nil {
		payload["complete"] = *res.Complete
	}
	if res.ErrorCode != nil {
		payload["error_code"] = *res.ErrorCode
	}
	return c.patchDataExportJob(ctx, exportJobID, payload)
}

// NotifyDataExportReady announces a finished export to its subject via the
// SECURITY DEFINER RPC (migration 20270607_001). Idempotency lives in the
// RPC rather than here: it inserts the inbox row and stamps
// `notified_at` under one row lock, so an at-least-once redelivery of the
// same `data_export` job cannot announce the same archive twice. Returns
// whether this call was the one that announced.
func (c *SupabaseClient) NotifyDataExportReady(ctx context.Context, exportJobID string) (bool, error) {
	params := map[string]any{"p_export_job_id": exportJobID}
	var announced bool
	if err := c.rpc(ctx, "notify_data_export_ready", params, &announced); err != nil {
		return false, err
	}
	return announced, nil
}

func (c *SupabaseClient) patchDataExportJob(ctx context.Context, exportJobID string, payload map[string]any) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	q := url.Values{}
	q.Set("id", "eq."+exportJobID)
	u := c.BaseURL + "/rest/v1/" + schema.TableDataExportJobs + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, u, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")
	_, err = c.do(ctx, req)
	return err
}
