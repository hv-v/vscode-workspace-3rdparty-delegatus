# `.atlassian/` — read-only local mirror of Jira and Confluence

Jira issues and Confluence pages, pulled from this machine over the corporate
VPN and indexed by the codebase-memory graph, so an agent reads them locally
instead of reaching the servers.

```
.atlassian/
├── README.md                        this file                               tracked
├── sources.json                     what to pull, server URLs and key pins  tracked
├── sync.sh                          the only thing that talks to the servers tracked
├── .cbmignore                       keeps .secrets/ out of the graph        tracked
├── .secrets/                        your login — see .secrets/README.md     placeholders only
├── navigation_map.md                generated index — read it first         ignored
├── .confluence/<id>.html            page source (storage-format XHTML)      ignored
├── .confluence/<id>.comments.html   its comments, same format               ignored
├── .jira/<status>/<KEY>.json        issue fields, one folder per status     ignored
└── .cache/                          version stamps, Jira field catalogue    ignored
```

Files hold the servers' own source, not a conversion. Pulled content is
corporate data: the workspace root `.gitignore` keeps it out of git, so it
stays on this machine. Only the tooling is tracked.

## Guarantees

| guarantee | how |
|---|---|
| **read-only** | `api_get` in `sync.sh` is the only request that carries credentials: `curl --request GET`, no body, no redirects, https only. |
| **from this host only** | `sync.sh` runs locally; the hosts resolve only over the VPN. `.claude/hooks/corp-guard.sh` refuses any agent `Bash` command naming a `jenoptik.corp` host, and `.claude/settings.json` denies `WebFetch` to both hosts — an agent reaches them only by running `sync.sh`. |
| **right server** | the servers' certificates come from a Jenoptik CA this machine does not trust, so each server's **public key is pinned** in `sources.json`: curl aborts before sending a byte if the key differs. A CA in `certs/` (below) adds chain verification on top. |
| **credentials stay put** | `.secrets/` is git-ignored except its placeholders, excluded from the graph by `.cbmignore`, and off-limits to the agent (a `Read` deny plus the guard hook); file mode 600, or the GNOME keyring; handed to curl through a pipe, never argv; sent only to hosts under `.group.jenoptik.corp`. |

Your password carries **all** of your permissions. Read-only is enforced by
this client, not by the server.

## Setup (once)

Everything private lives in `.atlassian/.secrets/` — inside the workspace,
but git-ignored and excluded from the graph. Details: `.secrets/README.md`.

```
.atlassian/.secrets/             mode 700
├── README.md                    tracked
├── credentials.example          tracked placeholder — copy it, never edit it
├── credentials                  ignored — your login, mode 600
└── certs/                       ignored — optional Jenoptik CA, *.pem or *.crt
```

1. **Credentials** — one of:

   - **file**:
     ```bash
     cd .atlassian/.secrets
     install -m 600 credentials.example credentials
     ${EDITOR:-nano} credentials       # replace the two placeholder values
     ```
   - **keyring** (password not on disk): `sudo apt install libsecret-tools`,
     then in your own terminal `.atlassian/sync.sh login`. The username is
     kept with it; a `credentials` file with only `ATLASSIAN_USER=` also works.

   A password in the file wins over the keyring.

2. **Certificates** — optional. Without them the pins authenticate the
   servers. If IT gives you the Jenoptik root + issuing CA, drop the files in
   `.atlassian/.secrets/certs/`; `sync.sh` then verifies the chain *and* the pin.

3. **Check, pull, schedule:**
   ```bash
   .atlassian/sync.sh check          # logs in, prints who you are — nothing else
   .atlassian/sync.sh pull --index   # first full pull, then index the graph
   .atlassian/sync.sh schedule       # weekly refresh, Mondays 09:00
   ```

**One failed login stops the script — it never retries.** Several failures in
a row make Jira require a CAPTCHA, which blocks scripted logins until you log
in once in the browser.

## Day to day

| want | run |
|---|---|
| a new Confluence page | `sync.sh add '<page link>'` (add `--children N` to follow child pages) |
| a new Jira issue | `sync.sh add SHIRE-1234`, or paste the issue / board link |
| refresh now | `sync.sh pull --index` |
| more queries or boards | edit `sources.json`, then `pull` |
| group statuses into folders | `jira.status_folders` in `sources.json` maps a status to a folder name (`"In Review": "review"`); unmapped statuses get their own folder named after the status. An issue moves folder on the pull after its status changes. |
| weekly refresh off | `sync.sh unschedule` |
| timer logs | `journalctl --user -u jo-atlassian-sync.service` |

A pull is incremental: it first asks only for version numbers (Confluence)
and update stamps (Jira), downloads full text only for what changed, and
rewrites only files whose content changed. `navigation_map.md` marks those ★.
Anything no longer reachable from `sources.json` is removed from the mirror.

The graph project is `home-vhaponov-Documents-jo-workspace-.atlassian`.

## When the certificate is renewed

The pull fails with *public key does not match the pin*. Open the site in the
browser, check the new certificate's SHA-256 fingerprint, then:

```bash
.atlassian/sync.sh pin            # shows configured vs observed
.atlassian/sync.sh pin --write    # adopts the observed key
```

Current certificates expire 2028-06-09.

## Limits

- Attachments and images are not downloaded; links in the source point at the server.
- Up to 200 comments per Confluence page; `max_pages` per pull (100);
  `max_issues_per_query` per Jira query (200).
- Storage format keeps macros as `<ac:…>` tags, not expanded — e.g. a Jira
  issue list macro shows its query, not its results.
