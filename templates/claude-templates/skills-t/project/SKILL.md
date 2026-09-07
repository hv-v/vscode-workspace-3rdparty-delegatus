---
name: project
description: Orientation for {{PROJECT}} - its architecture, main components, configuration and formats, contracts and the state of its design notes. Use before changing this code, when asked how {{PROJECT}} works or what a setting must contain, or when reconciling its design notes with the actual code.
---

# {{PROJECT}} — how it is put together

<!-- Single file by design: read whole, at the start of a task. Split only if a
     section becomes long AND is needed by a minority of tasks.
     Delete every comment in this file as you fill it. -->

<!-- One paragraph: what this component is for, who talks to it, what it
     produces. Name the ticket/epic if there is one. Then the repo layout in one
     line: the directories that matter and what each holds. -->

## Code graph

Project graph: `home-vhaponov-Documents-jo-workspace-{{PROJECT}}`. Query it
before reading files or grepping — `get_architecture` for the shape,
`search_graph` for a symbol, `trace_path` for who calls what, then
`get_code_snippet` for the source. Re-index with
`./docker/cbm/cbm.sh index {{PROJECT}}` if `index_status` looks stale.

<!-- If some part of this repo is genuinely outside the index (generated code,
     vendored blobs, a language the indexer skips), say so here - that is the
     only place a bare grep is the right first move. -->

## Runtime flow

```
{{ASCII diagram: the real call path from input to output}}
```

<!-- Highest-value block in the skill: it is what a reader cannot reconstruct
     quickly from the file tree. Follow it with a file → role table. -->

| file | role |
|---|---|
| {{...}} | {{one line, what it owns}} |

## Configuration

| name | type | meaning |
|---|---|---|
| {{...}} | {{...}} | {{what it controls, and the non-obvious consequence}} |

<!-- Any load-order subtlety: defaults, override precedence, when a callback is
     first live, what must be re-read explicitly and why. Silent
     misconfiguration comes from here. -->

### Input formats — what the parser actually accepts

```
{{a real, minimal, working example - not the idealised one from the design doc}}
```

<!-- Say whether the reader is lenient or strict, and what a malformed entry does:
     skipped-and-logged, or fatal. Name any documented format the code does NOT
     implement. -->

## Contracts

<!-- The interfaces this component owns: type, handler behaviour, and any pattern
     that must be preserved. Include known soft spots - names inferred by
     analogy, calls without timeouts. -->

## Validation and observability

<!-- What is checked, in what order, what it reports. Flag where a name is itself
     part of a contract (renaming it breaks a consumer). Then: what passing does
     NOT mean. -->

## Design docs — read with care

<!-- Which files are authoritative, which are historical, and which one wins when
     two disagree. If the status lines run ahead of the code, say so explicitly
     and list what is described there but not implemented. -->

Still open: {{the honest backlog}}

## Conventions

<!-- Build/format rules, where new sources must be registered, logging idiom.
     Close by pointing at the sibling skills. -->
