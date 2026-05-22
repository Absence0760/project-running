package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal"
	"github.com/Absence0760/project-running/apps/job_worker/internal/dataexport"
	"github.com/Absence0760/project-running/apps/job_worker/internal/livehub"
	"github.com/Absence0760/project-running/apps/job_worker/internal/premium"
	"github.com/Absence0760/project-running/apps/job_worker/internal/stravahook"
)

// stravaJobEnqueuer adapts SupabaseClient.EnqueueStravaEvent to the
// stravahook.JobEnqueuer interface. The leaf-package stravahook
// declares its own payload struct so its tests stay isolated from
// the `internal` package; we translate across them by marshalling
// to the wire-identical map[string]any here.
type stravaJobEnqueuer struct {
	client *internal.SupabaseClient
}

func (e *stravaJobEnqueuer) EnqueueStravaEvent(ctx context.Context, p stravahook.StravaEventPayload) (int64, error) {
	return e.client.EnqueueStravaEvent(ctx, map[string]any{
		"object_type": p.ObjectType,
		"object_id":   p.ObjectID,
		"aspect_type": p.AspectType,
		"owner_id":    p.OwnerID,
		"event_time":  p.EventTime,
	})
}

// dataexportBackend adapts SupabaseClient to dataexport.Backend.
// Same reasoning as stravaJobEnqueuer — the leaf package keeps its
// own types so tests don't import `internal`; this adapter is the
// production translation layer.
type dataexportBackend struct {
	client *internal.SupabaseClient
}

func (b *dataexportBackend) CheckRateLimitTiered(ctx context.Context, userID, bucket string, freeMax, proMax, windowSec int) (bool, int, error) {
	return b.client.CheckRateLimitTiered(ctx, userID, bucket, freeMax, proMax, windowSec)
}

func (b *dataexportBackend) FetchExportRuns(ctx context.Context, userID string, limit int) ([]dataexport.ExportRun, error) {
	rows, err := b.client.FetchExportRuns(ctx, userID, limit)
	if err != nil {
		return nil, err
	}
	out := make([]dataexport.ExportRun, len(rows))
	for i, r := range rows {
		out[i] = dataexport.ExportRun{
			ID: r.ID, UserID: r.UserID, StartedAt: r.StartedAt,
			DurationS: r.DurationS, DistanceM: r.DistanceM,
			Source: r.Source, ExternalID: r.ExternalID,
			Metadata: r.Metadata, TrackURL: r.TrackURL,
			IsPublic: r.IsPublic, EventID: r.EventID, RouteID: r.RouteID,
			CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
		}
	}
	return out, nil
}

func (b *dataexportBackend) DownloadTrackBytes(ctx context.Context, path string) ([]dataexport.TrackPoint, error) {
	pts, err := b.client.DownloadTrack(ctx, path)
	if err != nil {
		return nil, nil // swallow; caller drops the per-run GPX file
	}
	out := make([]dataexport.TrackPoint, len(pts))
	for i, p := range pts {
		out[i] = dataexport.TrackPoint{Lat: p.Lat, Lng: p.Lng}
		if p.Elevation != nil {
			ele := *p.Elevation
			out[i].Ele = &ele
		}
		if p.Timestamp != nil {
			ts := p.Timestamp.Format(time.RFC3339)
			out[i].Ts = &ts
		}
		if p.Bpm != nil {
			b := *p.Bpm
			out[i].Bpm = &b
		}
	}
	return out, nil
}

func (b *dataexportBackend) FetchExportRoutes(ctx context.Context, userID string) ([]dataexport.ExportRoute, error) {
	rows, err := b.client.FetchExportRoutes(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]dataexport.ExportRoute, len(rows))
	for i, r := range rows {
		out[i] = dataexport.ExportRoute{
			ID: r.ID, Name: r.Name, Waypoints: r.Waypoints,
			DistanceM: r.DistanceM, ElevationM: r.ElevationM,
			Surface: r.Surface, IsPublic: r.IsPublic, Slug: r.Slug,
			Tags: r.Tags, Featured: r.Featured, RunCount: r.RunCount,
			IsStarred: r.IsStarred, Description: r.Description,
			ClubID: r.ClubID, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
		}
	}
	return out, nil
}

func (b *dataexportBackend) FetchExportProfile(ctx context.Context, userID string) (map[string]interface{}, error) {
	return b.client.FetchExportProfile(ctx, userID)
}

func (b *dataexportBackend) FetchUserSettingsPrefs(ctx context.Context, userID string) (map[string]interface{}, error) {
	return b.client.FetchUserSettingsPrefs(ctx, userID)
}

func (b *dataexportBackend) DownloadRawTrackBytes(ctx context.Context, path string) ([]byte, error) {
	return b.client.DownloadRawTrackBytes(ctx, path)
}

func (b *dataexportBackend) UploadExportArtifact(ctx context.Context, path, contentType string, body []byte) error {
	return b.client.UploadExportArtifact(ctx, path, contentType, body)
}

func (b *dataexportBackend) CreateSignedURL(ctx context.Context, path string, ttlSec int) (string, error) {
	return b.client.CreateSignedURL(ctx, path, ttlSec)
}

// premiumBackend adapts SupabaseClient to premium.Backend.
type premiumBackend struct {
	client *internal.SupabaseClient
}

func (b *premiumBackend) FetchUserSubscriptionTier(ctx context.Context, userID string) (string, error) {
	return b.client.FetchUserSubscriptionTier(ctx, userID)
}

func (b *premiumBackend) FetchPremiumRuns(ctx context.Context, userID string, since time.Time, limit int) ([]premium.PremiumRun, error) {
	rows, err := b.client.FetchPremiumRuns(ctx, userID, since, limit)
	if err != nil {
		return nil, err
	}
	out := make([]premium.PremiumRun, len(rows))
	for i, r := range rows {
		out[i] = premium.PremiumRun{
			StartedAt: r.StartedAt,
			DistanceM: r.DistanceM,
			DurationS: r.DurationS,
			Metadata:  r.Metadata,
		}
	}
	return out, nil
}

// main wires environment → SupabaseClient → Worker.Run. Kept thin so
// the worker logic can be exercised from tests against a mock backend
// without booting an HTTP transport.
func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	baseURL := requireEnv(logger, "SUPABASE_URL")
	serviceKey := requireEnv(logger, "SUPABASE_SERVICE_ROLE_KEY")
	workerID := os.Getenv("WORKER_ID")
	if workerID == "" {
		host, _ := os.Hostname()
		if host == "" {
			host = "worker"
		}
		workerID = host
	}

	// OSRM_URL is the dev / prod hook that swaps the passthrough
	// shim for the real /match-based engine. Empty → passthrough,
	// which is enough for end-to-end smoke tests of the rest of the
	// pipeline. See apps/job_worker/osrm/README.md for the local
	// stack.
	var matcher internal.Matcher = internal.PassthroughMatcher{}
	if osrmURL := os.Getenv("OSRM_URL"); osrmURL != "" {
		matcher = internal.NewOSRMMatcher(osrmURL)
		logger.Info("matcher selected", "engine", "osrm", "url", osrmURL)
	} else {
		logger.Info("matcher selected", "engine", "passthrough")
	}

	client := internal.NewSupabaseClient(baseURL, serviceKey)

	// Strava OAuth client for the token_refresh dispatch path.
	// Optional — when either env var is missing the worker still
	// drains map_match jobs, but any token_refresh row fails permanent
	// with a clear "Strava client not configured" message. The Edge
	// Function path remains the fallback during cutover.
	stravaID := os.Getenv("STRAVA_CLIENT_ID")
	stravaSecret := os.Getenv("STRAVA_CLIENT_SECRET")
	var strava internal.StravaIngestor
	if stravaID != "" && stravaSecret != "" {
		strava = &internal.StravaClient{
			ClientID:     stravaID,
			ClientSecret: stravaSecret,
			HTTP:         client.HTTP, // reuse pooled client
		}
		logger.Info("strava: enabled (token_refresh + strava_event dispatch armed)")
	} else {
		logger.Warn("strava: DISABLED — STRAVA_CLIENT_ID/SECRET unset; token_refresh + strava_event jobs will fail permanent")
	}

	// `lastClaimAt` is the heartbeat the /health endpoint reads. The
	// worker's poll loop bumps it on every successful poll
	// (claim-or-empty), so /health flips to 503 only when the loop
	// itself is stuck — distinct from "queue empty" (which is fine).
	// Initialise to start-time so a freshly-launched container reports
	// healthy until the first poll lands.
	var lastClaimAtUnix atomic.Int64
	lastClaimAtUnix.Store(time.Now().Unix())

	worker := &internal.Worker{
		Backend: client,
		Matcher: matcher,
		Strava:  strava,
		Config: internal.Config{
			WorkerID:       workerID,
			PollInterval:   2 * time.Second,
			HandleTimeout:  5 * time.Minute,
			TransientDelay: 30,
		},
		Log:        logger,
		OnPollTick: func() { lastClaimAtUnix.Store(time.Now().Unix()) },
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	// Start a tiny health server on :8080. Fly.io's tcp_check probes
	// the port; the /health endpoint surfaces a JSON body with the
	// last-poll heartbeat for richer external monitoring (Better
	// Stack etc.). Port is configurable for local dev, defaults to
	// 8080 to match fly.toml.
	healthPort := os.Getenv("HEALTH_PORT")
	if healthPort == "" {
		healthPort = "8080"
	}
	// Live spectator hub — runs alongside the job-drain loop on the
	// same Go service. Picks Redis-backed pub/sub (multi-replica
	// fan-out, last-known TTL'd at 24h) when REDIS_URL is set,
	// otherwise falls back to the in-process Hub (single-replica /
	// dev path). Both satisfy `livehub.LivePubSub`.
	var hub livehub.LivePubSub
	if redisURL := os.Getenv("REDIS_URL"); redisURL != "" {
		rdb, err := livehub.ConfigureRedis(redisURL)
		if err != nil {
			logger.Error("livehub: REDIS_URL parse failed; falling back to in-process", "err", err)
			hub = livehub.NewHub()
		} else {
			redisHub := livehub.NewRedisHub(rdb)
			redisHub.Log = logger.With("component", "livehub-redis")
			hub = redisHub
			logger.Info("livehub: backend=redis (multi-replica fan-out)")
		}
	} else {
		hub = livehub.NewHub()
		logger.Info("livehub: backend=in-process (single-replica)")
	}
	// Privacy-zone fetcher. Wires the hub's push path to the
	// broadcaster's `user_settings.prefs.privacy_zones` so in-zone
	// pings are dropped before fan-out — same contract as the
	// `live_run_pings_drop_in_zone` trigger on the Supabase Realtime
	// path. Same service-role auth as the rest of the worker.
	zoneFetcher := &livehub.SupabaseZoneFetcher{
		BaseURL:    baseURL,
		ServiceKey: serviceKey,
		HTTP:       client.HTTP, // reuse the worker's pooled client
	}
	// JWT authorizer for the live hub. Source of truth is the
	// Supabase project's JWT secret (HS256). When SUPABASE_JWT_SECRET
	// is set the authorizer enforces:
	//   - push       : Bearer JWT required + sub == runs.user_id
	//   - subscribe  : owner-only on private runs, anon on public
	//   - snapshot   : same as subscribe
	// When unset the authorizer is nil and the hub stays permissive
	// (dev path). Production deploys MUST set the secret — fly.toml
	// + deployment.md document this.
	runMetaFetcher := &livehub.SupabaseRunMetaFetcher{
		BaseURL:    baseURL,
		ServiceKey: serviceKey,
		HTTP:       client.HTTP,
	}
	authorizer := livehub.NewJWTAuthorizer(os.Getenv("SUPABASE_JWT_SECRET"), hub, runMetaFetcher)
	hubSrv := &livehub.Server{
		Hub:            hub,
		Log:            logger.With("component", "livehub"),
		AllowedOrigins: parseOrigins(os.Getenv("LIVEHUB_ALLOWED_ORIGINS")),
		Zones:          zoneFetcher,
	}
	if authorizer != nil {
		hubSrv.Authorizer = authorizer.Authorize
		logger.Info("livehub auth: enabled (Supabase JWT)")
	} else {
		logger.Warn("livehub auth: DISABLED — SUPABASE_JWT_SECRET unset; permissive mode is for local dev only")
	}

	// Strava webhook receiver — mounts /v1/strava/webhook on the same
	// mux. Auth uses a shared URL secret + verify token (mirrors the
	// EF's contract); the body filter / dedupe / freshness gates live
	// in `internal/stravahook/server.go`. Events pass validation,
	// enqueue a `strava_event` job, and ack 200 in well under 2 s —
	// the worker's dispatch then does the activity fetch + Storage
	// upload async. See `apps/job_worker/deployment.md § Strava
	// webhook` for the cutover recipe.
	stravaWebhookSecret := os.Getenv("STRAVA_WEBHOOK_SECRET")
	stravaVerifyToken := os.Getenv("STRAVA_VERIFY_TOKEN")
	var stravaSrv *stravahook.Server
	if stravaWebhookSecret != "" && stravaVerifyToken != "" {
		stravaSrv = &stravahook.Server{
			WebhookSecret: stravaWebhookSecret,
			VerifyToken:   stravaVerifyToken,
			Enqueuer:      &stravaJobEnqueuer{client: client},
			WebhookEvents: client,
			Log:           logger.With("component", "stravahook"),
		}
		logger.Info("stravahook: enabled (Strava webhook endpoint mounted at /v1/strava/webhook)")
	} else {
		logger.Warn("stravahook: DISABLED — STRAVA_WEBHOOK_SECRET / STRAVA_VERIFY_TOKEN unset; webhook endpoint returns 503")
	}

	// Data export endpoint — POST /v1/export. JWT-authed (same
	// SUPABASE_JWT_SECRET the live hub uses), service-role for the
	// Storage upload + signed URL. Replaces the export-data Edge
	// Function. Refuses with 503 when the JWT secret isn't set —
	// matching the live hub's posture.
	var exportSrv *dataexport.Server
	if jwtSecret := os.Getenv("SUPABASE_JWT_SECRET"); jwtSecret != "" {
		exportSrv = &dataexport.Server{
			JWTSecret: []byte(jwtSecret),
			Backend:   &dataexportBackend{client: client},
			Log:       logger.With("component", "dataexport"),
		}
		logger.Info("dataexport: enabled (export endpoint mounted at /v1/export)")
	} else {
		logger.Warn("dataexport: DISABLED — SUPABASE_JWT_SECRET unset; export endpoint returns 503")
	}

	// Premium endpoints — Pro-tier-gated POSTs at /v1/premium/{vo2max,
	// race-predictor, recovery, training-plan}. Same JWT auth as the
	// data-export endpoint; an extra subscription_tier check before
	// the compute. Refuses with 503 when SUPABASE_JWT_SECRET unset.
	var premiumSrv *premium.Server
	if jwtSecret := os.Getenv("SUPABASE_JWT_SECRET"); jwtSecret != "" {
		premiumSrv = &premium.Server{
			JWTSecret: []byte(jwtSecret),
			Backend:   &premiumBackend{client: client},
			Log:       logger.With("component", "premium"),
		}
		logger.Info("premium: enabled (Pro endpoints mounted at /v1/premium/*)")
	} else {
		logger.Warn("premium: DISABLED — SUPABASE_JWT_SECRET unset; Pro endpoints return 503")
	}

	healthSrv := startHealthServer(logger, healthPort, &lastClaimAtUnix, workerID, hubSrv, stravaSrv, exportSrv, premiumSrv)
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = healthSrv.Shutdown(shutdownCtx)
	}()

	if err := worker.Run(ctx); err != nil {
		logger.Error("worker exited", "err", err)
		os.Exit(1)
	}
}

// startHealthServer mounts a /health endpoint on the configured port
// and returns the running server. The caller is expected to Shutdown
// it on exit.
//
// /health returns:
//   - 200 + `{"status":"ok",...}` while the worker poll loop is
//     ticking (heartbeat seen within 5 × PollInterval).
//   - 503 + `{"status":"stale",...}` when the heartbeat is stale —
//     Fly's auto-restart kicks in on repeated 503s.
//
// The grace period (5 × PollInterval = 10s) accommodates a job that
// happens to take that long to handle; longer-running jobs would
// trigger a restart, which is the correct response for "this job is
// hung".
func startHealthServer(log *slog.Logger, port string, lastClaim *atomic.Int64, workerID string, hub *livehub.Server, strava *stravahook.Server, export *dataexport.Server, prem *premium.Server) *http.Server {
	mux := http.NewServeMux()
	if hub != nil {
		hub.RegisterRoutes(mux)
	}
	if strava != nil {
		strava.RegisterRoutes(mux)
	}
	if export != nil {
		export.RegisterRoutes(mux)
	}
	if prem != nil {
		prem.RegisterRoutes(mux)
	}
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		ageSec := time.Now().Unix() - lastClaim.Load()
		w.Header().Set("Content-Type", "application/json")
		// 10s = 5 × default 2s PollInterval. If the loop ticks every
		// 2s in the steady state, anything over 10s means it's stuck.
		if ageSec > 10 {
			w.WriteHeader(http.StatusServiceUnavailable)
			fmt.Fprintf(w, `{"status":"stale","worker_id":%q,"poll_age_s":%d}`, workerID, ageSec)
			return
		}
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"status":"ok","worker_id":%q,"poll_age_s":%d}`, workerID, ageSec)
	})

	srv := &http.Server{Addr: ":" + port, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() {
		log.Info("health server listening", "port", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Error("health server failed", "err", err)
		}
	}()
	return srv
}

// parseOrigins splits a comma-separated env value into the
// AllowedOrigins list the WS upgrade enforces. Empty input → empty
// slice (caller treats as "skip origin check", which is fine for
// local dev / smoke tests; production sets at least one host).
func parseOrigins(env string) []string {
	if env == "" {
		return nil
	}
	parts := strings.Split(env, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func requireEnv(log *slog.Logger, name string) string {
	v := os.Getenv(name)
	if v == "" {
		log.Error("missing required env var", "name", name)
		os.Exit(2)
	}
	return v
}
