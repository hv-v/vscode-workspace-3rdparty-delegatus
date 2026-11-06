---
trigger: always_on
---

# IPP wiki: Local Mirror Only

COMPASS wiki pages live in `.wiki/`, a read-only mirror of `wiki.tok.ipp.cas.cz`.
- Start at `.wiki/navigation_map.md`. Pages are in `.wiki/.db/wiki.db`; read and search them only via `.wiki/kb.sh search "<question>"` or `.wiki/kb.sh page <id or title>`.
- Never contact the wiki directly over the network. A missing or stale page: run `.wiki/sync.sh add <link or title>` or `.wiki/sync.sh pull --index` alone, nothing chained.
- Never read or expose `.wiki/.ipp-wiki.env`.
- The mirror is git-ignored internal content: never copy it into a tracked file.
