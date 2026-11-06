---
trigger: always_on
---

# Jira and Confluence: Local Mirror Only

Ticket and design documentation lives in `.atlassian/`, a read-only mirror.
- Confluence SQLite database: `.atlassian/.db/confluence.db`. Query only via `.atlassian/kb.sh search` or `.atlassian/kb.sh page <id>`.
- Jira issues: `.atlassian/.jira/<status>/<KEY>.json`.
- Never contact `*.jenoptik.corp` directly over the network. Read only from the local mirror.
- Never read or expose credentials in `.atlassian/.secrets/`.
