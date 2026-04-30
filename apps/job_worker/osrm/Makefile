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

# `osrm-extract --profile foot.lua` produces a graph tuned for foot
# traffic: pedestrian-permitted ways, no motorway-only, slower default
# speeds, no one-way restrictions on shared paths. Critical for
# running tracks — using `car.lua` would discard half the parks +
# trails the runners actually care about.

.PHONY: download build clean serve stop logs ps

download: $(PBF)

$(PBF):
	@mkdir -p data
	@echo "→ Fetching OSM extract: $(REGION_URL)"
	curl -L --fail --output $(PBF) $(REGION_URL)
	@echo "✓ Saved $$(du -h $(PBF) | cut -f1) to $(PBF)"

build: $(PBF)
	@echo "→ Extracting (osrm-extract, foot profile)…"
	docker run --rm -v "$(PWD)/data:/data" $(IMAGE) \
		osrm-extract -p $(PROFILE) /data/region.osm.pbf
	@echo "→ Partitioning (osrm-partition)…"
	docker run --rm -v "$(PWD)/data:/data" $(IMAGE) \
		osrm-partition $(OSRM_BASE)
	@echo "→ Customizing (osrm-customize)…"
	docker run --rm -v "$(PWD)/data:/data" $(IMAGE) \
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
