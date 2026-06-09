# GraphHopper dev-stack helpers. One-time PBF seed + day-to-day server.
#
# Unlike OSRM (a separate extract/partition/customize pipeline), GraphHopper
# builds its routing graph itself on the first `docker compose up`, onto the
# mounted volume. So `make seed` only has to provision the PBF; the graph
# import happens inside the container.
#
# Region: reuses the OSRM extract by default so both engines share one map.
# Override REGION_URL to fetch a different one:
#   make seed REGION_URL=https://download.geofabrik.de/europe/great-britain-latest.osm.pbf

REGION_URL ?= https://download.geofabrik.de/australia-oceania/australia/victoria-latest.osm.pbf
PBF        := data/region.osm.pbf
OSRM_PBF   := ../osrm/data/region.osm.pbf

.PHONY: seed build serve up stop logs ps clean smoke

# Put the region PBF on the volume. Prefers the extract the OSRM stack already
# downloaded (both engines should import the SAME region); else downloads it.
seed: $(PBF)

$(PBF):
	@mkdir -p data
	@if [ -f "$(OSRM_PBF)" ]; then \
		echo "→ Reusing OSRM extract: $(OSRM_PBF)"; \
		cp "$(OSRM_PBF)" "$(PBF)"; \
	else \
		echo "→ Fetching OSM extract: $(REGION_URL)"; \
		curl -L --fail --output "$(PBF)" "$(REGION_URL)"; \
	fi
	@echo "✓ Seeded $$(du -h $(PBF) | cut -f1) to $(PBF)"

# Build the image — compiles graphhopper-web from source, slow the first time.
build:
	docker compose build

# Start the server (builds if needed; imports the graph on first boot).
serve up: $(PBF)
	docker compose up -d

stop:
	docker compose down

logs:
	docker compose logs -f

ps:
	docker compose ps

# Wipe the imported graph (keeps the PBF) so the next boot re-imports — e.g.
# after a config.yml change (new profile, LM toggle) or a fresh `make seed`.
clean:
	rm -rf data/graph-cache
	@echo "✓ Cleared graph-cache; PBF preserved. Run 'docker compose up' to re-import."

# End-to-end smoke: a foot round_trip near the Melbourne seed coords. Asserts a
# loop comes back. Requires this container up on :8989. Sends the dev shared
# secret (the Caddy guard 403s /route without it; /health is open).
smoke:
	@curl -s -H 'X-Engine-Key: dev-graphhopper-key' 'http://127.0.0.1:8989/route?profile=foot&point=-37.81,144.96&algorithm=round_trip&round_trip.distance=3000&round_trip.seed=1&points_encoded=false&instructions=false' \
		| grep -q '"points"' && echo "✓ round_trip OK" || (echo "✗ round_trip failed"; exit 1)
