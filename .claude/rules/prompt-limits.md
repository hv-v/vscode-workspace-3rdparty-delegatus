---
paths:
  - ".claude/limits/**"
  - ".claude/agents/common/prompt-verifier.md"
  - ".claude/skills/a-verify-prompt/**"
---

# Authoring a prompt limitation

`.claude/limits/` holds one file per limitation that a prompt must satisfy
before it is worked on — no assumptions about missing parts, no empty
references, attached names that actually resolve, grammar repaired only where it
creates a second reading. `.claude/limits/README.md` is the index and the file
contract; the `prompt-verifier` agent reads that index and opens only the files
whose trigger fired.

Two properties make this usable rather than ceremonial:

- **A limitation is data, not code.** Adding one means adding a file and a row
  in the index. Neither the agent nor the `a-verify-prompt` skill changes.
- **The verified prompt is capped at 1.5× the original**, targeting 1.2×. Lines
  are spent against that budget in priority order and dropped by name when it
  runs out, so the check cannot quietly bloat the thing it is checking.

Keep `append` lines short: the budget is the scarce resource, and a limitation
that always fits is worth more than one that is always dropped. The measured
thresholds for the current lines are in `.claude/limits/README.md`.

A limitation must be a check the verifier can actually run with `Read`, `Glob`,
`Bash` and the `mcp__codebase-memory__*` tools. A check it cannot execute is
worse than no check, because it reads as having been done.
