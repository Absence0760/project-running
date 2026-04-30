package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal"
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
	worker := &internal.Worker{
		Backend: client,
		Matcher: matcher,
		Config: internal.Config{
			WorkerID:       workerID,
			PollInterval:   2 * time.Second,
			HandleTimeout:  5 * time.Minute,
			TransientDelay: 30,
		},
		Log: logger,
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	if err := worker.Run(ctx); err != nil {
		logger.Error("worker exited", "err", err)
		os.Exit(1)
	}
}

func requireEnv(log *slog.Logger, name string) string {
	v := os.Getenv(name)
	if v == "" {
		log.Error("missing required env var", "name", name)
		os.Exit(2)
	}
	return v
}
