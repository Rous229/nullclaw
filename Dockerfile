# syntax=docker/dockerfile:1
# Thin runtime image for PaaS deploys (Back4app / Render / HF-style hosts).
# The binary is built by GitHub Actions and published to the rolling
# release `nullclaw-deploy`; this image just fetches and runs it.
FROM ubuntu:24.04

ARG BINARY_URL=https://github.com/Wing56076/nullclaw/releases/download/nullclaw-deploy/nullclaw

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libpq5 tzdata curl socat \
 && rm -rf /var/lib/apt/lists/*

# BINARY_VERSION is bumped by every CI build; copying it into the layer
# busts Docker cache so the fresh binary is always downloaded.
COPY deploy/BINARY_VERSION /tmp/binary-version
RUN curl -fsSL -o /usr/local/bin/nullclaw "${BINARY_URL}?v=$(cat /tmp/binary-version)" \
 && chmod +x /usr/local/bin/nullclaw

COPY deploy/render-entrypoint.sh /app/generate-config.sh
COPY deploy/start.sh /app/start.sh
RUN chmod +x /app/generate-config.sh /app/start.sh \
 && mkdir -p /nullclaw-data/workspace

ENV NULLCLAW_WORKSPACE=/nullclaw-data/workspace
ENV NULLCLAW_HOME=/nullclaw-data
ENV HOME=/nullclaw-data
ENV SHELL=/bin/sh
# PaaS platforms require an all-interfaces bind on their injected $PORT.
ENV NULLCLAW_ALLOW_PUBLIC_BIND=true

WORKDIR /nullclaw-data
EXPOSE 3000
ENTRYPOINT ["/app/start.sh"]
