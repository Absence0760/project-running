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

FROM maven:3.9-eclipse-temurin-21 AS build
ARG GH_VERSION
WORKDIR /src
# Shallow-clone the pinned release tag rather than vendoring the source tree.
RUN git clone --depth 1 --branch ${GH_VERSION} https://github.com/graphhopper/graphhopper.git . \
 && mvn -q -DskipTests clean package \
 && cp web/target/graphhopper-web-*.jar /graphhopper-web.jar

FROM eclipse-temurin:21-jre
WORKDIR /gh
COPY --from=build /graphhopper-web.jar /gh/graphhopper-web.jar
COPY config.yml /gh/config.yml

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
EXPOSE 8989

# A 200 from /health means the graph is loaded and the server is serving.
HEALTHCHECK --interval=30s --timeout=5s --start-period=600s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8989/health || exit 1

ENTRYPOINT ["/bin/sh", "-c", \
  "exec java $JAVA_OPTS -Ddw.graphhopper.datareader.file=$GH_PBF -Ddw.graphhopper.graph.location=$GH_DATA_DIR/graph-cache -jar /gh/graphhopper-web.jar server /gh/config.yml"]
