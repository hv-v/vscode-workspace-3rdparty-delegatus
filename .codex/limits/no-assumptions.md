---
name: no-assumptions
trigger: always
action: annotate
priority: 50
append: "Do not assume any part of this task that is not stated above — if a path, name, behaviour or implementation detail is missing, stop and ask rather than inventing one."
append-short: "State missing details as questions; never invent them."
---

# No assumptions about missing parts

The most expensive failure mode is a confident implementation of something that
was never specified. This limitation applies to every prompt, which is why its
line is the first one charged to the budget.

## Checks

1. **Find the gaps.** List every thing the prompt asks to be produced, and for
   each one ask whether the prompt says *where* it goes, *what shape* it has,
   and *how success is judged*. A gap is a requirement with no answer to one of
   those three.

2. **Classify each gap.**
   - **Fillable from the repo** — the answer exists in code, a skill, or the code
     graph. Not a gap; the executing agent will find it. Say where.
   - **Fillable by convention** — `AGENTS.md` or a project skill settles
     it. Not a gap. Name the convention.
   - **Genuinely open** — nothing in the workspace decides it. This is a gap.

3. **Three or more genuinely open gaps, or one that changes the shape of the
   deliverable** → **block**: return the prompt with the gaps as questions. A
   prompt this underspecified is cheaper to fix now than after the work.

4. **Fewer than that** → append the constraint line and list the open gaps in the
   report under `OPEN`, so the user sees them without the prompt growing.

## Not a gap

An unstated detail the prompt explicitly delegates ("use whatever formatter the
repo has", "your call"), or a detail that only affects work outside the ask.
Do not manufacture gaps to look thorough — every false gap costs the user a
round trip.
