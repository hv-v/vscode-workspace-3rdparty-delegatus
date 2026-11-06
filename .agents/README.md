# Workspace Antigravity Configuration

This directory (`.agents/`) serves as the native project-level customization root for **Antigravity (Google Deepmind)**, coexisting with Claude (`.claude/`) and OpenAI Codex (`.codex/`).

## Architecture & Layout

| Purpose | Workspace Location | Function |
|---|---|---|
| **Root Instructions** | `GEMINI.md` (root) | Workspace instructions automatically loaded by Antigravity IDE and CLI. |
| **Skills Registration** | `.agents/skills.json` | Registers `.agents/skills/`, `common/`, and `utests-coverage/`. |
| **Skills Directory** | `.agents/skills/<name>/SKILL.md` | Reusable procedural skills (`l-cpp`, `l-bash`, `a-verify-cpp`, etc.). |
| **Subagents Registration** | `.agents/agents.json` | Registers root and grouped custom subagents. |
| **Subagents Directory** | `.agents/agents/<name>.md` | Markdown subagent definitions with frontmatter instructions. |
| **Workspace Rules** | `.agents/rules/*.md` & `rules.json` | Scoped guidelines (code-graph first, Jira/GitLab local mirrors, etc.). |
| **Prompt Limitations** | `.agents/limits/*.md` | Limitation checks used by `prompt-verifier` and `a-verify-prompt`. |
| **Project Workflows** | `.agents/projects/` | Project orientation and navigation map (`navigation_map.md`). |
| **Lifecycle Hooks** | `.agents/hooks.json` | Event hooks for formatting (`clang-format`) and guardrails. |
| **MCP Integration** | `.mcp.json` (root) | `codebase-memory` MCP server definition. |

## Subagent Roster

Subagents are defined in `.agents/agents/` and referenced by `a-` skills:
- **`cpp-verifier`**: Verifies C++ diffs against `l-cpp` and repo guidelines (read-only).
- **`prompt-verifier`**: Verifies prompts against code graph and limits, enforces size ceiling (1.5×).
- **`prompt-parser`**: Splits verified prompts into tasks and detects routing decisions.
- **`cpp-tester`**: Generates and registers C++ unit tests (`gtest`).
- **`py-tester`**: Preserved stub for Python test delegation.

## Discovery & Loading Order

1. **Workspace Root Rules**: `GEMINI.md` loads automatically for all turns in this workspace.
2. **Skills & Agents**: Discovered directly and via `.agents/skills.json` and `.agents/agents.json`.
3. **MCP Tools**: Connected via `.mcp.json` (`codebase-memory`).
