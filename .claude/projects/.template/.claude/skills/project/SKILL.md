---
name: project
description: STUB (not yet written) - orientation for {{PROJECT}}. Use before changing {{PROJECT}} code or when asked how it works; it currently only records what is verified.
---

# {{PROJECT}} — how it is put together

> **STUB.** Nothing below is a verified account of the runtime behaviour. Do
> not cite it as one. Fill it from the code graph and real runs before relying
> on it — template: `templates/claude-templates/skills-t/project/SKILL.md`,
> standard: `templates/claude-templates/skills-t/HOW-TO-FILL.md`.

Repo: `{{PROJECT}}/`.
Code graph: `home-vhaponov-Documents-jo-workspace-{{PROJECT}}`. If
`index_status` says it is missing or stale, run
`./docker/cbm/cbm.sh index {{PROJECT}}` — then query the graph before reading
files or grepping.

## Verified so far

<!-- Only what you have confirmed: what this component is for, who talks to it,
     what it produces, and the directories that matter. Delete this comment. -->

## To fill

Runtime flow (the real call path, input to output), the configuration contract,
what validation passing does *not* prove, and which design notes run ahead of
the code.

## Sibling skills

`build`, `tester`, `deploy` are not written yet:
`./templates/claude-templates/skills-t/new-skill.sh <type> {{PROJECT}}`
