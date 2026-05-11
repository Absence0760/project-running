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
	"github.com/Absence0760/project-running/apps/job_worker/internal/livehub"
)

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
	// same Go service. Phase 2 follow-up will move ephemeral
	// positions into Upstash Redis; until then the in-memory Hub is
	// the single source of truth for in-flight runs. See
	// `internal/livehub/types.go` for the migration path.
	hub := livehub.NewHub()
	hubSrv := &livehub.Server{
		Hub:            hub,
		Log:            logger.With("component", "livehub"),
		AllowedOrigins: parseOrigins(os.Getenv("LIVEHUB_ALLOWED_ORIGINS")),
		// Authorizer left nil for the first slice → permissive.
		// Production must plug in a Supabase JWT verifier here
		// before enabling the public route — see server.go's
		// Authorizer field doc for the policy.
	}

	healthSrv := startHealthServer(logger, healthPort, &lastClaimAtUnix, workerID, hubSrv)
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
func startHealthServer(log *slog.Logger, port string, lastClaim *atomic.Int64, workerID string, hub *livehub.Server) *http.Server {
	mux := http.NewServeMux()
	if hub != nil {
		hub.RegisterRoutes(mux)
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
