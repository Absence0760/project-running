#!/usr/bin/env bash
# Full local BACKEND bringup — everything the apps talk to, in one shot.
#
# Starts (and returns; nothing blocks your terminal):
#   • the core stack via bin/dev-core.sh — Supabase (:54321) + seed,
#     Protomaps tiles (:8080), Ollama check, adb reverse
#   • the Go job worker (queue drain + live-spectator hub), backgrounded
#   • OSRM (:5000) + GraphHopper (:8989) routing engines, detached —
#     only when their graphs are already built (else a one-line hint)
#
# Then run the app for whichever platform you're testing, each in its own
# terminal:
#   npm run dev:run:web        # web        → http://localhost:7777
#   npm run dev:run:android    # mobile     → Flutter on a device/emulator
#   npm run dev:run:ios        # mobile iOS → Flutter on a simulator/device
#   (watch) cd apps/watch_wear/android && ./gradlew installDebug
#
# Subcommands:  up (default) | down | status | logs
# Usage:  npm run dev:full   (= bin/dev-full.sh up)

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -t 1 ]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; GRN=$'\e[32m'; YEL=$'\e[33m'; RED=$'\e[31m'; RST=$'\e[0m'
else
  BOLD=; DIM=; GRN=; YEL=; RED=; RST=
fi
step() { printf '\n%s▸ %s%s\n' "$BOLD" "$1" "$RST"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; }
warn() { printf '  %s⚠%s %s\n' "$YEL" "$RST" "$1"; }
err()  { printf '  %s✗%s %s\n' "$RED" "$RST" "$1"; }

DEVDIR="$ROOT/.dev"
WORKER_BIN="$DEVDIR/job_worker"
WORKER_PID="$DEVDIR/worker.pid"
WORKER_LOG="$DEVDIR/worker.log"

worker_running() {
  [ -f "$WORKER_PID" ] && kill -0 "$(cat "$WORKER_PID")" 2>/dev/null
}

# ── Routing engines (detached docker compose) ──────────────────────────────
# Each only starts if its graph is already built — the multi-GB build is a
# deliberate one-time `dev:setup:*` step, not something to trigger implicitly.
# The apps only ROUTE through these when OSRM_URL / GRAPHHOPPER_URL are set in
# their gitignored .env.local (off by default — decisions §137); starting the
# engines just makes them available.
start_engine() {
  local name="$1" dir="$2" port="$3" graph="$4" setup="$5"
  step "$name (:$port)"
  if curl -fs "http://127.0.0.1:$port" >/dev/null 2>&1; then
    ok "already running"
  elif [ ! -e "$graph" ]; then
    warn "graph not built — run '$setup' (optional; only $name-backed features need it)"
  elif ( cd "$dir" && docker compose up -d ) >/dev/null 2>&1; then
    ok "started (set its URL in .env.local to route through it)"
  else
    warn "didn't start — run 'docker compose up' in $dir to see why"
  fi
}

cmd_up() {
  # Core stack (Supabase + seed + tiles + Ollama + adb reverse). Reuse the
  # existing bringup; suppress its footer so we print one combined summary.
  DEV_CORE_NO_FOOTER=1 bin/dev-core.sh

  start_engine "OSRM (map matching)" apps/job_worker/osrm 5000 \
    apps/job_worker/osrm/data/region.osrm "npm run dev:setup:osrm"
  start_engine "GraphHopper (route generation)" apps/job_worker/graphhopper 8989 \
    apps/job_worker/graphhopper/data/region.osm.pbf "npm run dev:setup:graphhopper"

  # ── Job worker (queue drain + live-spectator hub) ─────────────────────────
  # Backgrounded so this command returns. We BUILD then run the binary (rather
  # than `go run`, which leaves its child alive on kill) so `down` is a clean
  # single-PID stop. GOTOOLCHAIN=auto so the build works even when the local Go
  # is a patch behind go.mod's pinned toolchain.
  step "Job worker (queue drain + live hub)"
  if worker_running; then
    ok "already running (pid $(cat "$WORKER_PID"))"
  else
    mkdir -p "$DEVDIR"
    if ( cd apps/job_worker && GOTOOLCHAIN=auto go build -o "$WORKER_BIN" . ) >/dev/null 2>&1; then
      ( cd apps/job_worker && nohup "$WORKER_BIN" >"$WORKER_LOG" 2>&1 & echo $! >"$WORKER_PID" )
      sleep 1
      if worker_running; then
        ok "started (pid $(cat "$WORKER_PID"); logs: npm run dev:full:logs)"
      else
        err "exited immediately — check $WORKER_LOG"
      fi
    else
      warn "build failed — run 'npm run dev:run:worker' in its own terminal to see the error"
    fi
  fi

  # ── Done ──────────────────────────────────────────────────────────────────
  printf '\n%s%sBackend services up.%s Run the app for your platform (own terminal):\n\n' "$BOLD" "$GRN" "$RST"
  printf '  %snpm run dev:run:web%s        %s# web        → http://localhost:7777%s\n' "$BOLD" "$RST" "$DIM" "$RST"
  printf '  %snpm run dev:run:android%s    %s# mobile     → Flutter on a device/emulator%s\n' "$BOLD" "$RST" "$DIM" "$RST"
  printf '  %snpm run dev:run:ios%s        %s# mobile iOS → Flutter on a simulator/device%s\n' "$BOLD" "$RST" "$DIM" "$RST"
  printf '  %s(watch) cd apps/watch_wear/android && ./gradlew installDebug%s\n\n' "$DIM" "$RST"
  printf '  %sstatus: npm run dev:full:status   ·   stop: npm run dev:full:down%s\n' "$DIM" "$RST"
  printf '  %spaywall (optional): npm run dev:payments   ·   secret-backed Edge fns: npm run dev:run:fns%s\n' "$DIM" "$RST"
}

cmd_down() {
  step "Job worker"
  if worker_running; then
    kill "$(cat "$WORKER_PID")" 2>/dev/null || true
    rm -f "$WORKER_PID"
    ok "stopped"
  else
    rm -f "$WORKER_PID"
    ok "not running"
  fi

  for e in "OSRM:apps/job_worker/osrm" "GraphHopper:apps/job_worker/graphhopper"; do
    name="${e%%:*}"; dir="${e#*:}"
    step "$name"
    if ( cd "$dir" && docker compose down ) >/dev/null 2>&1; then ok "stopped"; else ok "not running"; fi
  done

  step "Protomaps tiles"
  bin/protomaps-dev.sh stop >/dev/null 2>&1 && ok "stopped" || ok "not running"

  step "Supabase"
  ( cd apps/backend && supabase stop ) >/dev/null 2>&1 && ok "stopped" || ok "not running"

  printf '\n%sBackend services stopped.%s (Ollama is a system service — left running.)\n' "$BOLD" "$RST"
}

cmd_status() {
  step "Supabase"
  ( cd apps/backend && supabase status ) 2>/dev/null | grep -E "API URL|DB URL|Studio" || warn "not running"
  step "Containers"
  docker ps --filter 'name=job_worker_osrm' --filter 'name=job_worker_graphhopper' \
    --filter 'name=protomaps' --format '  {{.Names}}  {{.Status}}' 2>/dev/null || true
  step "Job worker"
  if worker_running; then ok "running (pid $(cat "$WORKER_PID"))"; else warn "not running"; fi
  step "Ollama"
  curl -fs http://localhost:11434/api/tags >/dev/null 2>&1 && ok "reachable on :11434" || warn "not reachable"
}

cmd_logs() {
  [ -f "$WORKER_LOG" ] || { err "no worker log yet — start it with: npm run dev:full"; exit 1; }
  tail -f "$WORKER_LOG"
}

case "${1:-up}" in
  up)     cmd_up ;;
  down)   cmd_down ;;
  status) cmd_status ;;
  logs)   cmd_logs ;;
  *) err "unknown subcommand '$1' (use: up | down | status | logs)"; exit 1 ;;
esac
