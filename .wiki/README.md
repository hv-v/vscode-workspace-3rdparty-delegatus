# `.wiki/` — read-only local mirror of the IPP wiki

Pages of the COMPASS wiki (`wiki.tok.ipp.cas.cz`, MediaWiki), pulled from
this machine and kept in one SQLite file, so an agent reads and searches them
locally instead of reaching the server. Same design as `.atlassian/`, without
Jira.

```
.wiki/
├── README.md                    this file                                  tracked
├── sources.json                 the wiki URL and what to pull              tracked
├── sync.sh                      the only thing that talks to the wiki      tracked
├── kb.sh                        read and search the pages (no network)     tracked
├── kb/kb.py                     the database code                          tracked
├── .cbmignore                   keeps the login and .db/ out of the graph  tracked
├── .ipp-wiki.env.example        credentials placeholder                    tracked
├── .ipp-wiki.env                your bot password, mode 600                ignored
├── navigation_map.md            generated index — read it first            ignored
└── .db/wiki.db                  pages (wikitext), search index             ignored
```

Everything stored is the wiki's own wikitext, not a rendering. Pulled pages
are internal IPP content: the workspace root `.gitignore` keeps them out of
git. Only the tooling is tracked.

## The database

`.db/wiki.db`, one row per page:

| column | holds |
|---|---|
| `revid` | the page's latest revision; a pull downloads a page only when it moved |
| `updated_at` | when that revision was saved, UTC, ISO 8601 |
| `categories` | the page's visible categories |
| `indexed` | 0 when the page changed since the last `kb.sh index`, 1 once its search index matches |
| `body` | the wikitext, as served |

and also `ns`, `title`, `updated_by`, `url`. `sync.sh` writes the file through
`kb/kb.py`, which needs only Python's standard library.

Reading and searching, with no network:

```bash
.wiki/kb.sh search "frequency bands of the microwave reflectometer"
.wiki/kb.sh search --keyword reflectometer   # keyword only: no Docker, instant
.wiki/kb.sh page Microwave reflectometer     # a page as text, by title or page id
.wiki/kb.sh page 1234 --source               # the wikitext
.wiki/kb.sh status
```

`search` fuses keyword matches (SQLite FTS5) with matches by meaning
(`multilingual-e5-small` vectors in sqlite-vec). Each page is split at its
`== headings ==` into pieces of at most 1200 characters. Templates are not
expanded: their parameter values are kept as text, their names dropped.

The model runs in the `ipp-wiki-kb` image, built from
[`docker/wiki/`](../docker/wiki/README.md); this `kb.py` is mounted into it. It
runs with `--network none`, a read-only root and your user id, and only `.db/`
mounted writable.

The model stays loaded in the wiki search service, configured in
`docker/wiki/` (container `ipp-wiki-kb`), separate from Confluence's in
`docker/confluence/`. The first search starts it in a
few seconds; after that a search takes about 1 s. Started by a search, it stops
itself after 30 minutes idle (about 410 MiB while running).

```bash
.wiki/kb.sh up | down | build      # start it now (30 min idle) / stop it / build the image
docker/wiki/services.sh up         # start it and keep it up until down
```

## Guarantees

| guarantee | how |
|---|---|
| **read-only** | twice: the login is a bot password with only *Basic rights*, so the server refuses writes; and the client sends one POST (`action=login`, the only way MediaWiki takes a login) and otherwise only GETs, with no redirects, https only. `sync.sh check` warns if the login could edit. |
| **right server** | normal certificate verification; requests go only to `base_url`, whose host must end in `allowed_host_suffix`. An optional `"pin": "sha256//…"` in `sources.json` adds public-key pinning. |
| **credentials stay put** | `.ipp-wiki.env` is git-ignored, excluded from the graph by `.cbmignore`, mode 600 (checked); parsed, never sourced; sent to curl through a pipe, never argv. The session cookie lives in a mode-600 temp file deleted on exit. |

## Setup (once)

1. **Bot password.** The wiki signs in through Keycloak SSO, and the API does not
   accept the SSO password. In the browser, go to
   `https://wiki.tok.ipp.cas.cz/index.php/Special:BotPasswords`. Create a bot
   (e.g. `mirror`) and tick **only "Basic rights"**. Note the password shown.
2. **Credentials:**
   ```bash
   cd .wiki
   install -m 600 .ipp-wiki.env.example .ipp-wiki.env
   ${EDITOR:-nano} .ipp-wiki.env      # WIKI_USER=<you>@mirror, WIKI_PASS=<bot password>
   ```
3. **Check, pull, schedule:**
   ```bash
   .wiki/sync.sh check          # logs in, prints who you are and whether it is read-only
   .wiki/sync.sh pull --index   # first full pull, then the search index and the graph
   .wiki/sync.sh schedule       # weekly refresh, Mondays 09:00 (launchd / systemd)
   ```
   `kb.sh build` once beforehand, or `pull --index` falls back to keyword search.

A failed login stops the script. It never retries.

## Day to day

| want | run |
|---|---|
| one page | `sync.sh add '<page link>'` or `sync.sh add 'Page title'` |
| a category | `sync.sh add Category:Diagnostics` (its pages, not subcategories) |
| a whole namespace | `sync.sh add ns:<number>` (`0` = main, set by default) |
| refresh now | `sync.sh pull --index` |
| search | `kb.sh search "<question>"`; then `kb.sh page <id or title>` |
| fewer pages | edit `namespaces`, `categories`, `pages` or `max_pages` in `sources.json`, then `pull` |
| weekly refresh off | `sync.sh unschedule` |
| refresh logs | macOS `~/Library/Logs/ipp-wiki-sync.log`; Linux `journalctl --user -u ipp-wiki-sync.service` |

A pull is incremental. It first lists the selected pages with their latest
revision ids, then downloads only pages whose revision moved, 50 per request.
A page the API leaves out of a large answer is fetched again on its own.
Pages no longer selected, or deleted on the wiki, leave the mirror.
`navigation_map.md` lists every page by namespace, changed ones marked ★.
`sync.sh` runs on the macOS system bash (3.2).

The graph project is `<ws>-.wiki`. It holds the tooling and the navigation
map; the pages are searched with `kb.sh`.

## Limits

- Images and attachments are not downloaded; `[file X]` marks where one was.
- Templates, `<ref>`s and parser functions are not expanded — what a template
  renders is not in the text, only its parameters.
- Redirect pages are skipped; a `pages` entry that is a redirect pulls its target.
- Hidden categories are not recorded.
