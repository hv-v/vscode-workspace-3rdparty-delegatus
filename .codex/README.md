# Workspace Codex configuration

Codex uses both `.codex` and `.agents`; they serve different purposes.

| Purpose | Workspace location |
| --- | --- |
| CLI and IDE settings | `.codex/config.toml` |
| Custom subagents | `.codex/agents/<name>.toml` |
| Skills and reusable command workflows | `.agents/skills/<skill-name>/SKILL.md` |
| General project instructions, when needed | `AGENTS.md` in the repository root or relevant subdirectory |

The skills and custom-agent directories are initially empty apart from README
files. Add definitions when there is a concrete workflow or specialist role.
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
