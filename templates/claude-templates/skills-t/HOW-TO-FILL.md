# How to fill a skill template

Read this once before filling any template. It is the whole standard.

## Rules

1. **The description is the entire matching surface.** `name` + `description` are
   the only parts loaded before a skill fires. Third person, name the concrete
   project and tools, end with `Use when ...` carrying the words a user would
   actually type. Vague description = the skill never triggers.
2. **`name` must equal the directory name.** Lowercase, `[a-z0-9-]`.
3. **Write only what you verified.** Every command must have been run, every log
   line copy-pasted from real output. An invented trap is worse than no trap.
   Establish the structure through the code graph first — `get_architecture`,
   `search_graph`, `trace_path` on the project's own CBM graph
   (`home-vhaponov-Documents-jo-workspace-<project>`) — and only then read the
   files it points at. A skill written from grep output describes the file
   names; one written from the graph describes the call path.
4. **Prefer the non-obvious.** Anything discoverable in ten seconds from the file
   tree does not belong in a skill. Traps, orderings and "looks broken but isn't"
   do.
5. **Delete, do not keep.** Remove every `<!-- comment -->`, every unfilled
   section and every reference file you did not write. `grep -rn '{{' <skill>`
   must come back empty.
6. **One file until it hurts.** Split into `references/` only when a section is
   long *and* needed by a minority of runs. `SKILL.md` is the entry point —
   never add a `main.md`.
7. **Keep `SKILL.md` under ~500 lines.** Link references with a relative path and
   say *when* to read them.
8. **The skill lives under `.claude/projects/<project root directory name>/`.**
   That name is the project's own directory name, spelled identically. Let
   `new-skill.sh` place it; never hand-create the path, and never put a project
   skill inside the project repo.
9. **Say when the graph is the answer.** If a section would send a reader
   grepping — "find every caller of X", "what includes this header" — write the
   `mcp__codebase-memory__*` query instead of the `grep` command.

## What belongs in each type

| type | fill it with |
|---|---|
| `build` | the one build command, the line that proves success, how to surface the *first* error, and what to edit when adding code |
| `tester` | how to run all tests, how to run one, whether the exit code lies, and what green does not prove |
| `deploy` | how to launch with nothing else running, the mandatory flags, and every silent or misattributed runtime failure |
| `project` | the runtime call path, the configuration contract, and which design docs are ahead of the code |
| `sandbox` | the scratch root, the disposable runtime, cleanup, and what must never be touched |
| `debug` | a triage table of real symptoms first, then backtrace / core / log / hang recipes |

## Done check

```bash
grep -rn '{{\|<!--' <skill-dir>     # must be empty
```

Until it is empty the skill is a draft: `install-skill.sh` refuses to copy any
skill still containing `{{...}}` into another project or into
`~/.claude/skills`. Fill it where it was created first.
