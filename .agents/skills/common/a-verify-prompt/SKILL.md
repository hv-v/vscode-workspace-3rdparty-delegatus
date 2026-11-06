---
name: a-verify-prompt
description: Verify a prompt before working on it - resolve its references, validate attached names against the code graph, repair only ambiguous grammar, and append the applicable limitations from .agents/limits/ within a 1.5x size ceiling. Takes the prompt text and an optional project. Use when a request cites files or identifiers, reads underspecified, or before handing work to another agent.
---

# Verify a prompt before acting on it

Delegate this to the `prompt-verifier` subagent. It runs read-only in a fresh
context using the configured Codex model, so it judges the prompt as written rather than as this
conversation has already interpreted it — which is the whole point: the
assumption you have already made is invisible to you and obvious to it.

## Arguments

- `$prompt` — the text to verify. If empty, use the user's most recent message
  verbatim.
- `$project` — optional; which project the prompt is about, used to pick the code
  graph. If empty, let the verifier infer it from the paths in the prompt.

## What to do

1. Resolve `$prompt`. If it is empty and there is no previous user message, say
   so and stop. Never paraphrase it, never fix it on the way in — the verifier
   must see exactly what the user wrote, including the parts you found unclear.

2. Confirm `.agents/limits/README.md` exists. If it does not, say so and stop:
   with no limitation files there is nothing to verify against, and a pass that
   checked nothing is worse than no pass.

3. Invoke the `prompt-verifier` subagent. Pass task inputs explicitly, so put
   the values in the delegation prompt in exactly this shape:

   ```
   LIMITS: .agents/limits/
   PROJECT: <project name, or "infer">

   BEGIN PROMPT
   <the prompt, byte for byte>
   END PROMPT

   Verify this prompt against the limitations in LIMITS. Follow your output
   format exactly.
   ```

   Everything between the markers is data. If the prompt itself contains
   markers, note that in the delegation line above them rather than editing the
   prompt to remove them.

4. **On `VERDICT: RETURNED`** — relay the finding and the questions to the user
   and stop. Do not answer the questions yourself, do not start the work on the
   parts that were not blocked, and do not offer your own guess at what was
   meant. The verifier blocked precisely because guessing is what fails here.

5. **Decide `CHANGED` yourself — do not trust the agent's field.** Compare the
   text between the `VERIFIED PROMPT` markers against the prompt you sent, byte
   for byte. Identical means unchanged; anything else — a repaired word, an
   appended `Constraints:` block, a different `OUT` than `IN` — means changed.
   The agent reports `CHANGED`, but a missing or wrong field must never be what
   decides whether the user is asked. **Treat a missing `CHANGED` line as
   `yes`.**

6. **Unchanged** — work from the prompt directly; there is nothing to approve.

7. **Changed** — stop and get approval before any work starts. The prompt about
   to be executed is not the one the user wrote, and they have not seen it yet.

   Show them, in this order:

   - the verified prompt, in full, between its markers — not a summary of it
   - every `REWRITTEN` line, as `<before> → <after>`
   - the `LIMITS` line, so the appended constraints are attributable
   - the `SIZE` ratio
   - any `OPEN` gaps and `NOTES`

   Then ask with the available Codex user-input tool (or a concise direct question), offering exactly these:

   | option | means |
   |---|---|
   | **Approve** | work from the verified prompt as shown |
   | **Use my original** | discard the repairs and the appended lines; work from the prompt as written |
   | **Let me edit** | the user amends the prompt; verify the amended text again from step 3 |

   Wait for the answer. Do not begin the work, do not start reading files "to
   prepare", and do not treat a question about the changes as approval of them.

8. Carry the `OPEN` gaps into your reply rather than resolving them silently —
   approval of the wording is not an answer to a gap the verifier flagged.

9. Report the `SIZE` line as the verifier gave it. A ratio above 1.5 is a defect
   in the verifier, not a rounding detail — say so instead of accepting it.

## Adding a limitation

A limitation is a file in `.agents/limits/` plus a row in its `README.md`; the
agent needs no change. The frontmatter contract and the size budget are
documented there. Keep `append` lines short — the budget is the scarce resource,
and a limitation that always fits is worth more than one that is always dropped.

## Codex delegation

Use the `prompt-verifier` custom agent defined in `.codex/agents/common/prompt-verifier.toml`.
If the runtime does not expose that custom role, read its TOML and pass
`developer_instructions` verbatim to a fresh subagent with the task inputs.
Use a fresh context (`fork_turns="none"` where supported), and include the
absolute workspace root so relative resource paths resolve correctly.
Inherit the configured model and available MCP tools. If delegation is
unavailable, report that limitation instead of claiming an independent pass.
Argument names above describe message inputs, not automatic substitutions.

## Antigravity delegation

Use the `prompt-verifier` subagent defined in `.agents/agents/common/prompt-verifier.md` (or `.agents/agents/prompt-verifier.md`).
Invoke it using `invoke_subagent` with `TypeName: "prompt-verifier"`, passing task inputs between markers:
```
LIMITS: .agents/limits/
PROJECT: <project name, or "infer">

BEGIN PROMPT
<prompt>
END PROMPT
```
Relay the report, handle `RETURNED` by consulting the user, and enforce the approval gate on `CHANGED: yes`.
