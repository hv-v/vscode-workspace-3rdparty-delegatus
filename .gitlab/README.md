# `.gitlab/`: read-only local mirror of your GitLab merge requests

Your open MRs, their review threads, their latest pipeline and the logs of the
jobs that failed. They are pulled from this machine over the corporate VPN
and indexed by the codebase-memory graph, so an agent can see why a pipeline
failed and what reviewers asked for without opening the web UI.

```
.gitlab/
├── README.md                     this file                                 tracked
├── sources.json                  server, key pin, group, which MRs to track tracked
├── sync.sh                       the only thing that talks to the server   tracked
├── .cbmignore                    keeps .secrets/ out of the graph          tracked
├── .secrets/                     your login (see .secrets/README.md)       placeholders only
├── navigation_map.md             generated index; read it first            ignored
├── .mr/<project>/<iid>.json      MR fields, pipeline, review threads       ignored
├── .logs/<project>/<job>.log     job logs, colour codes stripped           ignored
└── .cache/                       per-MR pieces and change stamps           ignored
```

## What an MR file holds

`.mr/shire/jen_metrics_monitor/42.json`, in reading order:

- **The MR:** title, branches, author, reviewers, merge status, conflicts,
  and a count of `open_threads`.
- **`pipeline`:** the latest one, child pipelines included:
  - job counts per status;
  - what is still running;
  - for each **failed** job: its stage, `failure_reason`, link, the path of
    its full log, and the log's last `log_tail_lines` lines (40), usually
    enough to see the error without opening the log.
- **`description`**, then **`threads`:** human comments only, with system
  notes ("added 1 commit") dropped. A code comment carries `at: file:line`
  and `resolved`.

## Guarantees

| guarantee | how |
|---|---|
| **read-only, on the server** | every data request carries a token limited to `read_api`. With a password, `sync.sh` asks for exactly that scope and refuses anything wider. A personal token must have only `read_*` scopes. |
| **read-only, in this client** | `api_get` is the only request that carries the token: `curl --request GET`, no body, no redirects, https only. A password login adds exactly two POSTs, `/oauth/token` and `/oauth/revoke`, which create and destroy that session token. |
| **from this host only** | `sync.sh` runs locally, and the host resolves only over the VPN. `.claude/hooks/corp-guard.sh` refuses any agent command naming a `jenoptik.corp` host except this script and plain `git` over SSH, and `.claude/settings.json` denies `WebFetch` to the host. |
| **right server** | the server's public key is pinned in `sources.json`, and curl aborts before sending a byte if it differs. A CA in `.secrets/certs/` adds chain verification on top. |
| **credentials stay put** | `.secrets/` is git-ignored except its placeholders, excluded from the graph, and off-limits to the agent. The file is mode 600, and its contents reach curl through a pipe, never argv. |

What it cannot do: retry a job, comment, approve, merge or push. Pushing a fix
is ordinary `git` over SSH, done when you say so.

## How this server is actually configured

- **Plain http.** `as-git-01` has no https, so `sources.json` opts in with
  `"allow_plain_http_host": "as-git-01.jenoptik.corp"`. The user explicitly
  accepted this on 2026-10-29. The token and all data cross the network
  unencrypted, nothing authenticates the server, and every run prints a
  warning. There is no pin. If https is ever enabled, set `base_url` back to
  `https://…`, delete that key, and run `pin`.
- **Token only.** `"password_login": false`: the script uses `GITLAB_TOKEN`
  and never sends a password, even if one is in the file.
- **External CI.** Pipelines here have `source: external`: Jenkins
  (`jenkins-hil`) builds the MRs and reports a commit status back. GitLab
  holds no jobs and no logs for them, so the MR file lists each status with
  its description and the link to the Jenkins build. Jenkins logs are not
  mirrored.

## Setup (once)

1. **Credentials**: see `.secrets/README.md`. Username and password work.
   A `read_api` personal token also works, if your account can create one.
2. **Pin the server's key**:
   ```bash
   .gitlab/sync.sh pin            # prints the key pin and the certificate fingerprint
   ```
   Compare the SHA-256 fingerprint with the browser (padlock → certificate
   details). If they match:
   ```bash
   .gitlab/sync.sh pin --write
   ```
3. **Check and pull**:
   ```bash
   .gitlab/sync.sh check          # logs in, prints who you are and which token kind
   .gitlab/sync.sh pull --index   # first pull, then index the graph
   ```

## Day to day

| want | run |
|---|---|
| refresh (comments, pipeline status) | `sync.sh pull --index` |
| track one more MR, even merged | `sync.sh add '<MR link>'` or `sync.sh add shire/project!42` |
| any job's log (passing, retried, still running) | `sync.sh log '<job link>'` |
| other MR lists | edit `queries` in `sources.json`: any [group MR API](https://docs.gitlab.com/ee/api/merge_requests.html#list-group-merge-requests) filters, with `{me}` for your username |

By default a pull tracks your open MRs in `shire`: the ones you authored, the
ones where you are a reviewer, and the ones pinned in `sources.json`.

A pull is incremental:

- **Always:** one request per query, and one per MR for its latest pipeline.
  An MR pinned in `sources.json` costs one more request.
- **Only when the MR's `updated_at` moved:** its details and threads.
- **Only when the pipeline's id, status or update stamp moved:** its jobs,
  and the logs of newly failed jobs. A finished job's log never changes, so
  it is downloaded once.
- **Files:** rewritten only when their content changed, and marked ★.
- **Pruning:**
  - MRs that left every query (merged, closed, review done) are removed,
    unless pinned.
  - Logs that no MR file points at are deleted after 14 days.

Refresh is on request only. Pipelines change by the minute, so a weekly timer
would mostly show stale states.

The graph project is `home-vhaponov-Documents-jo-workspace-.gitlab`.

## When the login is refused

The script stops at the first refusal and never retries, because repeated
failures can lock your account. The message names the server's reason:

- `invalid_grant`: wrong password. Fix `credentials`.
- `two-factor` / `unsupported_grant_type`: password login for API clients is
  off on this server, or your account uses 2FA. Then only a personal token
  works.

## When the certificate is renewed

The pull fails with *public key does not match the pin*. Run
`.gitlab/sync.sh pin`, compare the fingerprint with the browser, then run
`pin --write`.

## Limits

- `max_mrs_per_query` (100) per query; up to 1000 jobs per pipeline; 2000
  threads per MR; logs above 100 MB are not downloaded.
- Only the **latest** pipeline of each MR. Older ones are visible in the browser.
- Child pipelines one level deep. Their jobs show as `<trigger job> / <job>`.
- The MR's diff is not mirrored, because the code is in your local clone. A
  thread's `at` gives `file:line` on the MR's head commit (`sha`).
