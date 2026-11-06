# `docker/wiki/` — search service of the IPP wiki (MediaWiki) mirror

The search service of [`.wiki/`](../../.wiki/README.md), started and
stopped on its own. The Confluence one is in [`docker/confluence/`](../confluence/README.md).

| compose project | service | database | container |
|---|---|---|---|
| `ipp-wiki` | `wiki` | `.wiki/.db/wiki.db` | `ipp-wiki-kb` |

It holds the embedding model (`multilingual-e5-small`) in memory and answers
`search` and `index` for the mirror. The database is the mirror's SQLite
file. It is not a server of its own: `sync.sh` writes it on the host, and the
service reads and indexes it.

```
docker/wiki/
├── docker-compose.yml    the wiki service and its isolation
├── services.sh           build / up / down / status / logs / exec / run
└── .env                  generated: your uid and gid                    ignored
```

The image, `ipp-wiki-kb:local`, is built from [`Dockerfile`](Dockerfile) here: Python,
onnxruntime, sqlite-vec and the pinned model. Confluence builds its own.

## Use

```bash
docker/wiki/services.sh status              # state, memory, database
docker/wiki/services.sh up                  # start it, keep it up until down
docker/wiki/services.sh up --idle 1800      # exit after 30 min without a request
docker/wiki/services.sh down                # stop it, free its memory
docker/wiki/services.sh logs -f
docker/wiki/services.sh build               # build or rebuild the image
```

You rarely need this directly. `.wiki/kb.sh search` / `index` starts the
service on demand, with a 30-minute idle exit, and goes on using one you
started here. `up` without `--idle` keeps it up until `down`. About 410 MiB
while running, capped at 1 GiB.

`exec <kb.py args>` runs a command through the running service;
`run <kb.py args>` runs it in a one-off container that loads the model itself
(about 9 s). `.wiki/kb.sh` uses these two.

## Isolation

Every container, resident or one-off, runs with:

- `network_mode: none`: no network at all; the model is in the image;
- a read-only root, `/tmp` on tmpfs, all capabilities dropped, `no-new-privileges`;
- your uid/gid (from `.env`), so the bind-mounted database stays yours;
- only `.wiki/.db/` writable, and `.wiki/kb/kb.py` mounted read-only.

Clients reach the server over a Unix socket in the container's own `/tmp`,
through `docker exec`. That needs no port, and it works on Docker Desktop for
macOS, where a socket in a host-mounted folder does not. The compose
healthcheck pings that socket; `up` waits until it answers.

The model is pinned to a commit and to the SHA-256 of each file. The network
is used only by `build`.
