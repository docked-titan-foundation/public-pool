# ============================================================
# Stage 1: Source Fetcher + Builder
# ============================================================
# public-pool publishes no releases and no official image, so we build from
# source at a pinned commit. The commit SHA is the integrity check: git is
# content-addressed, so checking out a full SHA cannot silently give us
# different code the way a mutable tag or a re-generated tarball can.
ARG NODE_BASE=node:24.18.1-bookworm-slim@sha256:235600a8101ab264e117b1768e925532262668dc9b581ef1dd7d96ced463b8e7
# hadolint ignore=DL3006
FROM ${NODE_BASE} AS build

ARG PUBLIC_POOL_REPO=https://github.com/benjamin-wilson/public-pool.git
ARG PUBLIC_POOL_COMMIT=96a9202c11de2c6fc8d41155e2e779912a476dc7

# python3/build-essential/cmake are required to compile the native addons
# (sqlite3, secp256k1 bindings) that public-pool depends on.
# hadolint ignore=DL3008
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git \
        python3 \
        build-essential \
        cmake \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /build

# Fetch exactly the pinned commit, then assert we got it. `git fetch <sha>`
# fails outright if the remote no longer serves that object, and the HEAD check
# means a compromised remote cannot hand us a different tree under this SHA.
RUN git init -q . && \
    git remote add origin "${PUBLIC_POOL_REPO}" && \
    git fetch --depth 1 origin "${PUBLIC_POOL_COMMIT}" && \
    git checkout -q FETCH_HEAD && \
    test "$(git rev-parse HEAD)" = "${PUBLIC_POOL_COMMIT}"

# npm ci installs strictly from the committed lockfile — no version drift.
RUN npm ci && \
    npm run build && \
    npm prune --omit=dev && \
    npm cache clean --force

# ============================================================
# Stage 2: Runtime
# ============================================================
# hadolint ignore=DL3006
FROM ${NODE_BASE} AS runtime

ARG APP_VERSION
ARG BUILD_DATE
ARG VCS_REF
ARG PUBLIC_POOL_COMMIT=96a9202c11de2c6fc8d41155e2e779912a476dc7

# OCI Image Spec Labels. upstream.revision records which public-pool commit is
# baked in — the image tag tracks *this* repo's releases, not upstream's.
LABEL org.opencontainers.image.title="public-pool" \
      org.opencontainers.image.description="Hardened Public Pool — solo Bitcoin mining stratum server" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="https://github.com/docked-titan-foundation/public-pool" \
      org.opencontainers.image.licenses="GPL-3.0" \
      org.opencontainers.image.vendor="Docked Titan Foundation" \
      org.opencontainers.image.base.name="docker.io/library/node:24.16.0-bookworm-slim" \
      org.opencontainers.image.upstream.source="https://github.com/benjamin-wilson/public-pool" \
      org.opencontainers.image.upstream.revision="${PUBLIC_POOL_COMMIT}"

# tini reaps zombies and forwards signals, so a `docker stop` / pod eviction
# actually terminates the stratum listener instead of waiting out the timeout.
# hadolint ignore=DL3008
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        tini \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /public-pool

# The stock node image already ships an unprivileged `node` user (uid/gid 1000).
# Upstream's Dockerfile runs as root and copies the whole build tree (source +
# devDependencies) into the final image; we ship only dist/ and prod deps.
COPY --from=build --chown=node:node /build/dist         ./dist
COPY --from=build --chown=node:node /build/node_modules ./node_modules
COPY --from=build --chown=node:node /build/package.json ./package.json

# DB/ is the SQLite share store and the only path the process needs to write.
RUN mkdir -p /public-pool/DB && chown -R node:node /public-pool

# 3333 = stratum (miners), 3334 = HTTP API. Bitcoin RPC is outbound only, so
# unlike upstream we do not EXPOSE 8332.
EXPOSE 3333 3334

USER node

ENV NODE_ENV=production

# The API answering means the NestJS app is up; the stratum listener is bound in
# the same process, so this covers both.
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:'+(process.env.API_PORT||3334)+'/api/info').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "dist/main"]
