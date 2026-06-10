# graph_cycle dev-stack helpers. The sidecar parses an OSM PBF into an in-memory
# foot graph on boot, so the one-time setup is just getting the PBF onto ./data.
#
# REGION: graph_cycle must use the SAME OSM extract as the OSRM + GraphHopper
# graphs so the routable coverage matches. `make seed` copies it from the OSRM
# dev stack (../job_worker/osrm/data/region.osm.pbf) if present, else downloads
# the default region. Override REGION_URL to fetch a different one.

REGION_URL ?= https://download.geofabrik.de/australia-oceania/australia/victoria-latest.osm.pbf
OSRM_PBF   := ../job_worker/osrm/data/region.osm.pbf
PBF        := data/region.osm.pbf
DEV_KEY    := dev-graph-cycle-key

.PHONY: seed build serve up stop logs smoke dev test

# Put the region PBF on ./data — reuse the OSRM extract when it exists so all
# three engines share one download.
seed:
	@mkdir -p data
	@if [ -f "$(OSRM_PBF)" ]; then \
		echo "→ Reusing OSRM extract: $(OSRM_PBF)"; \
		cp "$(OSRM_PBF)" "$(PBF)"; \
	else \
		echo "→ Fetching OSM extract: $(REGION_URL)"; \
		curl -L --fail --output "$(PBF)" "$(REGION_URL)"; \
	fi
	@echo "✓ Seeded $$(du -h $(PBF) | cut -f1) to $(PBF)"

build:
	docker compose build

serve up:
	docker compose up -d

stop:
	docker compose down

logs:
	docker compose logs -f

# Run the server directly (no Docker) against the seeded PBF — fastest inner
# loop. Needs Go (GOTOOLCHAIN=auto if your local toolchain is older than go.mod).
dev:
	GRAPH_CYCLE_PBF=$(PBF) GRAPH_CYCLE_API_KEY=$(DEV_KEY) go run .

test:
	go test ./...

# Smoke the guard + cycle search. Expects the server up (compose or `make dev`)
# and a PBF whose coverage includes the query point — override START for your
# seeded region.
START ?= -37.81,144.96
smoke:
	@curl -s -H 'X-Engine-Key: $(DEV_KEY)' \
		-X POST 'http://127.0.0.1:8989/cycle' \
		-H 'Content-Type: application/json' \
		-d '{"start":{"lat":'"$$(echo $(START) | cut -d, -f1)"',"lng":'"$$(echo $(START) | cut -d, -f2)"'},"targetDistanceM":5000}' \
		| grep -q '"found"' && echo "✓ /cycle responded" || (echo "✗ no response — is the server up + the PBF seeded for this region?" && exit 1)
