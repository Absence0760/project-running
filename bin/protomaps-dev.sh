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
# see docs/architecture/decisions.md § 68 + docs/ops/protomaps_local_setup.md.
#
# Usage:
#   bin/protomaps-dev.sh fetch              # downloads a PMTiles file
#   bin/protomaps-dev.sh start              # boots the container
#   bin/protomaps-dev.sh restart            # stop + start (pick up new PMTiles)
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
# Read more in docs/ops/protomaps_local_setup.md.

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
DEFAULT_SAMPLE_URL="${DEFAULT_SAMPLE_URL:-https://r2-public.protomaps.com/protomaps-sample-datasets/cb_2018_us_zcta510_500k.pmtiles}"

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

# Surface a meaningful error when `docker info` fails — distinguish
# the three real cases (daemon down vs not in docker group vs CLI
# missing). The previous "daemon is not running" catch-all was
# misleading when the user was just missing group membership.
check_docker_daemon() {
	# Capture stderr so we can pattern-match the failure mode.
	local stderr
	if stderr="$(docker info 2>&1 >/dev/null)"; then
		return 0
	fi
	if echo "$stderr" | grep -qiE "permission denied|cannot connect to the Docker"; then
		# Could be EITHER no perms OR no daemon — the Docker CLI
		# error string varies by version. Surface both fixes so
		# the user picks the one that applies.
		err "docker info failed: $stderr"
		log ""
		log "If the daemon isn't running:"
		log "    sudo systemctl start docker"
		log ""
		log "If you're not in the docker group:"
		log "    sudo usermod -aG docker \$USER && newgrp docker"
		exit 1
	fi
	err "docker info failed: $stderr"
	exit 1
}

# Tail the last [n] lines of the container's stderr on a wait-loop
# failure. Without this, the user is left guessing why tileserver-gl
# didn't bind — usually a malformed PMTiles file or a config schema
# mismatch, both of which show up in the container logs in seconds.
tail_container_logs() {
	local n="${1:-20}"
	if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
		log ""
		log "${C_DIM}--- last $n lines from $CONTAINER_NAME ---${C_RESET}"
		docker logs --tail "$n" "$CONTAINER_NAME" 2>&1 | sed 's/^/    /'
		log "${C_DIM}--- end of logs ---${C_RESET}"
	fi
}

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
	check_docker_daemon
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

	# The container mounts a single host directory at /data. If the
	# user pointed PMTILES_FILE at a path outside PROTOMAPS_HOME
	# (e.g. they have a big .pmtiles somewhere else and don't want
	# to copy it), the basename ends up in config.json but the file
	# isn't visible inside the container — tileserver-gl fails on
	# "data source not found". Detect this BEFORE Docker spins up
	# and offer a clear fix.
	local pmtiles_dir
	pmtiles_dir="$(cd "$(dirname "$PMTILES_FILE")" && pwd)"
	local home_resolved
	home_resolved="$(cd "$PROTOMAPS_HOME" && pwd)"
	if [[ "$pmtiles_dir" != "$home_resolved" ]]; then
		err "PMTILES_FILE lives outside PROTOMAPS_HOME:"
		log "    PMTILES_FILE:   $PMTILES_FILE"
		log "    PROTOMAPS_HOME: $PROTOMAPS_HOME"
		log ""
		log "The container only mounts PROTOMAPS_HOME at /data, so the"
		log "PMTiles file must live inside that directory. Fix one of:"
		log ""
		log "  ${C_BOLD}A. Symlink it in${C_RESET} (cheap, no copy):"
		log "       ln -sf \"$PMTILES_FILE\" \\"
		log "         \"$PROTOMAPS_HOME/$(basename "$PMTILES_FILE")\""
		log "       PMTILES_FILE=\"$PROTOMAPS_HOME/$(basename "$PMTILES_FILE")\" \\"
		log "         bin/protomaps-dev.sh start"
		log ""
		log "  ${C_BOLD}B. Point PROTOMAPS_HOME at the file's directory${C_RESET}:"
		log "       PROTOMAPS_HOME=\"$pmtiles_dir\" \\"
		log "         PMTILES_FILE=\"$PMTILES_FILE\" \\"
		log "         bin/protomaps-dev.sh start"
		log ""
		log "  ${C_BOLD}C. Move the file${C_RESET}:"
		log "       mv \"$PMTILES_FILE\" \"$PROTOMAPS_HOME/\""
		exit 1
	fi

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
		--restart unless-stopped \
		-p "${PROTOMAPS_PORT}:8080" \
		-v "${PROTOMAPS_HOME}:/data:ro" \
		"$DOCKER_IMAGE" \
		--config /data/config.json \
		>/dev/null
	ok "container started"

	step "Waiting for the server to come up"
	# tileserver-gl v5 DOES expose /health (returns "OK" plus a
	# 200) — Docker's own healthcheck inside the image hits it.
	# An earlier audit pass said it might not exist; live boot
	# proved otherwise. One curl per iteration is enough.
	for i in {1..30}; do
		if curl -fs "http://localhost:${PROTOMAPS_PORT}/health" >/dev/null 2>&1; then
			ok "ready at http://localhost:${PROTOMAPS_PORT}"
			break
		fi
		sleep 1
		if (( i == 30 )); then
			err "server failed to come up within 30s"
			log "common causes: invalid PMTiles file, port collision, malformed config"
			# Auto-tail logs rather than telling the user to do it
			# manually — they already have to dig through a wall of
			# tileserver-gl output.
			tail_container_logs 30
			exit 1
		fi
	done

	cmd_env
}

cmd_restart() {
	# Common iteration: swap a PMTiles file, regenerate a style,
	# pick up a new config — the script's `start` rebuilds the
	# config + style files but won't restart an already-running
	# container. `restart` makes that one-liner.
	cmd_stop
	cmd_start
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
	step "Add these to your apps' env files"
	cat <<EOF

  ${C_BOLD}apps/web/.env.development${C_RESET}  ${C_DIM}(committed; outranks .env.local on Vite — decisions § 137)${C_RESET}
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
USAGE="usage: bin/protomaps-dev.sh {fetch|start|restart|stop|status|logs|env}"
case "$cmd" in
	fetch)    cmd_fetch ;;
	start)    cmd_start ;;
	restart)  cmd_restart ;;
	stop)     cmd_stop ;;
	status)   cmd_status ;;
	logs)     cmd_logs ;;
	env)      cmd_env ;;
	"")
		err "missing subcommand"
		log "$USAGE"
		exit 1
		;;
	*)
		err "unknown subcommand: $cmd"
		log "$USAGE"
		exit 1
		;;
esac
