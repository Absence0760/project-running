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
# see docs/decisions.md § 68 + the followups doc.
#
# Usage:
#   bin/protomaps-dev.sh start              # boots the container
#   bin/protomaps-dev.sh stop               # kills it
#   bin/protomaps-dev.sh status             # is it running?
#   bin/protomaps-dev.sh logs               # tail the container logs
#   bin/protomaps-dev.sh env                # print the .env.local overrides
#
# First-run downloads (one-time):
#   • A regional .pmtiles extract — default is "monaco" (~10 MB) so
#     the smoke test runs fast. Override with PMTILES_REGION (any slug
#     from https://maps.protomaps.com/extracts), or PMTILES_URL for a
#     direct override.
#   • A Protomaps basemap style JSON.
#
# Configuration:
#   PMTILES_REGION   Region slug for the PMTiles file (default: monaco).
#   PMTILES_URL      Full URL to a .pmtiles file (overrides region).
#   PROTOMAPS_PORT   Local port (default: 8080).
#   PROTOMAPS_HOME   Cache dir for the .pmtiles + style + config
#                    (default: $XDG_CACHE_HOME/protomaps-dev or
#                    ~/.cache/protomaps-dev).
#
# Read more in docs/protomaps_local_setup.md.

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# ---- configuration --------------------------------------------------------

PROTOMAPS_PORT="${PROTOMAPS_PORT:-8080}"
PMTILES_REGION="${PMTILES_REGION:-monaco}"
PROTOMAPS_HOME="${PROTOMAPS_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/protomaps-dev}"

CONTAINER_NAME="run-protomaps-dev"
DOCKER_IMAGE="maptiler/tileserver-gl:v5.0.0"
PMTILES_FILE="${PROTOMAPS_HOME}/${PMTILES_REGION}.pmtiles"
STYLE_FILE="${PROTOMAPS_HOME}/style.json"
CONFIG_FILE="${PROTOMAPS_HOME}/config.json"

# Default PMTiles source — Protomaps' build server publishes daily
# extracts at this URL pattern. Override with PMTILES_URL for any
# custom extract (e.g. a continent-scale file you keep elsewhere).
PMTILES_URL="${PMTILES_URL:-https://build.protomaps.com/${PMTILES_REGION}.pmtiles}"

# ---- subcommands ----------------------------------------------------------

cmd_start() {
	step "Checking prerequisites"
	need_cmd docker
	need_cmd curl
	if ! docker info >/dev/null 2>&1; then
		fatal "docker daemon is not running. Start it with: sudo systemctl start docker"
	fi
	ok "docker is up"

	step "Ensuring cache dir ${C_DIM}${PROTOMAPS_HOME}${C_RESET}"
	mkdir -p "$PROTOMAPS_HOME"
	ok "cache dir ready"

	step "Fetching PMTiles file ${C_DIM}${PMTILES_REGION}${C_RESET}"
	if [[ -f "$PMTILES_FILE" ]]; then
		ok "already cached ($(du -h "$PMTILES_FILE" | cut -f1))"
	else
		log "downloading from $PMTILES_URL"
		if ! curl -fL --progress-bar -o "${PMTILES_FILE}.partial" "$PMTILES_URL"; then
			rm -f "${PMTILES_FILE}.partial"
			fatal "PMTiles download failed. Check the region slug or set PMTILES_URL to a known-good extract."
		fi
		mv "${PMTILES_FILE}.partial" "$PMTILES_FILE"
		ok "downloaded ($(du -h "$PMTILES_FILE" | cut -f1))"
	fi

	step "Writing tileserver-gl config"
	# A protomaps basemap style would normally be downloaded here, but
	# tileserver-gl auto-generates a usable style.json from any PMTiles
	# file via its /styles/{id}/style.json endpoint when configured
	# with a `data.source` block. We write the minimal config that
	# wires the PMTiles file as the v3 source the basemap expects.
	cat > "$CONFIG_FILE" <<EOF
{
	"options": {
		"paths": {
			"root": "/data",
			"pmtiles": "",
			"mbtiles": ""
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
			"pmtiles": "${PMTILES_REGION}.pmtiles"
		}
	}
}
EOF
	# Minimal Protomaps-compatible vector style. tileserver-gl
	# substitutes `{pmtiles_path}` at request time with the URL of
	# the source it served from the config. A real production style
	# would have road labels, place names, etc. — the dev style
	# stays tiny so the file is readable.
	cat > "$STYLE_FILE" <<'EOF'
{
	"version": 8,
	"name": "Protomaps Basic",
	"sources": {
		"protomaps": {
			"type": "vector",
			"url": "pmtiles://{pmtiles_path}"
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
			"source": "protomaps",
			"source-layer": "earth",
			"paint": { "fill-color": "#222" }
		},
		{
			"id": "water",
			"type": "fill",
			"source": "protomaps",
			"source-layer": "water",
			"paint": { "fill-color": "#15233a" }
		},
		{
			"id": "roads",
			"type": "line",
			"source": "protomaps",
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
		--restart unless-stopped \
		-p "${PROTOMAPS_PORT}:8080" \
		-v "${PROTOMAPS_HOME}:/data:ro" \
		"$DOCKER_IMAGE" \
		--config /data/config.json \
		>/dev/null
	ok "container started"

	step "Waiting for the server to come up"
	for i in {1..30}; do
		if curl -fs "http://localhost:${PROTOMAPS_PORT}/health" >/dev/null 2>&1; then
			ok "ready at http://localhost:${PROTOMAPS_PORT}"
			break
		fi
		sleep 1
		if (( i == 30 )); then
			err "server failed to come up within 30s"
			log "check the logs with: bin/protomaps-dev.sh logs"
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
	start)  cmd_start ;;
	stop)   cmd_stop ;;
	status) cmd_status ;;
	logs)   cmd_logs ;;
	env)    cmd_env ;;
	"")
		err "missing subcommand"
		log "usage: bin/protomaps-dev.sh {start|stop|status|logs|env}"
		exit 1
		;;
	*)
		err "unknown subcommand: $cmd"
		log "usage: bin/protomaps-dev.sh {start|stop|status|logs|env}"
		exit 1
		;;
esac
