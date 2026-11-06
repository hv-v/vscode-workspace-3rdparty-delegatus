# Workspace Codex configuration

Codex uses both `.codex` and `.agents`; they serve different purposes.

| Purpose | Workspace location |
| --- | --- |
| CLI and IDE settings | `.codex/config.toml` |
| Custom subagents | `.codex/agents/<name>.toml` |
| Skills and reusable command workflows | `.agents/skills/<skill-name>/SKILL.md` |
| Project skills | `.agents/projects/<project>/.agents/skills/` |
| Prompt limitations | `.agents/limits/` |
| General project instructions, when needed | `AGENTS.md` in the repository root or relevant subdirectory |
| Project context shared with Claude (tickets, design notes, examples, logs) | `.projects/<project>/` in the workspace root |

Agents and skills have been converted from `.claude`, preserving the groups
and project hierarchy. See `agents/README.md`, `../.agents/skills/README.md`,
and `../.agents/projects/navigation_map.md`. Everything under `.agents/` is
shared with Antigravity, which reads the same root (`../.agents/README.md`).
The root `AGENTS.md` routes project guidance.
A README is documentation and does not register a skill or agent.

## Current settings

`config.toml` allows workspace edits, requests approval when necessary, and uses
cached web search. Model, reasoning effort, and service tier inherit from
`~/.codex/config.toml`.

Project configuration loads only for trusted projects. This workspace is already
trusted in the local user configuration. Start a new Codex session to load config
changes; explicit session overrides and managed policies can take precedence.

Keep authentication and session data in the user-level Codex directory. Do not
set `CODEX_HOME` to this workspace folder.

## Commands and skills

Use `.agents/skills/<skill-name>/SKILL.md` for reusable workflows. Each skill needs
YAML frontmatter with `name` and `description`, followed by its instructions.
Invoke it explicitly with `$skill-name`, or let Codex select it by its description.
Keep each skill focused and its trigger conditions clear.

There is no need for a workspace `.codex/commands` folder. Legacy custom slash
prompts in `~/.codex/prompts` are deprecated; OpenAI recommends skills instead.

## Custom subagents

Add standalone TOML definitions to `.codex/agents/`. Give each agent a narrow role
and appropriate permissions. Built-in agents are available without custom files.

## Official OpenAI documentation

- [Configuration](https://learn.chatgpt.com/docs/config-file/config-basic)
- [Skills](https://learn.chatgpt.com/docs/build-skills)
- [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Custom prompts deprecation](https://learn.chatgpt.com/docs/custom-prompts)

## Migration details

`migration-map.json` records each source and destination. The migration includes
5 agent definitions (one unimplemented), 10 workspace skills (four unimplemented),
7 project skills (including the template and two partial stubs), C++ references,
project support assets and prompt limitations. Original Claude files are retained.
Project context (tickets, design notes, examples) has since been merged from both
trees into the shared `.projects/` and is no longer listed in the map. Project
skills and limitations moved from `.codex/projects/` and `.codex/limits/` to
`.agents/`, where Antigravity reads them too; the map records the new paths.
Claude argument metadata is expressed as delegation-message inputs, and agent
skill preloading is replaced with explicit reads. Models inherit the Codex parent.
Claude hooks, command shortcuts and settings are not activated by this migration.

Nested skills and project skills can always be loaded through the maps above.
If a custom agent is absent from the roster, the corresponding wrapper skill
provides a fresh-subagent fallback using the TOML instructions. Start a new
Codex session to load the root instructions and custom agents.
