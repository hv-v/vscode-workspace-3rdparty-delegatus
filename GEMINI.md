# jo-workspace — Antigravity specifics

`AGENTS.md` holds the rules shared with Codex and loads alongside this file;
`.agents/rules/*.md` (always-on) hold the detail. This file covers only what is
specific to Antigravity. Overview of the tree: [.agents/README.md](.agents/README.md).

## What is wired, and where

| piece | file | note |
|---|---|---|
| code graph (MCP) | `.agents/plugins/jo-workspace/mcp_config.json` | the `codebase-memory` server; Antigravity ignores `.mcp.json` |
| hooks | `.agents/hooks.json` → `.agents/hooks/claude-hook.sh` | runs the scripts in `.claude/hooks/`, translating payloads both ways |
| grouped skills | `.agents/skills.json` | `common/` and `utests-coverage/` are not found by the one-level scan |
| grouped subagents | `.agents/agents.json` | same reason, for `.agents/agents/common/` and `utests-coverage/` |
| rules | `.agents/rules/*.md`, registered by `.agents/rules.json` | `always_on` except `generated-files.md` (glob) |

## Hooks that will stop you

| hook | event / tool | denies |
|---|---|---|
| `graph-status` | session start | — reports projects with no code graph |
| `graph-first` | `run_command` | a recursive grep or `find -name` over a project tree |
| `corp-guard` | commands, URL reads, file tools | a corporate host outside the sync scripts; any access to a real `credentials` file |
| `guard-generated` | file edits | a hand-edit of `.gitmodules` |
| `clang-format` | after file edits | — formats C++ with the owning repo's `.clang-format` |

A denial names the rule and the allowed alternative; follow it rather than
rephrasing the command to get past the hook.

## Subagents

`cpp-verifier`, `prompt-verifier`, `prompt-parser` and `cpp-tester` run with
`inheritMcp: true`, so they get the code graph. Drive them through their `a-`
skills, which define the inputs to pass. `py-tester` is a stub, hidden and not
invocable.
