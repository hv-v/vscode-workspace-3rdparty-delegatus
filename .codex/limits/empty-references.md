---
name: empty-references
trigger: the prompt cites a path, file, directory, ticket, skill, agent or template
action: block
priority: 20
---

# Empty or missing references

A prompt that points at something empty is not a prompt yet. Working from an
empty reference produces invented content that looks sourced — the worst
possible output. This check runs **before** any other, because everything else
reasons about what the references contain.

## Checks

1. **Extract every reference.** Anything that names a location: a path
   (`src/Foo.cpp`, `.codex/limits/`), a skill or agent name, a ticket file
   (`1619.md`), a template, a code-graph project, a URL.

2. **Resolve each one.** Paths and directories with `Glob` or `test -e`; skills
   and agents using `.agents/skills/README.md` and `.codex/agents/README.md`; a project graph with
   `mcp__codebase-memory__index_status`. Resolve relative paths against the
   workspace root, then against the project the prompt is about.

3. **Measure it.** For a file, `wc -c`. For a directory, whether it holds
   anything but `.gitkeep`. For a skill or agent file, whether it has content
   below skill frontmatter, or nonempty `developer_instructions` in agent TOML. For a graph project, whether it is indexed.

4. **Decide:**

   | finding | outcome |
   |---|---|
   | missing | **block** |
   | zero bytes | **block** |
   | frontmatter only, no body | **block** |
   | directory holding only `.gitkeep` | **block** |
   | carries a `> **STUB.**` banner | **pass**, and say so in `NOTES` — a stub is honest about being empty |
   | not indexed, but the prompt needs the graph | **pass**, and put the `cbm.sh index` command in `NOTES` |

5. **On block, return the prompt unchanged** with one line per bad reference:
   what was cited, how it was resolved, and what was found there. Never
   substitute a similar file that does have content, and never continue with the
   remaining references — the user decides what the reference should have been.

## Do not

Do not treat a file the prompt asks you to *create* as a missing reference:
`write X to .codex/limits/new-rule.md` cites a destination, not a source. The
verb decides — read/use/follow/according-to means source; write/create/add means
destination.
