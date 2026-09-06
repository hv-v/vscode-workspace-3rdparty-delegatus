# syntax=docker/dockerfile:1.7
#
# codebase-memory-mcp — build + runtime image for jo-workspace.
#
# Stage 1 (builder)  gcc/node build of the pure-C server WITH the 3D graph UI
#                    embedded into the binary (graph-ui -> embed-frontend.sh).
#                    Network is used here, at build time only.
# Stage 2 (runtime)  minimal image, non-root, no compilers, no network egress
#                    (see docker-compose.yml).
#
# Build context is the checkout at 3rdparty/codebase-memory-mcp; this file lives
# in the workspace so the submodule stays a clean, untouched upstream tree.

ARG UBUNTU_IMAGE=ubuntu:24.04

# ─────────────────────────── stage 1: builder ───────────────────────────
FROM ${UBUNTU_IMAGE} AS builder

# Node is needed only to build graph-ui. Ubuntu noble ships node 18, which is
# below what vite 6 / tailwind 4 require, so take the official LTS tarball and
# verify it against a pinned digest.
ARG NODE_VERSION=24.20.0
ARG NODE_SHA256=2f2c0da162318f0de47665410c7c8c2ed3d36c8f3105de4bbc61176c70a7cbf2

ENV DEBIAN_FRONTEND=noninteractive

# Mirrors the upstream CI dependency set (test-infrastructure/Dockerfile);
# sqlite3, tree-sitter and the grammars are all vendored in the repo.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        ccache \
        curl \
        g++ \
        gcc \
        git \
        make \
        pkg-config \
        python3 \
        xz-utils \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSLo /tmp/node.tar.xz \
        "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && printf '%s  /tmp/node.tar.xz\n' "${NODE_SHA256}" | sha256sum -c - \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner \
    && rm -f /tmp/node.tar.xz \
    && node --version && npm --version

WORKDIR /src
COPY . /src

# CCACHE_COMPILERCHECK=content: a cache hit is byte-identical to a cold compile
# by construction, so the BuildKit cache mount can never yield a stale object.
ENV CCACHE_DIR=/ccache \
    CCACHE_COMPILERCHECK=content \
    CCACHE_MAXSIZE=2G

# scripts/build.sh is upstream's single source of truth for release builds;
# --with-ui runs `npm ci && npm run build` and links the embedded assets.
RUN --mount=type=cache,target=/ccache,sharing=locked \
    --mount=type=cache,target=/root/.npm,sharing=locked \
    scripts/build.sh --with-ui CC=gcc CXX=g++ \
    && test -x build/c/codebase-memory-mcp \
    && build/c/codebase-memory-mcp --version

# ─────────────────────────── stage 2: runtime ───────────────────────────
FROM ${UBUNTU_IMAGE} AS runtime

# Match the host user so the read-only workspace mount is readable and the
# cache volume is not owned by root.
ARG CBM_UID=1000
ARG CBM_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

# socat + iproute2 back the UI forwarder in the entrypoint (see the comment
# there); tini reaps the daemon's children as PID 1.
RUN apt-get update && apt-get install -y --no-install-recommends \
        iproute2 \
        socat \
        tini \
    && rm -rf /var/lib/apt/lists/*

# ubuntu:24.04 ships a stock `ubuntu` account on uid 1000; drop whatever holds
# the requested id before claiming it.
RUN set -eux; \
    if getent passwd "${CBM_UID}" >/dev/null; then \
        userdel -rf "$(getent passwd "${CBM_UID}" | cut -d: -f1)" 2>/dev/null || true; \
    fi; \
    if ! getent group "${CBM_GID}" >/dev/null; then groupadd -g "${CBM_GID}" cbm; fi; \
    useradd -u "${CBM_UID}" -g "${CBM_GID}" -m -d /home/cbm -s /bin/bash cbm; \
    mkdir -p /cbm/cache; \
    chown -R "${CBM_UID}:${CBM_GID}" /cbm /home/cbm

COPY --from=builder --chown=root:root /src/build/c/codebase-memory-mcp /usr/local/bin/codebase-memory-mcp
# entrypoint.sh lives next to this Dockerfile, outside the source context;
# it arrives as the named build context "cbmdocker" (see docker-compose.yml).
COPY --from=cbmdocker --chown=root:root entrypoint.sh /usr/local/bin/cbm-entrypoint.sh
RUN chmod 0755 /usr/local/bin/codebase-memory-mcp /usr/local/bin/cbm-entrypoint.sh

# CBM_CACHE_DIR is the canonical per-account cache root: every process in this
# container (the keepalive session, `docker exec` MCP sessions, one-shot CLI
# calls) must agree on it or CBM's admission barrier rejects them.
ENV CBM_CACHE_DIR=/cbm/cache \
    CBM_RUNTIME_DIR=/tmp \
    CBM_UI_PORT=9749 \
    HOME=/home/cbm

USER cbm
WORKDIR /home/cbm
EXPOSE 9749

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/${CBM_UI_PORT}' || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/cbm-entrypoint.sh"]
