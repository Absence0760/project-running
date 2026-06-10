// graph_cycle is a standalone map sidecar for the "Generate a route by distance"
// loop generator (docs/features/graph_cycle_loop_generation.md, v3). It parses
// an OSM PBF into an in-memory foot graph at boot and serves a cycle search over
// the real street network.
//
// Deployed to Fly alongside OSRM + GraphHopper, fronted by Caddy as a
// shared-secret guard on a public https endpoint (the generate-route Lambda runs
// on AWS and has no 6PN path into Fly) — same posture as GraphHopper.
//
// Env:
//   - GRAPH_CYCLE_PBF   path to the OSM PBF (default /data/region.osm.pbf,
//     mirroring the volume layout of the OSRM/GraphHopper apps).
//   - PORT              localhost bind port for the Go server (default 8990);
//     Caddy owns the public 8989 and proxies here after the key check.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/Absence0760/project-running/apps/graph_cycle/internal/api"
	"github.com/Absence0760/project-running/apps/graph_cycle/internal/graph"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	pbf := envOr("GRAPH_CYCLE_PBF", "/data/region.osm.pbf")
	port := envOr("PORT", "8990")

	log.Info("building foot graph", "pbf", pbf)
	started := time.Now()
	g, stats, err := graph.Build(pbf)
	if err != nil {
		log.Error("graph build failed", "err", err, "pbf", pbf)
		os.Exit(1)
	}
	log.Info("graph built",
		"nodes", stats.Nodes, "edges", stats.Edges, "ways", stats.Ways,
		"took", time.Since(started).String())
	if stats.Nodes == 0 {
		// An empty graph means the PBF was missing/empty or had no foot ways —
		// every request would be loop-poor. Fail loud rather than serve a
		// silently useless engine.
		log.Error("graph has zero nodes — wrong or empty PBF?", "pbf", pbf)
		os.Exit(1)
	}

	srv := api.New(g, stats, log)
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)

	httpSrv := &http.Server{
		Addr:              "127.0.0.1:" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		log.Info("listening", "addr", httpSrv.Addr)
		if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("http server failed", "err", err)
			stop()
		}
	}()

	<-ctx.Done()
	log.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = httpSrv.Shutdown(shutdownCtx)
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
