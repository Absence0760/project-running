# Multi-stage build. Final image is distroless static so there's no
# shell, no package manager, no glibc — just the binary. CGO is off
# so the build is fully static and portable across distros.

# Pinned by digest (in addition to tag) to satisfy OpenSSF Scorecard
# PinnedDependenciesID — bumping the tag without re-pinning the
# digest no-ops the pin, so resolve the new digest with
# `docker manifest inspect golang:<tag>` when bumping.
FROM golang:1.27-alpine@sha256:cf6fca6641884b8433441b2b0652976f975e1d0fdd26d177eaaf8596087f3125 AS build
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
