---
name: a-verify-cpp
description: Verify that the C++ added or changed in a repository conforms to the l-cpp skill and that repo's own guidelines. Takes the repo path and an optional guidelines file. Use before committing C++, or when asked to check a change for style and guideline compliance.
---

# Verify C++ against the standard

Delegate this to the `cpp-verifier` subagent. It runs read-only in its own
context after explicitly reading `.agents/skills/l-cpp/SKILL.md`, so its findings are not coloured by
whatever this conversation has already decided.

## Arguments

- `$repo` — repository to verify. If empty, use the current working directory.
- `$guidelines` — optional path to repo-specific rules, or inline text. If empty,
  `l-cpp` alone is the standard.

## What to do

1. Resolve `$repo` to an absolute path. If it is empty, use the working
   directory. If it does not exist, say so and stop.

2. If `$guidelines` is a path, confirm it exists. If it is empty, check the repo
   for an obvious candidate — `CONTRIBUTING.md`, `docs/code_style.md`, a
   `AGENTS.md` — and offer it rather than silently reviewing without one.

3. Invoke the `cpp-verifier` subagent. Pass task inputs explicitly, so put
   both values in the delegation prompt in exactly this shape:

   ```
   REPO: <absolute path>
   GUIDELINES: <absolute path, inline text, or "none">

   Verify the C++ added or changed in REPO against the l-cpp skill and
   GUIDELINES. Follow your reporting format exactly.
   ```

   Add a scope line only if the user named one, for example
   `SCOPE: git diff main...HEAD` or `SCOPE: src/Registry.cpp`.

4. Relay the subagent's report verbatim. Do not re-rank, soften or summarise it —
   its whole value is that it applied written rules rather than judgement.

5. If the verdict is CHANGES REQUESTED, ask whether to apply the fixes. Do not
   apply them as part of verification; the verifier is read-only by design and
   the separation is deliberate.

## Codex delegation

Use the `cpp-verifier` custom agent defined in `.codex/agents/cpp-verifier.toml`.
If the runtime does not expose that custom role, read its TOML and pass
`developer_instructions` verbatim to a fresh subagent with the task inputs.
Use a fresh context (`fork_turns="none"` where supported), and include the
absolute workspace root so relative resource paths resolve correctly.
Inherit the configured model and available MCP tools. If delegation is
unavailable, report that limitation instead of claiming an independent pass.
Argument names above describe message inputs, not automatic substitutions.

## Antigravity delegation

Use the `cpp-verifier` subagent defined in `.agents/agents/cpp-verifier.md`.
Invoke it using `invoke_subagent` with `TypeName: "cpp-verifier"` (or define it dynamically via `define_subagent` if absent from the runtime roster).
Pass the formatted task inputs in the delegation prompt:
```
REPO: <absolute path>
GUIDELINES: <absolute path, inline text, or "none">
```
Use read-only workspace mode (`Workspace: "inherit"`), and inherit the model. Relay the subagent's report verbatim.
