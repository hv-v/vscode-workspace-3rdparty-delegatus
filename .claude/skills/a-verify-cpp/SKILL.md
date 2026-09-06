---
name: a-verify-cpp
description: Verify that the C++ added or changed in a repository conforms to the l-cpp skill and that repo's own guidelines. Takes the repo path and an optional guidelines file. Use before committing C++, or when asked to check a change for style and guideline compliance.
argument-hint: "[repo] [guidelines]"
arguments: [repo, guidelines]
allowed-tools: Bash(git *), Bash(ls *), Read, Agent
---

# Verify C++ against the standard

Delegate this to the `cpp-verifier` subagent. It runs read-only in its own
context with the `l-cpp` skill preloaded, so its findings are not coloured by
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
   `.claude/CLAUDE.md` — and offer it rather than silently reviewing without one.

3. Invoke the `cpp-verifier` subagent. Subagents receive no arguments, so put
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
