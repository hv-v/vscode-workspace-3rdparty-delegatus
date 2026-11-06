# Workspace Antigravity Custom Agents

This directory defines custom subagents for Antigravity (Gemini), converted and adapted from the workspace agent definitions in `.claude/agents/` and `.codex/agents/`.

Each subagent is defined in Markdown with standard frontmatter (`name`, `description`) and developer instructions. Subagents inherit the parent MCP configuration (including `codebase-memory`).

| Agent | Location | Status | Purpose |
|---|---|---|---|
| `prompt-parser` | [common/prompt-parser.md](common/prompt-parser.md) | Active | Splits an approved prompt into individual tasks and routes each to the matching agent. |
| `prompt-verifier` | [common/prompt-verifier.md](common/prompt-verifier.md) | Active | Validates prompt references and names against the code graph, repairs ambiguous grammar, and applies limits. |
| `cpp-verifier` | [cpp-verifier.md](cpp-verifier.md) | Active | Verifies C++ diffs against `l-cpp` and repo guidelines (read-only). |
| `cpp-tester` | [utests-coverage/cpp-tester.md](utests-coverage/cpp-tester.md) | Active | Implements C++ unit tests (gtest) for existing sources; registers them in CMake. |
| `py-tester` | [utests-coverage/py-tester.md](utests-coverage/py-tester.md) | Stub | Python test agent (stub, matching source status). |

## Discovery & Delegation

- Configured via `.agents/agents.json` to discover both root and grouped (`common/`, `utests-coverage/`) subagents.
- Subagents can be invoked directly with `invoke_subagent` or defined via `define_subagent`.
- Wrapped and driven by their corresponding `a-` skills in `.agents/skills/` (`a-verify-cpp`, `a-prompt-parser`, `a-verify-prompt`, `a-cpp-tester`, `a-py-tester`).
