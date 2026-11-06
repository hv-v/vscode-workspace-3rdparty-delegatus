---
trigger: always_on
---

# GitLab: Local Mirror Only

Merge requests, review threads, pipelines, and failed job logs live in `.gitlab/`, a read-only local mirror.
- Start at `.gitlab/navigation_map.md`.
- Read local files in `.gitlab/.mr/<project>/<iid>.json`.
- Never contact `*.jenoptik.corp` directly over the network. Stale: `.gitlab/sync.sh pull --index`; an untracked MR: `.gitlab/sync.sh add <MR link>`; a missing job log: `.gitlab/sync.sh log <job link>` — each run alone. Plain `git` over SSH is allowed.
- Never read or expose credentials in `.gitlab/.secrets/`; the `corp-guard` hook denies it. A refused login stops the script; never re-run it in a loop.
- Commit and push only when the user asks.
