---
paths:
  - "templates/**"
  - ".claude/skills/**"
  - ".claude/projects/**/skills/**"
---

# Creating and sharing a skill

Templates and installer scripts live in `templates/claude-templates/skills-t/` —
see its `README.md` and `HOW-TO-FILL.md`. Create with
`new-skill.sh <type> <project>`, share an already-filled one with
`install-skill.sh <skill> <project|--global>`. Both write into
`.claude/projects/<project>/.claude/skills/`; neither touches the project repo.

Never copy the template tree into a `.claude/skills/` directory: templates are
auto-discovered there and pollute the skill roster with placeholder
descriptions.

Do not hand-create a skill directory. The scripts derive the project name with
`basename`, substitute `{{PROJECT}}`, and keep the frontmatter `name:` equal to
the directory name — the three things that are wrong most often when a skill is
written by hand.
