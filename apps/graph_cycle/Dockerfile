# Multi-stage build for the graph_cycle map sidecar. Final image is distroless
# static — no shell, no package manager, just the binary — exactly like
# job_worker. CGO is off so the build is fully static.
#
# Unlike the GraphHopper app next door, there is NO Caddy sidecar: this Go
# server enforces the X-Engine-Key guard in-process (internal/api/guard.go), so
# it binds the public Fly port (8989) directly and the image stays single-binary.
#
# The OSM PBF is NOT baked into the image; it lives on the mounted volume at
# /data/region.osm.pbf (operator-uploaded, the SAME extract OSRM/GraphHopper
# use) and is parsed into an in-memory foot graph on boot.

# Pinned by digest (in addition to tag) to satisfy OpenSSF Scorecard
# PinnedDependenciesID — resolve a new digest with
# `docker manifest inspect golang:<tag>` when bumping. Kept identical to
# apps/job_worker/Dockerfile so both Go services share one base.
FROM golang:1.26-alpine@sha256:f23e8b227fb4493eabe03bede4d5a32d04092da71962f1fb79b5f7d1e6c2a17f AS build
WORKDIR /src

# Cache go.mod / go.sum first so dependency-only changes don't invalidate the
# source layer.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/graph_cycle .

FROM gcr.io/distroless/static-debian12:nonroot@sha256:d093aa3e30dbadd3efe1310db061a14da60299baff8450a17fe0ccc514a16639
COPY --from=build /out/graph_cycle /graph_cycle

# Public guarded port (the Go server binds it; Fly's http_service forwards here).
# Health is checked by Fly over HTTP — distroless has no shell for an in-image
# HEALTHCHECK, same as job_worker.
EXPOSE 8989
USER nonroot:nonroot
ENTRYPOINT ["/graph_cycle"]
