---
name: name-validity
trigger: the prompt attaches an identifier, symbol, class, function, file, package, node, topic, service, project or skill name
action: block
priority: 30
---

# Attached names must be real and well formed

Names are where a prompt silently goes wrong: a misremembered class, a package
that was renamed, a topic with a typo. One code-graph query settles it, and the
graph is why this check is cheap enough to run every time.

## Checks

1. **Collect the attached names** and label each one **existing** or **new**:

   | verb in the prompt | label |
   |---|---|
   | fix, change, rename, remove, extend, test, review, call, use | **existing** — must resolve |
   | add, create, implement, introduce, name it | **new** — must only be well formed |

   When the verb is ambiguous, treat the name as existing: a false "does not
   exist" is one question, a false "assumed new" is wasted work.

2. **Well-formedness first** — it costs nothing. Against `l-cpp` for C++ names:
   `PascalCase` types, `camelCase` functions and locals, trailing underscore on
   members, `k` prefix on constants. Against this workspace for everything else:
   skill and agent directory names are `[a-z0-9-]`, a project entry under
   `.claude/projects/` is spelled exactly like the project's root directory.
   Malformed **new** name → block with the corrected spelling.

3. **Existence, through the graph.** Resolve the project first, then query its
   graph `home-vhaponov-Documents-jo-workspace-<project>`:

   - codebase-memory `search_graph` — the symbol, class or function
   - codebase-memory `get_file_outline` — a file's symbols, to confirm a
     method belongs to the type the prompt attached it to
   - codebase-memory `search_code` — literals the graph does not hold:
     topics, services, parameter names, YAML keys

   **Cap: 8 queries per prompt, one per distinct name.** Over the cap, check the
   names the prompt leans on most and say in `NOTES` which went unchecked.

4. **Decide:**

   | finding | outcome |
   |---|---|
   | exact hit | pass |
   | no hit, but a near miss in the results | **block** — quote the near miss as `did you mean`, with its `file:line` |
   | no hit at all | **block** — say which project graph was searched |
   | project not indexed | pass, with the `./docker/cbm/cbm.sh index <project>` command in `NOTES` |
   | graph unreachable | pass, and say so — never present a grep fallback as a graph check |

5. **Never repair a name silently.** A near miss is a question, not a fix: the
   user may be naming something they are about to create.
