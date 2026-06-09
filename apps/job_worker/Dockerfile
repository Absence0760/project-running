# Multi-stage build. Final image is distroless static so there's no
# shell, no package manager, no glibc — just the binary. CGO is off
# so the build is fully static and portable across distros.

# Pinned by digest (in addition to tag) to satisfy OpenSSF Scorecard
# PinnedDependenciesID — bumping the tag without re-pinning the
# digest no-ops the pin, so resolve the new digest with
# `docker manifest inspect golang:<tag>` when bumping.
FROM golang:1.26-alpine@sha256:f23e8b227fb4493eabe03bede4d5a32d04092da71962f1fb79b5f7d1e6c2a17f AS build
WORKDIR /src

# Cache go.mod / go.sum first so dependency-only changes don't
# invalidate the source layer.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/job_worker .

FROM gcr.io/distroless/static-debian12:nonroot@sha256:d093aa3e30dbadd3efe1310db061a14da60299baff8450a17fe0ccc514a16639
COPY --from=build /out/job_worker /job_worker

# slog JSON logs go to stdout. No HTTP listener — the worker is
# pure outbound, so no EXPOSE.
USER nonroot:nonroot
ENTRYPOINT ["/job_worker"]
