---
name: a-prompt-parser
description: Split an approved prompt into its separate tasks and detect which agent should handle each one. Takes the approved prompt and an optional project. Use after a-verify-prompt has passed and the user has approved, before starting any of the work.
---

# Split an approved prompt and route its tasks

Delegate this to the `prompt-parser` subagent. It runs read-only in its own
context with the code graph granted, so it classifies the prompt as written
rather than as this conversation has already decided to approach it.

This is the step after verification in the prompt pipeline:

```
Initial prompt
  -> a-verify-prompt          verify references, names, grammar, limitations
  -> [approved by user]       the gate; nothing runs before it
  -> a-prompt-parser          split into tasks + detect the agent for each   <- here
  -> main session dispatches  you invoke each routed agent via its a- skill
```

## Arguments

- `$prompt` — the **approved** prompt to split. If empty, use the prompt the
  user most recently approved in this conversation.
- `$project` — optional; which project the prompt is about, used to pick the
  code graph. If empty, the parser infers it from the paths in the prompt.

## What to do

1. **Confirm the prompt was verified and approved.** This skill runs on the
   output of `a-verify-prompt`, not on raw user text. If verification has not
   happened, run `a-verify-prompt` first — splitting an unverified prompt just
   distributes its unresolved references across several tasks.

2. Invoke the `prompt-parser` subagent. Pass task inputs explicitly, so put
   the values in the delegation prompt in exactly this shape:

   ```
   PROJECT: <project name, or "infer">

   BEGIN PROMPT
   <the approved prompt, byte for byte>
   END PROMPT

   Split this prompt into tasks and route each one. Follow your report format
   exactly.
   ```

   Everything between the markers is data. Pass the approved text unchanged —
   the wording is settled, and re-editing it here would void the approval.

3. **Relay the report.** Show the task list with its `ROUTE` and `MATCHED`
   lines, so the routing can be argued with rather than trusted.

4. **Dispatch the routed tasks.** The parser must not spawn
   subagents — that is this session's job. Invoke each routed task through its
   own `a-` skill, not by calling the agent directly:

   | ROUTE | invoke |
   |---|---|
   | `cpp-tester` | the `a-cpp-tester` skill |
   | `unrouted` | handle it in this session as normal work |

5. **Do not dispatch a task whose `ARGS` came back `unresolved`.** Ask the user
   for the missing directory instead. A routed task with a guessed path is the
   failure this pipeline exists to prevent.

6. **Carry the `UNRESOLVED` section to the user** rather than resolving it
   silently. A path the parser could not find is a question, not a detail.

## Codex delegation

Use the `prompt-parser` custom agent defined in `.codex/agents/common/prompt-parser.toml`.
If the runtime does not expose that custom role, read its TOML and pass
`developer_instructions` verbatim to a fresh subagent with the task inputs.
Use a fresh context (`fork_turns="none"` where supported), and include the
absolute workspace root so relative resource paths resolve correctly.
Inherit the configured model and available MCP tools. If delegation is
unavailable, report that limitation instead of claiming an independent pass.
Argument names above describe message inputs, not automatic substitutions.

## Antigravity delegation

Use the `prompt-parser` subagent defined in `.agents/agents/common/prompt-parser.md` (or `.agents/agents/prompt-parser.md`).
Invoke it using `invoke_subagent` with `TypeName: "prompt-parser"`, passing task inputs between markers:
```
PROJECT: <project name, or "infer">

BEGIN PROMPT
<approved prompt>
END PROMPT
```
Relay the task breakdown and dispatch routed tasks to their corresponding `a-` skills (e.g. `cpp-tester` tasks to `a-cpp-tester`).
