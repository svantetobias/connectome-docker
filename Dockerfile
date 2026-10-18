# syntax=docker/dockerfile:1
# Unofficial container for anima-research/connectome-host.
# Builds from an upstream git ref (tag, branch or commit).
ARG BUN_IMAGE=oven/bun:1.4.3@sha256:ec06c3b6cea04192ae6770c434f668ca41d343ad19fa6472216c7b48be39c598
ARG NODE_IMAGE=node:22.23.3-bookworm@sha256:0e5f906573693feaa1e21057ebdcfdb5bd5021f050b2dc7c9deceb629c7da2a8

FROM ${BUN_IMAGE} AS bun

FROM ${NODE_IMAGE} AS build
ARG UPSTREAM_REPO=https://github.com/anima-research/connectome-host.git
ARG UPSTREAM_REF=main
COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun
WORKDIR /app
RUN git init -q . && git remote add origin "$UPSTREAM_REPO" \
 && git fetch -q --depth 1 origin "$UPSTREAM_REF" && git checkout -q FETCH_HEAD \
 && rm -rf .git
# installs deps; postinstall builds the web UI SPA (needs npm)
RUN bun install --frozen-lockfile || bun install
RUN test -d web/dist || test -d dist/web || npm run build:web

# Optional chat bridges (off by default; enabled via ZULIP_ENABLED / DISCORD_ENABLED)
FROM ${NODE_IMAGE} AS bridges
ARG ZULIP_MCP_REPO=https://github.com/antra-tess/zulip_mcp.git
ARG ZULIP_MCP_REF=0642e3308db86ad262c4cd8aec0283d95ae55554
ARG DISCORD_MCPL_REPO=https://github.com/anima-research/discord-mcpl.git
ARG DISCORD_MCPL_REF=5da8c26a326d84e0c65a9fb171fc6ca445dfb535
RUN set -e; for spec in "zulip_mcp $ZULIP_MCP_REPO $ZULIP_MCP_REF" "discord-mcpl $DISCORD_MCPL_REPO $DISCORD_MCPL_REF"; do \
      set -- $spec; mkdir -p "/opt/$1"; cd "/opt/$1"; \
      git init -q . && git remote add origin "$2" && git fetch -q --depth 1 origin "$3" && git checkout -q FETCH_HEAD && rm -rf .git; \
      npm ci --ignore-scripts --no-audit --no-fund && npm run build && npm prune --omit=dev --no-audit --no-fund; \
    done; test -f /opt/zulip_mcp/build/index.js; test -f /opt/discord-mcpl/dist/src/index.js

FROM ${BUN_IMAGE} AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates tini git \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build --chown=bun:bun /app /app
COPY --chown=bun:bun docker/ /app/docker/
# real Node.js for the bridges (the bun image's `node` is a bun shim)
COPY --from=bridges /usr/local/bin/node /usr/local/bin/node
COPY --from=bridges /opt/zulip_mcp /opt/zulip_mcp
COPY --from=bridges /opt/discord-mcpl /opt/discord-mcpl
# Files upstream looks up in its working directory (/app, not writable at runtime)
# are symlinked into /config so they persist and are writable as PUID:PGID.
RUN mkdir -p /data /config /input && chown -R bun:bun /data /config /input \
 && for f in mcpl-servers.json mcpl-servers.agent.json; do rm -f "/app/$f"; ln -s "/config/$f" "/app/$f"; done
ENV DATA_DIR=/data \
    WEBUI_PORT=7340 \
    NODE_ENV=production \
    PUID=99 PGID=100 UMASK=022 PROVIDER=anthropic \
    ZULIP_ENABLED=false DISCORD_ENABLED=false ZULIP_RC_PATH=/config/.zuliprc \
    HOME=/home/bun \
    SLEEP_PRIVILEGED_FILE=/config/sleep-privileged.json
VOLUME ["/data", "/config", "/input"]
EXPOSE 7340
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 CMD ["/app/docker/healthcheck.sh"]
ENTRYPOINT ["/usr/bin/tini", "--", "/app/docker/entrypoint.sh"]
