---
name: tester
description: Run and debug the {{PROJECT}} tests, lint and coverage. Use when asked to test {{PROJECT}}, run or filter a single test, check its coverage, or diagnose a failing, crashing or newly added test in this repo.
---

# Test {{PROJECT}}

<!-- Two sentences max: where tests run and what the runner actually does.
     Delete every comment in this file as you fill it. -->

## Scope

<!-- One line on what this covers, one on what it does not. -->

## Run everything

```bash
{{...}}
```

Healthy tail: {{the exact lines that mean green}}

<!-- If the exit code lies (runner reports success while tests failed), say so
     here and give the grep that tells the truth. -->

## Run one test

<!-- The fastest loop that skips a full rebuild, and what it costs: does it use
     the last built sources or the current ones? -->

```bash
{{...}}
```

## What the suites cover

| file | suites | notes |
|---|---|---|
| {{...}} | {{...}} | {{what it actually exercises}} |

<!-- Any pattern a new test must follow, and what breaks if it does not. -->

## Stages

<!-- Delete the ones you do not create. -->

- Writing, filtering and debugging one test — [references/unit-test-stage.md](references/unit-test-stage.md)
- Producing and reading coverage that means something — [references/coverage-stage.md](references/coverage-stage.md)
- Symptom → cause → fix for test failures seen — [references/error-catalogue.md](references/error-catalogue.md)

## Traps

<!-- Failures that look like something they are not. Symptom in bold, real cause
     after. Include deliberate slowness so nobody "optimises" it away. -->

## Gaps

<!-- What green does NOT prove, and which skill covers that half. -->
