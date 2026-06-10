# Self-hosted GraphHopper routing engine serving the `foot` profile, used
# by the "Generate a route by distance" feature's round_trip loop generator.
#
# There is NO official prebuilt GraphHopper Docker image (the
# graphhopper/graphhopper Docker Hub org is empty), so — unlike the OSRM app
# next door, which runs the upstream osrm/osrm-backend image — we build the
# runnable web jar from a pinned source tag and own the config ourselves.
#
# Two stages: a Maven build that produces graphhopper-web-*.jar, then a slim
# JRE runtime. The OSM graph is NOT baked into the image; it is built on first
# boot from the PBF on the mounted volume (graph.location = /data/graph-cache),
# exactly like OSRM's graph lives on its volume rather than in the image. A
# redeploy that only changes config therefore does not rebuild the graph.
#
# REGION: GraphHopper must import the SAME OSM region PBF as the OSRM graph
# (apps/job_worker/osrm — default Victoria, Australia for the seed; UK for the
# v1 prod plan in deployment.md). The operator drops region.osm.pbf onto the
# volume; see README.md for the build/seed step.

ARG GH_VERSION=10.0

# Base images pinned by manifest-list (multi-arch index) digest, not a bare
# tag, so a re-pushed upstream tag can't silently change the build (Scorecard
# Pinned-Dependencies). The digest is the index, not a single-arch manifest, so
# the build host still gets its matching arch. Re-pin on a deliberate bump:
#   skopeo inspect --raw docker://maven:3.9-eclipse-temurin-21 | sha256.
FROM maven:3.9-eclipse-temurin-21@sha256:d7e7f57407437c014571f1ad5a9955f03fc3edcb1d964067ef351fa38e798665 AS build
ARG GH_VERSION
WORKDIR /src
# Shallow-clone the pinned release tag rather than vendoring the source tree.
RUN git clone --depth 1 --branch ${GH_VERSION} https://github.com/graphhopper/graphhopper.git . \
 && mvn -q -DskipTests clean package \
 && cp web/target/graphhopper-web-*.jar /graphhopper-web.jar

FROM eclipse-temurin:21-jre@sha256:194b590649efee5555de080c634905a30c2885190210e37ada26370ed2a9c781
WORKDIR /gh
COPY --from=build /graphhopper-web.jar /gh/graphhopper-web.jar
COPY config.yml /gh/config.yml

# Caddy fronts GraphHopper as the shared-secret guard (see Caddyfile). Pull the
# binary from the official multi-arch image rather than curling a pinned tarball
# so the arch matches the build platform. Digest-pinned (manifest-list index, so
# arch-matching is preserved) for the same supply-chain reason as the FROM lines.
COPY --from=caddy:2.8@sha256:226d1f059b75399fe19182893c7184591c07b97afc8dfcf44eeb80c9a77a530f /usr/bin/caddy /usr/local/bin/caddy
COPY Caddyfile /gh/Caddyfile

# Graph cache + the source PBF both live on the mounted volume so the graph
# survives redeploys and is reused across boots.
ENV GH_DATA_DIR=/data
ENV GH_PBF=/data/region.osm.pbf

# round_trip is a CORE GraphHopper algorithm, but it only runs in FLEXIBLE
# mode — Contraction Hierarchies (the default speed-mode preparation) cannot
# serve it. config.yml therefore leaves profiles_ch empty so the `foot`
# profile is import-prepared for flexible routing, and round_trip requests
# succeed WITHOUT the caller having to pass ch.disable=true. The generate-route
# core (apps/web/src/lib/routes/generate/graphhopper.ts) does not send that
# param, so this server-side choice is load-bearing.
#
# datareader.file is passed at boot; the first boot imports the PBF into
# graph.location, later boots reuse the cache.
ENV JAVA_OPTS="-Xmx2500m -Xms2500m"
# 8989 = Caddy (public guard); GraphHopper itself binds 127.0.0.1:8990.
EXPOSE 8989

# Health goes through Caddy (the open /health route) so the check validates both
# the guard AND GraphHopper. A 200 means the graph is loaded and serving.
HEALTHCHECK --interval=30s --timeout=5s --start-period=600s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8989/health || exit 1

# Start GraphHopper (binds 127.0.0.1:8990) in the background, then exec Caddy in
# the foreground on the public 8989. If GraphHopper dies, /health stops
# returning 200 and the healthcheck restarts the machine. Caddy reads the
# GRAPHHOPPER_API_KEY secret from the environment (Caddyfile).
ENTRYPOINT ["/bin/sh", "-c", \
  "java $JAVA_OPTS -Ddw.graphhopper.datareader.file=$GH_PBF -Ddw.graphhopper.graph.location=$GH_DATA_DIR/graph-cache -jar /gh/graphhopper-web.jar server /gh/config.yml & exec caddy run --config /gh/Caddyfile --adapter caddyfile"]
