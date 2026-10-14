# `.template` — the shape of one project entry

Copy this directory to `.claude/projects/<project root directory name>/` when a
new project joins the workspace, then replace `{{PROJECT}}` everywhere:

```bash
cp -r .claude/projects/.template .claude/projects/<project>
grep -rl '{{PROJECT}}' .claude/projects/<project> | xargs sed -i 's/{{PROJECT}}/<project>/g'
```

The directory name **is** the project's root directory name, spelled
identically — that mapping is how the configuration is found.

| path | holds |
|---|---|
| `.claude/skills/` | `project` (orientation), plus `build`, `tester`, `deploy`, `sandbox`, `debug` as they are written |
| `.claude/commands/` | `/commands` scoped to this project, grouped in subdirectories |
| `.claude/agents/` | subagents scoped to this project |

Ticket text, design notes, examples and logs are not agent-specific and do not
go here. Copy their skeleton to the shared root at the same time:

```bash
cp -r .projects/.template .projects/<project>
```

In the `project` skill, say which `.projects/<project>/.design_todos/` notes are
authoritative and which run ahead of the code.

Real skills are **not** hand-written into `.claude/skills/`. Generate them so
the frontmatter and placeholders are right:

```bash
./templates/claude-templates/skills-t/new-skill.sh <type> <project>
```

The `project/SKILL.md` here is a stub on purpose: it names what must be
established before anything else is written. Leave the STUB banner in place
until the file is genuinely filled — an unmarked half-skill is worse than none.
Do not delete `.gitkeep` files from directories that are still empty.
