# jo-workspace Antigravity instructions

This file guides the Antigravity (Gemini) coding agent in `jo-workspace`. It mirrors and unifies the capabilities established for Claude (`.claude/`) and Codex (`.codex/`, `AGENTS.md`).

---

## 1. Code Context and Architecture: Graph First

Before executing any file search or refactoring, query the **`codebase-memory` (CBM)** MCP server:
- Hosted via docker (`docker/cbm/cbm.sh`) and registered in `.mcp.json`.
- Query the project's own graph, named after its absolute workspace path:
  `home-vhaponov-Documents-jo-workspace-<repo directory name>`
- Query order:
  1. `get_architecture` — project structure and key components.
  2. `search_graph` — symbol definitions and locations (class, function, message, node).
  3. `trace_path` — caller/callee relations, inheritance, include chains.
  4. `query_graph` — multi-hop graph questions.
  5. `get_file_outline` / `get_code_snippet` — targeted symbol inspection.
  6. `search_code`, then file search/grep — literals, CMake files, build scripts.
- **Rule**: If the graph is unreachable or unindexed, report that status before falling back to file search. Treat the graph as an index map; always verify line numbers and source code against working-tree files.

---

## 2. Skills and Procedures

Skills provide authoritative procedural instructions and override general defaults.
- **Workspace Skills**: Located in `.agents/skills/`.
  - Configured and indexed via `.agents/skills.json` (covering `.agents/skills/`, `.agents/skills/common/`, and `.agents/skills/utests-coverage/`).
  - `l-cpp`: Modern C++17/20/23 coding standard, RAII, ownership, concurrency, naming, and gtest rules.
  - `l-bash`: Strict mode, quoting, traps, error handling, shellcheck.
  - `a-verify-cpp`: Verification of C++ diffs using the `cpp-verifier` subagent.
  - `a-verify-prompt` & `a-prompt-parser`: Verification and task dispatch pipeline.
  - `a-cpp-tester`: Test generation using the `cpp-tester` subagent.
- **Project Skills**: Project-specific workflows (build, test, deploy) live under `.agents/projects/<project>/.agents/skills/` (and `.codex/projects/`). Refer to `.agents/projects/navigation_map.md`.
- **Unimplemented Skills**: `p-build`, `p-deploy`, `p-tester`, and `a-py-tester` are stubs preserved from the source migration; report their missing implementation explicitly rather than simulating execution.

---

## 3. Custom Subagents

Subagents handle focused tasks in separate contexts:
- Defined in `.agents/agents/` (indexed in `.agents/agents/README.md`, registered in `.agents/agents.json`).
- Available subagents:
  - `cpp-verifier`: Read-only C++ guideline and formatting checker (`.agents/agents/cpp-verifier.md`).
  - `prompt-verifier`: Read-only prompt verification against code graph and limits (`.agents/agents/common/prompt-verifier.md`).
  - `prompt-parser`: Read-only task splitter and routing detector (`.agents/agents/common/prompt-parser.md`).
  - `cpp-tester`: C++ unit test authoring (`.agents/agents/utests-coverage/cpp-tester.md`). Writes only to `TEST_DIR` and test registration files (`test/Sources.cmake`).
  - `py-tester`: Python test authoring stub (`.agents/agents/utests-coverage/py-tester.md`).
- Delegation: Driven through their respective `a-` skills (`a-verify-cpp`, `a-verify-prompt`, `a-prompt-parser`, `a-cpp-tester`).

---

## 4. Prompt Verification Pipeline and Limits

When working on complex tasks or prompts requiring verification:
1. `a-verify-prompt` verifies references, identifiers, and grammar against limitation rules in `.agents/limits/` (`empty-references.md`, `name-validity.md`, `no-assumptions.md`, `grammar.md`).
2. **Size Budget**: Verified prompts must not exceed 1.5× original character count.
3. **Approval Gate**: If a prompt is modified or annotated, obtain explicit user approval before proceeding.
4. `a-prompt-parser` breaks the approved prompt into discrete tasks and routes test tasks to `cpp-tester`.

---

## 5. Local Mirrors: Jira, Confluence, and GitLab

- **Atlassian (`.atlassian/`)**: Read-only local mirror of Jira and Confluence.
  - Confluence SQLite database: `.atlassian/.db/confluence.db`. Access strictly via `.atlassian/kb.sh search` and `.atlassian/kb.sh page <id>`.
  - Jira tickets: `.atlassian/.jira/<status>/<KEY>.json`.
- **GitLab (`.gitlab/`)**: Read-only local mirror of merge requests, review comments, pipelines, and failed job logs. Navigation: `.gitlab/navigation_map.md`.
- **Security Rule**: Never send direct HTTP/API requests to `*.jenoptik.corp`. Never inspect, print, or edit credentials under `.atlassian/.secrets/` or `.gitlab/.secrets/`.

---

## 6. Generated Files

- `.gitmodules` is generated dynamically from `.gitmodules.t` and `.gitparams` by running `./gen-gitmodules.sh`. Never edit `.gitmodules` by hand.

---

## 7. Shared Project Context

- Project notes, ticket text, design documentation, and logs are shared across all agents in `.projects/<project>/`:
  - `.task_todos/`
  - `.design_todos/`
  - `.examples/`
  - `.errors/`
- Never duplicate these files under `.agents/` or `.codex/`.
