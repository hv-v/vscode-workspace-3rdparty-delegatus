---
paths:
  - ".claude/limits/**"
  - ".claude/agents/common/prompt-verifier.md"
  - ".claude/skills/common/a-verify-prompt/**"
  - ".claude/agents/common/prompt-parser.md"
  - ".claude/skills/common/a-prompt-parser/**"
  - ".claude/settings.json"
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

## The pipeline this belongs to

Verification is the first stage of three, and the parts live together under
`common/` in both trees — `.claude/agents/common/` and
`.claude/skills/common/`:

```
Initial prompt
  -> a-verify-prompt / prompt-verifier    references, names, grammar, limitations
  -> [approved by user]                   the gate; nothing runs before it
  -> a-prompt-parser / prompt-parser      split into tasks + route each to an agent
  -> main session dispatches              each routed task via its own a- skill
```

The gate is the load-bearing part. The parser is deliberately fed the
**approved** text, not the raw prompt: splitting an unverified prompt only
distributes its unresolved references across several tasks, and each one then
looks specific enough to act on.

Neither agent spawns anything. The verifier returns a verdict, the parser
returns a routing table, and this session does the dispatching — so every
delegation stays visible in one transcript.

## What makes it run at all

The skill is not invoked on its own. A `UserPromptSubmit` hook in
`.claude/settings.json` injects the instruction to run `a-verify-prompt` and to
gate on the result. It is a single `jq` filter — no model call, so it costs
nothing per prompt — and it stays silent for prompts under 80 characters, which
carry nothing to verify and cannot fit a constraint line inside the budget
anyway.

**It is off by default.** The hook fires only when `JO_VERIFY_PROMPT=1` is in
the session environment. Turn it on for this machine with
`"env": {"JO_VERIFY_PROMPT": "1"}` in `.claude/settings.local.json` (restart the
session), or for one launch with `JO_VERIFY_PROMPT=1 claude`. With it off, the
skill still runs when asked for explicitly.

The hook only asks; the gate itself lives in the skill, which decides `CHANGED`
by comparing the verified prompt against the original rather than trusting the
agent to emit the field. If approval ever stops appearing, check in this order:
`JO_VERIFY_PROMPT=1` is set, then `/hooks` shows the hook is live, then the skill was invoked, then the comparison
in step 5 of `a-verify-prompt`.
