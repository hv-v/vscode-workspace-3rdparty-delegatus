#!/bin/sh
# Container entrypoint: install the login key, then start Delegatus.
#
# The access key comes from a compose secret (docker/delegatus/.secrets/token,
# mounted at /run/secrets/delegatus_token). Delegatus reads and re-chmods its
# key at $XDG_CONFIG_HOME/delegatus/token, so a read-only bind cannot serve as
# that file: it is copied into the config volume on every start instead, which
# also makes a rotated secret take effect on the next restart.
#
# Binding 0.0.0.0 is what turns the key on: Delegatus asks every connection for
# it as soon as the bind is not loopback. The port is published on host
# loopback only (docker-compose.yml), so this is not an exposure.
set -eu

secret=/run/secrets/delegatus_token
key_dir="${XDG_CONFIG_HOME:?}/delegatus"
key_file="${key_dir}/token"

if [ ! -r "$secret" ]; then
    echo "delegatus-entrypoint: no access key at $secret; run ./delegatus.sh init" >&2
    exit 78
fi
key=$(tr -d '[:space:]' < "$secret")
case "$key" in
    *[!0-9a-f]* | "")
        echo "delegatus-entrypoint: the access key must be 32 lowercase hex characters" >&2
        exit 78
        ;;
esac
if [ "${#key}" -ne 32 ]; then
    echo "delegatus-entrypoint: the access key must be 32 lowercase hex characters" >&2
    exit 78
fi

umask 077
mkdir -p "$key_dir"
printf '%s' "$key" > "${key_file}.new"
mv -f "${key_file}.new" "$key_file"

# Delegatus prints its sign-in link, key included, in the startup banner; a
# container's stdout is kept by the Docker log driver. Mask the key on the way
# out: `./delegatus.sh url` is the one place to read it. tini runs with -g, so
# a stop signal reaches the whole group, bun as well as this filter.
bun bin/cli.mjs --hostname 0.0.0.0 --port "${DELEGATUS_PORT:-8898}" --no-open "$@" 2>&1 \
    | sed -u -e 's/\([?&]k=\)[0-9a-f]\{32\}/\1<redacted>/g' -e "s/${key}/<redacted>/g"
