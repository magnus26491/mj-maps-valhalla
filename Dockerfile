FROM ghcr.io/gis-ops/docker-valhalla/valhalla:latest
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      wget ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 8002
HEALTHCHECK --interval=30s --timeout=10s --start-period=5400s --retries=3 \
  CMD wget -qO- http://localhost:8002/status || exit 1
ENTRYPOINT ["/entrypoint.sh"]
