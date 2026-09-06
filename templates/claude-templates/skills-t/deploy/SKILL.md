---
name: deploy
description: Run {{PROJECT}} standalone and drive it - probe, observe, exercise its interfaces, smoke-test it. Use when asked to run, start, launch, deploy or smoke-test {{PROJECT}}, inspect its live behaviour, or confirm a change works in the real process rather than only in unit tests.
---

# Run and drive {{PROJECT}}

<!-- Two sentences max: what the observable surface is. If there is no GUI, say
     what stands in for one. Delete every comment as you fill this in. -->

## Scope

<!-- What this covers, what it does not. Name the prerequisite skill (build). -->

## Setup

<!-- Absolute paths only - a path resolved against the wrong cwd fails silently
     or, with mounts, shadows the target. Point at the files this skill ships. -->

```bash
{{...}}
```

Files shipped here: `assets/{{config}}` — {{...}}; `scripts/driver.py` — {{...}}.

## Launch

```bash
{{...}}
```

<!-- Which flags/env are mandatory and why (one clause each, detail goes in
     Gotchas). Then the log lines that prove it came up, and which of them are
     expected-but-alarming when run without its usual surroundings. -->

## Drive it

```bash
{{...}}
```

| command | what it does |
|---|---|
| `probe` | what is actually reachable |
| `watch` | capture the output channels |
| `smoke` | all checks in order, with verdicts, non-zero on failure |

## Stages

<!-- Delete the ones you do not create. -->

- Running and inspecting by hand — [references/runtime-stage.md](references/runtime-stage.md)
- Cluster/orchestrated deployment and how it differs — [references/cluster-stage.md](references/cluster-stage.md)

## Gotchas

<!-- The highest-value section of a deploy skill. Every silent, intermittent or
     misattributed failure belongs here: symptom in bold, real cause after.
     Include failures that are actually the correct answer in this setup. -->
