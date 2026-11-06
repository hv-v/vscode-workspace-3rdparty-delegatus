---
trigger: always_on
---

# Prompt Limitations Pipeline

When prompt verification is active:
1. `a-verify-prompt` checks references, identifiers against the code graph, ambiguous grammar, and limitations in `.agents/limits/`.
2. Any edit or limitation addition requires user approval before proceeding. Size budget is capped at 1.5× original character count.
3. Once approved, `a-prompt-parser` breaks the prompt into tasks and routes to the appropriate agent or main session.
