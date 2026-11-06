# `.agents/limits/` — limitation rules for the prompt verifier

One file per limitation. The `prompt-verifier` agent reads **this index first**
and then opens only the files whose trigger fired — that is what keeps the pass
cheap. Adding a limitation means adding a file here and a row below; no agent
edit.

## The index

| file | trigger | action | appends |
|---|---|---|---|
| [empty-references.md](empty-references.md) | the prompt cites a path, file, ticket, skill or agent | **block** | nothing |
| [name-validity.md](name-validity.md) | the prompt attaches an identifier, symbol, package, topic or file name | **block** | nothing |
| [no-assumptions.md](no-assumptions.md) | always | annotate | 1 line |
| [grammar.md](grammar.md) | always | rewrite | nothing |

`block` returns the prompt to the user unchanged and does not spend budget.
`annotate` appends its line to the prompt. `rewrite` repairs the prompt text in
place. Lower priority number wins when the budget forces a choice.

## The file contract

Every limitation file carries this frontmatter and nothing else is read from it
mechanically:

```yaml
---
name: <matches the filename, [a-z0-9-]>
trigger: always | <the condition, in one line>
action: block | annotate | rewrite
priority: <integer; lower is kept first when the budget is tight>
append: <the exact line added to the prompt; omit for block/rewrite>
append-short: <a ≤60-char form used when the budget is tight; optional>
---
```

The body is the instruction list: what the verifier checks, in order, and what
each outcome is. Write checks the verifier can actually perform with `Read`,
`Glob`, `Bash` and the `codebase-memory` MCP tools — a check it cannot
execute is worse than no check, because it reads as having been done.

## The size budget

The verified prompt must not exceed **1.5×** the original character count, and
should land near **1.2×**. `append` lines are spent against that budget in
priority order; when the next line would break the ceiling the verifier uses
`append-short`, and if that still breaks it the line is dropped and named in the
report. Blocking checks cost nothing — they either pass silently or return the
prompt.

This is why appended lines are short and why most limitations append nothing:
the budget is the scarce resource, and a limitation that always fits is worth
more than one that is always dropped.

**What the budget means for a short prompt.** With the current lines, measured:

| prompt length | what fits |
|---|---|
| ≥ 362 chars | the full `no-assumptions` line (166 chars + a 15-char block header) |
| ≥ 138 chars | its `append-short` form only |
| < 138 chars | nothing is appended |

A short prompt is therefore verified but not annotated — and that is correct,
not a failure: **blocking checks cost no budget and always run.** Empty
references, unresolvable names and undecidable sentences return the prompt at
any length. Dropped lines are named on the verifier's `LIMITS:` output line
after `skipped:`, so the difference stays visible; do not shorten the constraint
text to make it fit.
