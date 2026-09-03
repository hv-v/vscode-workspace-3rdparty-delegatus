---
name: build
description: {{One line - what this builds and how.}} Use when asked to build, compile, rebuild or produce an artifact for {{PROJECT}}, when adding a source file or dependency to it, or when a build error needs triage.
---

# Build {{PROJECT}}

<!-- Two sentences max: what produces the artifact, and the single hard rule that
     is easy to get wrong. Delete every comment in this file as you fill it. -->

## Scope

<!-- One line on what this covers, one on what it does not. -->

## Setup

<!-- Exact commands that must run before a build: cwd, env, credentials,
     dependency fetch. For each, say what breaks without it and with which
     message. Never assume the cwd; keep any `cd` in the same shell invocation
     as the build command. -->

```bash
{{...}}
```

## Build

<!-- The one command. Then the one log line that proves it worked. -->

```bash
{{...}}
```

Healthy signal: {{the exact line that means success}}

## On failure

<!-- How to get the FIRST error out of the log - most runners truncate and show
     the last, which is rarely the cause. -->

```bash
{{...}}
```

## Stages

<!-- Only if a section grew long AND is needed by a minority of runs. Say WHEN to
     read each file, not just that it exists. Delete the ones you do not create. -->

- Sources, dependency graph, what to edit when adding code — [references/compilation-stage.md](references/compilation-stage.md)
- Formatting / static analysis inside the build — [references/linter-stage.md](references/linter-stage.md)
- Symptom → cause → fix for every failure seen — [references/error-catalogue.md](references/error-catalogue.md)

## Traps

<!-- Only failures that have actually cost time. Symptom in bold, then the real
     cause. Guesses are noise - delete this section until you have real ones. -->

## Next

<!-- Point at the sibling skills: tester, deploy, project. -->
