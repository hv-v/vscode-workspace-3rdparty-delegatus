---
name: debug
description: Diagnose {{PROJECT}} when it crashes, hangs, misbehaves at runtime or produces no output - backtraces, core dumps, log levels, live introspection, and the failure modes that mimic bugs. Use when asked to debug, investigate a crash, segfault, hang, timeout or silent failure of {{PROJECT}}, or when a failure is not explained by the build and test logs.
---

# Debug {{PROJECT}}

<!-- Single file by design: read top to bottom while something is broken. Split
     only if tool recipes outgrow the triage table. Delete every comment. -->

## Triage first

<!-- Match the symptom before reaching for a tool - most rows here are not bugs
     in the code. One row per failure that has actually happened; do not invent
     rows. -->

| symptom | most likely cause | first check |
|---|---|---|
| {{...}} | {{...}} | {{...}} |

## Backtrace

<!-- Where the debug symbols and build tree actually live (often not the runtime
     artifact), the command to get a symbolized backtrace, and how to rebuild
     with symbols if they are absent. -->

```bash
{{...}}
```

## Core dumps

<!-- Where a core actually lands given the host settings, and the usual reason it
     does not appear at all. -->

```bash
{{...}}
```

## Logs and tracing

<!-- The logging idiom, the exact flag/env to raise the level, how to filter.
     Cross-reference the deploy skill for expected-but-alarming lines rather
     than repeating them. -->

```bash
{{...}}
```

## Live introspection

<!-- How to inspect a running process without restarting it. Point at the deploy
     driver for the scripted version. -->

## Hangs and deadlocks

<!-- The re-entrancy and blocking hazards specific to this codebase, the pattern
     that avoids them, and how to dump the stacks of a stuck process. -->

## Traps

<!-- Failure modes that look like code bugs and are not: environment flags,
     intermittent transport behaviour, deliberate timeouts, harmless noise.
     Each one recorded here is an hour nobody loses again. -->

## Next

<!-- tester to reproduce it as a test, sandbox to try a fix, project for what the
     code is supposed to do. -->
