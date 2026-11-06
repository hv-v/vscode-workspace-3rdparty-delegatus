# Delegatus — offline, loopback-only container

[Delegatus](https://github.com/Latand/delegatus) is a board and orchestrator
for Claude Code, Codex and Copilot agents. Here it runs as a hardened container
built from the clone in `3rdparty/delegatus`, with no route off the host.

```bash
./delegatus.sh up        # init (.env + key), build if needed, start
./delegatus.sh configure # apply workspace.json: settings + one project per repo
./delegatus.sh url       # sign-in link: http://127.0.0.1:8898/?k=<key>
./delegatus.sh status    # container, HTTP answer, isolation proof
```

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

A new repository in the workspace joins on the next `configure`. Roles,
the worker limit and learned rules are left at Delegatus's defaults: with no
engine connected there is nothing to assign them to yet.

The workspace is mounted **read-only at its own host path**, so transcript
working directories and project roots resolve inside the container exactly as
on the host. Nothing in it can be changed from the container. Hidden behind an
empty mount (`compose.masks.yml`, generated from `mask_paths` in
`delegatus.sh`, only for paths that exist): the `.atlassian/` and `.gitlab/`
credentials and mirrored corporate data, this directory's `.env` and
`.secrets/`, and `docker/cbm/.env`.

## What it can and cannot do in this shape

| works | does not work, by design |
|---|---|
| your Claude Code and Codex transcripts as searchable chats (read-only) | starting agents, orchestrators or pipelines — no `claude`/`codex` in the image and no internet for their APIs |
| the board, settings, team sign-in | install ping, update checks, Telegram, voice backends, GitHub PRs |

Agent work needs egress to the provider APIs (`api.anthropic.com`,
`api.openai.com`/`chatgpt.com`). Opening that is a deliberate change: an
allow-list proxy for exactly those hosts, the CLIs installed in the image, and
their logins kept in the container's own volume — never the host's. Do not
switch the network to a NAT bridge to get there.

## Files

| file | tracked | role |
|---|---|---|
| `Dockerfile` | yes | upstream deps/build stages + our own runtime stage |
| `docker-compose.yml` | yes | the hardened service, network and volume |
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
| `chmod u+s /usr/bin/nsenter` + shims for claude, codex, bun, uv, just, tmux, tailscale | any process in the container enters host PID 1's namespaces as your user | no nsenter, no shims |
| `group_add` docker GID + a `docker` CLI shim | Docker socket access is root on the host | no Docker access |
| `network_mode: host` | everything the host can reach, plus the install ping | no-NAT bridge, DNS black-holed, port on `127.0.0.1` only |
| `${HOME}:${HOME}` read-write | every file you own, including keys and other tools' credentials | a named volume for its own state; transcripts and the workspace mounted read-only, with its secrets and corporate mirrors masked |
| key off on a loopback bind | any local process or page that reaches the port runs commands as you | key always on (in-container bind `0.0.0.0`), login via `.secrets/token` |
| install ping on by default | daily request to `delegatus.org` | `DELEGATUS_TELEMETRY=0`, `DO_NOT_TRACK=1`, pinned in compose; unreachable anyway |
| self-update from the git remote / npm | unreviewed code replaces the running app | the clone has no remote; updates are a manual pull and rebuild |

Also: read-only root filesystem (only `/home/delegatus`, `/tmp` and Next's
cache are writable), `pids_limit`, a memory ceiling, no `curl`, `gh`, `ssh` or
`sudo` in the image.

`./delegatus.sh check-isolation` proves the network part from inside the
container: name resolution and a TCP connect to a public address must both
fail.

## The login key

Delegatus asks every connection for its access key whenever it is bound to a
non-loopback address, which inside the container it always is. The key lives
in `.secrets/token`; compose passes it as a secret and `entrypoint.sh` copies
it into the config volume on each start (Delegatus re-chmods that file, so it
cannot be a read-only bind). `./delegatus.sh rotate-key` replaces it and
restarts; sessions signed in with the old key are refused. The `url` link
carries the key — treat it as the key.

## Updating the clone

`3rdparty/` is git-ignored and the clone's remote was removed so nothing can
update it behind your back. To update deliberately:

```bash
cd 3rdparty/delegatus
git fetch https://github.com/Latand/delegatus.git main
git log --oneline HEAD..FETCH_HEAD     # read what changes
git merge --ff-only FETCH_HEAD
cd ../../docker/delegatus
git -C ../../3rdparty/delegatus diff ORIG_HEAD -- Dockerfile   # carry deps/build changes over
./delegatus.sh build && ./delegatus.sh restart
```

Then re-index the code graph: `./docker/cbm/cbm.sh index 3rdparty/delegatus`.

## State

Everything Delegatus writes — `state/` SQLite, accounts, the key copy — is in
the `delegatus-home` volume. `./delegatus.sh down --volumes` deletes it.
