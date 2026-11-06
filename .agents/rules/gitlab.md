---
trigger: always_on
---

# GitLab: Local Mirror Only

Merge requests, review threads, pipelines, and failed job logs live in `.gitlab/`, a read-only local mirror.
- Start at `.gitlab/navigation_map.md`.
- Read local files in `.gitlab/.mr/<project>/<iid>.json`.
- Never contact `*.jenoptik.corp` directly over the network.
- Never read or expose credentials in `.gitlab/.secrets/`.
