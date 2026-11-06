# syntax=docker/dockerfile:1.7
#
# Delegatus for jo-workspace — a hardened, offline image.
#
# Build context: 3rdparty/delegatus (the clone). The deps and build stages
# follow the upstream Dockerfile; the runtime stage is our own, because the
# upstream one is built to escape its container:
#   * `chmod u+s /usr/bin/nsenter` plus shims for claude, codex, bun, uv, just,
#     tmux, tailscale and docker that nsenter into host PID 1's namespaces;
#   * gh, curl, a docker client shim and a faster-whisper venv that downloads
#     models at first use.
# None of that is here. Nothing in this image can reach the host's namespaces,
# and the compose file gives it no route off the host.
#
# When the clone is updated, diff the upstream deps/build stages against these
# two and carry over any change (bun pin, patches, build env).

ARG NODE_IMAGE=node:22.16.0-bookworm-slim
ARG BUN_VERSION=1.4.0

FROM ${NODE_IMAGE} AS deps
ARG BUN_VERSION
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm install -g "bun@${BUN_VERSION}"
COPY package.json bun.lock ./
# patchedDependencies in package.json: the install fails without them.
COPY patches ./patches
RUN bun install --frozen-lockfile

FROM ${NODE_IMAGE} AS build
ARG BUN_VERSION
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=production \
    NEXT_PUBLIC_RUNTIME_UI=1
RUN npm install -g "bun@${BUN_VERSION}"
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN --mount=type=cache,target=/app/.next/cache \
    env -u __NEXT_PRIVATE_STANDALONE_CONFIG \
        -u __NEXT_PRIVATE_PREBUNDLED_REACT \
        -u __NEXT_PRIVATE_BUILD_WORKER \
        bun run build
# Upstream #76: a umask-077 checkout yields files the runtime user cannot read.
RUN chmod -R u=rwX,go=rX /app

FROM ${NODE_IMAGE} AS runtime
ARG BUN_VERSION
ARG DELEGATUS_UID=1000
ARG DELEGATUS_GID=1000

# git: pipelines and project discovery read repositories. tini: reaps the
# launcher's detached children. No curl, gh, ssh, sudo or nsenter shims.
RUN set -eu; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates git tini; \
    rm -rf /var/lib/apt/lists/*; \
    npm install -g "bun@${BUN_VERSION}"; \
    npm cache clean --force; \
    # The base image's `node` user is UID/GID 1000; re-home it, and renumber it
    # only when the host user differs, so mounted transcripts stay readable.
    if [ "${DELEGATUS_GID}" != "1000" ]; then groupmod -g "${DELEGATUS_GID}" node; fi; \
    if [ "${DELEGATUS_UID}" != "1000" ]; then usermod -u "${DELEGATUS_UID}" node; fi; \
    usermod -l delegatus -d /home/delegatus -m node; \
    groupmod -n delegatus node; \
    mkdir -p /home/delegatus/.config /home/delegatus/.cache /home/delegatus/.claude /home/delegatus/.codex; \
    chown -R delegatus:delegatus /home/delegatus

WORKDIR /app
COPY --from=build --chown=root:root /app/.next ./.next
COPY --from=build --chown=root:root /app/dist ./dist
COPY --from=build --chown=root:root /app/public ./public
COPY --from=build --chown=root:root /app/package.json /app/next.config.ts /app/tsconfig.json ./
COPY --from=build --chown=root:root /app/bin ./bin
COPY --from=build --chown=root:root /app/src ./src
COPY --from=build --chown=root:root /app/vendor ./vendor
COPY --from=build --chown=root:root /app/scripts ./scripts
COPY --from=build --chown=root:root /app/node_modules ./node_modules
# entrypoint.sh is not in the clone: it comes from the `dlgdocker` additional
# build context (docker/delegatus/), named in docker-compose.yml.
COPY --from=dlgdocker --chmod=755 entrypoint.sh /usr/local/bin/delegatus-entrypoint

# The app tree is root-owned and read-only to the service user; only HOME
# (config, state, caches) is writable, and the compose file puts that on a
# named volume. Next's runtime cache is pointed at a tmpfs.
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    NEXT_PUBLIC_RUNTIME_UI=1 \
    HOME=/home/delegatus \
    XDG_CONFIG_HOME=/home/delegatus/.config \
    XDG_CACHE_HOME=/home/delegatus/.cache \
    DELEGATUS_TELEMETRY=0 \
    DO_NOT_TRACK=1 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/usr/local/bin:/usr/bin:/bin

USER delegatus
EXPOSE 8898
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/delegatus-entrypoint"]
