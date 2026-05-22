#!/usr/bin/env bash
#
# protomaps-dev.sh — local Protomaps tile server for dev.
#
# Eliminates the MapTiler dependency during development. Boots
# `tileserver-gl` (the full version, not -light) in Docker, points it
# at a PMTiles file containing OpenStreetMap-derived vector tiles, and
# exposes a single localhost endpoint that serves BOTH:
#
#   • MapLibre vector tiles + style.json (web app uses these)
#   • Server-rasterised PNG tiles (mobile + Wear OS use these)
#
# This is the dev path. The production migration to self-hosted
# Protomaps (S3 + PMTiles via Range requests) is a separate decision —
# see docs/decisions.md § 68 + docs/protomaps_local_setup.md.
#
# Usage:
#   bin/protomaps-dev.sh fetch              # downloads a PMTiles file
#   bin/protomaps-dev.sh start              # boots the container
#   bin/protomaps-dev.sh stop               # kills it
#   bin/protomaps-dev.sh status             # is it running?
#   bin/protomaps-dev.sh logs               # tail the container logs
#   bin/protomaps-dev.sh env                # print the .env.local overrides
#
# Important: this script does NOT auto-download a PMTiles file.
# Protomaps publishes daily WORLD builds (~80GB) — not per-region
# pre-builds — at https://build.protomaps.com/<YYYYMMDD>.pmtiles.
# For dev you either:
#
#   (a) Run `bin/protomaps-dev.sh fetch` which downloads a small
#       sample (US states, ~1MB) — enough to verify the wire end
#       to end, not enough to render real run locations.
#   (b) Generate a regional extract from the daily world build
#       using the `pmtiles` Go CLI:
#         pmtiles extract https://build.protomaps.com/$(date +%Y%m%d).pmtiles \
#           ~/.cache/protomaps-dev/world.pmtiles --bbox=...
#   (c) Provide your own .pmtiles file at $PROTOMAPS_HOME/world.pmtiles
#       and point PMTILES_FILE at it.
#
# Read more in docs/protomaps_local_setup.md.

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# ---- configuration --------------------------------------------------------

PROTOMAPS_PORT="${PROTOMAPS_PORT:-8080}"
PROTOMAPS_HOME="${PROTOMAPS_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/protomaps-dev}"
PMTILES_FILE="${PMTILES_FILE:-${PROTOMAPS_HOME}/world.pmtiles}"

# Docker image tag — pinned to a known-good release so a tag drift
# doesn't silently break our config. `latest` would track upstream
# changes that could break the schema below. Bump deliberately.
DOCKER_IMAGE="${DOCKER_IMAGE:-maptiler/tileserver-gl:v5.6.0}"
CONTAINER_NAME="run-protomaps-dev"
CONFIG_FILE="${PROTOMAPS_HOME}/config.json"
STYLE_FILE="${PROTOMAPS_HOME}/style.json"

# Default sample source for `fetch`. Protomaps publishes small
# sample PMTiles in their public R2 bucket. The US-states file is
# the smallest one that's still useful as a smoke test (renders a
# real polygon, not just a 2-pixel test fixture).
DEFAULT_SAMPLE_URL="${DEFAULT_SAMPLE_URL:-https://r2-public.protomaps.com/protomaps-sample-datasets/cb_2018_us_state_20m.pmtiles}"

# ---- helpers --------------------------------------------------------------

# Strip trailing slashes + validate input is shell-safe before
# letting it through to docker / curl. `bash -n` won't catch a
# value like `:; rm -rf` here — we trust the operator's .env but
# guard against accidental garbage from a copy/paste.
require_safe_value() {
	local name="$1" value="$2"
	if [[ "$value" =~ [^A-Za-z0-9_./:@?=,+-] ]]; then
		fatal "$name contains shell-unsafe characters: '$value'"
	fi
}

require_safe_value PROTOMAPS_PORT "$PROTOMAPS_PORT"
require_safe_value DOCKER_IMAGE "$DOCKER_IMAGE"

# ---- subcommands ----------------------------------------------------------

cmd_fetch() {
	step "Fetching sample PMTiles into ${C_DIM}${PMTILES_FILE}${C_RESET}"
	need_cmd curl
	mkdir -p "$PROTOMAPS_HOME"

	if [[ -f "$PMTILES_FILE" ]]; then
		warn "file already exists ($(du -h "$PMTILES_FILE" | cut -f1))"
		log "remove or rename it first if you want a fresh download"
		return 0
	fi

	# Clean up the partial file if the user Ctrl-Cs mid-download —
	# otherwise the next run would refuse to start because a stale
	# `.partial` lingers. The trap is per-subshell so it doesn't
	# leak into the other subcommands.
	local partial="${PMTILES_FILE}.partial"
	trap 'rm -f "$partial"' EXIT INT TERM

	log "downloading from $DEFAULT_SAMPLE_URL"
	log "(this is a ~1MB US-states sample — enough to smoke-test the wire,"
	log " NOT enough to render real run locations. See the doc header"
	log " for how to get a regional extract or the full world build.)"
	if ! curl -fL --progress-bar -o "$partial" "$DEFAULT_SAMPLE_URL"; then
		fatal "PMTiles download failed."
	fi
	mv "$partial" "$PMTILES_FILE"
	# Clear the trap now that the move succeeded — otherwise EXIT
	# would still fire and rm a file that no longer exists at the
	# .partial path. (No real harm, but cleaner.)
	trap - EXIT INT TERM
	ok "downloaded ($(du -h "$PMTILES_FILE" | cut -f1))"
}

cmd_start() {
	step "Checking prerequisites"
	need_cmd docker
	need_cmd curl
	if ! docker info >/dev/null 2>&1; then
		fatal "docker daemon is not running. Start it with: sudo systemctl start docker"
	fi
	ok "docker is up"

	step "Looking for PMTiles file ${C_DIM}${PMTILES_FILE}${C_RESET}"
	if [[ ! -f "$PMTILES_FILE" ]]; then
		err "PMTiles file not found"
		log ""
		log "Options:"
		log "  ${C_BOLD}1. Quick smoke test${C_RESET} (US states, ~1MB):"
		log "       bin/protomaps-dev.sh fetch"
		log ""
		log "  ${C_BOLD}2. Regional extract${C_RESET} (your area, MB to GB):"
		log "       # Install once: brew install pmtiles  OR  go install github.com/protomaps/go-pmtiles@latest"
		log "       pmtiles extract https://build.protomaps.com/\$(date +%Y%m%d).pmtiles \\"
		log "         \"$PMTILES_FILE\" --bbox=MIN_LON,MIN_LAT,MAX_LON,MAX_LAT"
		log ""
		log "  ${C_BOLD}3. Full world build${C_RESET} (~80GB):"
		log "       curl -L -o \"$PMTILES_FILE\" https://build.protomaps.com/\$(date +%Y%m%d).pmtiles"
		log ""
		log "  ${C_BOLD}4. Use your own .pmtiles file${C_RESET}:"
		log "       PMTILES_FILE=/path/to/file.pmtiles bin/protomaps-dev.sh start"
		exit 1
	fi
	ok "found ($(du -h "$PMTILES_FILE" | cut -f1))"

	step "Writing tileserver-gl config"
	# tileserver-gl reads the PMTiles file via the `data` block; the
	# style.json references the source by id. The basename of the
	# PMTiles file (relative to /data) is what tileserver-gl uses.
	local pmtiles_basename
	pmtiles_basename="$(basename "$PMTILES_FILE")"
	cat > "$CONFIG_FILE" <<EOF
{
	"options": {
		"paths": {
			"root": "/data",
			"styles": "",
			"pmtiles": ""
		},
		"serveStaticMaps": true
	},
	"styles": {
		"basic": {
			"style": "style.json"
		}
	},
	"data": {
		"v3": {
			"pmtiles": "${pmtiles_basename}"
		}
	}
}
EOF

	# Minimal MapLibre style. The "v3" source id matches the
	# `data.v3` entry in config.json above; tileserver-gl rewrites
	# the source URL at request time so the browser fetches tiles
	# from the same origin as the style.json. A real production
	# style would include road labels, place names, contour lines —
	# the dev style stays minimal so the file is legible.
	cat > "$STYLE_FILE" <<'EOF'
{
	"version": 8,
	"name": "Protomaps Basic (dev)",
	"sources": {
		"v3": {
			"type": "vector",
			"url": "mbtiles://v3"
		}
	},
	"layers": [
		{
			"id": "background",
			"type": "background",
			"paint": { "background-color": "#1a1a1a" }
		},
		{
			"id": "earth",
			"type": "fill",
			"source": "v3",
			"source-layer": "earth",
			"paint": { "fill-color": "#222" }
		},
		{
			"id": "water",
			"type": "fill",
			"source": "v3",
			"source-layer": "water",
			"paint": { "fill-color": "#15233a" }
		},
		{
			"id": "roads",
			"type": "line",
			"source": "v3",
			"source-layer": "roads",
			"paint": { "line-color": "#666", "line-width": 1 }
		}
	]
}
EOF
	ok "config + style written"

	step "Booting ${C_DIM}${CONTAINER_NAME}${C_RESET}"
	if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
		warn "container already running — stop it first with: bin/protomaps-dev.sh stop"
		log "or use ${C_BOLD}bin/protomaps-dev.sh logs${C_RESET} to watch it"
		return 0
	fi
	# Remove any stopped container with the same name so the next
	# docker run doesn't fail with NameAlreadyInUse.
	docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

	docker run -d \
		--name "$CONTAINER_NAME" \
		-p "${PROTOMAPS_PORT}:8080" \
		-v "${PROTOMAPS_HOME}:/data:ro" \
		"$DOCKER_IMAGE" \
		--config /data/config.json \
		>/dev/null
	ok "container started"

	step "Waiting for the server to come up"
	# tileserver-gl doesn't expose /health. The root path returns
	# the landing page once it's up; /styles.json returns the
	# styles list. Try either — the first that responds 200 wins.
	for i in {1..30}; do
		if curl -fs "http://localhost:${PROTOMAPS_PORT}/styles.json" >/dev/null 2>&1 \
			|| curl -fs "http://localhost:${PROTOMAPS_PORT}/" >/dev/null 2>&1; then
			ok "ready at http://localhost:${PROTOMAPS_PORT}"
			break
		fi
		sleep 1
		if (( i == 30 )); then
			err "server failed to come up within 30s"
			log "check the logs with: bin/protomaps-dev.sh logs"
			log "common causes: invalid PMTiles file, port collision, malformed config"
			exit 1
		fi
	done

	cmd_env
}

cmd_stop() {
	step "Stopping ${C_DIM}${CONTAINER_NAME}${C_RESET}"
	if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
		log "no container with that name — nothing to stop"
		return 0
	fi
	docker rm -f "$CONTAINER_NAME" >/dev/null
	ok "stopped"
}

cmd_status() {
	if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
		ok "running at http://localhost:${PROTOMAPS_PORT}"
		log "    PMTiles: $PMTILES_FILE"
		log "    cache:   $PROTOMAPS_HOME"
		log "    image:   $DOCKER_IMAGE"
	else
		warn "not running"
		log "start with: bin/protomaps-dev.sh start"
	fi
}

cmd_logs() {
	if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
		fatal "container not running"
	fi
	docker logs -f --tail 50 "$CONTAINER_NAME"
}

cmd_env() {
	step "Add these to your apps' .env.local files"
	cat <<EOF

  ${C_BOLD}apps/web/.env.local${C_RESET}
    PUBLIC_TILE_STYLE_URL=http://localhost:${PROTOMAPS_PORT}/styles/basic/style.json

  ${C_BOLD}apps/mobile_android/.env.local + apps/mobile_ios/.env.local${C_RESET}
    TILE_URL_TEMPLATE=http://localhost:${PROTOMAPS_PORT}/styles/basic/{z}/{x}/{y}.png

  ${C_BOLD}apps/watch_wear/android/.env.local${C_RESET}
    PUBLIC_TILE_URL_TEMPLATE=http://localhost:${PROTOMAPS_PORT}/styles/basic/{z}/{x}/{y}.png

  ${C_DIM}Note:${C_RESET} the mobile + Wear apps need ${C_DIM}10.0.2.2${C_RESET} instead of
  ${C_DIM}localhost${C_RESET} when running in the Android emulator (it's the alias
  the emulator uses to reach the host machine). For Wear OS, append
  ${C_DIM}-PPUBLIC_TILE_URL_TEMPLATE=...${C_RESET} on the gradle invocation since the
  value flows through BuildConfig at build time.

EOF
}

# ---- dispatch -------------------------------------------------------------

cmd="${1:-}"
case "$cmd" in
	fetch)  cmd_fetch ;;
	start)  cmd_start ;;
	stop)   cmd_stop ;;
	status) cmd_status ;;
	logs)   cmd_logs ;;
	env)    cmd_env ;;
	"")
		err "missing subcommand"
		log "usage: bin/protomaps-dev.sh {fetch|start|stop|status|logs|env}"
		exit 1
		;;
	*)
		err "unknown subcommand: $cmd"
		log "usage: bin/protomaps-dev.sh {fetch|start|stop|status|logs|env}"
		exit 1
		;;
esac
