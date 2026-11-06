---
paths:
  - ".claude/settings.json"
  - ".claude/settings.local.json"
  - ".claude/hooks/**"
---

# Hooks — the rules the harness enforces

A rule in `.claude/rules/` is context: it shapes what I do, but I can skip it.
A hook is a command the harness runs regardless. Anything that must hold every
time belongs here, and everything here exists to make one written rule
mechanical.

**There is no `.claude/hooks/` config discovery.** Hooks are declared as JSON in
`.claude/settings.json` (committed, this workspace) or `.claude/settings.local.json`
(personal, this machine); `~/.claude/settings.json` applies to every project.
`.claude/hooks/` holds only the *scripts* those declarations point at. `/hooks`
is a slash command that opens a UI over those files — not a path.

| event | script | makes real |
|---|---|---|
| `SessionStart` | `graph-status.sh` | names project directories with no code graph, so `rules/code-graph.md` cannot be followed silently against an unindexed repo |
| `UserPromptSubmit` | inline `jq` | asks for `a-verify-prompt` plus the approval gate — **off unless `JO_VERIFY_PROMPT=1`**; see `rules/prompt-limits.md` |
| `PreToolUse` / `Bash` | `graph-first.sh` | denies a recursive `grep`/`find` over a project tree — `rules/code-graph.md` |
| `PreToolUse` / `Bash\|WebFetch` | `corp-guard.sh` | denies any command or fetch naming a `jenoptik.corp` host except a bare `.atlassian/sync.sh` or `.gitlab/sync.sh` call or plain `git` over SSH, and any command touching a real `credentials` file in `.atlassian/.secrets/` or `.gitlab/.secrets/` — `rules/atlassian.md`, `rules/gitlab.md`; a `permissions.deny` on WebFetch and Read backs it up, since a hook fails open |
| `PreToolUse` / `Write\|Edit` | `guard-generated.sh` | denies a hand-edit of `.gitmodules` — `rules/generated-files.md` |
| `PostToolUse` / `Write\|Edit` | `clang-format.sh` | applies the owning repo's `.clang-format` — the layout authority in `l-cpp` |

## Shared with Antigravity

Antigravity runs the same scripts: `.agents/hooks.json` calls
`.agents/hooks/claude-hook.sh <script>`, which translates its payload into the
shape above and the answer back. So a script here must keep reading only
`tool_name`, `tool_input.command`, `tool_input.file_path` and `tool_input.url`,
and answer only through `permissionDecision` or `additionalContext` — anything
else never reaches Antigravity. `corp-guard.sh` also checks `Read`/`Write`/`Edit`
paths for the credentials files, because Antigravity has no `permissions.deny`
to back it up.

## Writing one

Scripts take the hook JSON on stdin and are read with `jq`, never by
interpolating payload text into a command line — a file path or a prompt may
contain quotes, backticks or `$(...)`.

- **Fail open.** A missing tool, an absent config file, a timeout: `exit 0` and
  say nothing. A hook that breaks unrelated work gets disabled, and then it
  enforces nothing at all.
- **Deny with a way forward.** A `permissionDecisionReason` names the rule *and*
  what to do instead. `graph-first.sh` denies a recursive grep but says how to
  run a legitimate literal search, because text search stays correct for what
  the graph does not hold.
- **Never guess a project's standard.** `clang-format.sh` walks up for the
  repo's own `.clang-format` and exits when there is none.
- **Test before wiring**: pipe a synthesized payload into the script and check
  both that it fires and that the cases which must pass stay silent. Then
  `jq -e` the settings file — malformed JSON silently disables every setting in
  it.

Declaring a hook is not enough to run it: the settings watcher only watches
directories that already had a settings file when the session started. After
adding one, open `/hooks` or restart, then confirm it fired.

## Known drift

`clang-format.sh` runs the **host** binary (18.1.3), while the projects run
their `clang_format` check inside the tester image. If the container pins a
different major version the two can disagree, and the hook would then be
introducing the churn it exists to prevent. Pin them, or drop this hook, if a
formatting check ever fails on code the hook just formatted.
