# Delegatus — loopback-only container with a workspace orchestrator

[Delegatus](https://github.com/Latand/delegatus) is a board and orchestrator
for Claude Code, Codex and Copilot agents. Here it runs as a hardened container
with the Claude Code and Codex CLIs inside it. Its only route off the host is
an allow-list proxy to those two providers' APIs. One orchestrator is seated
on the workspace root and covers every repository in it.

```bash
./delegatus.sh up        # init (.env + key), build if needed, start
./delegatus.sh configure # apply workspace.json: settings + one project per repo
./delegatus.sh url       # sign-in link: http://127.0.0.1:8898/?k=<key>
./delegatus.sh status    # container, HTTP answer, engines, isolation proof
./delegatus.sh seat      # seat the workspace orchestrator (after signing in)
```

## The workspace orchestrator

One Delegatus orchestrator ("seat") manages the whole workspace. It is seated
on the **workspace-root project**, not on a submodule:

1. `./delegatus.sh url`, open the link, then **Accounts**. For Claude (and
   Codex, if workers should use it) **add an account** and sign it in. Do not
   sign in the built-in "Main" account: its home's transcript folder is the
   host's, mounted read-only, so its agents could not save their sessions.
   Claude signs in through a browser link and a pasted code; Codex uses a
   device code. Credentials stay in the `delegatus-home` volume.
2. `./delegatus.sh seat` resolves the root's project key from its directory,
   names it after `projects.workspaceRoot`, and designates the seat with
   Delegatus's **stock mandate**, unedited, so later releases upgrade it. The
   engine, model and effort come from the `orchestrator` block of
   `workspace.json`. Re-running keeps a live seat.
3. Choose which engine each worker role runs in the UI (menu → Agent mapping).

Delegatus refuses a seat's launch into another project's directory, and every
submodule is a repository, so a project of its own. Workers therefore start
at the workspace root and work in a submodule by path.
`.claude/rules/delegatus.md` (and `.agents/rules/delegatus.md` for Codex) tell
the agents so. Gemini is not a Delegatus engine.

## Workspace configuration — `workspace.json`

The tracked defaults for this workspace, applied through Delegatus's own API by
`./delegatus.sh configure` (signs in with the key, then sets each item; safe to
re-run — an existing project answers `already present`):

| key | meaning |
|---|---|
| `operator.locale`, `operator.timeZone` | interface language (`en`/`uk`) and the time zone reports use |
| `projects.workspaceRoot` | name of the project for the workspace root itself |
| `projects.discover` | workspace-relative globs; every match holding a `.git` becomes a project named after its directory |
| `projects.exclude` | workspace-relative paths left out (the two reference collections in `3rdparty/`) |
| `orchestrator.engine`, `.model`, `.effort` | the runtime `seat` designates the workspace orchestrator with (`claude`/`codex`) |

A new repository in the workspace joins on the next `configure`. Roles,
the worker limit and learned rules are left at Delegatus's defaults.

The workspace is mounted **read-write at its own host path**: agents edit it,
and transcript working directories and project roots resolve inside the
container exactly as on the host. Hidden behind an empty read-only mount
(`compose.masks.yml`, generated from `mask_paths` in `delegatus.sh`, only for
paths that exist): the `.atlassian/` and `.gitlab/` credentials and mirrored
corporate data, this directory's `.env` and `.secrets/`, and
`docker/cbm/.env`. The host's own `~/.claude/projects` and `~/.codex/sessions`
stay read-only; agents started here write to their account homes in the
volume.

## Network: the allow-list proxy

The container's network is a no-NAT bridge with a black-holed resolver, so it
reaches nothing directly. `proxy` (tinyproxy, `proxy/`) sits on that bridge and
on a normal NAT network. It tunnels **only to port 443 of the hosts in
`proxy/allow`**:

| host | for |
|---|---|
| `api.anthropic.com` | Claude API, account profile |
| `platform.claude.com`, `console.anthropic.com` | Claude OAuth token exchange and refresh |
| `api.openai.com` | OpenAI API |
| `chatgpt.com`, `auth.openai.com` | Codex with a ChatGPT sign-in, device login |

Everything else gets 403: Delegatus's install ping and update checks, GitHub,
npm, telemetry. The container reaches the proxy by IP (`DELEGATUS_PROXY_IP`,
default `172.31.97.10`), since it has no working DNS. Adding a host is an edit
to `proxy/allow` and `./delegatus.sh build && ./delegatus.sh restart`.
`check-isolation` proves both halves.

## What it can and cannot do in this shape

| works | does not work, by design |
|---|---|
| your Claude Code and Codex transcripts as searchable chats (read-only) | Docker inside the container: no code graph (`cbm.sh`), no Docker builds or tests — the ROS 2 projects build only on the host |
| orchestrator, workers and pipelines on Claude and Codex | `git push` and anything else over SSH |
| the board, settings, team sign-in | install ping, update checks, Telegram, voice backends, GitHub PRs, Gemini |

## Files

| file | tracked | role |
|---|---|---|
| `Dockerfile` | yes | the base image: upstream deps/build stages + our own runtime stage |
| `Dockerfile.agents` | yes | the base image + pinned Claude Code and Codex CLIs and `jq`; what runs |
| `proxy/` | yes | the allow-list proxy: `Dockerfile`, `tinyproxy.conf`, `allow` |
| `docker-compose.yml` | yes | the hardened services, networks and volume |
| `entrypoint.sh` | yes | installs the key into the config volume, starts `bin/cli.mjs` |
| `delegatus.sh` | yes | the only way you should need to drive it |
| `env.example` | yes | template for `.env` |
| `workspace.json` | yes | the workspace defaults `configure` applies |
| `compose.masks.yml` | **no** | generated on every run: empty mounts over the masked workspace paths |
| `.env` | **no** | machine values: UID/GID, port, transcript paths, memory limit |
| `.secrets/token` | **no** | the login key (32 hex, `0600`, directory `0700`) |

## Security: what upstream ships, and what this does instead

The upstream `docker-compose.yml` and `Dockerfile` are written for a container
that acts on the host. Each item is a way out of the container:

| upstream | risk | here |
|---|---|---|
| `privileged: true`, `pid: host` | full device and process access to the host | no privileges, `cap_drop: ALL`, `no-new-privileges`, own PID namespace |
| `chmod u+s /usr/bin/nsenter` + shims for claude, codex, bun, uv, just, tmux, tailscale | any process in the container enters host PID 1's namespaces as your user | no nsenter, no shims; claude and codex installed in the image, signed in from the volume |
| `group_add` docker GID + a `docker` CLI shim | Docker socket access is root on the host | no Docker access |
| `network_mode: host` | everything the host can reach, plus the install ping | no-NAT bridge, DNS black-holed, port on `127.0.0.1` only; out only through the allow-list proxy |
| `${HOME}:${HOME}` read-write | every file you own, including keys and other tools' credentials | a named volume for its own state; host transcripts read-only; the workspace read-write with its secrets and corporate mirrors masked |
| key off on a loopback bind | any local process or page that reaches the port runs commands as you | key always on (in-container bind `0.0.0.0`), login via `.secrets/token` |
| install ping on by default | daily request to `delegatus.org` | `DELEGATUS_TELEMETRY=0`, `DO_NOT_TRACK=1`, pinned in compose; unreachable anyway |
| self-update from the git remote / npm | unreviewed code replaces the running app | the clone has no remote; updates are a manual pull and rebuild |

Also: read-only root filesystem (only `/home/delegatus`, `/tmp` and Next's
cache are writable), `pids_limit`, a memory ceiling, no `curl`, `gh`, `ssh` or
`sudo` in the image.

`./delegatus.sh check-isolation` proves the network part from inside the
container: name resolution and a direct TCP connect to a public address must
both fail, and through the proxy `api.anthropic.com` must be tunnelled (200)
while `example.com` is refused (403).

What opening the APIs changes: an agent in the container can read and write
the workspace and send what it reads to Anthropic or OpenAI — the same as
running Claude Code or Codex on the host, minus your home directory, Docker,
SSH and every other host.

## The login key

Delegatus asks every connection for its access key whenever it is bound to a
non-loopback address, which inside the container it always is. The key lives
in `.secrets/token`; compose passes it as a secret and `entrypoint.sh` copies
it into the config volume on each start (Delegatus re-chmods that file, so it
cannot be a read-only bind). `./delegatus.sh rotate-key` replaces it and
restarts; sessions signed in with the old key are refused. The `url` link
carries the key — treat it as the key.

## Images, and updating the clone

Two images: the **base** (`delegatus:local`, `Dockerfile`, built from the
clone) and the **agents** image (`delegatus:agents`, `Dockerfile.agents`, the
base plus the CLIs). `./delegatus.sh build` rebuilds only the agents image and
the proxy, so it needs no clone; `build --base` rebuilds the base first. To
move the CLIs, change their `ARG` pins — Codex only to a version Delegatus has
a protocol pin for (`src/lib/accounts/protocol/<version>/`).

The clone sits in `3rdparty/delegatus`; upstream's `main` is its local `main`
branch. To update it deliberately:

```bash
cd 3rdparty/delegatus
git fetch https://github.com/Latand/delegatus.git main
git log --oneline HEAD..FETCH_HEAD     # read what changes
git merge --ff-only FETCH_HEAD
cd ../../docker/delegatus
git -C ../../3rdparty/delegatus diff ORIG_HEAD -- Dockerfile   # carry deps/build changes over
./delegatus.sh build --base && ./delegatus.sh restart
```

Then re-index the code graph: `./docker/cbm/cbm.sh index 3rdparty/delegatus`.

## State

Everything Delegatus writes — `state/` SQLite, accounts, the key copy — is in
the `delegatus-home` volume. `./delegatus.sh down --volumes` deletes it.
