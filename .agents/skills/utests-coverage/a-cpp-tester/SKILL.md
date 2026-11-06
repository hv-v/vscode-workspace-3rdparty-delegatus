---
name: a-cpp-tester
description: Implement C++ unit tests for existing sources. Takes the test, src and include directories and an optional list of targets. Use whenever a task asks for unit tests, more coverage, or a test implementation for C++ - this skill is the only route to creating a C++ test file.
---

# Implement C++ unit tests

Delegate this to the `cpp-tester` subagent. It runs in its own context with the
`l-cpp` skill read explicitly and the inherited code graph available, so it works from the repo's
own conventions rather than from whatever this conversation has already assumed
about the code.

**This is the only route to a new C++ test file.** If a task — or any part of a
task — calls for a test implementation, it goes through here. Do not write a
test yourself "to save a round trip"; a test written outside this path skips the
framework detection, the naming contract and the build registration that make it
actually run.

## Arguments

- `$test_dir` — where tests are written. Required.
- `$src_dir` — implementation sources under test. Required.
- `$include_dir` — public headers of the same unit. Required.
- `$targets` — optional; specific files, classes or functions to cover. Empty
  means every source under `$src_dir`.

The three directories are required because guessing them is how tests land in
the wrong package. Only if the user cannot supply them, fall back to
`<project>/src`, `<project>/includes` and `<project>/test` — and say in your
reply that you fell back and to what.

## What to do

1. Resolve the three directories to absolute paths. If one was given but does
   not exist, say so and stop — do not test the nearest similar directory.

2. If a directory is missing from the request, ask for it before falling back.
   The fallback exists for the case where the answer is genuinely "the defaults";
   it is not a substitute for asking.

3. Invoke the `cpp-tester` subagent. Pass task inputs explicitly, so put the
   values in the delegation prompt in exactly this shape:

   ```
   TEST_DIR:    <absolute path>
   SRC_DIR:     <absolute path>
   INCLUDE_DIR: <absolute path>
   TARGETS:     <files, classes or functions, or "all sources under SRC_DIR">

   Implement unit tests for the sources under SRC_DIR. Detect the framework
   from the repo's build files, follow the existing tests' conventions, and
   register every new file in the test build list. Follow your report format
   exactly.
   ```

   Add a scope line only if the user named one, for example
   `SCOPE: only the branches changed in git diff main...HEAD`.

4. Relay the subagent's report verbatim, including its `NOT COVERED` and
   `BLOCKED` sections. Those are the parts that get dropped in a summary and
   they are the parts that matter — a coverage report without its gaps reads as
   completeness.

5. **Do not build or run the tests as part of this skill.** Builds go through
   Docker and the project's own `build` and `tester` skills. Relay the agent's
   `NEXT` line and let the user decide.

6. If the report has a `BLOCKED` section, ask whether to make those source
   changes. The agent is barred from touching production code by design, and
   that separation is the point — do not quietly apply them yourself.

## Codex delegation

Use the `cpp-tester` custom agent defined in `.codex/agents/utests-coverage/cpp-tester.toml`.
If the runtime does not expose that custom role, read its TOML and pass
`developer_instructions` verbatim to a fresh subagent with the task inputs.
Use a fresh context (`fork_turns="none"` where supported), and include the
absolute workspace root so relative resource paths resolve correctly.
Inherit the configured model and available MCP tools. If delegation is
unavailable, report that limitation instead of claiming an independent pass.
Argument names above describe message inputs, not automatic substitutions.

## Antigravity delegation

Use the `cpp-tester` subagent defined in `.agents/agents/utests-coverage/cpp-tester.md` (or `.agents/agents/cpp-tester.md`).
Invoke it using `invoke_subagent` with `TypeName: "cpp-tester"` and workspace write permission (`Workspace: "inherit"`).
Pass the task inputs in the delegation prompt:
```
TEST_DIR: <path>
SRC_DIR: <path>
INCLUDE_DIR: <path>
TARGETS: <paths or classes, optional>
```
Relay the report verbatim; do not run Docker builds directly in this skill.
