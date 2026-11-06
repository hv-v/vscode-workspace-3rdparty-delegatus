---
trigger: always_on
---

# Jira and Confluence: Local Mirror Only

Ticket and design documentation lives in `.atlassian/`, a read-only mirror.
- Confluence SQLite database: `.atlassian/.db/confluence.db`. Query only via `.atlassian/kb.sh search` or `.atlassian/kb.sh page <id>`.
- Jira issues: `.atlassian/.jira/<status>/<KEY>.json`.
- Never contact `*.jenoptik.corp` directly over the network. Read only from the local mirror. A missing or stale page: run `.atlassian/sync.sh add <link>` or `.atlassian/sync.sh pull --index` alone, nothing chained.
- The `corp-guard` hook (`.agents/hooks.json`) denies any other command or URL fetch naming a corporate host.
- Never read or expose credentials in `.atlassian/.secrets/`; the `corp-guard` hook denies it.
- The mirror is git-ignored corporate data: never copy it into a tracked file.
