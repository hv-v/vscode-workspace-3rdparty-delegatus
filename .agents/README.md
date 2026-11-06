# `.agents/` — shared by Codex and Antigravity

Both Codex and Antigravity treat `.agents/` as their workspace customization
root, so everything here is read by both unless the table says otherwise.
Claude Code has its own tree, `.claude/`, which these files were converted from.

| purpose | path | read by |
|---|---|---|
| shared instructions | `../AGENTS.md` | Codex, Antigravity |
| Antigravity-only instructions | `../GEMINI.md` | Antigravity |
| workspace skills | `skills/<name>/SKILL.md`, map in `skills/README.md` | Codex, Antigravity |
| grouped skills (`common/`, `utests-coverage/`) | registered by `skills.json` | Antigravity (Codex reads them by path) |
| project skills | `projects/<project>/.agents/skills/`, map in `projects/navigation_map.md` | both, by path |
| prompt limitations | `limits/` | both, through `a-verify-prompt` |
| subagents | `agents/*.md`, registered by `agents.json` | Antigravity (Codex: `../.codex/agents/*.toml`) |
| always-on rules | `rules/*.md`, registered by `rules.json` | Antigravity |
| hooks | `hooks.json` → `hooks/claude-hook.sh` → `../.claude/hooks/*.sh` | Antigravity |
| code graph MCP server | `plugins/jo-workspace/mcp_config.json` | Antigravity (Codex: `../.codex/config.toml`) |

Ticket text, design notes, examples and logs are not here: they are shared with
Claude in `../.projects/<project>/`.

## Antigravity notes

- **Manifests scan one level deep.** A skill or agent inside a grouping folder
  is found only because `skills.json` / `agents.json` name that folder. Add a
  new group there; never add a symlink.
- **MCP comes from the plugin.** Antigravity reads MCP servers from
  `~/.gemini/config/mcp_config.json` or from a plugin, never from `.mcp.json`.
  The command is an absolute path, as in `.mcp.json` and `.codex/config.toml`.
  Check it with `agy plugin validate .agents/plugins/jo-workspace`.
- **Hooks are adapters.** Antigravity sends `toolCall.name` / `toolCall.args`
  in camelCase and expects `{"decision": …}` back; the Claude scripts read
  `tool_name` / `tool_input`. `hooks/claude-hook.sh` translates both ways, so
  the enforcement logic lives once, in `.claude/hooks/`. It fails open and never
  answers `allow`, which would skip the user's approval. Hooks run with
  `.agents/` as the working directory. List what loaded with
  `agy -p /hooks`.
- **Subagents** are Markdown with YAML frontmatter. `inheritMcp: true` gives an
  agent the code graph; `subagent: false` + `hidden: true` keeps the
  `py-tester` stub out of the roster. List them with `agy agents`.
