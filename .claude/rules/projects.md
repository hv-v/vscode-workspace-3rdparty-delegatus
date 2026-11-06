# Project configuration lives in `.claude/projects/`, never in the project repo

`<project>` **is always the project's root directory name, spelled
identically** — `jen_calibration_manager/` in the workspace is served by
`.claude/projects/jen_calibration_manager/.claude/`. No prefix, no shortening,
no plural. That one-to-one mapping is how a project's configuration is found,
so it is a hard rule: if the repo directory is renamed, rename this one in the
same commit.

```
.claude/projects/jen_calibration_manager/.claude/
├── skills/{build,tester,deploy,project}/SKILL.md
├── commands/{build,tester}/*.md
└── agents/*.md
```

**Start at `.claude/projects/navigation_map.md`** — it maps every entry to its
repo, its code graph and what is actually filled in versus still a stub.
`.claude/projects/.template/` is the skeleton to copy when a project joins.

Why here and not inside the repo: the project repos are submodules with their
own history, and workspace tooling has no business appearing in their diffs.

## Project context lives in `.projects/`, shared with every agent

What does not depend on the agent — ticket text, design notes, examples, build
logs — sits once at the workspace root, under the same project name:

```
.projects/jen_calibration_manager/
├── .task_todos/      ticket text, one file per ticket
├── .design_todos/    design notes
├── .examples/        snippets worth copying, not owned by the repo
└── .errors/          build and run logs kept for diagnosis
```

`.claude/projects/` and `.agents/projects/` (shared by Codex and Antigravity)
hold only agent-specific files. Never put a context file under either of them:
a copy in one agent tree is a copy the other agents never see. `.projects/README.md` lists every entry; copy
`.projects/.template/` when a project joins.

Working on a project:

1. Resolve the project root directory name from the files you are touching, and
   check it against the navigation map.
2. Read `.claude/projects/<that name>/.claude/skills/*/SKILL.md` — these are
   directory-scoped and do not appear in the session's skill roster, so read
   them by path rather than assuming an absent skill means none exists. A file
   carrying a `> **STUB.**` banner records only verified facts: use it as a
   starting point, not as an account of behaviour, and fill in what you learn.
3. Check `.projects/<that name>/` for the ticket and design context of the task
   — the `project` skill names which notes are authoritative.
4. Load the workspace `l-` skills for the languages involved.
