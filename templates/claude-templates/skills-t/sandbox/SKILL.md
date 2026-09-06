---
name: sandbox
description: Throwaway environment for experimenting with {{PROJECT}} - a scratch runtime, a scratch checkout, and the scratch paths to write to. Use when asked to try something out, prototype, poke at an API, reproduce a report, or run a one-off experiment for {{PROJECT}} without touching the working tree, the build artifacts or a shared environment.
---

# Sandbox for {{PROJECT}}

<!-- Single file by design - short, and every section is needed on every use.
     Delete every comment as you fill it in. -->

Where to experiment so nothing lands in the repo, a tagged artifact or a shared
environment by accident.

## Rules

<!-- The invariants, one line each. At minimum: never modify the working tree to
     try something out; never reuse a released/tagged name; never point at a
     shared environment or real hardware. Name what is off limits and what is
     fair game. -->

## Scratch paths

```bash
{{...}}
```

<!-- One scratch root. Anything written outside it is a bug in the experiment. -->

## Scratch runtime

<!-- The fastest disposable environment - usually the already-built artifact with
     a shell instead of its entrypoint. Say what is available inside it. -->

```bash
{{...}}
```

## Scratch checkout

<!-- The right way to get an isolated copy of the source here, and the obvious
     way that fails (and how it fails). -->

## Cleanup

```bash
{{...}}
```

<!-- What survives cleanup and must be removed by hand. -->

## Promoting an experiment

An experiment is not a change. When it works, redo it properly in the working
tree: register new sources where they belong, add a test, rebuild from a clean
checkout. Never copy a scratch artifact into the repo.
