# Workspace custom agents

One TOML definition per agent, preserving the source groups. Models and MCP
configuration inherit from the parent; the Claude `haiku` alias is not carried
over. Read-only roles use `sandbox_mode = "read-only"`; the C++ test writer uses
`workspace-write` and limits its edits in its instructions. Claude tool
allowlists and colors are not Codex fields; task boundaries are instructions,
not equivalent per-tool enforcement. Required skills are read explicitly.

| agent | definition | status |
|---|---|---|
| `prompt-parser` | [common/prompt-parser.toml](common/prompt-parser.toml) | converted |
| `prompt-verifier` | [common/prompt-verifier.toml](common/prompt-verifier.toml) | converted |
| `cpp-verifier` | [cpp-verifier.toml](cpp-verifier.toml) | converted |
| `cpp-tester` | [utests-coverage/cpp-tester.toml](utests-coverage/cpp-tester.toml) | converted |
| `py-tester` | [utests-coverage/py-tester.toml](utests-coverage/py-tester.toml) | unimplemented stub |

If a nested role is absent from the runtime roster, its matching `a-` skill
reads the TOML and passes `developer_instructions` to a fresh generic subagent.
Do not flatten the groups or create duplicate definitions.

Format: https://learn.chatgpt.com/docs/agent-configuration/subagents
