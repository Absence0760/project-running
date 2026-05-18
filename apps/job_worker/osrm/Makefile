# OSRM dev-stack helpers. One-time region setup + day-to-day server.
#
# Region picker: REGION_URL points at a Geofabrik PBF. Override on the
# CLI to swap regions:
#
#   make download REGION_URL=https://download.geofabrik.de/europe/great-britain/england/greater-london-latest.osm.pbf
#
# The seed data has its routes in Melbourne (Victoria, Australia) so
# Victoria is the default region — gives `make build` something to
# match against the seed runs without fetching the whole continent.

REGION_URL ?= https://download.geofabrik.de/australia-oceania/australia/victoria-latest.osm.pbf
PBF        := data/region.osm.pbf
OSRM_BASE  := data/region.osrm
PROFILE    := /opt/foot.lua
IMAGE      := osrm/osrm-backend:latest
# Run docker as the invoking host user so build outputs land owned by
# the user, not root. Without this, the bind-mount target ends up
# `root:root` and subsequent `curl --output` / make runs hit
# "Permission denied". `id -u` / `id -g` resolve at make-time.
DOCKER_USER := --user $(shell id -u):$(shell id -g)

# `osrm-extract --profile foot.lua` produces a graph tuned for foot
# traffic: pedestrian-permitted ways, no motorway-only, slower default
# speeds, no one-way restrictions on shared paths. Critical for
# running tracks — using `car.lua` would discard half the parks +
# trails the runners actually care about.

.PHONY: download build clean serve stop logs ps smoke check-perms

# Bail early if `data/` already exists but isn't writable by the
# invoking user — almost always the result of a prior
# `docker compose up` running as root and creating the bind-mount
# target. Tell the user the one-line fix instead of letting curl /
# docker fail mid-build with a stack of confusing errors.
check-perms:
	@if [ -d data ] && [ ! -w data ]; then \
		echo ""; \
		echo "  ✗ apps/job_worker/osrm/data/ exists but isn't writable by $$USER."; \
		echo "    A previous \`docker compose up\` ran as root and created this"; \
		echo "    directory. Fix with:"; \
		echo ""; \
		echo "      sudo chown -R $$USER:$$USER apps/job_worker/osrm/data"; \
		echo ""; \
		echo "    Then re-run \`pnpm dev:setup:osrm\`."; \
		echo ""; \
		exit 1; \
	fi

download: check-perms $(PBF)

$(PBF):
	@mkdir -p data
	@echo "→ Fetching OSM extract: $(REGION_URL)"
	curl -L --fail --output $(PBF) $(REGION_URL)
	@echo "✓ Saved $$(du -h $(PBF) | cut -f1) to $(PBF)"

build: check-perms $(PBF)
	@echo "→ Extracting (osrm-extract, foot profile)…"
	docker run --rm $(DOCKER_USER) -v "$(PWD)/data:/data" $(IMAGE) \
		osrm-extract -p $(PROFILE) /data/region.osm.pbf
	@echo "→ Partitioning (osrm-partition)…"
	docker run --rm $(DOCKER_USER) -v "$(PWD)/data:/data" $(IMAGE) \
		osrm-partition $(OSRM_BASE)
	@echo "→ Customizing (osrm-customize)…"
	docker run --rm $(DOCKER_USER) -v "$(PWD)/data:/data" $(IMAGE) \
		osrm-customize $(OSRM_BASE)
	@echo "✓ Build complete. Run 'docker compose up' to serve."

# Convenience targets for day-to-day dev.
serve:
	docker compose up -d

stop:
	docker compose down

logs:
	docker compose logs -f

ps:
	docker compose ps

# Wipe the extracted graph (keeps the downloaded PBF). Use this after
# `make download` of a fresher extract so `make build` rebuilds.
clean:
	rm -f data/region.osrm*
	@echo "✓ Cleared extracted graph; PBF preserved. Run 'make build' to regenerate."

# End-to-end smoke test: queue a Melbourne run through the live stack
# and assert run_matched_tracks goes status=matched. Requires:
#   - this OSRM container up on $$OSRM_URL (default 127.0.0.1:5000)
#   - the local Supabase stack up (apps/backend)
#   - the worker running with OSRM_URL set, in another terminal
# Tunables live at the top of smoke.sh — OSRM_URL, WAIT_S,
# SEED_USER_ID, PG_CONTAINER.
smoke:
	@./smoke.sh
