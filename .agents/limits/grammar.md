---
name: grammar
trigger: always
action: rewrite
priority: 40
---

# Grammar, only where it changes meaning

Grammar repair here has one purpose: remove readings the prompt did not intend.
It is not style correction, and the user is not being graded. Most prompts need
no change at all.

## Checks

1. **Repair only what creates a second reading:**
   - a missing or misplaced negation (`do not` that reads as `do`)
   - a clause boundary that attaches a condition to the wrong requirement
   - a list whose items are not parallel, so the scope of a shared verb is
     unclear
   - a pronoun with two possible antecedents
   - a missing verb or subject that leaves a requirement unreadable

2. **Never touch:** identifiers, paths, code, quoted text, command lines, the
   order of requirements, the user's terminology, or a phrasing that is merely
   informal. Non-native phrasing that reads unambiguously is left exactly as it
   is.

3. **Two readings that grammar cannot settle → block.** State both readings as a
   numbered choice and return the prompt. Do not pick the likelier one; picking
   is the failure this whole verifier exists to prevent.

4. **Size.** The repaired prompt must not exceed the original by more than 10%.
   Repair shortens more often than it lengthens; if it is growing, the repair has
   turned into a rewrite — stop.

5. **Report every change.** Each repair appears in `REWRITTEN` as
   `<before> → <after>`, one line each, so the user can reject it. A repair the
   user cannot see is a silent reinterpretation of their request.

## Worked shape

```
REWRITTEN
  "not in ohher folder hust in that" → "not in another folder, just in that one"
  "check that names is valida" → "check that the names are valid"
```

Both are unambiguous once repaired, so neither blocks. Had the first one been
`restore files in A and B only not in that one`, the antecedent of *that one* is
undecidable and the prompt is returned.
